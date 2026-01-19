internal import jsi
internal import ExpoModulesJSI_Cxx

public struct JSPromise: JavaScriptType, ~Copyable {
  private typealias PromiseContinuation = CheckedContinuation<JavaScriptValue.Ref, any Error>

  private weak var runtime: JavaScriptRuntime?
  private let object: JavaScriptObject
  private let deferredPromise = DeferredPromise()

  init(_ runtime: JavaScriptRuntime, _ object: consuming facebook.jsi.Object) {
    self.runtime = runtime
    self.object = JavaScriptObject(runtime, object)
  }

  @JavaScriptActor
  public func getResult() async throws -> JavaScriptValue {
    guard let runtime else {
      JS.runtimeLostFatalError()
    }
    let deferredPromise = self.deferredPromise

    let onFulfilled = runtime.createSyncFunction("onFulfilled") { this, arguments in
      // [JS thread]
      let value = arguments[0].ref()
      Task.immediate_polyfill {
        await deferredPromise.resolve(value)
      }
      return .undefined()
    }
    let onRejected = runtime.createSyncFunction("onRejected") { this, arguments in
      // [JS thread]
      let error = arguments[0].ref()
      Task.immediate_polyfill {
        await deferredPromise.reject(error)
      }
      return .undefined()
    }

    object
      .getPropertyAsFunction("then")
      .call(arguments: onFulfilled.ref(), onRejected.ref())

    return try await deferredPromise.getValue().take()
  }

  public func asValue() -> JavaScriptValue {
    return object.asValue()
  }
}

public final class JavaScriptPromise: JavaScriptType {
  nonisolated(unsafe) private weak var runtime: JavaScriptRuntime?
  private let task: Task<JavaScriptValue.Ref, any Error>
  private let object: JavaScriptObject
  private let data = PromiseData()
  private let resolveFunction: JavaScriptValue.Ref
  private let rejectFunction: JavaScriptValue.Ref

  /**
   Returns the current state of the promise, one of: `pending`, `fulfilled`, `rejected`.
   */
  public var state: State {
    return data.state
  }

  @JavaScriptActor
  public init(_ runtime: JavaScriptRuntime) {
    self.runtime = runtime

    // Create refs for resolve and reject functions.
    // They will be set in the Promise setup function.
    self.resolveFunction = JavaScriptValue.Ref()
    self.rejectFunction = JavaScriptValue.Ref()

    self.task = Task.detached { [data] in
      return try await withCheckedThrowingContinuation { continuation in
        data.continuation = continuation
      }
    }

    // Create function that is the promise setup. It is called immediately on `callAsConstructor`.
    let setup = runtime.createSyncFunction("setup") { [resolveFunction, rejectFunction] this, arguments in
      resolveFunction.reset(arguments[0])
      rejectFunction.reset(arguments[1])
      return .undefined()
    }

    self.object = runtime
      .global()
      .getPropertyAsFunction("Promise")
      .callAsConstructor(setup.ref())
      .getObject()
  }

  public func resolve(_ result: consuming JavaScriptValue) {
    guard let runtime else {
      return
    }
    guard data.state == .pending else {
      fatalError("Cannot settle a promise more than once")
    }
    let ref = result.ref()

    // `JavaScriptActor` does not guarantee thread safety here. Make sure to jump to JS thread.
    runtime.execute { [data, resolveFunction, rejectFunction] in
      runtime.assertThread()
      // Continuations does not support non-copyable types, so the value is passed as a reference.
      data.continuation?.resume(returning: ref)
      data.state = .fulfilled

      // Call the actual `resolve` function in JS.
      _ = try! resolveFunction.take().getFunction().call(arguments: ref)

      rejectFunction.release()
    }
  }

  public func reject(_ error: any Error) {
    guard let runtime else {
      return
    }
    guard data.state == .pending else {
      fatalError("Cannot settle a promise more than once")
    }

    // `JavaScriptActor` does not guarantee thread safety here. Make sure to jump to JS thread.
    runtime.execute { [data, resolveFunction, rejectFunction] in
      let errorRef = JavaScriptError(runtime, message: error.localizedDescription).ref()
      data.continuation?.resume(throwing: error)
      data.state = .rejected

      // Call the actual `reject` function in JS.
      _ = try! rejectFunction.take().getFunction().call(arguments: errorRef)

      resolveFunction.release()
    }
  }

  public func get() async throws -> JavaScriptValue {
    return try await task.value.take()
  }

  public func asValue() -> JavaScriptValue {
    return object.asValue()
  }

  /**
   Enum representing each of the possible Promise's state.
   */
  public enum State: String {
    /**
     Initial state, neither fulfilled nor rejected.
     */
    case pending
    /**
     Operation was completed successfully.
     */
    case fulfilled
    /**
     Operation failed.
     */
    case rejected
  }

  /**
   Stores mutable data that must stay separated from `JavaScriptPromise` to make it a sendable and non-copyable struct, as other JavaScript types.
   */
  private final class PromiseData: @unchecked Sendable {
    var continuation: CheckedContinuation<JavaScriptValue.Ref, any Error>? = nil
    var result: Result<JavaScriptValue.Ref, any Error>? = nil
    var state: State = .pending
  }
}
