//
//  EventMonitors.swift
//  PiIsland
//
//  Global event monitors using Combine
//

import AppKit
import Combine

/// Shared global event monitors
@MainActor
final class EventMonitors: Sendable {
    static let shared = EventMonitors()

    let mouseLocation = PassthroughSubject<CGPoint, Never>()
    let mouseDown = PassthroughSubject<Void, Never>()

    private init() {
        setupMonitors()
    }

    private func setupMonitors() {
        // Global mouse moved
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in
                self?.mouseLocation.send(NSEvent.mouseLocation)
            }
        }

        // Local mouse moved (within app)
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in
                self?.mouseLocation.send(NSEvent.mouseLocation)
            }
            return event
        }

        // Global mouse down
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.mouseDown.send()
            }
        }

        // Local mouse down
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.mouseDown.send()
            }
            return event
        }
    }
}
