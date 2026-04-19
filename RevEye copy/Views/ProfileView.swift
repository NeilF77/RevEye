// ProfileView.swift
// RevEye
//
// The Profile tab. Shows the user's stats (total scans, unique models, makes,
// audio samples), current streak, a link to all badges with a progress bar,
// highlights, and the audio dataset research link.

import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    // Observe badge service for live badge count updates
    @ObservedObject private var badgeService = BadgeService.shared
    private let db = DatabaseManager.shared

    @State private var detections: [Detection] = []
    @State private var audioCount = 0

    // Tracks the earned badge count the user last saw on the profile screen.
    // When new badges are earned, the difference shows as a notification dot.
    @AppStorage("profileLastSeenBadgeCount") private var lastSeenBadgeCount: Int = 0

    private var newBadgeCount: Int {
        max(0, earned.count - lastSeenBadgeCount)
    }

    private var earned: [Badge] { badgeService.badges.filter { $0.earned } }
    private var locked: [Badge] { badgeService.badges.filter { !$0.earned } }

    // Calculates the user's most-scanned car brand
    private var favouriteMake: String {
        let makes = detections
            .filter { $0.vehicleLabel != "Unknown Vehicle" }
            .compactMap { $0.vehicleLabel.components(separatedBy: " ").first }
        let counted = Dictionary(grouping: makes, by: { $0 }).mapValues { $0.count }
        return counted.max(by: { $0.value < $1.value })?.key ?? "—"
    }

    // Counts how many different car brands the user has scanned
    private var uniqueMakes: Int {
        Set(detections
            .filter { $0.vehicleLabel != "Unknown Vehicle" }
            .compactMap { $0.vehicleLabel.components(separatedBy: " ").first }).count
    }

    private var uniqueModels: Int {
        Set(detections.map { $0.vehicleLabel }).count
    }

    // Finds the detection with the highest confidence score
    private var bestDetection: Detection? {
        detections.max(by: { $0.confidence < $1.confidence })
    }

    // Current consecutive day streak from the database
    private var streak: Int { db.currentStreak() }

    private var userName: String {
        Auth.auth().currentUser?.displayName ?? "Driver"
    }

    var body: some View {
        NavigationView {
            ZStack {
                REColors.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    
                    // Profile layout: header, streak, badges, stats, highlights, links
VStack(spacing: RE.s24) {
                        userHeader
                        streakCard
                        badgesCard
                        statsGrid
                        highlightsSection
                        audioDatasetCard
                        menuSection
                        Spacer().frame(height: RE.s32)
                    }
                    .padding(.horizontal, RE.s16)
                    .padding(.top, RE.s8)
                }
            }
            .navigationTitle("Profile")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: {
                        Image(systemName: "gearshape").foregroundColor(REColors.textSec)
                    }
                }
            }
                        // Load all data when the profile tab appears
.onAppear {
                detections = db.fetchAllDetections()
                audioCount = db.audioSampleCount()
                badgeService.refreshBadges()
            }
        }
    }

    // User Header

    // Top section showing avatar initial, display name, and summary stats
    private var userHeader: some View {
        HStack(spacing: RE.s16) {
            ZStack {
                Circle().fill(REColors.blue.opacity(0.2)).frame(width: 56, height: 56)
                Text(String(userName.prefix(1)).uppercased())
                    .font(.system(size: 22, weight: .bold)).foregroundColor(REColors.blue)
            }
            VStack(alignment: .leading, spacing: RE.s4) {
                Text(userName).font(REFont.heading).foregroundColor(REColors.text)
                Text("\(detections.count) scans · \(earned.count) badges")
                    .font(REFont.caption).foregroundColor(REColors.textDim)
            }
            Spacer()
        }
        .padding(.top, RE.s8)
    }

    // Streak Card

    // Streak display card - glows orange when streak is 3+ days
    private var streakCard: some View {
        HStack(spacing: RE.s16) {
            Image(systemName: "flame.fill")
                .font(.system(size: 24))
                .foregroundColor(streak >= 3 ? REColors.accent : REColors.textDim)
            VStack(alignment: .leading, spacing: 2) {
                Text(streak > 0 ? "\(streak) day streak" : "No streak yet")
                    .font(REFont.heading).foregroundColor(REColors.text)
                Text(streak > 0 ? "Keep scanning daily to grow your streak!" : "Scan a vehicle today to start one")
                    .font(REFont.small).foregroundColor(REColors.textDim)
            }
            Spacer()
            if streak > 0 {
                Text("\(streak)").font(.system(size: 28, weight: .bold)).foregroundColor(REColors.accent)
            }
        }
        .padding(RE.s16)
        .background(streak >= 3 ? REColors.accent.opacity(0.08) : REColors.bgCard)
        .cornerRadius(RE.r12)
        .overlay(RoundedRectangle(cornerRadius: RE.r12).stroke(streak >= 3 ? REColors.accent.opacity(0.2) : Color.clear, lineWidth: 1))
    }

    // Badges Card (simple row + progress bar)

    // Navigation card linking to the full badges screen.
    // Shows trophy icon, earned/total count, notification dot for new badges,
    // and a progress bar. Styled to look obviously tappable.
    private var badgesCard: some View {
        VStack(spacing: RE.s12) {
            NavigationLink { BadgesView().onAppear { lastSeenBadgeCount = earned.count } } label: {
                HStack(spacing: RE.s12) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 18))
                            .foregroundColor(REColors.accent)

                        // Red notification dot with count when new badges are available
                        if newBadgeCount > 0 {
                            Text("\(newBadgeCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(Color.red)
                                .clipShape(Circle())
                                .offset(x: 6, y: -6)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("All Badges")
                            .font(REFont.heading)
                            .foregroundColor(REColors.text)
                        Text("Tap to view your collection")
                            .font(REFont.small)
                            .foregroundColor(REColors.textDim)
                    }
                    Spacer()
                    Text("\(earned.count)/\(badgeService.badges.count)")
                        .font(REFont.mono)
                        .foregroundColor(REColors.accent)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(REColors.accent)
                }
                .padding(RE.s16)
                .background(REColors.bgCard)
                .cornerRadius(RE.r12)
                .overlay(RoundedRectangle(cornerRadius: RE.r12).stroke(REColors.accent.opacity(0.35), lineWidth: 1.5))
            }

            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(REColors.bgInput).frame(height: 4)
                    Capsule().fill(REColors.accent)
                        .frame(width: badgeService.badges.isEmpty ? 0 :
                            g.size.width * CGFloat(earned.count) / CGFloat(badgeService.badges.count), height: 4)
                }
            }.frame(height: 4)

            if !earned.isEmpty {
                HStack(spacing: RE.s12) {
                    ForEach(earned.suffix(4)) { b in
                        VStack(spacing: RE.s4) {
                            Text(b.emoji).font(.system(size: 22))
                            Text(b.title).font(REFont.small).foregroundColor(REColors.textDim).lineLimit(1)
                        }.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // Stats Grid

    // 2x2 grid of stat cards (total scans, unique models, makes, audio)
    private var statsGrid: some View {
        VStack(spacing: RE.s8) {
            HStack(spacing: RE.s8) {
                statCard("\(detections.count)", "Total Scans", "car.fill", REColors.blue)
                statCard("\(uniqueModels)", "Unique Models", "globe", REColors.accent)
            }
            HStack(spacing: RE.s8) {
                statCard("\(uniqueMakes)", "Makes Found", "flag.checkered", REColors.blueLight)
                statCard("\(audioCount)", "Audio Samples", "waveform", REColors.confGreen)
            }
        }
    }

    // Reusable stat card showing an icon, large number, and label
    private func statCard(_ value: String, _ label: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: RE.s8) {
            Image(systemName: icon).font(.system(size: 16)).foregroundColor(color)
            Text(value).font(.system(size: 24, weight: .bold)).foregroundColor(REColors.text)
            Text(label).font(REFont.small).foregroundColor(REColors.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RE.s16).background(REColors.bgCard).cornerRadius(RE.r12)
    }

    // Highlights

    // Key achievements like favourite brand, best confidence, and audio contributed
    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: RE.s12) {
            Text("Highlights").font(REFont.heading).foregroundColor(REColors.text)
            highlightRow(icon: "heart.fill", color: REColors.accent, title: "Favourite Brand", value: favouriteMake)
            if let best = bestDetection {
                highlightRow(icon: "target", color: REColors.confGreen, title: "Most Confident",
                             value: "\(best.vehicleLabel) (\(Int(best.confidence * 100))%)")
            }
            highlightRow(icon: "flag.checkered", color: REColors.blueLight, title: "Makes Discovered",
                         value: "\(uniqueMakes) brand\(uniqueMakes == 1 ? "" : "s") found")
            if audioCount > 0 {
                highlightRow(icon: "waveform", color: REColors.confGreen, title: "Audio Contributed",
                             value: "\(audioCount) sample\(audioCount == 1 ? "" : "s")")
            }
        }
    }

    // Reusable row for the highlights section — styled flat (no card background)
    // so users don't mistake it for a tappable element.
    private func highlightRow(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: RE.s12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(color).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(REFont.small).foregroundColor(REColors.textDim)
                Text(value).font(REFont.body).foregroundColor(REColors.text).lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, RE.s8).padding(.horizontal, RE.s4)
    }

    // Audio Dataset Card

    // Link to the external audio dataset research website
    private var audioDatasetCard: some View {
        Button {
            if let url = URL(string: "https://neilf77.github.io/RevEye-AudioWebpage") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: RE.s12) {
                ZStack {
                    Circle()
                        .fill(REColors.confGreen.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "globe")
                        .font(.system(size: 16))
                        .foregroundColor(REColors.confGreen)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Audio Dataset")
                        .font(REFont.heading).foregroundColor(REColors.text)
                    Text("Browse the crowdsourced vehicle sound database")
                        .font(REFont.small).foregroundColor(REColors.textDim)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12)).foregroundColor(REColors.textDim)
            }
            .padding(RE.s16)
            .background(REColors.bgCard)
            .cornerRadius(RE.r12)
        }
    }

    // Menu Section

    // Navigation link to Settings
    private var menuSection: some View {
        VStack(spacing: 0) {
            NavigationLink { SettingsView() } label: {
                menuRow("gearshape", "Settings", REColors.textSec, badge: nil)
            }
        }
    }

    // Reusable navigation row for the bottom menu section
    private func menuRow(_ icon: String, _ title: String, _ color: Color, badge: String?) -> some View {
        HStack(spacing: RE.s12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundColor(color).frame(width: 24)
            Text(title).font(REFont.body).foregroundColor(REColors.text)
            if let badge {
                Text(badge)
                    .font(REFont.small)
                    .foregroundColor(REColors.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(REColors.accent.opacity(0.15))
                    .cornerRadius(100)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(REColors.textDim)
        }.padding(.vertical, RE.s12)
    }

}
