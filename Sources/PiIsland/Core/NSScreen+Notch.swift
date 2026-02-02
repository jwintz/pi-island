//
//  NSScreen+Notch.swift
//  PiIsland
//
//  Extensions for NSScreen to detect notch and built-in display
//

import AppKit

extension NSScreen {
    /// Returns the size of the notch on this screen
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            // Fallback for non-notch displays - wider to accommodate content
            return CGSize(width: 320, height: 38)
        }

        let notchHeight = safeAreaInsets.top
        let fullWidth = frame.width
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0

        guard leftPadding > 0, rightPadding > 0 else {
            return CGSize(width: 180, height: notchHeight)
        }

        let notchWidth = fullWidth - leftPadding - rightPadding + 4
        return CGSize(width: notchWidth, height: notchHeight)
    }

    /// Whether this is the built-in display
    var isBuiltinDisplay: Bool {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(screenNumber) != 0
    }

    /// The built-in display
    static var builtin: NSScreen? {
        if let builtin = screens.first(where: { $0.isBuiltinDisplay }) {
            return builtin
        }
        return NSScreen.main
    }

    /// Whether this screen has a physical notch
    var hasPhysicalNotch: Bool {
        safeAreaInsets.top > 0
    }
}
