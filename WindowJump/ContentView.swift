//
//  ContentView.swift
//  WindowJump
//
//  Created by wake on 2026-06-29.
//

import SwiftUI

struct ContentView: View {
    let controller: WindowJumpController
    @State private var accessibilityGranted: Bool

    init(controller: WindowJumpController) {
        self.controller = controller
        _accessibilityGranted = State(initialValue: controller.accessibilityGranted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("WindowJump")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Press Cmd+Opt+V to label visible windows. Click a label or type its letter to focus that window.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(accessibilityGranted ? .green : .orange)

                Text(accessibilityGranted ? "Accessibility permission granted" : "Accessibility permission required")
                    .fontWeight(.medium)
            }

            HStack(spacing: 10) {
                Button("Open Accessibility Settings") {
                    controller.openAccessibilitySettings()
                    refreshPermission()
                }

                Button("Show Window Labels") {
                    controller.showOverlay()
                    refreshPermission()
                }
                .disabled(!accessibilityGranted)
            }

            Text("If permission was just granted, choose Refresh Permission from the menu or reopen WindowJump.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 420)
        .onAppear(perform: refreshPermission)
    }

    private func refreshPermission() {
        controller.refreshPermission()
        accessibilityGranted = controller.accessibilityGranted
    }
}
