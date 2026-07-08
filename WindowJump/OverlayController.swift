//
//  OverlayController.swift
//  WindowJump
//
//  Created by wake on 2026-06-29.
//

import AppKit

@MainActor
final class OverlayController {
    private var overlayWindows: [OverlayWindow] = []
    private var onDismiss: (() -> Void)?
    private var onSelect: ((WindowTarget) -> Void)?

    var isVisible: Bool {
        !overlayWindows.isEmpty
    }

    func show(
        targets: [WindowTarget],
        onSelect: @escaping (WindowTarget) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        dismiss(notify: false)

        guard !targets.isEmpty else {
            onDismiss()
            return
        }

        self.onSelect = onSelect
        self.onDismiss = onDismiss

        for screen in NSScreen.screens {
            let screenTargets = targets.filter {
                screen.frame.insetBy(dx: -1, dy: -1).contains($0.labelPoint)
            }
            guard !screenTargets.isEmpty else {
                continue
            }

            let overlayWindow = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            overlayWindow.level = .screenSaver
            overlayWindow.backgroundColor = .clear
            overlayWindow.isOpaque = false
            overlayWindow.hasShadow = false
            overlayWindow.ignoresMouseEvents = false
            overlayWindow.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .ignoresCycle,
                .transient
            ]

            let overlayView = OverlayView(
                frame: CGRect(origin: .zero, size: screen.frame.size),
                screenFrame: screen.frame,
                screenTargets: screenTargets,
                allTargets: targets,
                onSelect: { [weak self] target in
                    self?.select(target)
                },
                onDismiss: { [weak self] in
                    self?.dismiss()
                }
            )

            overlayWindow.contentView = overlayView
            overlayWindow.makeFirstResponder(overlayView)
            overlayWindow.orderFrontRegardless()
            overlayWindows.append(overlayWindow)
        }

        if let firstWindow = overlayWindows.first {
            NSApp.activate(ignoringOtherApps: true)
            firstWindow.makeKeyAndOrderFront(nil)
        }
    }

    func dismiss() {
        dismiss(notify: true)
    }

    private func dismiss(notify: Bool) {
        for window in overlayWindows {
            window.orderOut(nil)
        }

        overlayWindows.removeAll()
        onSelect = nil
        let dismissHandler = onDismiss
        onDismiss = nil

        if notify {
            dismissHandler?()
        }
    }

    private func select(_ target: WindowTarget) {
        let selectHandler = onSelect
        dismiss(notify: true)
        selectHandler?(target)
    }
}

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

private struct BadgeDescriptor {
    let target: WindowTarget
    let frame: CGRect
}

private final class OverlayView: NSView {
    private let allTargets: [WindowTarget]
    private let onSelect: (WindowTarget) -> Void
    private let onDismiss: () -> Void
    private var typedLabel = ""
    private var pendingSelection: DispatchWorkItem?

    override var acceptsFirstResponder: Bool {
        true
    }

    init(
        frame: CGRect,
        screenFrame: CGRect,
        screenTargets: [WindowTarget],
        allTargets: [WindowTarget],
        onSelect: @escaping (WindowTarget) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.allTargets = allTargets
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.10).cgColor

        let badges = screenTargets.map { target in
            BadgeDescriptor(target: target, frame: Self.badgeFrame(for: target, in: screenFrame))
        }

        for badge in badges {
            addSubview(BadgeButton(descriptor: badge, onSelect: onSelect))
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        onDismiss()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDismiss()
            return
        }

        guard let characters = event.charactersIgnoringModifiers?.uppercased() else {
            return
        }

        for character in characters where character.isLetter {
            handleTypedCharacter(String(character))
        }
    }

    private func handleTypedCharacter(_ character: String) {
        pendingSelection?.cancel()

        let proposedLabel = typedLabel + character
        if applyLabelInput(proposedLabel) {
            return
        }

        typedLabel = ""
        _ = applyLabelInput(character)
    }

    @discardableResult
    private func applyLabelInput(_ label: String) -> Bool {
        let exactMatch = allTargets.first { $0.label == label }
        let hasLongerMatch = allTargets.contains { $0.label.hasPrefix(label) && $0.label != label }

        guard exactMatch != nil || hasLongerMatch else {
            return false
        }

        typedLabel = label

        if let exactMatch, !hasLongerMatch {
            onSelect(exactMatch)
            return true
        }

        if let exactMatch {
            let workItem = DispatchWorkItem { [weak self] in
                self?.onSelect(exactMatch)
            }
            pendingSelection = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
        } else {
            let workItem = DispatchWorkItem { [weak self] in
                self?.typedLabel = ""
            }
            pendingSelection = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
        }

        return true
    }

    private static func badgeFrame(for target: WindowTarget, in screenFrame: CGRect) -> CGRect {
        let width = max(CGFloat(34), CGFloat(target.label.count * 18 + 18))
        let height = CGFloat(34)
        let desiredX = target.labelPoint.x - width / 2
        let desiredY = target.labelPoint.y - height / 2
        let x = min(max(desiredX, screenFrame.minX + 8), screenFrame.maxX - width - 8)
        let y = min(max(desiredY, screenFrame.minY + 8), screenFrame.maxY - height - 8)

        return CGRect(
            x: x - screenFrame.minX,
            y: y - screenFrame.minY,
            width: width,
            height: height
        )
    }
}

private final class BadgeButton: NSButton {
    private let targetWindow: WindowTarget
    private let onSelect: (WindowTarget) -> Void

    init(descriptor: BadgeDescriptor, onSelect: @escaping (WindowTarget) -> Void) {
        self.targetWindow = descriptor.target
        self.onSelect = onSelect
        super.init(frame: descriptor.frame)

        title = descriptor.target.label
        target = self
        action = #selector(selectWindow)
        isBordered = false
        bezelStyle = .regularSquare
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 7
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        focusRingType = .none
        toolTip = Self.tooltip(for: descriptor.target)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        attributedTitle = NSAttributedString(string: descriptor.target.label, attributes: attributes)
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func selectWindow() {
        onSelect(targetWindow)
    }

    private static func tooltip(for target: WindowTarget) -> String {
        if target.title.isEmpty {
            return target.appName
        }

        return "\(target.appName): \(target.title)"
    }
}
