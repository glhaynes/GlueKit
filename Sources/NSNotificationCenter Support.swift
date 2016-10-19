//
//  NSNotificationCenter Support.swift
//  GlueKit
//
//  Created by Károly Lőrentey on 2015-11-30.
//  Copyright © 2015 Károly Lőrentey. All rights reserved.
//

import Foundation

extension NotificationCenter {
    /// Creates a Source that observes the specified notifications and forwards it to its connected sinks.
    ///
    /// The returned source holds strong references to the notification center and the sender (if any).
    /// The source will only observe the notification while a sink is actually connected.
    ///
    /// - Parameter name: The name of the notification to observe.
    /// - Parameter sender: The sender of the notifications to observe, or nil for any object. This parameter is nil by default.
    /// - Parameter queue: The operation queue on which the source will trigger. If you pass nil, the sinks are run synchronously on the thread that posted the notification. This parameter is nil by default.
    /// - Returns: A Source that triggers when the specified notification is posted.
    public func source(forName name: NSNotification.Name, sender: AnyObject? = nil, queue: OperationQueue? = nil) -> Source<Notification> {
        return NotificationSource(center: self, name: name, sender: sender, queue: queue).source
    }
}

@objc private class NotificationSource: NSObject, SignalDelegate {
    typealias SourceValue = Notification

    let center: NotificationCenter
    let name: NSNotification.Name
    let sender: AnyObject?
    let queue: OperationQueue?

    var signal = OwningSignal<Notification>()

    init(center: NotificationCenter, name: NSNotification.Name, sender: AnyObject?, queue: OperationQueue?) {
        self.center = center
        self.name = name
        self.sender = sender
        self.queue = queue
    }

    var source: Source<Notification> {
        return signal.with(self).source
    }

    @objc private func didReceive(_ notification: Notification) {
        if let queue = queue {
            queue.addOperation {
                self.signal.send(notification)
            }
        }
        else {
            self.signal.send(notification)
        }
    }

    func start(_ signal: Signal<Notification>) {
        center.addObserver(self, selector: #selector(didReceive(_:)), name: name, object: sender)
    }

    func stop(_ signal: Signal<Notification>) {
        center.removeObserver(self, name: name, object: sender)
    }
}
