//
//  RevEyeTheme.swift
//  RevEye
//
//  Created 12/03/2026 — UI overhaul
//  Single source of truth for all visual styling.

import SwiftUI

// MARK: - Colour Palette

struct REColors {
    // Backgrounds
    static let bgPrimary     = Color(hex: "0D1B2A")   // Deep navy
    static let bgSecondary   = Color(hex: "1B2838")   // Dark slate (cards)
    static let bgElevated    = Color(hex: "1E293B")   // Charcoal (inputs, surfaces)
    static let bgTertiary    = Color(hex: "253347")   // Slightly lighter (hover/press states)

    // Brand
    static let brandBlue     = Color(hex: "3B82F6")   // Electric blue — primary CTA
    static let brandBlueLight = Color(hex: "60A5FA")   // Secondary blue
    static let brandBlueDark = Color(hex: "1E3A5F")   // Subtle blue (borders, dividers)

    // Accent (the standout colour)
    static let accent        = Color(hex: "F59E0B")   // Amber/Orange
    static let accentLight   = Color(hex: "FBBF24")   // Lighter amber
    static let accentSubtle  = Color(hex: "F59E0B").opacity(0.15)

    // Confidence
    static let confHigh      = Color(hex: "10B981")   // Emerald green
    static let confMedium    = Color(hex: "F59E0B")   // Amber
    static let confLow       = Color(hex: "FB923C")   // Orange
    static let confNone      = Color(hex: "6B7280")   // Grey

    // Text
    static let textPrimary   = Color(hex: "F1F5F9")   // Off-white
    static let textSecondary = Color(hex: "94A3B8")   // Cool grey
    static let textMuted     = Color(hex: "64748B")   // Muted

    // Semantic
    static let success       = Color(hex: "10B981")
    static let warning       = Color(hex: "FBBF24")
    static let error         = Color(hex: "EF4444")

    // Helper: map ConfidenceTier → colour
    static func forTier(_ tier: ConfidenceTier) -> Color {
        switch tier {
        case .high:   return confHigh
        case .low:    return confMedium
        case .tooLow: return confNone
        }
    }
}

// MARK: - Typography Scale

struct REFonts {
    static let largeTitle  = Font.system(size: 28, weight: .bold)
    static let title       = Font.system(size: 22, weight: .bold)
    static let title3      = Font.system(size: 18, weight: .semibold)
    static let headline    = Font.system(size: 16, weight: .semibold)
    static let body        = Font.system(size: 15, weight: .regular)
    static let callout     = Font.system(size: 14, weight: .medium)
    static let caption     = Font.system(size: 12, weight: .regular)
    static let caption2    = Font.system(size: 11, weight: .regular)
    static let mono        = Font.system(size: 14, weight: .medium, design: .monospaced)
}

// MARK: - Spacing Scale

struct RESpacing {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 20
    static let xxl: CGFloat = 28
    static let xxxl: CGFloat = 40
}

// MARK: - Corner Radii

struct RERadius {
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 20
    static let pill: CGFloat = 100
}

// MARK: - Hex Colour Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8)  & 0xFF) / 255.0
        let b = Double(int         & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Reusable Button Styles

/// Primary action button — electric blue, full width
struct REPrimaryButton: ButtonStyle {
    var color: Color = REColors.brandBlue
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(REFonts.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, RESpacing.md)
            .background(isDisabled ? REColors.bgTertiary : color)
            .foregroundColor(isDisabled ? REColors.textMuted : .white)
            .cornerRadius(RERadius.md)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

/// Secondary / outlined button
struct RESecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(REFonts.callout)
            .frame(maxWidth: .infinity)
            .padding(.vertical, RESpacing.md)
            .background(REColors.bgElevated)
            .foregroundColor(REColors.textPrimary)
            .cornerRadius(RERadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: RERadius.md)
                    .stroke(REColors.brandBlueDark, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

/// Small pill-shaped button for inline actions
struct REPillButton: ButtonStyle {
    var color: Color = REColors.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(REFonts.caption)
            .padding(.horizontal, RESpacing.md)
            .padding(.vertical, RESpacing.sm)
            .background(color.opacity(configuration.isPressed ? 0.7 : 0.15))
            .foregroundColor(color)
            .cornerRadius(RERadius.pill)
    }
}

// MARK: - Reusable Card Modifier

struct RECardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(RESpacing.lg)
            .background(REColors.bgSecondary)
            .cornerRadius(RERadius.lg)
    }
}

extension View {
    func reCard() -> some View { modifier(RECardModifier()) }
}
