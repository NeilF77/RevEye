//
//  BadgesView.swift
//  RevEye
//
//  UI overhaul v8 — dark theme, locked badges with hints

import SwiftUI

struct BadgesView: View {
    @ObservedObject private var badgeService = BadgeService.shared

    private var earned: [Badge] { badgeService.badges.filter { $0.earned } }
    private var locked: [Badge] { badgeService.badges.filter { !$0.earned } }

    var body: some View {
        ZStack {
            REColors.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: RE.s24) {

                    // Progress summary
                    VStack(spacing: RE.s8) {
                        HStack {
                            Text("\(earned.count) of \(badgeService.badges.count) earned")
                                .font(REFont.heading).foregroundColor(REColors.text)
                            Spacer()
                            Text("\(Int(Double(earned.count) / max(1, Double(badgeService.badges.count)) * 100))%")
                                .font(REFont.mono).foregroundColor(REColors.accent)
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(REColors.bgInput).frame(height: 6)
                                Capsule().fill(REColors.accent)
                                    .frame(width: badgeService.badges.isEmpty ? 0 :
                                        g.size.width * CGFloat(earned.count) / CGFloat(badgeService.badges.count), height: 6)
                            }
                        }.frame(height: 6)
                    }
                    .padding(.horizontal, RE.s16)
                    .padding(.top, RE.s8)

                    // Earned badges
                    if !earned.isEmpty {
                        VStack(alignment: .leading, spacing: RE.s12) {
                            Text("Earned")
                                .font(REFont.label).foregroundColor(REColors.textDim)
                                .padding(.horizontal, RE.s16)

                            ForEach(earned) { badge in
                                badgeRow(badge, locked: false)
                                    .padding(.horizontal, RE.s16)
                            }
                        }
                    }

                    // Locked badges
                    if !locked.isEmpty {
                        VStack(alignment: .leading, spacing: RE.s12) {
                            Text("Locked")
                                .font(REFont.label).foregroundColor(REColors.textDim)
                                .padding(.horizontal, RE.s16)

                            ForEach(locked) { badge in
                                badgeRow(badge, locked: true)
                                    .padding(.horizontal, RE.s16)
                            }
                        }
                    }

                    Spacer().frame(height: RE.s48)
                }
            }
        }
        .navigationTitle("Badges")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { badgeService.refreshBadges() }
    }

    private func badgeRow(_ badge: Badge, locked: Bool) -> some View {
        HStack(spacing: RE.s16) {
            Text(badge.emoji)
                .font(.system(size: 28))
                .grayscale(locked ? 0.8 : 0)
                .opacity(locked ? 0.4 : 1)

            VStack(alignment: .leading, spacing: RE.s4) {
                Text(badge.title)
                    .font(REFont.heading)
                    .foregroundColor(locked ? REColors.textDim : REColors.text)

                Text(badge.description)
                    .font(REFont.caption)
                    .foregroundColor(locked ? REColors.textDim.opacity(0.6) : REColors.textSec)
                    .lineLimit(2)
            }

            Spacer()

            if !locked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(REColors.success)
                    .font(.system(size: 16))
            } else {
                Image(systemName: "lock.fill")
                    .foregroundColor(REColors.textDim.opacity(0.4))
                    .font(.system(size: 14))
            }
        }
        .padding(RE.s12)
        .background(REColors.bgCard)
        .cornerRadius(RE.r12)
    }
}
