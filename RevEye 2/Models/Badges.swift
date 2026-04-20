// Badges.swift
// RevEye
//
// Defines the Badge struct and the full list of badges users can earn.
// Each badge has a unique ID that matches what BadgeService uses to award them.
// The "earned" field starts false here; DatabaseManager merges the real
// state from Firestore on top at runtime.

import Foundation

struct Badge: Identifiable, Codable, Equatable {
    let id: String          // Unique identifier, e.g. "first_photo", "detections_50"
    let title: String       // Display name shown to the user
    let description: String // What the user needs to do to earn it
    let emoji: String       // Visual representation in the UI
    var earned: Bool        // Whether the user has earned this badge
    var earnedAt: String?   // ISO 8601 timestamp of when it was earned, nil if not yet
}

extension Badge {
    static let all: [Badge] = [
        // First steps - earned quickly to give new users early wins.
        Badge(id: "first_photo", title: "Ignition", description: "Scan your first vehicle photo", emoji: "🔑", earned: false),
        Badge(id: "first_video", title: "Dashcam Rolling", description: "Scan your first video", emoji: "🎬", earned: false),
        Badge(id: "first_save", title: "Garage Opener", description: "Save your first vehicle to your garage", emoji: "🏠", earned: false),

        // Collection milestones - progressively harder targets.
        Badge(id: "detections_5", title: "Collection Started", description: "Save 5 vehicles to your garage", emoji: "🛣️", earned: false),
        Badge(id: "detections_25", title: "Petrolhead", description: "Save 25 vehicles - you know your cars", emoji: "⛽", earned: false),
        Badge(id: "detections_50", title: "Grand Tourer", description: "Save 50 vehicles to your garage", emoji: "🏁", earned: false),
        Badge(id: "detections_100", title: "Living Legend", description: "Save 100 vehicles - you're in a league of your own", emoji: "👑", earned: false),

        // Accuracy and skill - reward good photos and corrections.
        Badge(id: "high_confidence", title: "Keen Spotter", description: "Get a detection with 60%+ confidence", emoji: "🦅", earned: false),
        Badge(id: "perfect_shot", title: "Bullseye", description: "Get a detection with 90%+ confidence - perfect angle", emoji: "🎯", earned: false),
        Badge(id: "correction_hero", title: "Pit Crew", description: "Correct a wrong prediction - helping RevEye learn", emoji: "🔧", earned: false),
        Badge(id: "video_detection", title: "Rolling Shot", description: "Identify a vehicle from a video scan", emoji: "🎞️", earned: false),

        // Diversity - encourage scanning different brands.
        Badge(id: "unique_makes_5", title: "Mixed Fleet", description: "Discover 5 different car makes", emoji: "🅿️", earned: false),
        Badge(id: "unique_makes_10", title: "World Tour", description: "Discover 10 different car makes from around the globe", emoji: "🌍", earned: false),
        Badge(id: "unique_makes_15", title: "Brand Collector", description: "Discover 15 different car makes - a true connoisseur", emoji: "🏅", earned: false),

        // Audio contributions - reward users who help build the sound database.
        Badge(id: "first_audio", title: "Exhaust Note", description: "Contribute your first engine sound", emoji: "🔊", earned: false),
        Badge(id: "audio_5", title: "Sound Check", description: "Contribute 5 engine sounds to the database", emoji: "🎵", earned: false),
        Badge(id: "audio_10", title: "Dyno Operator", description: "Contribute 10 engine sounds - fuelling research", emoji: "🎧", earned: false),

        // Time and dedication - streak and unusual usage patterns.
        Badge(id: "night_owl", title: "Midnight Cruise", description: "Scan a vehicle after midnight", emoji: "🌙", earned: false),
        Badge(id: "streak_3", title: "Three-Day Rally", description: "Scan vehicles on 3 consecutive days", emoji: "⚡", earned: false),
        Badge(id: "streak_7", title: "Endurance Run", description: "Scan vehicles 7 days in a row - relentless", emoji: "🏆", earned: false),

        // Sharing - encourage social engagement.
        Badge(id: "first_share", title: "Show & Shine", description: "Share your first detection with friends", emoji: "📣", earned: false),
        Badge(id: "shares_5", title: "Car Show Host", description: "Share 5 detections - spreading the word", emoji: "🎪", earned: false),
    ]
}
