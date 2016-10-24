//
//  SelectOperator.swift
//  GlueKit
//
//  Created by Károly Lőrentey on 2015-12-06.
//  Copyright © 2015 Károly Lőrentey. All rights reserved.
//

extension ObservableValueType {
    /// Map is an operator that implements key path coding and observing.
    /// Given an observable parent and a key that selects an observable child component (a.k.a "field") of its value,
    /// `map` returns a new observable that can be used to look up and modify the field and observe its changes
    /// indirectly through the parent.
    ///
    /// @param key: An accessor function that returns a component of self (a field) that is itself observable.
    /// @returns A new observable that tracks changes to both self and the field returned by `key`.
    ///
    /// For example, take the model for a hypothetical group chat system below.
    /// ```
    /// class Account {
    ///     let name: Variable<String>
    ///     let avatar: Variable<Image>
    /// }
    /// class Message {
    ///     let author: Variable<Account>
    ///     let text: Variable<String>
    /// }
    /// class Room {
    ///     let latestMessage: Observable<Message>
    ///     let newMessages: Source<Message>
    ///     let messages: ArrayVariable<Message>
    /// }
    /// let currentRoom: Variable<Room>
    /// ```
    ///
    /// You can create an observable for the latest message in the current room with
    /// ```Swift
    /// let observable = currentRoom.map{$0.latestMessage}
    /// ```
    /// Sinks connected to `observable.futureValues` will fire whenever the current room changes, or when a new
    /// message is posted in the current room. The observable can also be used to simply retrieve the latest
    /// message at any time.
    ///
    public func map<O: ObservableValueType>(_ key: @escaping (Value) -> O) -> AnyObservableValue<O.Value> {
        return ValueMappingForValueField(parent: self, key: key).anyObservable
    }
}

/// A source of changes for an Observable field.
private final class ValueMappingForValueField<Parent: ObservableValueType, Field: ObservableValueType>: _BaseObservableValue<Field.Value> {
    typealias Value = Field.Value
    typealias Change = ValueChange<Value>

    let parent: Parent
    let key: (Parent.Value) -> Field

    private var currentValue: Field.Value? = nil
    private var field: Field? = nil

    override var value: Field.Value {
        if let v = currentValue { return v }
        return key(parent.value).value
    }

    init(parent: Parent, key: @escaping (Parent.Value) -> Field) {
        self.parent = parent
        self.key = key
    }

    override func startObserving() {
        precondition(currentValue == nil)
        let field = key(parent.value)
        self.field = field
        self.currentValue = field.value
        connect(to: field)
        parent.updates.add(parentSink)
    }

    override func stopObserving() {
        precondition(currentValue != nil)
        self.field!.updates.remove(fieldSink)
        parent.updates.remove(parentSink)
        self.field = nil
        self.currentValue = nil
    }

    private func connect(to field: Field) {
        self.field!.updates.remove(fieldSink)
        self.field = field
        field.updates.add(fieldSink)
    }

    private var parentSink: AnySink<ValueUpdate<Parent.Value>> {
        return MethodSink(owner: self, identifier: 0, method: ValueMappingForValueField.applyParentUpdate).anySink
    }
    private var fieldSink: AnySink<ValueUpdate<Field.Value>> {
        return MethodSink(owner: self, identifier: 1, method: ValueMappingForValueField.applyFieldUpdate).anySink
    }

    private func applyParentUpdate(_ update: ValueUpdate<Parent.Value>) {
        switch update {
        case .beginTransaction:
            beginTransaction()
        case .change(let change):
            let field = key(change.new)
            let old = currentValue!
            let new = field.value
            currentValue = new
            sendChange(ValueChange(from: old, to: new))
            connect(to: field)
        case .endTransaction:
            endTransaction()
        }
    }

    private func applyFieldUpdate(_ update: ValueUpdate<Field.Value>) {
        switch update {
        case .beginTransaction:
            beginTransaction()
        case .change(let change):
            let old = currentValue!
            currentValue = change.new
            sendChange(ValueChange(from: old, to: change.new))
        case .endTransaction:
            endTransaction()
        }
    }
}

extension ObservableValueType where Change == ValueChange<Value> {
    /// Map is an operator that implements key path coding and observing.
    /// Given an observable parent and a key that selects an observable child component (a.k.a "field") of its value,
    /// `map` returns a new observable that can be used to look up and modify the field and observe its changes
    /// indirectly through the parent. If the field is updatable, then the result will be, too.
    ///
    /// @param key: An accessor function that returns a component of self (a field) that is itself updatable.
    /// @returns A new updatable that tracks changes to both self and the field returned by `key`.
    ///
    /// For example, take the model for a hypothetical group chat system below.
    /// ```
    /// class Account {
    ///     let name: Variable<String>
    ///     let avatar: Variable<Image>
    /// }
    /// class Message {
    ///     let author: Variable<Account>
    ///     let text: Variable<String>
    /// }
    /// class Room {
    ///     let latestMessage: Observable<Message>
    ///     let messages: ArrayVariable<Message>
    ///     let newMessages: Source<Message>
    /// }
    /// let currentRoom: Variable<Room>
    /// ```
    ///
    /// You can create an updatable for the avatar image of the author of the latest message in the current room with
    /// ```Swift
    /// let updatable = currentRoom.map{$0.latestMessage}.map{$0.author}.map{$0.avatar}
    /// ```
    /// Sinks connected to `updatable.futureValues` will fire whenever the current room changes, or when a new message is posted
    /// in the current room, or when the author of that message is changed, or when the current
    /// author changes their avatar. The updatable can also be used to simply retrieve the avatar at any time,
    /// or to update it.
    ///
    public func map<U: UpdatableValueType>(_ key: @escaping (Value) -> U) -> AnyUpdatableValue<U.Value> where U.Change == ValueChange<U.Value> {
        return ValueMappingForUpdatableField<Self, U>(parent: self, key: key).anyUpdatable
    }
}

private final class ValueMappingForUpdatableField<Parent: ObservableValueType, Field: UpdatableValueType>: _AbstractUpdatableValue<Field.Value> where Parent.Change == ValueChange<Parent.Value>, Field.Change == ValueChange<Field.Value> {
    typealias Value = Field.Value

    private let _observable: ValueMappingForValueField<Parent, Field>

    init(parent: Parent, key: @escaping (Parent.Value) -> Field) {
        self._observable = ValueMappingForValueField<Parent, Field>(parent: parent, key: key)
    }

    override var value: Field.Value {
        get {
            return _observable.value
        }
        set {
            _observable.key(_observable.parent.value).value = newValue
        }
    }

    override func withTransaction<Result>(_ body: () -> Result) -> Result {
        return _observable.key(_observable.parent.value).withTransaction(body)
    }

    override var updates: ValueUpdateSource<Value> {
        return _observable.updates
    }
}
