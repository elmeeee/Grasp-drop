//
//  OtterTheme.swift
//  Otter
//
//  Created by Elmee on 11/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import SwiftUI
import AppKit

struct OtterTheme {
    // Official Brand Colors from Otter.svg / App Icon
    static let primary = Color(red: 79/255, green: 70/255, blue: 229/255) // #4F46E5 (Indigo)
    static let accent = Color(red: 6/255, green: 182/255, blue: 212/255)  // #06B6D4 (Cyan)
    static let purpleAccent = Color(red: 139/255, green: 92/255, blue: 246/255) // #8B5CF6

    static var gradient: LinearGradient {
        LinearGradient(
            colors: [primary, accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var reverseGradient: LinearGradient {
        LinearGradient(
            colors: [accent, primary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The Otter app icon, shown in the panel header and sheets. Uses the
    /// full-resolution artwork (not the 16 px menu bar glyph) so it stays sharp.
    static func loadBarIconImage() -> NSImage? {
        if let image = NSImage(named: "otter-app-256") {
            return image
        }
        let candidates = [
            Bundle.main.url(forResource: "otter-app-256", withExtension: "png"),
            Bundle.main.resourceURL?.appendingPathComponent("otter-app-256.png"),
        ]
        for url in candidates.compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: url.path), let img = NSImage(contentsOf: url) {
                return img
            }
        }
        return nil
    }
}

// Clean BarIcon Symbol matching Otter_bar.svg / BarIcon@2x (NO Background Box!)
struct OtterBarIconView: View {
    var size: CGFloat = 28
    var useGradient: Bool = true

    var body: some View {
        Group {
            if let barImg = OtterTheme.loadBarIconImage() {
                Image(nsImage: barImg)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                ZStack {
                    // Outer Arc
                    OtterOuterArcShape()
                        .stroke(
                            useGradient ? AnyShapeStyle(OtterTheme.gradient) : AnyShapeStyle(Color.white),
                            style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round, lineJoin: .round)
                        )

                    // Inner Catch Arc
                    OtterInnerArcShape()
                        .stroke(
                            useGradient ? AnyShapeStyle(OtterTheme.accent.opacity(0.6)) : AnyShapeStyle(Color.white.opacity(0.6)),
                            style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round, lineJoin: .round)
                        )
                }
                .frame(width: size, height: size)
            }
        }
    }
}

// Vector Path for Outer C-Arc (matching Otter_bar.svg)
struct OtterOuterArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 13.5 * sx, y: 7.5 * sy))
        p.addCurve(
            to: CGPoint(x: 19 * sx, y: 13 * sy),
            control1: CGPoint(x: 16.538 * sx, y: 7.5 * sy),
            control2: CGPoint(x: 19 * sx, y: 9.962 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 13.5 * sx, y: 18.5 * sy),
            control1: CGPoint(x: 19 * sx, y: 16.038 * sy),
            control2: CGPoint(x: 16.538 * sx, y: 18.5 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 8 * sx, y: 13 * sy),
            control1: CGPoint(x: 10.462 * sx, y: 18.5 * sy),
            control2: CGPoint(x: 8 * sx, y: 16.038 * sy)
        )
        p.addLine(to: CGPoint(x: 15 * sx, y: 13 * sy))
        return p
    }
}

// Vector Path for Inner Catch Arc (matching Otter_bar.svg)
struct OtterInnerArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 10.5 * sx, y: 16.5 * sy))
        p.addCurve(
            to: CGPoint(x: 5 * sx, y: 11 * sy),
            control1: CGPoint(x: 7.462 * sx, y: 16.5 * sy),
            control2: CGPoint(x: 5 * sx, y: 14.038 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 10.5 * sx, y: 5.5 * sy),
            control1: CGPoint(x: 5 * sx, y: 7.962 * sy),
            control2: CGPoint(x: 7.462 * sx, y: 5.5 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 16 * sx, y: 11 * sy),
            control1: CGPoint(x: 13.538 * sx, y: 5.5 * sy),
            control2: CGPoint(x: 16 * sx, y: 7.962 * sy)
        )
        return p
    }
}
