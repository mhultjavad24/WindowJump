//
//  WindowJumpApp.swift
//  WindowJump
//
//  Created by wake on 2026-06-29.
//

import SwiftUI

@main
struct WindowJumpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
