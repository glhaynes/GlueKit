//
//  ArrayFilteringOnObservableBool.swift
//  GlueKit
//
//  Created by Károly Lőrentey on 2016-10-07.
//  Copyright © 2016. Károly Lőrentey. All rights reserved.
//

extension ObservableArrayType {
    public func filter<Test: ObservableValueType>(test: @escaping (Element) -> Test) -> AnyObservableArray<Element> where Test.Value == Bool {
        return ArrayFilteringOnObservableBool<Self, Test>(parent: self, test: test).anyObservableArray
    }
}

private final class SinkForTest<Parent: ObservableArrayType, Test: ObservableValueType>: SinkType, RefListElement where Test.Value == Bool {
    typealias Owner = ArrayFilteringOnObservableBool<Parent, Test>

    unowned let owner: Owner
    let field: Test
    var refListLink = RefListLink<SinkForTest<Parent, Test>>()

    init(owner: Owner, field: Test) {
        self.owner = owner
        self.field = field

        field.updates.add(self)
    }

    func disconnect() {
        field.updates.remove(self)
    }

    func receive(_ update: ValueUpdate<Bool>) {
        owner.applyFieldUpdate(update, from: self)
    }
}

private class ArrayFilteringOnObservableBool<Parent: ObservableArrayType, Test: ObservableValueType>: _BaseObservableArray<Parent.Element> where Test.Value == Bool {
    typealias Element = Parent.Element
    typealias Change = ArrayChange<Element>
    typealias FieldSink = SinkForTest<Parent, Test>

    private let parent: Parent
    private let test: (Element) -> Test

    private var indexMapping: ArrayFilteringIndexmap<Element>
    private var elementConnections = RefList<FieldSink>()

    init(parent: Parent, test: @escaping (Element) -> Test) {
        self.parent = parent
        self.test = test
        let elements = parent.value
        self.indexMapping = ArrayFilteringIndexmap(initialValues: elements, test: { test($0).value })
        super.init()
        parent.updates.add(parentSink)
        self.elementConnections = RefList(elements.lazy.map { FieldSink(owner: self, field: test($0)) })
    }

    deinit {
        parent.updates.remove(parentSink)
        self.elementConnections.forEach { $0.disconnect() }
    }

    private var parentSink: AnySink<ArrayUpdate<Element>> {
        return MethodSink(owner: self, identifier: 0, method: ArrayFilteringOnObservableBool.applyParentUpdate).anySink
    }

    private func applyParentUpdate(_ update: ArrayUpdate<Element>) {
        switch update {
        case .beginTransaction:
            beginTransaction()
        case .change(let change):
            for mod in change.modifications {
                let inputRange = mod.inputRange
                inputRange.forEach { elementConnections[$0].disconnect() }
                elementConnections.replaceSubrange(inputRange, with: mod.newElements.map { FieldSink(owner: self, field: test($0)) })
            }
            let filteredChange = self.indexMapping.apply(change)
            if !filteredChange.isEmpty {
                sendChange(filteredChange)
            }
        case .endTransaction:
            endTransaction()
        }
    }

    fileprivate func applyFieldUpdate(_ update: ValueUpdate<Bool>, from sink: FieldSink) {
        switch update {
        case .beginTransaction:
            beginTransaction()
        case .change(let change):
            if change.old == change.new { return }
            let index = elementConnections.index(of: sink)!
            let c = indexMapping.matchingIndices.count
            if change.new, let filteredIndex = indexMapping.insert(index) {
                sendChange(ArrayChange(initialCount: c, modification: .insert(parent[index], at: filteredIndex)))
            }
            else if !change.new, let filteredIndex = indexMapping.remove(index) {
                sendChange(ArrayChange(initialCount: c, modification: .remove(parent[index], at: filteredIndex)))
            }
        case .endTransaction:
            endTransaction()
        }
    }

    override var isBuffered: Bool { return false }

    override subscript(index: Int) -> Element {
        return parent[indexMapping.matchingIndices[index]]
    }

    override subscript(bounds: Range<Int>) -> ArraySlice<Element> {
        precondition(0 <= bounds.lowerBound && bounds.lowerBound <= bounds.upperBound && bounds.upperBound <= count)
        var result: [Element] = []
        result.reserveCapacity(bounds.count)
        for index in indexMapping.matchingIndices[bounds] {
            result.append(parent[index])
        }
        return ArraySlice(result)
    }

    override var value: Array<Element> {
        return indexMapping.matchingIndices.map { parent[$0] }
    }

    override var count: Int {
        return indexMapping.matchingIndices.count
    }
}
