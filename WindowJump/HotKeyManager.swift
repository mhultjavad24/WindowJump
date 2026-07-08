//
//  HotKeyManager.swift
//  WindowJump
//
//  Created by wake on 2026-06-29.
//

import Carbon
import Foundation

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (@MainActor () -> Void)?

    deinit {
        unregister()
    }

    func register(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        unregister()

        let hotKeyID = EventHotKeyID(signature: Self.fourCharCode("WJMP"), id: 1)
        let modifiers = UInt32(cmdKey | optionKey)

        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard hotKeyStatus == noErr else {
            NSLog("WindowJump failed to register hotkey: \(hotKeyStatus)")
            return
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return noErr
                }

                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.handler?()
                }

                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        if installStatus != noErr {
            NSLog("WindowJump failed to install hotkey handler: \(installStatus)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private static func fourCharCode(_ string: String) -> OSType {
        var result: OSType = 0

        for scalar in string.unicodeScalars.prefix(4) {
            result = (result << 8) + OSType(scalar.value)
        }

        return result
    }
}
