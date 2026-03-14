//
//  RevEyeTheme.swift
//  RevEye
//
//  UI overhaul v5 — deeper red, sign up support

import SwiftUI

struct REColors {
    static let bg          = Color(hex: "0F1923")
    static let bgCard      = Color(hex: "172030")
    static let bgInput     = Color(hex: "1C2738")

    static let blue        = Color(hex: "3B82F6")
    static let blueLight   = Color(hex: "60A5FA")
    static let blueMuted   = Color(hex: "1D3557")

    static let accent      = Color(hex: "E8910D")

    // Display confidence colours (40% / 70% UI thresholds)
    static let confGreen   = Color(hex: "34D399")
    static let confOrange  = Color(hex: "E8910D")
    static let confRed     = Color(hex: "A63D3D")   // muted red for low confidence
    static let confNone    = Color(hex: "64748B")

    // Text
    static let text        = Color.white
    static let textSec     = Color(hex: "CBD5E1")
    static let textDim     = Color(hex: "7B8BA3")

    // Semantic
    static let success     = Color(hex: "34D399")
    static let error       = Color(hex: "EF4444")

    // Destructive — deeper, richer dark red
    static let destructive     = Color(hex: "7F2D2D")   // button background
    static let destructiveText = Color(hex: "E57373")   // text-only (warmer, less pink)

    static func displayConf(_ confidence: Double) -> Color {
        let pct = confidence * 100
        if pct >= 70 { return confGreen }
        if pct >= 40 { return confOrange }
        return confRed
    }

    static func forTier(_ tier: ConfidenceTier) -> Color {
        switch tier {
        case .high:   return confGreen
        case .low:    return confOrange
        case .tooLow: return confNone
        }
    }
}

struct REFont {
    static let title    = Font.system(size: 22, weight: .bold)
    static let heading  = Font.system(size: 17, weight: .semibold)
    static let body     = Font.system(size: 15, weight: .regular)
    static let label    = Font.system(size: 14, weight: .medium)
    static let caption  = Font.system(size: 13, weight: .regular)
    static let small    = Font.system(size: 12, weight: .regular)
    static let mono     = Font.system(size: 13, weight: .medium, design: .monospaced)
}

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

struct RESecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(REFont.label)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(REColors.bgInput)
            .foregroundColor(REColors.textSec)
            .cornerRadius(RE.r12)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

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

extension View {
    func reCard() -> some View {
        self.padding(RE.s16)
            .background(REColors.bgCard)
            .cornerRadius(RE.r16)
    }
}
