//
//  WindowFocusService.swift
//  WindowJump
//
//  Created by wake on 2026-06-29.
//

import AppKit
import ApplicationServices

@MainActor
enum WindowFocusService {
    static func focus(_ target: WindowTarget) {
        let appElement = AXUIElementCreateApplication(target.pid)
        let trueValue = kCFBooleanTrue! as CFTypeRef

        AXUIElementSetAttributeValue(target.axWindow, kAXMainAttribute as CFString, trueValue)
        AXUIElementSetAttributeValue(target.axWindow, kAXFocusedAttribute as CFString, trueValue)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, target.axWindow)
        AXUIElementPerformAction(target.axWindow, kAXRaiseAction as CFString)

        if let app = NSRunningApplication(processIdentifier: target.pid) {
            app.unhide()
            if #available(macOS 14.0, *) {
                app.activate(options: [.activateAllWindows])
            } else {
                app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
        }

        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, target.axWindow)
        AXUIElementPerformAction(target.axWindow, kAXRaiseAction as CFString)
    }
}
