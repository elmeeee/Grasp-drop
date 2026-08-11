//
//  SettingsView.swift
//  Grasp
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var transferManager: TransferManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [GraspTheme.primary, GraspTheme.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 36, height: 36)
                            .shadow(color: GraspTheme.primary.opacity(0.4), radius: 6, x: 0, y: 2)

                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Grasp Preferences")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("Configure device settings & hotkeys")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .opacity(0.4)

                // Scrollable Settings Content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Section 1: General
                        VStack(alignment: .leading, spacing: 8) {
                            Text("GENERAL SETTINGS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            VStack(spacing: 10) {
                                HStack {
                                    Label("Device Name", systemImage: "laptopcomputer")
                                        .font(.subheadline)
                                    Spacer()
                                    Text(transferManager.deviceName)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.primary.opacity(0.06))
                                        .cornerRadius(6)
                                }

                                Divider()
                                    .opacity(0.3)

                                HStack {
                                    Label("Save Location", systemImage: "folder.fill")
                                        .font(.subheadline)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text((transferManager.downloadPath as NSString).lastPathComponent)
                                            .font(.caption)
                                            .bold()
                                            .lineLimit(1)
                                        Text(transferManager.downloadPath)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Button("Browse...") {
                                        transferManager.selectDownloadFolder()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }

                        // Section 2: Automation & Shortcuts
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AUTOMATION & SHORTCUTS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            VStack(spacing: 10) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Global Shortcut")
                                            .font(.subheadline)
                                        Text("Open Grasp Menu Bar panel from anywhere")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text("⌘ ⇧ G")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(GraspTheme.primary.opacity(0.2))
                                        .foregroundColor(GraspTheme.accent)
                                        .cornerRadius(6)
                                }

                                Divider()
                                    .opacity(0.3)

                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Auto-Accept Incoming Transfers")
                                            .font(.subheadline)
                                        Text("Skip PIN consent prompt and save files instantly")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $transferManager.autoAccept)
                                        .toggleStyle(SwitchToggleStyle(tint: GraspTheme.primary))
                                }

                                Divider()
                                    .opacity(0.3)

                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Play Completion Sound")
                                            .font(.subheadline)
                                        Text("Play system chime when file transfer finishes")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $transferManager.soundEnabled)
                                        .toggleStyle(SwitchToggleStyle(tint: GraspTheme.primary))
                                }
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }
                    }
                }

                Divider()
                    .opacity(0.4)

                // Footer
                HStack {
                    Text("Grasp v2.0 • KaMy Studio")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GraspTheme.primary)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .frame(width: 440, height: 490)
    }
}
