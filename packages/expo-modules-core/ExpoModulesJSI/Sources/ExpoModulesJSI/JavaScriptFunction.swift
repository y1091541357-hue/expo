// Copyright 2025-present 650 Industries. All rights reserved.

internal import jsi
internal import ExpoModulesJSI_Cxx

public struct JavaScriptFunction: JavaScriptType, ~Copyable {
  internal weak var runtime: JavaScriptRuntime?
  internal let pointee: facebook.jsi.Function

  internal/*!*/ init(_ runtime: JavaScriptRuntime, _ pointee: consuming facebook.jsi.Function) {
    self.runtime = runtime
    self.pointee = pointee
  }

  // MARK: - Calling

  /**
   Calls the function with the given `this` object and arguments.
   */
  @discardableResult
  public func call(this: consuming JavaScriptObject? = nil, arguments: consuming JSValuesBuffer? = nil) -> JavaScriptValue {
    guard let runtime else {
      JS.runtimeLostFatalError()
    }
    let jsiResult = if let this {
      pointee.callWithThis(runtime.pointee, this.pointee, arguments?.baseAddress, arguments?.count ?? 0)
    } else {
      pointee.call(runtime.pointee, arguments?.baseAddress, arguments?.count ?? 0)
    }
    return JavaScriptValue(runtime, jsiResult)
  }

  /**
   Calls the function with the given `this` object and arguments.
   */
  @discardableResult
  public func call<each T: JSRepresentable>(this: consuming JavaScriptObject? = nil, arguments: repeat each T) -> JavaScriptValue {
    guard let runtime else {
      JS.runtimeLostFatalError()
    }
    let argumentsBuffer = JSValuesBuffer.allocate(in: runtime, with: repeat each arguments)
    return self.call(this: this, arguments: argumentsBuffer)
  }

  /**
   Calls the function as a constructor with the given buffer of arguments. It's like calling a function with the `new` keyword.
   */
  public func callAsConstructor(_ arguments: consuming JSValuesBuffer? = nil) -> JavaScriptValue {
    guard let runtime else {
      JS.runtimeLostFatalError()
    }
    let jsiResult = pointee.callAsConstructor(runtime.pointee, arguments?.baseAddress, arguments?.count ?? 0)
    return JavaScriptValue(runtime, jsiResult)
  }

  /**
   Calls the function as a constructor with the given arguments. It's like calling a function with the `new` keyword.
   */
  public func callAsConstructor<each T: JSRepresentable>(_ arguments: repeat each T) -> JavaScriptValue {
    guard let runtime else {
      JS.runtimeLostFatalError()
    }
    let argumentsBuffer = JSValuesBuffer.allocate(in: runtime, with: repeat each arguments)
    return callAsConstructor(argumentsBuffer)
  }

  // MARK: - Conversions

  public func asValue() -> JavaScriptValue {
    guard let jsiRuntime = runtime?.pointee else {
      JS.runtimeLostFatalError()
    }
    return JavaScriptValue(runtime, expo.valueFromFunction(jsiRuntime, pointee))
  }

  public func asObject() -> JavaScriptObject {
    guard let runtime else {
      JS.runtimeLostFatalError()
    }
    let jsiRuntime = runtime.pointee
    return JavaScriptObject(runtime, expo.valueFromFunction(jsiRuntime, pointee).getObject(jsiRuntime))
  }
}

extension JavaScriptFunction: JSRepresentable {
  public static func fromJSValue(_ value: borrowing JavaScriptValue) -> JavaScriptFunction {
    return value.getFunction()
  }

  public func toJSValue(in runtime: JavaScriptRuntime) -> JavaScriptValue {
    return asValue()
  }
}

extension JavaScriptFunction: JSIRepresentable {
  static func fromJSIValue(_ value: borrowing facebook.jsi.Value, in runtime: facebook.jsi.Runtime) -> JavaScriptFunction {
    fatalError("Unimplemented")
  }

  func toJSIValue(in runtime: facebook.jsi.Runtime) -> facebook.jsi.Value {
    return asValue().pointee
  }
}
