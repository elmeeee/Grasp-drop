//
//  WebShareModalView.swift
//  Grasp
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct WebShareModalView: View {
    @ObservedObject var transferManager: TransferManager
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var qrScale: CGFloat = 0.95
    @State private var pulseGlow = false

    private var activeURL: String {
        if !transferManager.webURL.isEmpty {
            return transferManager.webURL
        }
        return "http://127.0.0.1:7456"
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)

            VStack(spacing: 14) {
                // MARK: - Header Banner (Clean BarIcon Logo, No Background Box)
                HStack(spacing: 12) {
                    GraspBarIconView(size: 32, useGradient: true)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Instant Web Share")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)

                            Text("LIVE")
                                .font(.system(size: 9, weight: .black))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.12))
                                .foregroundColor(.primary)
                                .clipShape(Capsule())
                        }

                        Text("Share files from iPhone, Android, Windows & Linux")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
                .padding(.horizontal, 4)

                Divider()
                    .opacity(0.3)

                // MARK: - QR Code Showcase Card
                VStack(spacing: 12) {
                    ZStack {
                        // Ambient Glowing Aura (Glass Aura)
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.primary.opacity(pulseGlow ? 0.15 : 0.08))
                            .frame(width: 196, height: 196)
                            .blur(radius: pulseGlow ? 12 : 6)

                        // White QR Container Box
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 184, height: 184)
                            .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 5)

                        if let qrImage = generateQRCode(from: activeURL) {
                            ZStack {
                                Image(nsImage: qrImage)
                                    .resizable()
                                    .interpolation(.none)
                                    .scaledToFit()
                                    .frame(width: 154, height: 154)

                                // Center BarIcon Logo (Clean, No Background Box)
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 32, height: 32)
                                        .shadow(color: Color.black.opacity(0.15), radius: 3)

                                    GraspBarIconView(size: 22, useGradient: false)
                                }
                            }
                            .scaleEffect(qrScale)
                            .onAppear {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    qrScale = 1.0
                                }
                                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                                    pulseGlow = true
                                }
                            }
                        } else {
                            VStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.regular)
                                Text("Generating QR...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Supported Devices Badges
                    HStack(spacing: 6) {
                        Label("iOS", systemImage: "apple.logo")
                        Text("•")
                        Label("Android", systemImage: "phone")
                        Text("•")
                        Label("Windows", systemImage: "desktopcomputer")
                        Text("•")
                        Label("Linux", systemImage: "terminal")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(12)
                }

                // MARK: - Copy URL Bar
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)

                    Text(activeURL)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(activeURL, forType: .string)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            copied = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation {
                                copied = false
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                .font(.system(size: 11))
                            Text(copied ? "Copied!" : "Copy")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary)
                        .foregroundColor(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(6)
                        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

                // MARK: - How it Works Steps
                HStack(spacing: 12) {
                    StepItem(number: "1", title: "Same Wi-Fi", desc: "Connect device to Wi-Fi")
                    StepItem(number: "2", title: "Scan / Open", desc: "Scan QR or enter URL")
                    StepItem(number: "3", title: "Send Files", desc: "Drag & drop to transfer")
                }
                .padding(.top, 2)

                Spacer(minLength: 4)

                // MARK: - Footer
                HStack {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(GraspTheme.accent)
                            .frame(width: 6, height: 6)
                        Text("Web Server Active")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GraspTheme.primary)
                    .controlSize(.regular)
                }
                .padding(.bottom, 6)
            }
            .padding(18)
        }
        .frame(width: 410, height: 500)
    }

    private func generateQRCode(from string: String) -> NSImage? {
        guard !string.isEmpty else { return nil }
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        if let outputImage = filter.outputImage {
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return NSImage(cgImage: cgImage, size: NSSize(width: 160, height: 160))
            }
        }
        return nil
    }
}

struct StepItem: View {
    let number: String
    let title: String
    let desc: String

    var body: some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(GraspTheme.primary)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(desc)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
