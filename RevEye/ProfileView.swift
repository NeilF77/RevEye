//
//  ProfileView.swift
//  RevEye
//
//  UI overhaul v8 — collection link, streak card

import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @ObservedObject private var badgeService = BadgeService.shared
    private let db = DatabaseManager.shared

    @State private var detections: [Detection] = []
    @State private var audioCount = 0

    private var earned: [Badge] { badgeService.badges.filter { $0.earned } }
    private var locked: [Badge] { badgeService.badges.filter { !$0.earned } }

    private var favouriteMake: String {
        let makes = detections.compactMap { $0.vehicleLabel.components(separatedBy: " ").first }
        let counted = Dictionary(grouping: makes, by: { $0 }).mapValues { $0.count }
        return counted.max(by: { $0.value < $1.value })?.key ?? "—"
    }

    private var uniqueMakes: Int {
        Set(detections.compactMap { $0.vehicleLabel.components(separatedBy: " ").first }).count
    }

    private var uniqueModels: Int {
        Set(detections.map { $0.vehicleLabel }).count
    }

    private var bestDetection: Detection? {
        detections.max(by: { $0.confidence < $1.confidence })
    }

    private var streak: Int { db.currentStreak() }

    private var nextBadge: Badge? { locked.first }

    private var userName: String {
        Auth.auth().currentUser?.displayName ?? "Driver"
    }

    var body: some View {
        NavigationView {
            ZStack {
                REColors.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: RE.s24) {
                        userHeader
                        streakCard
                        statsGrid
                        highlightsSection
                        if let next = nextBadge { nextBadgeCard(next) }
                        badgeProgressSection
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
            .onAppear {
                detections = db.fetchAllDetections()
                audioCount = db.audioSampleCount()
                badgeService.refreshBadges()
            }
        }
    }

    // MARK: - User Header

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

    // MARK: - Streak Card

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
                Text("\(streak)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(REColors.accent)
            }
        }
        .padding(RE.s16)
        .background(
            streak >= 3
                ? REColors.accent.opacity(0.08)
                : REColors.bgCard
        )
        .cornerRadius(RE.r12)
        .overlay(
            RoundedRectangle(cornerRadius: RE.r12)
                .stroke(streak >= 3 ? REColors.accent.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Stats Grid

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

    private func statCard(_ value: String, _ label: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: RE.s8) {
            Image(systemName: icon).font(.system(size: 16)).foregroundColor(color)
            Text(value).font(.system(size: 24, weight: .bold)).foregroundColor(REColors.text)
            Text(label).font(REFont.small).foregroundColor(REColors.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RE.s16).background(REColors.bgCard).cornerRadius(RE.r12)
    }

    // MARK: - Highlights

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: RE.s12) {
            Text("Highlights").font(REFont.heading).foregroundColor(REColors.text)
            highlightRow(icon: "heart.fill", color: REColors.accent, title: "Favourite Brand", value: favouriteMake)
            if let best = bestDetection {
                highlightRow(icon: "target", color: REColors.confGreen, title: "Most Confident",
                             value: "\(best.vehicleLabel) (\(Int(best.confidence * 100))%)")
            }
            highlightRow(icon: "flag.checkered", color: REColors.blueLight, title: "Makes Discovered",
                         value: "\(uniqueMakes) of \(uniqueMakes < 10 ? "10" : "20") — keep exploring!")
        }
    }

    private func highlightRow(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: RE.s12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(color).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(REFont.small).foregroundColor(REColors.textDim)
                Text(value).font(REFont.body).foregroundColor(REColors.text).lineLimit(1)
            }
            Spacer()
        }
        .padding(RE.s12).background(REColors.bgCard).cornerRadius(RE.r8)
    }

    // MARK: - Next Badge

    private func nextBadgeCard(_ badge: Badge) -> some View {
        VStack(alignment: .leading, spacing: RE.s12) {
            Text("Next Badge").font(REFont.heading).foregroundColor(REColors.text)
            HStack(spacing: RE.s16) {
                Text(badge.emoji).font(.system(size: 32)).grayscale(0.5).opacity(0.6)
                VStack(alignment: .leading, spacing: RE.s4) {
                    Text(badge.title).font(REFont.body).foregroundColor(REColors.text)
                    Text(badge.description).font(REFont.small).foregroundColor(REColors.textDim)
                }
                Spacer()
            }
            .padding(RE.s12).background(REColors.bgCard).cornerRadius(RE.r12)
            .overlay(RoundedRectangle(cornerRadius: RE.r12).stroke(REColors.accent.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: - Badge Progress

    private var badgeProgressSection: some View {
        VStack(alignment: .leading, spacing: RE.s12) {
            HStack {
                Text("Badges").font(REFont.heading).foregroundColor(REColors.text)
                Spacer()
                Text("\(earned.count)/\(badgeService.badges.count)").font(REFont.mono).foregroundColor(REColors.accent)
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

    // MARK: - Menu

    private var menuSection: some View {
        VStack(spacing: 0) {
            NavigationLink { CollectionView() } label: { menuRow("car.2.fill", "My Garage", REColors.blue) }
            Divider().background(REColors.bgInput)
            NavigationLink { BadgesView() } label: { menuRow("trophy.fill", "All Badges", REColors.accent) }
            Divider().background(REColors.bgInput)
            NavigationLink { AudioLibraryView() } label: { menuRow("waveform", "Audio Library", REColors.blueLight) }
            Divider().background(REColors.bgInput)
            NavigationLink { SettingsView() } label: { menuRow("gearshape", "Settings", REColors.textSec) }
        }
    }

    private func menuRow(_ icon: String, _ title: String, _ color: Color) -> some View {
        HStack(spacing: RE.s12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundColor(color).frame(width: 24)
            Text(title).font(REFont.body).foregroundColor(REColors.text)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(REColors.textDim)
        }.padding(.vertical, RE.s12)
    }
}
