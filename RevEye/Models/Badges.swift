//
//  Badges.swift
//  RevEye
//
//  Created by user on 09/03/2026.
//

import Foundation

struct Badge: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let description: String
    let emoji: String
    var earned: Bool
    var earnedAt: String?   // ISO8601 — nil until earned
}

// All possible badges. `earned` is always false here —
// DatabaseManager merges the real state on top at runtime.
extension Badge {
    static let all: [Badge] = [
        // ── Onboarding ──────────────────────────────────────────────
        Badge(id: "first_photo",
              title: "First Scan",
              description: "Upload your first car photo",
              emoji: "📸", earned: false),
        Badge(id: "first_video",
              title: "Lights, Camera!",
              description: "Upload your first video",
              emoji: "🎬", earned: false),
        Badge(id: "first_save",
              title: "First in the Garage",
              description: "Save your first detection",
              emoji: "🚗", earned: false),
        Badge(id: "first_sync",
              title: "Cloud Connected",
              description: "Sync a detection to the cloud",
              emoji: "☁️", earned: false),

        // ── Milestones ──────────────────────────────────────────────
        Badge(id: "detections_5",
              title: "Getting Started",
              description: "Save 5 detections",
              emoji: "🔥", earned: false),
        Badge(id: "detections_25",
              title: "Car Enthusiast",
              description: "Save 25 detections",
              emoji: "🏆", earned: false),
        Badge(id: "detections_50",
              title: "Road Warrior",
              description: "Save 50 detections",
              emoji: "💯", earned: false),

        // ── Achievement ─────────────────────────────────────────────
        Badge(id: "high_confidence",
              title: "Sharp Eye",
              description: "Get a detection with 60%+ confidence",
              emoji: "🎯", earned: false),
        Badge(id: "video_detection",
              title: "Video Detective",
              description: "Detect a car through a video scan",
              emoji: "🕵️", earned: false),

        // ── Time-based ──────────────────────────────────────────────
        Badge(id: "night_owl",
              title: "Night Owl",
              description: "Make a detection after midnight",
              emoji: "🌙", earned: false),
        Badge(id: "streak_3",
              title: "Three-Day Streak",
              description: "Make detections on 3 consecutive days",
              emoji: "⚡", earned: false),

        // ── Diversity ───────────────────────────────────────────────
        Badge(id: "unique_makes_5",
              title: "Variety Spotter",
              description: "Detect 5 different car makes",
              emoji: "🌍", earned: false),
        Badge(id: "unique_makes_10",
              title: "Global Garage",
              description: "Detect 10 different car makes",
              emoji: "🌐", earned: false),

        // ── Audio Contributions ─────────────────────────────────────
        Badge(id: "first_audio",
              title: "Sound Collector",
              description: "Contribute your first audio sample",
              emoji: "🎧", earned: false),
        Badge(id: "audio_5",
              title: "Audio Archivist",
              description: "Contribute 5 audio samples",
              emoji: "🎵", earned: false),
    ]
}
