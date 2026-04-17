// BadgesView.swift
// RevEye
//
// Shows all badges the user can earn. Earned badges display in a 3-column
// grid. Locked badges show as a list with progress bars indicating how
// close the user is to earning each one. Tapping any badge opens a detail sheet.

import SwiftUI

struct BadgesView: View {
    @ObservedObject private var badgeService = BadgeService.shared
    private let db = DatabaseManager.shared

    // Split badges into earned and locked for display in separate sections
    private var earned: [Badge] { badgeService.badges.filter { $0.earned } }
    private var locked: [Badge] { badgeService.badges.filter { !$0.earned } }

    // 3-column grid layout for the earned badges section
    private let columns = [
        GridItem(.flexible(), spacing: RE.s12),
        GridItem(.flexible(), spacing: RE.s12),
        GridItem(.flexible(), spacing: RE.s12)
    ]

    @State private var selectedBadge: Badge?
    // Local data used to calculate progress towards locked badges
    @State private var detections: [Detection] = []
    @State private var audioCount = 0
    @State private var streak = 0
    @State private var shareCount = 0

    private var uniqueMakes: Int {
        Set(detections.compactMap { $0.vehicleLabel.components(separatedBy: " ").first }).count
    }

    var body: some View {
        ZStack {
            REColors.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: RE.s24) {

                    progressHeader

                    if !earned.isEmpty {
                        sectionHeader("Earned", count: earned.count, color: REColors.accent)
                        
                        // Earned badges in a 3-column grid
LazyVGrid(columns: columns, spacing: RE.s12) {
                            ForEach(earned) { badge in
                                badgeCell(badge, unlocked: true)
                                    .onTapGesture { selectedBadge = badge }
                            }
                        }
                    }

                    if !locked.isEmpty {
                        sectionHeader("Locked", count: locked.count, color: REColors.textDim)
                        
LazyVGrid(columns: columns, spacing: RE.s12) {
                            
                            // Each locked badge shows how close the user is to earning it
ForEach(locked) { badge in
                                badgeCell(badge, unlocked: false)
                                    .onTapGesture { selectedBadge = badge }
                            }
                        }
                    }

                    Spacer().frame(height: RE.s48)
                }
                .padding(.horizontal, RE.s16)
                .padding(.top, RE.s8)
            }
        }
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            badgeService.refreshBadges()
            detections = db.fetchAllDetections()
            audioCount = db.audioSampleCount()
            streak = db.currentStreak()
            shareCount = badgeService.shareCount
        }
        .sheet(item: $selectedBadge) { badge in
            badgeDetail(badge)
        }
    }

    // Progress Header

    // Header card showing total earned count and a percentage ring
    private var progressHeader: some View {
        VStack(spacing: RE.s12) {
            HStack {
                VStack(alignment: .leading, spacing: RE.s4) {
                    Text("\(earned.count) of \(badgeService.badges.count)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(REColors.text)
                    Text("badges earned")
                        .font(REFont.caption)
                        .foregroundColor(REColors.textDim)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(REColors.bgInput, lineWidth: 4)
                        .frame(width: 52, height: 52)
                    Circle()
                        .trim(from: 0, to: badgeService.badges.isEmpty ? 0 :
                                CGFloat(earned.count) / CGFloat(badgeService.badges.count))
                        .stroke(REColors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(-90))
                    Text("\(pct)%")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(REColors.accent)
                }
            }
        }
        .padding(RE.s16)
        .background(REColors.bgCard)
        .cornerRadius(RE.r12)
    }

    private var pct: Int {
        badgeService.badges.isEmpty ? 0 : Int(Double(earned.count) / Double(badgeService.badges.count) * 100)
    }

    // Section Header

    // Section divider with title and count badge
    private func sectionHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: RE.s8) {
            Text(title)
                .font(REFont.heading)
                .foregroundColor(REColors.text)
            Text("\(count)")
                .font(REFont.small)
                .foregroundColor(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.15))
                .cornerRadius(100)
            Spacer()
        }
    }

    // Badge Cell

    // Grid cell for an earned badge - shows emoji and title
    private func badgeCell(_ badge: Badge, unlocked: Bool) -> some View {
        VStack(spacing: RE.s4) {
            Text(badge.emoji)
                .font(.system(size: 28))
                .grayscale(unlocked ? 0 : 0.8)
                .opacity(unlocked ? 1 : 0.4)

            Text(badge.title)
                .font(REFont.small)
                .foregroundColor(unlocked ? REColors.text : REColors.textDim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if !unlocked, let progress = badgeProgress(badge) {
                VStack(spacing: 2) {
                    
            // Overall progress bar showing percentage of badges earned
GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(REColors.bgInput).frame(height: 3)
                            Capsule().fill(REColors.accent)
                                .frame(width: g.size.width * CGFloat(progress.current) / CGFloat(max(progress.target, 1)), height: 3)
                        }
                    }
                    .frame(height: 3)
                    Text("\(progress.current)/\(progress.target)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(REColors.textDim)
                }
                .padding(.horizontal, RE.s4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, RE.s8)
        .padding(.horizontal, RE.s4)
        .background(unlocked ? REColors.bgCard : REColors.bgInput.opacity(0.5))
        .cornerRadius(RE.r12)
        .overlay(
            RoundedRectangle(cornerRadius: RE.r12)
                .stroke(unlocked ? REColors.accent.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    // Progress Calculation

    // Simple struct to hold current/target values for progress calculation
private struct BadgeProgress {
        let current: Int
        let target: Int
    }

    // Maps each badge ID to its progress values based on the user's current
    // detection count, audio count, streak, share count, etc.
    private func badgeProgress(_ badge: Badge) -> BadgeProgress? {
        let count = detections.count
                // Map each badge ID to its current/target progress based on user data
switch badge.id {
        case "detections_5":    return BadgeProgress(current: min(count, 5), target: 5)
        case "detections_25":   return BadgeProgress(current: min(count, 25), target: 25)
        case "detections_50":   return BadgeProgress(current: min(count, 50), target: 50)
        case "detections_100":  return BadgeProgress(current: min(count, 100), target: 100)

        case "unique_makes_5":  return BadgeProgress(current: min(uniqueMakes, 5), target: 5)
        case "unique_makes_10": return BadgeProgress(current: min(uniqueMakes, 10), target: 10)
        case "unique_makes_15": return BadgeProgress(current: min(uniqueMakes, 15), target: 15)

        case "audio_5":         return BadgeProgress(current: min(audioCount, 5), target: 5)
        case "audio_10":        return BadgeProgress(current: min(audioCount, 10), target: 10)

        case "streak_3":        return BadgeProgress(current: min(streak, 3), target: 3)
        case "streak_7":        return BadgeProgress(current: min(streak, 7), target: 7)

        case "shares_5":        return BadgeProgress(current: min(shareCount, 5), target: 5)

        default: return nil
        }
    }

    // Badge Detail Sheet

    // Detail sheet shown when tapping any badge. Shows large emoji, title,
    // description, earned date or progress bar, and a share button for earned badges.
    private func badgeDetail(_ badge: Badge) -> some View {
        ZStack {
            REColors.bg.ignoresSafeArea()

            VStack(spacing: RE.s24) {
                Spacer().frame(height: RE.s16)

                ZStack {
                    Circle()
                        .fill(badge.earned ? REColors.accent.opacity(0.12) : REColors.bgInput)
                        .frame(width: 100, height: 100)
                    Text(badge.emoji)
                        .font(.system(size: 48))
                        .grayscale(badge.earned ? 0 : 0.8)
                        .opacity(badge.earned ? 1 : 0.5)
                }

                Text(badge.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(REColors.text)

                Text(badge.description)
                    .font(REFont.body)
                    .foregroundColor(REColors.textSec)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RE.s32)

                if badge.earned {
                    if let earnedAt = badge.earnedAt {
                        HStack(spacing: RE.s8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(REColors.confGreen)
                            Text("Earned \(formatDate(earnedAt))")
                                .font(REFont.caption)
                                .foregroundColor(REColors.textDim)
                        }
                        .padding(.horizontal, RE.s16)
                        .padding(.vertical, RE.s8)
                        .background(REColors.confGreen.opacity(0.1))
                        .cornerRadius(100)
                    }

                    ShareLink(
                        item: "I just earned the \"\(badge.title)\" badge on RevEye! \(badge.emoji) \(badge.description). Think you can keep up?",
                        preview: SharePreview("RevEye Badge: \(badge.title)")
                    ) {
                        HStack(spacing: RE.s8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Badge")
                        }
                    }
                    .buttonStyle(REPrimaryButton(color: REColors.accent))
                    .padding(.horizontal, RE.s32)
                } else {
                    if let progress = badgeProgress(badge) {
                        
                        // Locked badges as a list with progress bars showing how close
                        // the user is to earning each one
VStack(spacing: RE.s8) {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(REColors.bgInput).frame(height: 6)
                                    Capsule().fill(REColors.accent)
                                        .frame(width: g.size.width * CGFloat(progress.current) / CGFloat(max(progress.target, 1)), height: 6)
                                }
                            }
                            .frame(height: 6)
                            .padding(.horizontal, RE.s32)

                            Text("\(progress.current) of \(progress.target)")
                                .font(REFont.mono)
                                .foregroundColor(REColors.accent)
                        }
                    } else {
                        HStack(spacing: RE.s8) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(REColors.textDim)
                            Text("Not yet earned")
                                .font(REFont.caption)
                                .foregroundColor(REColors.textDim)
                        }
                        .padding(.horizontal, RE.s16)
                        .padding(.vertical, RE.s8)
                        .background(REColors.bgInput)
                        .cornerRadius(100)
                    }
                }

                Spacer()
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // Formats an ISO 8601 timestamp into a readable date
    private func formatDate(_ iso: String) -> String {
        let p = ISO8601DateFormatter()
        guard let d = p.date(from: iso) else { return iso }
        let f = DateFormatter(); f.dateStyle = .medium
        return f.string(from: d)
    }
}
