//
//  WindowScanner.swift
//  WindowJump
//
//  Created by wake on 2026-06-29.
//

import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class WindowScanner {
    private struct VisibleWindow {
        let windowNumber: Int
        let pid: pid_t
        let appName: String
        let title: String
        let cgFrame: CGRect
        let nsFrame: CGRect
        let labelPoint: CGPoint
    }

    private struct AXWindowInfo {
        let element: AXUIElement
        let frame: CGRect
        let title: String
    }

    func visibleWindows() -> [WindowTarget] {
        let visibleWindows = readVisibleCGWindows()
        var axCache: [pid_t: [AXWindowInfo]] = [:]
        var usedAXWindows = Set<CFHashCode>()
        var targets: [WindowTarget] = []

        for visibleWindow in visibleWindows {
            let axWindows = axCache[visibleWindow.pid] ?? readAXWindows(for: visibleWindow.pid)
            axCache[visibleWindow.pid] = axWindows

            guard let matchedAXWindow = bestAXMatch(
                for: visibleWindow,
                in: axWindows,
                usedAXWindows: usedAXWindows
            ) else {
                continue
            }

            usedAXWindows.insert(CFHash(matchedAXWindow.element))
            let label = Self.label(for: targets.count)
            targets.append(
                WindowTarget(
                    id: "\(visibleWindow.pid)-\(visibleWindow.windowNumber)",
                    label: label,
                    pid: visibleWindow.pid,
                    windowNumber: visibleWindow.windowNumber,
                    appName: visibleWindow.appName,
                    title: visibleWindow.title.isEmpty ? matchedAXWindow.title : visibleWindow.title,
                    frame: visibleWindow.nsFrame,
                    labelPoint: visibleWindow.labelPoint,
                    axWindow: matchedAXWindow.element
                )
            )
        }

        return targets
    }

    private func readVisibleCGWindows() -> [VisibleWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let screenBounds = Self.cgScreenBounds()
        var occludingFrames: [CGRect] = []
        var results: [VisibleWindow] = []

        for info in windowInfo {
            guard
                let layer = info[kCGWindowLayer as String] as? Int,
                let pidValue = info[kCGWindowOwnerPID as String] as? Int,
                let windowNumber = info[kCGWindowNumber as String] as? Int,
                let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
                let cgFrame = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else {
                continue
            }

            let pid = pid_t(pidValue)
            let alpha = (info[kCGWindowAlpha as String] as? Double) ?? 1

            defer {
                if layer == 0, alpha >= 0.95, cgFrame.width >= 1, cgFrame.height >= 1 {
                    occludingFrames.append(cgFrame)
                }
            }

            guard layer == 0, pidValue != Int(currentPID) else {
                continue
            }

            if alpha <= 0.01 {
                continue
            }

            guard cgFrame.width >= 60, cgFrame.height >= 40 else {
                continue
            }

            let visibleCoverage = Self.visibleCoverage(
                of: cgFrame,
                screenBounds: screenBounds,
                occludingFrames: occludingFrames
            )

            guard visibleCoverage.fraction >= Self.minimumVisibleFraction else {
                continue
            }

            guard let runningApplication = NSRunningApplication(processIdentifier: pid), !runningApplication.isHidden else {
                continue
            }

            let appName = (info[kCGWindowOwnerName as String] as? String) ?? runningApplication.localizedName ?? "Unknown"
            guard !Self.ignoredOwnerNames.contains(appName) else {
                continue
            }

            guard let nsFrame = Self.nsFrame(fromCGFrame: cgFrame) else {
                continue
            }

            guard let labelPoint = Self.nsPoint(fromCGPoint: visibleCoverage.labelPoint) else {
                continue
            }

            results.append(
                VisibleWindow(
                    windowNumber: windowNumber,
                    pid: pid,
                    appName: appName,
                    title: (info[kCGWindowName as String] as? String) ?? "",
                    cgFrame: cgFrame,
                    nsFrame: nsFrame,
                    labelPoint: labelPoint
                )
            )
        }

        return results
    }

    private static func visibleCoverage(
        of frame: CGRect,
        screenBounds: [CGRect],
        occludingFrames: [CGRect]
    ) -> (fraction: CGFloat, labelPoint: CGPoint) {
        let totalArea = frame.area
        guard totalArea > 0 else {
            return (0, CGPoint(x: frame.midX, y: frame.midY))
        }

        let bounds = screenBounds.isEmpty ? [frame] : screenBounds
        var visibleRegions = bounds
            .map { $0.intersection(frame) }
            .filter { !$0.isNull && !$0.isEmpty }

        for occludingFrame in occludingFrames where occludingFrame.intersects(frame) {
            visibleRegions = visibleRegions.flatMap { $0.subtracting(occludingFrame) }

            if visibleRegions.isEmpty {
                return (0, CGPoint(x: frame.midX, y: frame.midY))
            }
        }

        let visibleArea = visibleRegions.reduce(CGFloat.zero) { $0 + $1.area }
        let labelRegion = visibleRegions.max { $0.area < $1.area } ?? frame
        let labelPoint = CGPoint(x: labelRegion.midX, y: labelRegion.midY)

        return (visibleArea / totalArea, labelPoint)
    }

    private static func cgScreenBounds() -> [CGRect] {
        NSScreen.screens.compactMap { screen in
            guard
                let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            else {
                return nil
            }

            return CGDisplayBounds(displayID)
        }
    }

    private func readAXWindows(for pid: pid_t) -> [AXWindowInfo] {
        let appElement = AXUIElementCreateApplication(pid)
        guard let windows = Self.arrayAttribute(appElement, kAXWindowsAttribute as CFString) else {
            return []
        }

        return windows.compactMap { window in
            guard
                Self.stringAttribute(window, kAXRoleAttribute as CFString) == kAXWindowRole,
                Self.boolAttribute(window, kAXMinimizedAttribute as CFString) != true,
                let position = Self.pointAttribute(window, kAXPositionAttribute as CFString),
                let size = Self.sizeAttribute(window, kAXSizeAttribute as CFString),
                size.width >= 60,
                size.height >= 40
            else {
                return nil
            }

            return AXWindowInfo(
                element: window,
                frame: CGRect(origin: position, size: size),
                title: Self.stringAttribute(window, kAXTitleAttribute as CFString) ?? ""
            )
        }
    }

    private func bestAXMatch(
        for visibleWindow: VisibleWindow,
        in axWindows: [AXWindowInfo],
        usedAXWindows: Set<CFHashCode>
    ) -> AXWindowInfo? {
        let candidates = axWindows.filter { !usedAXWindows.contains(CFHash($0.element)) }
        guard !candidates.isEmpty else {
            return nil
        }

        let best = candidates
            .map { axWindow in
                (window: axWindow, score: Self.frameScore(visibleWindow.cgFrame, axWindow.frame))
            }
            .min { $0.score < $1.score }

        guard let best, best.score <= 180 else {
            if visibleWindow.title.isEmpty {
                return nil
            }

            return candidates.first {
                !$0.title.isEmpty && $0.title == visibleWindow.title
            }
        }

        return best.window
    }

    private static func frameScore(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.minX - rhs.minX)
            + abs(lhs.minY - rhs.minY)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }

    private static func nsFrame(fromCGFrame cgFrame: CGRect) -> CGRect? {
        let center = CGPoint(x: cgFrame.midX, y: cgFrame.midY)
        let screenAndBounds = screenAndCGBounds(containing: center, fallbackFrame: cgFrame)

        guard let screenAndBounds else {
            return nil
        }

        let screen = screenAndBounds.screen
        let cgBounds = screenAndBounds.cgBounds
        let x = screen.frame.minX + (cgFrame.minX - cgBounds.minX)
        let y = screen.frame.maxY - (cgFrame.minY - cgBounds.minY) - cgFrame.height

        return CGRect(x: x, y: y, width: cgFrame.width, height: cgFrame.height)
    }

    private static func nsPoint(fromCGPoint cgPoint: CGPoint) -> CGPoint? {
        let pointFrame = CGRect(origin: cgPoint, size: CGSize(width: 1, height: 1))
        let screenAndBounds = screenAndCGBounds(containing: cgPoint, fallbackFrame: pointFrame)

        guard let screenAndBounds else {
            return nil
        }

        let screen = screenAndBounds.screen
        let cgBounds = screenAndBounds.cgBounds
        let x = screen.frame.minX + (cgPoint.x - cgBounds.minX)
        let y = screen.frame.maxY - (cgPoint.y - cgBounds.minY)

        return CGPoint(x: x, y: y)
    }

    private static func screenAndCGBounds(
        containing point: CGPoint,
        fallbackFrame: CGRect
    ) -> (screen: NSScreen, cgBounds: CGRect)? {
        let screens = NSScreen.screens.compactMap { screen -> (screen: NSScreen, cgBounds: CGRect)? in
            guard
                let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            else {
                return nil
            }

            return (screen, CGDisplayBounds(displayID))
        }

        if let exactMatch = screens.first(where: { $0.cgBounds.contains(point) }) {
            return exactMatch
        }

        return screens
            .map { ($0.screen, $0.cgBounds, $0.cgBounds.intersection(fallbackFrame).width * $0.cgBounds.intersection(fallbackFrame).height) }
            .filter { $0.2 > 0 }
            .max { $0.2 < $1.2 }
            .map { ($0.0, $0.1) }
    }

    private static func label(for index: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

        if index < letters.count {
            return String(letters[index])
        }

        let adjustedIndex = index - letters.count
        let first = letters[(adjustedIndex / letters.count) % letters.count]
        let second = letters[adjustedIndex % letters.count]
        return String([first, second])
    }

    private static func arrayAttribute(_ element: AXUIElement, _ attribute: CFString) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }

        return value as? [AXUIElement]
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }

        return value as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }

        return value as? Bool
    }

    private static func pointAttribute(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = value as! AXValue
        guard
            AXValueGetType(axValue) == .cgPoint
        else {
            return nil
        }

        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private static func sizeAttribute(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = value as! AXValue
        guard
            AXValueGetType(axValue) == .cgSize
        else {
            return nil
        }

        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    private static let ignoredOwnerNames: Set<String> = [
        "Control Center",
        "Dock",
        "Notification Center",
        "SystemUIServer",
        "Window Server",
        "WindowJump"
    ]

    private static let minimumVisibleFraction = CGFloat(0.10)
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else {
            return 0
        }

        return width * height
    }

    func subtracting(_ rect: CGRect) -> [CGRect] {
        let overlap = intersection(rect)
        guard !overlap.isNull, !overlap.isEmpty else {
            return [self]
        }

        if overlap == self {
            return []
        }

        var pieces: [CGRect] = []

        if minY < overlap.minY {
            pieces.append(CGRect(x: minX, y: minY, width: width, height: overlap.minY - minY))
        }

        if overlap.maxY < maxY {
            pieces.append(CGRect(x: minX, y: overlap.maxY, width: width, height: maxY - overlap.maxY))
        }

        if minX < overlap.minX {
            pieces.append(CGRect(
                x: minX,
                y: overlap.minY,
                width: overlap.minX - minX,
                height: overlap.height
            ))
        }

        if overlap.maxX < maxX {
            pieces.append(CGRect(
                x: overlap.maxX,
                y: overlap.minY,
                width: maxX - overlap.maxX,
                height: overlap.height
            ))
        }

        return pieces.filter { !$0.isEmpty }
    }
}
