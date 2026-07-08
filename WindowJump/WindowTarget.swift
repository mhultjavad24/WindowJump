//
//  WindowTarget.swift
//  WindowJump
//
//  Created by wake on 2026-06-29.
//

import ApplicationServices
import CoreGraphics
import Foundation

struct WindowTarget: Identifiable {
    let id: String
    let label: String
    let pid: pid_t
    let windowNumber: Int
    let appName: String
    let title: String
    let frame: CGRect
    let labelPoint: CGPoint
    let axWindow: AXUIElement
}
