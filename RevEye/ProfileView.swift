//
//  ProfileView.swift
//  RevEye
//
//  Created 12/03/2026 — UI overhaul
//  Profile tab: quick stats, badges, audio library, logout.
//  Consolidates features that were previously spread across toolbar links.

import SwiftUI

struct ProfileView: View {
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var badgeService = BadgeService.shared

    private let db = DatabaseManager.shared
    @State private var detectionCount = 0
    @State private var audioCount = 0

    private var earnedBadges: [Badge] { badgeService.badges.filter { $0.earned } }

    var body: some View {
        NavigationView {
            ZStack {
                REColors.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: RESpacing.xl) {
                        // ── Stats Summary ──────────────────────────
                        statsCard

                        // ── Quick Badge Preview ────────────────────
                        badgePreview

                        // ── Menu Links ─────────────────────────────
                        menuSection

                        // ── Logout ─────────────────────────────────
                        logoutButton
                    }
                    .padding(RESpacing.lg)
                }
            }
            .navigationTitle("Profile")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                detectionCount = db.fetchAllDetections().count
                audioCount = db.audioSampleCount()
                badgeService.refreshBadges()
            }
        }
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        HStack(spacing: 0) {
            statItem(value: "\(detectionCount)", label: "Detections", icon: "car.fill")
            Divider()
                .frame(height: 40)
                .background(REColors.brandBlueDark)
            statItem(value: "\(earnedBadges.count)", label: "Badges", icon: "trophy.fill")
            Divider()
                .frame(height: 40)
                .background(REColors.brandBlueDark)
            statItem(value: "\(audioCount)", label: "Audio", icon: "waveform")
        }
        .reCard()
    }

    private func statItem(value: String, label: String, icon: String) -> some View {
        VStack(spacing: RESpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(REColors.accent)
            Text(value)
                .font(REFonts.title)
                .foregroundColor(REColors.textPrimary)
            Text(label)
                .font(REFonts.caption2)
                .foregroundColor(REColors.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Badge Preview

    private var badgePreview: some View {
        VStack(alignment: .leading, spacing: RESpacing.md) {
            HStack {
                Text("Badges")
                    .font(REFonts.headline)
                    .foregroundColor(REColors.textPrimary)
                Spacer()
                NavigationLink {
                    BadgesView()
                } label: {
                    Text("View All")
                        .font(REFonts.caption)
                        .foregroundColor(REColors.accent)
                }
            }

            // Progress bar
            HStack(spacing: RESpacing.sm) {
                Text("\(earnedBadges.count)/\(badgeService.badges.count)")
                    .font(REFonts.mono)
                    .foregroundColor(REColors.accent)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(REColors.bgElevated)
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [REColors.accent, REColors.accentLight],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: badgeService.badges.isEmpty ? 0 :
                                    geo.size.width * CGFloat(earnedBadges.count) / CGFloat(badgeService.badges.count),
                                height: 6
                            )
                    }
                }
                .frame(height: 6)
            }

            // Recent badges (last 4 earned)
            if !earnedBadges.isEmpty {
                HStack(spacing: RESpacing.md) {
                    ForEach(earnedBadges.suffix(4)) { badge in
                        VStack(spacing: 4) {
                            Text(badge.emoji)
                                .font(.system(size: 24))
                            Text(badge.title)
                                .font(REFonts.caption2)
                                .foregroundColor(REColors.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .reCard()
    }

    // MARK: - Menu Section

    private var menuSection: some View {
        VStack(spacing: 1) {
            NavigationLink {
                BadgesView()
            } label: {
                menuRow(icon: "trophy.fill", title: "All Badges", color: REColors.accent)
            }

            NavigationLink {
                AudioLibraryView()
            } label: {
                menuRow(icon: "waveform", title: "Audio Library", color: REColors.brandBlue)
            }
        }
        .cornerRadius(RERadius.md)
    }

    private func menuRow(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: RESpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: RERadius.sm)
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
            }
            Text(title)
                .font(REFonts.body)
                .foregroundColor(REColors.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(REColors.textMuted)
        }
        .padding(RESpacing.md)
        .background(REColors.bgSecondary)
    }

    // MARK: - Logout

    private var logoutButton: some View {
        Button {
            AuthService.shared.signOut()
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out")
            }
        }
        .buttonStyle(RESecondaryButton())
        .padding(.top, RESpacing.md)
    }
}
