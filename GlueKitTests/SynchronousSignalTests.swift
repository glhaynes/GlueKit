//
//  SynchronousSignalTests.swift
//  GlueKit
//
//  Created by Károly Lőrentey on 2015-12-03.
//  Copyright © 2015 Károly Lőrentey. All rights reserved.
//

import XCTest
@testable import GlueKit

// These are literally the same tests as the non-reentrant tests of SignalTests.
// TODO: Is there a way to easily unify them?

class SynchronousSignalProtocolTests: XCTestCase {

    //MARK: Test simple stuff

    func testSimpleConnection() {
        let signal = SynchronousSignal<Int>()

        signal.send(1)

        var r = [Int]()
        let connection = signal.connect { i in r.append(i) }

        signal.send(2)
        signal.send(3)
        signal.send(4)

        connection.disconnect()

        signal.send(5)

        XCTAssertEqual(r, [2, 3, 4])
    }

    func testReleasingConnectionDisconnects() {
        let signal = SynchronousSignal<Int>()
        var values = [Int]()
        var c: Connection? = nil

        c = signal.connect { values.append($0) }
        signal.send(1)
        c = nil
        signal.send(2)

        XCTAssertEqual(values, [1])
        noop(c)
    }

    func testDuplicateDisconnect() {
        let signal = SynchronousSignal<Int>()

        let c = signal.connect { i in }

        // It is OK to call disconnect twice.
        c.disconnect()
        c.disconnect()
    }

    func testMultipleConnections() {
        let signal = SynchronousSignal<Int>()

        signal.send(1)

        var a = [Int]()
        let c1 = signal.connect { i in a.append(i) }

        signal.send(2)

        var b = [Int]()
        let c2 = signal.connect { i in b.append(i) }

        signal.send(3)

        c1.disconnect()

        signal.send(4)

        c2.disconnect()

        signal.send(5)

        XCTAssertEqual(a, [2, 3])
        XCTAssertEqual(b, [3, 4])
    }

    //MARK: Test memory management

    func testConnectionRetainsTheSignal() {
        var values = [Int]()
        weak var weakSignal: SynchronousSignal<Int>? = nil
        weak var weakConnection: Connection? = nil
        do {
            let connection: Connection
            do {
                let signal = SynchronousSignal<Int>()
                weakSignal = signal
                connection = signal.connect { i in values.append(i) }
                weakConnection = .Some(connection)

                signal.send(1)
            }

            XCTAssertNotNil(weakSignal)
            XCTAssertNotNil(weakConnection)
            noop(connection)
        }
        XCTAssertNil(weakSignal)
        XCTAssertNil(weakConnection)
        XCTAssertEqual(values, [1])
    }

    func testDisconnectingConnectionReleasesResources() {
        weak var weakSignal: SynchronousSignal<Int>? = nil
        weak var weakResource: NSMutableArray? = nil

        let connection: Connection
        do {
            let signal = SynchronousSignal<Int>()
            weakSignal = signal

            let resource = NSMutableArray()
            weakResource = resource

            connection = signal.connect { i in
                resource.addObject(i)
            }
            signal.send(1)
        }

        XCTAssertNotNil(weakSignal)
        XCTAssertNotNil(weakResource)

        XCTAssertEqual(weakResource, NSArray(object: 1))

        connection.disconnect()

        XCTAssertNil(weakSignal)
        XCTAssertNil(weakResource)
    }

    func testSourceDoesNotRetainConnection() {
        var values = [Int]()
        weak var weakConnection: Connection? = nil
        let signal = SynchronousSignal<Int>()
        do {
            let connection = signal.connect { values.append($0) }
            weakConnection = connection

            signal.send(1)
            noop(connection)
        }

        signal.send(2)
        XCTAssertNil(weakConnection)

        XCTAssertEqual(values, [1])
    }

    //MARK: Test sinks adding and removing connections

    func testAddingAConnectionInASink() {
        let signal = SynchronousSignal<Int>()

        var v1 = [Int]()
        var c1: Connection? = nil

        var v2 = [Int]()
        var c2: Connection? = nil

        signal.send(1)

        c1 = signal.connect { i in
            v1.append(i)
            if c2 == nil {
                c2 = signal.connect { v2.append($0) }
            }
        }

        XCTAssertNil(c2)

        signal.send(2)

        XCTAssertNotNil(c2)

        signal.send(3)

        c1?.disconnect()
        c2?.disconnect()

        signal.send(4)

        XCTAssertEqual(v1, [2, 3])
        XCTAssertEqual(v2, [3])
    }

    func testRemovingConnectionWhileItIsBeingTriggered() {
        let signal = SynchronousSignal<Int>()

        signal.send(1)

        var r = [Int]()

        var c: Connection? = nil
        c = signal.connect { i in
            r.append(i)
            c?.disconnect()
        }

        signal.send(2)
        signal.send(3)
        signal.send(4)

        XCTAssertEqual(r, [2])
    }

    func testRemovingNextConnection() {
        let signal = SynchronousSignal<Int>()

        var r = [Int]()

        var c1: Connection? = nil
        var c2: Connection? = nil

        signal.send(0)

        // We don't know which connection fires first.
        // After disconnect() returns, the connection must not fire any more -- even if disconnect is called by a sink.

        c1 = signal.connect { i in
            r.append(i)
            c2?.disconnect()
            c2 = nil
        }

        c2 = signal.connect { i in
            r.append(i)
            c1?.disconnect()
            c1 = nil
        }

        XCTAssertTrue(c1 != nil && c2 != nil)

        signal.send(1)
        XCTAssertTrue((c1 == nil) != (c2 == nil))

        signal.send(2)
        signal.send(3)
        XCTAssertTrue((c1 == nil) != (c2 == nil))

        XCTAssertEqual(r, [1, 2, 3])
    }


    func testRemovingAndReaddingConnectionsAlternately() {
        // This is a weaker test of the semantics of connect/disconnect nested in sinks.
        let signal = SynchronousSignal<Int>()

        var r1 = [Int]()
        var r2 = [Int]()

        var c1: Connection? = nil
        var c2: Connection? = nil

        var sink1: (Int->Void)!
        var sink2: (Int->Void)!

        sink1 = { i in
            r1.append(i)
            c1?.disconnect()
            c2 = signal.connect(sink2)
        }

        sink2 = { i in
            r2.append(i)
            c2?.disconnect()
            c1 = signal.connect(sink1)
        }

        c1 = signal.connect(sink1)
        for i in 1...6 {
            signal.send(i)
        }

        XCTAssertEqual(r1, [1, 3, 5])
        XCTAssertEqual(r2, [2, 4, 6])
    }

    func testSinkDisconnectingThenReconnectingItself() {
        // This is a weaker test of the semantics of connect/disconnect nested in sinks.
        let signal = SynchronousSignal<Int>()

        var r = [Int]()
        var c: Connection? = nil
        var sink: (Int->Void)!

        sink = { i in
            r.append(i)
            c?.disconnect()
            c = signal.connect(sink)
        }
        c = signal.connect(sink)

        for i in 1...6 {
            signal.send(i)
        }

        c?.disconnect()

        XCTAssertEqual(r, [1, 2, 3, 4, 5, 6])
    }

    // MARK: Test didConnectFirstSink and didDisconnectLastSink

    func testFirstAndLastConnectCallbacksAreCalled() {
        var first = 0
        var last = 0
        let signal = SynchronousSignal<Int>(didConnectFirstSink: { first++ }, didDisconnectLastSink: { last++ })

        XCTAssertEqual(first, 0)
        XCTAssertEqual(last, 0)

        signal.send(0)

        XCTAssertEqual(first, 0)
        XCTAssertEqual(last, 0)

        var count = 0
        let connection = signal.connect { i in count++ }

        XCTAssertEqual(first, 1)
        XCTAssertEqual(last, 0)
        XCTAssertEqual(count, 0)

        signal.send(1)

        XCTAssertEqual(first, 1)
        XCTAssertEqual(last, 0)
        XCTAssertEqual(count, 1)

        connection.disconnect()

        XCTAssertEqual(first, 1)
        XCTAssertEqual(last, 1)
        XCTAssertEqual(count, 1)

        signal.send(2)

        XCTAssertEqual(first, 1)
        XCTAssertEqual(last, 1)
        XCTAssertEqual(count, 1)
    }

    func testFirstAndLastConnectCallbacksCanBeCalledMultipleTimes() {
        var first = 0
        var last = 0
        let signal = SynchronousSignal<Int>(didConnectFirstSink: { first++ }, didDisconnectLastSink: { last++ })

        let c1 = signal.connect { i in }

        XCTAssertEqual(first, 1)
        XCTAssertEqual(last, 0)

        c1.disconnect()

        XCTAssertEqual(first, 1)
        XCTAssertEqual(last, 1)

        let c2 = signal.connect { i in }

        XCTAssertEqual(first, 2)
        XCTAssertEqual(last, 1)

        c2.disconnect()

        XCTAssertEqual(first, 2)
        XCTAssertEqual(last, 2)
    }

    func testFirstConnectCallbackIsOnlyCalledOnFirstConnections() {
        var first = 0
        let signal = SynchronousSignal<Int>(didConnectFirstSink: { first++ }, didDisconnectLastSink: { })

        XCTAssertEqual(first, 0)

        let c1 = signal.connect { i in }

        XCTAssertEqual(first, 1)
        let c2 = signal.connect { i in }
        c1.disconnect()
        c2.disconnect()

        let c3 = signal.connect { i in }
        XCTAssertEqual(first, 2)
        c3.disconnect()
    }

    func testLastConnectCallbackIsOnlyCalledOnLastConnections() {
        var last = 0
        let signal = SynchronousSignal<Int>(didConnectFirstSink: { }, didDisconnectLastSink: { last++ })

        XCTAssertEqual(last, 0)

        let c1 = signal.connect { i in }
        let c2 = signal.connect { i in }
        c1.disconnect()
        XCTAssertEqual(last, 0)
        c2.disconnect()
        XCTAssertEqual(last, 1)

        let c3 = signal.connect { i in }
        XCTAssertEqual(last, 1)
        c3.disconnect()
        XCTAssertEqual(last, 2)
    }
}