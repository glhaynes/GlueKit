//
//  CompositeObservable.swift
//  GlueKit
//
//  Created by Károly Lőrentey on 2016-10-09.
//  Copyright © 2016. Károly Lőrentey. All rights reserved.
//

import Foundation

extension ObservableValueType {
    public func combined<Other: ObservableValueType>(_ other: Other) -> AnyObservableValue<(Value, Other.Value)> {
        return CompositeObservable(left: self, right: other, combinator: { ($0, $1) }).anyObservable
    }

    public func combined<A: ObservableValueType, B: ObservableValueType>(_ a: A, _ b: B) -> AnyObservableValue<(Value, A.Value, B.Value)> {
        return combined(a).combined(b, by: { a, b in (a.0, a.1, b) })
    }

    public func combined<A: ObservableValueType, B: ObservableValueType, C: ObservableValueType>(_ a: A, _ b: B, _ c: C) -> AnyObservableValue<(Value, A.Value, B.Value, C.Value)> {
        return combined(a, b).combined(c, by: { a, b in (a.0, a.1, a.2, b) })
    }

    public func combined<A: ObservableValueType, B: ObservableValueType, C: ObservableValueType, D: ObservableValueType>(_ a: A, _ b: B, _ c: C, _ d: D) -> AnyObservableValue<(Value, A.Value, B.Value, C.Value, D.Value)> {
        return combined(a, b, c).combined(d, by: { a, b in (a.0, a.1, a.2, a.3, b) })
    }

    public func combined<A: ObservableValueType, B: ObservableValueType, C: ObservableValueType, D: ObservableValueType, E: ObservableValueType>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E) -> AnyObservableValue<(Value, A.Value, B.Value, C.Value, D.Value, E.Value)> {
        return combined(a, b, c, d).combined(e, by: { a, b in (a.0, a.1, a.2, a.3, a.4, b) })
    }


    public func combined<Other: ObservableValueType, Output>(_ other: Other, by combinator: @escaping (Value, Other.Value) -> Output) -> AnyObservableValue<Output> {
        return CompositeObservable(left: self, right: other, combinator: combinator).anyObservable
    }

    public func combined<A: ObservableValueType, B: ObservableValueType, Output>(_ a: A, _ b: B, by combinator: @escaping (Value, A.Value, B.Value) -> Output) -> AnyObservableValue<Output> {
        return combined(a).combined(b, by: { a, b in combinator(a.0, a.1, b) })
    }

    public func combined<A: ObservableValueType, B: ObservableValueType, C: ObservableValueType, Output>(_ a: A, _ b: B, _ c: C, by combinator: @escaping (Value, A.Value, B.Value, C.Value) -> Output) -> AnyObservableValue<Output> {
        return combined(a, b).combined(c, by: { a, b in combinator(a.0, a.1, a.2, b) })
    }

    public func combined<A: ObservableValueType, B: ObservableValueType, C: ObservableValueType, D: ObservableValueType, Output>(_ a: A, _ b: B, _ c: C, _ d: D, by combinator: @escaping (Value, A.Value, B.Value, C.Value, D.Value) -> Output) -> AnyObservableValue<Output> {
        return combined(a, b, c).combined(d, by: { a, b in combinator(a.0, a.1, a.2, a.3, b) })
    }

    public func combined<A: ObservableValueType, B: ObservableValueType, C: ObservableValueType, D: ObservableValueType, E: ObservableValueType, Output>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, by combinator: @escaping (Value, A.Value, B.Value, C.Value, D.Value, E.Value) -> Output) -> AnyObservableValue<Output> {
        return combined(a, b, c, d).combined(e, by: { a, b in combinator(a.0, a.1, a.2, a.3, a.4, b) })
    }
}

/// An AnyObservableValue that is calculated from two other observables.
private final class CompositeObservable<Left: ObservableValueType, Right: ObservableValueType, Value>: _BaseObservableValue<Value> {
    typealias Change = ValueChange<Value>

    private let left: Left
    private let right: Right
    private let combinator: (Left.Value, Right.Value) -> Value

    private var _leftValue: Left.Value? = nil
    private var _rightValue: Right.Value? = nil
    private var _value: Value? = nil

    public init(left: Left, right: Right, combinator: @escaping (Left.Value, Right.Value) -> Value) {
        self.left = left
        self.right = right
        self.combinator = combinator
    }

    deinit {
        assert(_value == nil)
    }

    public override var value: Value {
        if let value = _value { return value }
        return combinator(left.value, right.value)
    }

    internal override func startObserving() {
        assert(_value == nil)
        let v1 = left.value
        let v2 = right.value
        _leftValue = v1
        _rightValue = v2
        _value = combinator(v1, v2)

        left.updates.add(MethodSink(owner: self, identifier: 1, method: CompositeObservable.applyLeft))
        right.updates.add(MethodSink(owner: self, identifier: 2, method: CompositeObservable.applyRight))
    }

    internal override func stopObserving() {
        left.updates.remove(MethodSink(owner: self, identifier: 1, method: CompositeObservable.applyLeft))
        right.updates.remove(MethodSink(owner: self, identifier: 2, method: CompositeObservable.applyRight))
        _value = nil
        _leftValue = nil
        _rightValue = nil
    }

    private func applyLeft(_ update: ValueUpdate<Left.Value>) {
        switch update {
        case .beginTransaction:
            beginTransaction()
        case .change(let change):
            _leftValue = change.new
            let old = _value!
            let new = combinator(_leftValue!, _rightValue!)
            _value = new
            sendChange(ValueChange(from: old, to: new))
        case .endTransaction:
            endTransaction()
        }
    }

    private func applyRight(_ update: ValueUpdate<Right.Value>) {
        switch update {
        case .beginTransaction:
            beginTransaction()
        case .change(let change):
            _rightValue = change.new
            let old = _value!
            let new = combinator(_leftValue!, _rightValue!)
            _value = new
            sendChange(ValueChange(from: old, to: new))
        case .endTransaction:
            endTransaction()
        }
    }
}

//MARK: Operations with observables of equatable values

public func == <A: ObservableValueType, B: ObservableValueType>(a: A, b: B) -> AnyObservableValue<Bool>
where A.Value == B.Value, A.Value: Equatable {
    return a.combined(b, by: ==)
}

public func != <A: ObservableValueType, B: ObservableValueType>(a: A, b: B) -> AnyObservableValue<Bool>
where A.Value == B.Value, A.Value: Equatable {
    return a.combined(b, by: !=)
}

//MARK: Operations with observables of comparable values

public func < <A: ObservableValueType, B: ObservableValueType>(a: A, b: B) -> AnyObservableValue<Bool>
where A.Value == B.Value, A.Value: Comparable {
    return a.combined(b, by: <)
}

public func > <A: ObservableValueType, B: ObservableValueType>(a: A, b: B) -> AnyObservableValue<Bool>
where A.Value == B.Value, A.Value: Comparable {
    return a.combined(b, by: >)
}

public func <= <A: ObservableValueType, B: ObservableValueType>(a: A, b: B) -> AnyObservableValue<Bool>
where A.Value == B.Value, A.Value: Comparable {
    return a.combined(b, by: <=)
}

public func >= <A: ObservableValueType, B: ObservableValueType>(a: A, b: B) -> AnyObservableValue<Bool>
where A.Value == B.Value, A.Value: Comparable {
    return a.combined(b, by: >=)
}

public func min<A: ObservableValueType, B: ObservableValueType, Value: Comparable>(_ a: A, _ b: B) -> AnyObservableValue<Value>
where A.Value == Value, B.Value == Value {
    return a.combined(b, by: min)
}

public func max<A: ObservableValueType, B: ObservableValueType, Value: Comparable>(_ a: A, _ b: B) -> AnyObservableValue<Value>
where A.Value == Value, B.Value == Value {
    return a.combined(b, by: max)
}

//MARK: Operations with observables of boolean values

public prefix func ! <O: ObservableValueType>(v: O) -> AnyObservableValue<Bool> where O.Value == Bool {
    return v.map { !$0 }
}

public func && <A: ObservableValueType, B: ObservableValueType>(a: A, b: B) -> AnyObservableValue<Bool>
where A.Value == Bool, B.Value == Bool {
    return a.combined(b, by: { a, b in a && b })
}

public func || <A: ObservableValueType, B: ObservableValueType>(a: A, b: B) -> AnyObservableValue<Bool>
where A.Value == Bool, B.Value == Bool {
    return a.combined(b, by: { a, b in a || b })
}

//MARK: Operations with observables of integer arithmetic values

public prefix func - <O: ObservableValueType>(v: O) -> AnyObservableValue<O.Value> where O.Value: SignedNumber {
    return v.map { -$0 }
}

public func + <A: ObservableValueType, B: ObservableValueType, Value: IntegerArithmetic>(a: A, b: B) -> AnyObservableValue<Value>
where A.Value == Value, B.Value == Value {
    return a.combined(b, by: +)
}

public func - <A: ObservableValueType, B: ObservableValueType, Value: IntegerArithmetic>(a: A, b: B) -> AnyObservableValue<Value>
where A.Value == Value, B.Value == Value {
    return a.combined(b, by: -)
}

public func * <A: ObservableValueType, B: ObservableValueType, Value: IntegerArithmetic>(a: A, b: B) -> AnyObservableValue<Value>
where A.Value == Value, B.Value == Value {
    return a.combined(b, by: *)
}

public func / <A: ObservableValueType, B: ObservableValueType, Value: IntegerArithmetic>(a: A, b: B) -> AnyObservableValue<Value>
where A.Value == Value, B.Value == Value {
    return a.combined(b, by: /)
}

public func % <A: ObservableValueType, B: ObservableValueType, Value: IntegerArithmetic>(a: A, b: B) -> AnyObservableValue<Value>
where A.Value == Value, B.Value == Value {
    return a.combined(b, by: %)
}

//MARK: Operations with floating point values

public func + <A: ObservableValueType, B: ObservableValueType, Value: FloatingPoint>(a: A, b: B) -> AnyObservableValue<Value>
where A.Value == Value, B.Value == Value {
    return a.combined(b, by: +)
}

public func - <A: ObservableValueType, B: ObservableValueType, Value: FloatingPoint>(a: A, b: B) -> AnyObservableValue<Value>
where A.Value == Value, B.Value == Value {
    return a.combined(b, by: -)
}

public func * <A: ObservableValueType, B: ObservableValueType, Value: FloatingPoint>(a: A, b: B) -> AnyObservableValue<Value>
where A.Value == Value, B.Value == Value {
    return a.combined(b, by: *)
}

public func / <A: ObservableValueType, B: ObservableValueType, Value: FloatingPoint>(a: A, b: B) -> AnyObservableValue<Value>
where A.Value == Value, B.Value == Value {
    return a.combined(b, by: /)
}
