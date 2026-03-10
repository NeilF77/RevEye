//
//  BadgesView.swift
//  RevEye
//

import SwiftUI

struct BadgesView: View {
    @ObservedObject private var badgeService = BadgeService.shared

    private var earned: [Badge] { badgeService.badges.filter { $0.earned } }
    private var locked: [Badge] { badgeService.badges.filter { !$0.earned } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: Summary header
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [.orange, .yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                            .frame(width: 70, height: 70)
                        Text("\(earned.count)")
                            .font(.system(size: 28, weight: .black))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(earned.count) of \(badgeService.badges.count) Badges Earned")
                            .font(.headline)
                        Text("\(locked.count) still to unlock")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.systemGray5))
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(LinearGradient(
                                        colors: [.orange, .yellow],
                                        startPoint: .leading,
                                        endPoint: .trailing))
                                    .frame(
                                        width: badgeService.badges.isEmpty ? 0 :
                                            geo.size.width * CGFloat(earned.count) / CGFloat(badgeService.badges.count),
                                        height: 8)
                                    .animation(.easeInOut(duration: 0.6), value: earned.count)
                            }
                        }
                        .frame(height: 8)
                    }
                    Spacer()
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)

                // MARK: Earned
                if !earned.isEmpty {
                    Text("Earned")
                        .font(.title3).fontWeight(.bold)
                        .padding(.horizontal, 4)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(earned) { BadgeCard(badge: $0, isEarned: true) }
                    }
                }

                // MARK: Locked
                if !locked.isEmpty {
                    Text("Locked")
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(locked) { BadgeCard(badge: $0, isEarned: false) }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Badges")
        .onAppear {
            // Re-fetch from Firebase every time the view appears so badges earned
            // on another device show up immediately
            BadgeService.shared.fetchFromFirebase()
        }
    }
}

// MARK: - Badge Card

private struct BadgeCard: View {
    let badge: Badge
    let isEarned: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isEarned
                        ? LinearGradient(colors: [.orange.opacity(0.25), .yellow.opacity(0.15)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color(.systemGray5), Color(.systemGray5)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)

                Text(badge.emoji)
                    .font(.system(size: 30))
                    .grayscale(isEarned ? 0 : 1)
                    .opacity(isEarned ? 1 : 0.4)

                if !isEarned {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .offset(x: 20, y: 20)
                }
            }

            Text(badge.title)
                .font(.caption).fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .foregroundColor(isEarned ? .primary : .secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(badge.description)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if isEarned, let earnedAt = badge.earnedAt,
               let date = ISO8601DateFormatter().date(from: earnedAt) {
                Text(date, style: .date)
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isEarned ? Color.orange.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
    }
}