//
//  MenuBarView.swift
//  Grasp
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

struct MenuBarView: View {
    @ObservedObject var transferManager: TransferManager
    @State private var showingWebModal = false
    @State private var showingSettingsModal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Header Card (Clean BarIcon Logo, No Background Box)
            HStack(spacing: 12) {
                GraspBarIconView(size: 28, useGradient: true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("Grasp")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .lineLimit(1)

                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(transferManager.deviceName)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Menu {
                        Button(action: { transferManager.setVisibility(.everyone) }) {
                            Label("Visible to Everyone", systemImage: "person.3.fill")
                        }
                        Button(action: { transferManager.setVisibility(.off) }) {
                            Label("Receiver Off", systemImage: "eye.slash.fill")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(transferManager.visibilityMode.statusColor)
                                .frame(width: 6, height: 6)
                            Text(transferManager.visibilityMode.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                }

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { transferManager.isRunning },
                        set: { transferManager.toggleEngine($0) }
                    )
                )
                .toggleStyle(SwitchToggleStyle(tint: .blue))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )

            // MARK: - Incoming Transfer Request Card with PIN Verification
            if let pending = transferManager.currentPendingTransfer {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 28, height: 28)
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.blue)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("INCOMING QUICK SHARE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.blue)
                            Text(pending.deviceName)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }

                        Spacer()
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(pending.fileName)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                            Text("\(pending.formattedSize) • \(pending.fileCount) file(s)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    // PIN Verification Badge (Crucial for Quick Share Security)
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SECURITY PIN VERIFICATION")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(pending.pinCode)
                                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                                .foregroundColor(.primary)
                                .tracking(3)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.green)
                            Text("Verify on sender device")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.35), lineWidth: 1))

                    // Accept & Decline Action Buttons
                    HStack(spacing: 8) {
                        Button(action: {
                            transferManager.declinePendingTransferByID(pending.id)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                Text("Decline")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)

                        Button(action: {
                            transferManager.acceptPendingTransferByID(pending.id)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Accept")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(LinearGradient(colors: [.blue.opacity(0.6), .cyan.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                        )
                )
                .shadow(color: Color.blue.opacity(0.25), radius: 8, x: 0, y: 4)
            }

            // MARK: - Active Live Transfer Progress Card
            if let active = transferManager.activeTransfer {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.blue)
                        Text("RECEIVING FILE...")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.blue)
                        Spacer()
                        Text(active.formattedSpeed)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Text(active.fileName)
                        .font(.caption)
                        .bold()
                        .lineLimit(1)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * active.progressFraction, height: 6)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text(active.formattedSize)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: { transferManager.cancelActiveTransfer() }) {
                            Text("Cancel")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.3), lineWidth: 1))
                .cornerRadius(12)
            }

            // MARK: - Outbound File Dropzone & Quick Actions Bar
            VStack(spacing: 8) {
                // Primary Send File Action
                Button(action: { transferManager.selectAndSendFiles() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Send / Share Files...")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .help("Pick file(s) to publish on Web Hub & Quick Share")

                HStack(spacing: 8) {
                    Button(action: { showingWebModal = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "qrcode")
                            Text("Instant Web QR")
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: { transferManager.openDownloadFolder() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("Downloads")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button(action: { showingSettingsModal = true }) {
                        Image(systemName: "gearshape")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("Settings")
                }
            }

            Divider()
                .opacity(0.4)

            // MARK: - Transfers History Section
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("RECENT TRANSFERS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    Spacer()

                    if !transferManager.recentTransfers.isEmpty {
                        Button(action: { transferManager.clearHistory() }) {
                            Text("Clear")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if transferManager.recentTransfers.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "tray.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.secondary.opacity(0.6))
                            Text("Ready to receive files from Quick Share or Web")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 16)
                        Spacer()
                    }
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(10)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(transferManager.recentTransfers) { item in
                                Button(action: {
                                    transferManager.openFileInFinder(item.filePath)
                                }) {
                                    HStack(spacing: 10) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(item.iconColor.opacity(0.15))
                                                .frame(width: 30, height: 30)
                                            Image(systemName: item.iconName)
                                                .font(.system(size: 13))
                                                .foregroundColor(item.iconColor)
                                        }

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(item.fileName)
                                                .font(.caption)
                                                .bold()
                                                .lineLimit(1)
                                            HStack(spacing: 4) {
                                                Text("\(item.formattedSize) • \(item.formattedTime)")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                if item.isWebUpload {
                                                    Text("• Web")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(.blue)
                                                }
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: "arrow.forward.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(6)
                                    .background(Color.primary.opacity(0.05))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .help("Show in Finder")
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                }
            }

            Divider()
                .opacity(0.4)

            // MARK: - Footer Section (Clean & Minimalist)
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(transferManager.isRunning ? Color.green : Color.gray)
                        .frame(width: 7, height: 7)
                        .shadow(color: transferManager.isRunning ? Color.green.opacity(0.6) : Color.clear, radius: 4)

                    Text(transferManager.isRunning ? "Receiver Active" : "Receiver Off")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Quit") {
                    transferManager.stopEngine()
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.red)
            }
        }
        .padding(14)
        .frame(width: 330, alignment: .top)
        .background(
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.25), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .sheet(isPresented: $showingWebModal) {
            WebShareModalView(transferManager: transferManager)
        }
        .sheet(isPresented: $showingSettingsModal) {
            SettingsView(transferManager: transferManager)
        }
    }
}
