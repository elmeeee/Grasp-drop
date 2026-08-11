//
//  GraspTheme.swift
//  Grasp
//
//  Created by Elmee on 11/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import SwiftUI
import AppKit

struct GraspTheme {
    // Official Brand Colors from Grasp.svg / App Icon
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

    static func loadBarIconImage() -> NSImage? {
        if let image = NSImage(named: "BarIcon") {
            return image
        }
        let possiblePaths = [
            Bundle.main.path(forResource: "BarIcon@2x", ofType: "png"),
            Bundle.main.path(forResource: "BarIcon", ofType: "png"),
            (Bundle.main.resourcePath as NSString?)?.appendingPathComponent("BarIcon@2x.png"),
            (Bundle.main.resourcePath as NSString?)?.appendingPathComponent("BarIcon.png"),
            "/Users/phincon/Documents/Project/Grasp/BarIcon@2x.png",
            "/Users/phincon/Documents/Project/Grasp/BarIcon.png"
        ]
        for path in possiblePaths.compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: path), let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        return nil
    }
}

// Clean BarIcon Symbol matching Grasp_bar.svg / BarIcon@2x (NO Background Box!)
struct GraspBarIconView: View {
    var size: CGFloat = 28
    var useGradient: Bool = true

    var body: some View {
        Group {
            if let barImg = GraspTheme.loadBarIconImage() {
                Image(nsImage: barImg)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                ZStack {
                    // Outer Arc
                    GraspOuterArcShape()
                        .stroke(
                            useGradient ? AnyShapeStyle(GraspTheme.gradient) : AnyShapeStyle(Color.white),
                            style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round, lineJoin: .round)
                        )

                    // Inner Catch Arc
                    GraspInnerArcShape()
                        .stroke(
                            useGradient ? AnyShapeStyle(GraspTheme.accent.opacity(0.6)) : AnyShapeStyle(Color.white.opacity(0.6)),
                            style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round, lineJoin: .round)
                        )
                }
                .frame(width: size, height: size)
            }
        }
    }
}

// Vector Path for Outer C-Arc (matching Grasp_bar.svg)
struct GraspOuterArcShape: Shape {
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

// Vector Path for Inner Catch Arc (matching Grasp_bar.svg)
struct GraspInnerArcShape: Shape {
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
