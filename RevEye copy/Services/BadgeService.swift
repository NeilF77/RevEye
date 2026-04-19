// BadgeService.swift
// RevEye
//
// Manages the badge/achievement system. Firebase Firestore is the source of
// truth for which badges a user has earned. Local SQLite is just a cache for
// display. When badges are awarded, they're written to Firestore first, then
// cached locally. This is a singleton accessed via BadgeService.shared.

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

final class BadgeService: ObservableObject {
    static let shared = BadgeService()

    // The full badge list with earned status, observed by BadgesView and ProfileView
    @Published var badges: [Badge] = Badge.all   // starts with all locked
    // True while fetching badges from Firebase
    @Published var isLoading = false

    private let firestore = Firestore.firestore()
    private let db = DatabaseManager.shared
    // Current Firebase user ID, or nil if not logged in
    private var userId: String? { Auth.auth().currentUser?.uid }

    private init() {
        refreshBadges()
    }

    // Fetches earned badges from Firestore, updates the local cache, and publishes to the UI.
    func refreshBadges() {
        guard let uid = userId else {
            DispatchQueue.main.async { self.badges = Badge.all }
            return
        }

        isLoading = true

        firestore.collection("users").document(uid)
            .collection("badges").getDocuments { [weak self] snapshot, error in
                guard let self else { return }
                defer { DispatchQueue.main.async { self.isLoading = false } }

                if let error {
                    print("BadgeService Firebase error: \(error.localizedDescription)")
                    let local = self.db.fetchAllBadges()
                    DispatchQueue.main.async { self.badges = local }
                    return
                }

                let earnedFromFirebase = snapshot?.documents.compactMap { doc -> (id: String, earnedAt: String)? in
                    guard let earnedAt = doc.data()["earnedAt"] as? String else { return nil }
                    return (id: doc.documentID, earnedAt: earnedAt)
                } ?? []

                self.db.resetAllBadges()
                if !earnedFromFirebase.isEmpty {
                    self.db.mergeBadgesFromFirebase(earnedFromFirebase)
                }

                let updated = self.db.fetchAllBadges()
                DispatchQueue.main.async { self.badges = updated }
            }
    }

    // Resets all local badge state. Called on logout.
    func clearLocal() {
        db.resetAllBadges()
        DispatchQueue.main.async { self.badges = Badge.all }
    }

    // Awards a badge. Returns the Badge if newly earned, nil if already earned.
    @discardableResult
    func award(_ badgeId: String) -> Badge? {
        if badges.first(where: { $0.id == badgeId })?.earned == true { return nil }
        guard let uid = userId else { return nil }

        let earnedAt = ISO8601DateFormatter().string(from: Date())

        firestore.collection("users").document(uid)
            .collection("badges").document(badgeId)
            .setData(["earnedAt": earnedAt])

        db.earnBadge(id: badgeId)
        let updated = db.fetchAllBadges()
        let earnedBadge = updated.first(where: { $0.id == badgeId })
        DispatchQueue.main.async { self.badges = updated }
        return earnedBadge
    }

    // Check helpers

    func checkFirstPhoto()  { award("first_photo") }
    func checkFirstVideo()  { award("first_video") }

    @discardableResult
    // Checks all applicable badge conditions after a photo save.
    func checkAfterPhotoSave(confidence: Double, allDetections: [Detection]) -> [Badge] {
        var newlyEarned: [Badge] = []
        if let b = award("first_save")       { newlyEarned.append(b) }
        newlyEarned += checkDetectionCount(allDetections.count)
        newlyEarned += checkConfidence(confidence)
        if let b = checkNightOwl()           { newlyEarned.append(b) }
        newlyEarned += checkStreak()
        newlyEarned += checkUniqueMakes(detections: allDetections)
        return newlyEarned
    }

    @discardableResult
    func checkAfterVideoDetection(allDetections: [Detection]) -> [Badge] {
        var newlyEarned: [Badge] = []
        if let b = award("video_detection")  { newlyEarned.append(b) }
        newlyEarned += checkDetectionCount(allDetections.count)
        newlyEarned += checkStreak()
        newlyEarned += checkUniqueMakes(detections: allDetections)
        return newlyEarned
    }

    @discardableResult
    func checkAfterAudioUpload() -> [Badge] {
        var newlyEarned: [Badge] = []
        let count = db.audioSampleCount()
        if let b = award("first_audio")             { newlyEarned.append(b) }
        if count >= 5,  let b = award("audio_5")    { newlyEarned.append(b) }
        if count >= 10, let b = award("audio_10")   { newlyEarned.append(b) }
        return newlyEarned
    }

    // Call when user corrects a wrong prediction (data quality contribution)
    @discardableResult
    func checkAfterCorrection() -> Badge? {
        award("correction_hero")
    }

    // Sharing

    private static let shareCountKey = "reveye_share_count"

    // Tracks share count and awards sharing badges.
    @discardableResult
    func checkAfterShare() -> [Badge] {
        let count = UserDefaults.standard.integer(forKey: Self.shareCountKey) + 1
        UserDefaults.standard.set(count, forKey: Self.shareCountKey)

        var newlyEarned: [Badge] = []
        if let b = award("first_share")              { newlyEarned.append(b) }
        if count >= 5, let b = award("shares_5")     { newlyEarned.append(b) }
        return newlyEarned
    }

    var shareCount: Int {
        UserDefaults.standard.integer(forKey: Self.shareCountKey)
    }

    // Private helpers

    private func checkDetectionCount(_ count: Int) -> [Badge] {
        var earned: [Badge] = []
        if count >= 5,   let b = award("detections_5")   { earned.append(b) }
        if count >= 25,  let b = award("detections_25")  { earned.append(b) }
        if count >= 50,  let b = award("detections_50")  { earned.append(b) }
        if count >= 100, let b = award("detections_100") { earned.append(b) }
        return earned
    }

    private func checkConfidence(_ confidence: Double) -> [Badge] {
        var earned: [Badge] = []
        if confidence >= 0.60, let b = award("high_confidence") { earned.append(b) }
        if confidence >= 0.90, let b = award("perfect_shot")    { earned.append(b) }
        return earned
    }

    private func checkNightOwl() -> Badge? {
        let hour = Calendar.current.component(.hour, from: Date())
        return (hour >= 0 && hour < 5) ? award("night_owl") : nil
    }

    private func checkStreak() -> [Badge] {
        let streak = db.currentStreak()
        var earned: [Badge] = []
        if streak >= 3, let b = award("streak_3") { earned.append(b) }
        if streak >= 7, let b = award("streak_7") { earned.append(b) }
        return earned
    }

    private func checkUniqueMakes(detections: [Detection]) -> [Badge] {
        let makes = Set(detections.map { $0.vehicleLabel.components(separatedBy: " ").first ?? "" })
        var earned: [Badge] = []
        if makes.count >= 5,  let b = award("unique_makes_5")  { earned.append(b) }
        if makes.count >= 10, let b = award("unique_makes_10") { earned.append(b) }
        if makes.count >= 15, let b = award("unique_makes_15") { earned.append(b) }
        return earned
    }
}
