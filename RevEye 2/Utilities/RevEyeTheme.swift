// RevEyeTheme.swift
// RevEye
//
// Centralised design system for the app. Defines all colours, fonts, spacing
// constants, and reusable button styles so the UI stays consistent across
// every screen.

import SwiftUI

// All colours used across the app, defined as static constants.
// Using hex values keeps them consistent with the Figma/design spec.
struct REColors {
    // Background layers, darkest to lightest.
    static let bg          = Color(hex: "0F1923")
    static let bgCard      = Color(hex: "172030")
    static let bgInput     = Color(hex: "1C2738")

    // Primary blue for buttons and interactive elements.
    static let blue        = Color(hex: "3B82F6")
    static let blueLight   = Color(hex: "60A5FA")
    // Orange accent for highlights, streaks, and the tab bar tint.
    static let accent      = Color(hex: "E8910D")

    // Confidence tiers: green (high) / orange (medium) / red (low).
    static let confGreen   = Color(hex: "34D399")
    static let confOrange  = Color(hex: "E8910D")
    static let confRed     = Color(hex: "A63D3D")
    static let confNone    = Color(hex: "64748B")

    // Text hierarchy: bright white for primary, greys for secondary/dim.
    static let text        = Color.white
    static let textSec     = Color(hex: "CBD5E1")
    static let textDim     = Color(hex: "7B8BA3")

    static let success     = Color(hex: "34D399")
    static let error       = Color(hex: "EF4444")

    // Destructive actions (delete buttons, error states).
    static let destructive     = Color(hex: "7F2D2D")
    static let destructiveText = Color(hex: "E57373")

    // Picks the tier colour for a confidence score in [0, 1].
    static func displayConf(_ confidence: Double) -> Color {
        let pct = confidence * 100
        if pct >= 70 { return confGreen }
        if pct >= 40 { return confOrange }
        return confRed
    }
}
// Font sizes used across the app. Defined here so they can be changed in one place.
struct REFont {
    static let title    = Font.system(size: 22, weight: .bold)
    static let heading  = Font.system(size: 17, weight: .semibold)
    static let body     = Font.system(size: 15, weight: .regular)
    static let label    = Font.system(size: 14, weight: .medium)
    static let caption  = Font.system(size: 13, weight: .regular)
    static let small    = Font.system(size: 12, weight: .regular)
    static let mono     = Font.system(size: 13, weight: .medium, design: .monospaced)
}
// Spacing and corner radius constants. Using these instead of magic numbers
// keeps padding and rounding consistent throughout the app.
struct RE {
    static let s4:  CGFloat = 4
    static let s8:  CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let s48: CGFloat = 48
    static let r8:  CGFloat = 8
    static let r12: CGFloat = 12
    static let r16: CGFloat = 16
}
// Helper to create a SwiftUI Color from a hex string like "0F1923"
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red:   Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8)  & 0xFF) / 255,
            blue:  Double(int         & 0xFF) / 255
        )
    }
}
// Reusable button styles so every button in the app looks consistent
struct REPrimaryButton: ButtonStyle {
    var color: Color = REColors.blue
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(REFont.heading)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color)
            .foregroundColor(.white)
            .cornerRadius(RE.r12)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
// Destructive button style - dark red background for delete/danger actions
struct REDestructiveButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(REFont.heading)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(REColors.destructive)
            .foregroundColor(.white)
            .cornerRadius(RE.r12)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
// Convenience modifier that applies the standard card background and rounding
extension View {
    func reCard() -> some View {
        self.padding(RE.s16)
            .background(REColors.bgCard)
            .cornerRadius(RE.r16)
    }
}
