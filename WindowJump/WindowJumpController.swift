//
//  WindowJumpController.swift
//  WindowJump
//
//  Created by wake on 2026-06-29.
//

import AppKit
import SwiftUI

@MainActor
final class WindowJumpController: NSObject, NSMenuDelegate {
    private(set) var accessibilityGranted = AccessibilityPermission.isGranted
    private(set) var overlayVisible = false

    private let hotKeyManager = HotKeyManager()
    private let scanner = WindowScanner()
    private let overlayController = OverlayController()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func start() {
        AccessibilityPermission.requestPrompt()
        refreshPermission()
        configureStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        hotKeyManager.register { [weak self] in
            self?.toggleOverlay()
        }
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        overlayController.dismiss()
        hotKeyManager.unregister()
    }

    func toggleOverlay() {
        if overlayController.isVisible {
            overlayController.dismiss()
        } else {
            showOverlay()
        }
    }

    func showOverlay() {
        refreshPermission()

        guard accessibilityGranted else {
            showSettingsWindow()
            AccessibilityPermission.requestPrompt()
            return
        }

        let targets = scanner.visibleWindows()
        guard !targets.isEmpty else {
            NSSound.beep()
            return
        }

        overlayVisible = true
        overlayController.show(
            targets: targets,
            onSelect: { target in
                WindowFocusService.focus(target)
            },
            onDismiss: { [weak self] in
                self?.overlayVisible = false
            }
        )
    }

    func refreshPermission() {
        accessibilityGranted = AccessibilityPermission.isGranted
        updateStatusItemImage()
    }

    func openAccessibilitySettings() {
        AccessibilityPermission.requestPrompt()
        AccessibilityPermission.openSettings()
    }

    @objc private func showLabelsMenuAction() {
        showOverlay()
    }

    @objc private func showSettingsMenuAction() {
        showSettingsWindow()
    }

    @objc private func refreshPermissionMenuAction() {
        refreshPermission()
    }

    @objc private func openAccessibilitySettingsMenuAction() {
        openAccessibilitySettings()
    }

    @objc private func quitMenuAction() {
        NSApp.terminate(nil)
    }

    @objc private func applicationDidResignActive() {
        if overlayController.isVisible {
            overlayController.dismiss()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshPermission()
        rebuildMenu(menu)
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "WindowJump")
            button.imagePosition = .imageOnly
            button.toolTip = "WindowJump"
        }

        let menu = NSMenu()
        menu.delegate = self
        rebuildMenu(menu)
        statusItem.menu = menu
        updateStatusItemImage()
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let statusItem = NSMenuItem(
            title: accessibilityGranted ? "Accessibility: Granted" : "Accessibility: Required",
            action: nil,
            keyEquivalent: ""
        )
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())

        let showItem = NSMenuItem(
            title: "Show Window Labels",
            action: #selector(showLabelsMenuAction),
            keyEquivalent: "v"
        )
        showItem.keyEquivalentModifierMask = [.command, .option]
        showItem.target = self
        showItem.isEnabled = accessibilityGranted
        menu.addItem(showItem)

        let settingsItem = NSMenuItem(
            title: "WindowJump Settings...",
            action: #selector(showSettingsMenuAction),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        let refreshItem = NSMenuItem(
            title: "Refresh Permission",
            action: #selector(refreshPermissionMenuAction),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        let accessibilityItem = NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettingsMenuAction),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit WindowJump",
            action: #selector(quitMenuAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func updateStatusItemImage() {
        guard let button = statusItem?.button else {
            return
        }

        let symbolName = accessibilityGranted ? "rectangle.3.group.fill" : "rectangle.3.group"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "WindowJump")
        button.contentTintColor = accessibilityGranted ? nil : .systemOrange
    }

    private func showSettingsWindow() {
        refreshPermission()

        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: ContentView(controller: self))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "WindowJump"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("WindowJumpSettings")
        window.delegate = self
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension WindowJumpController: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.settingsWindow = nil
        }
    }
}
