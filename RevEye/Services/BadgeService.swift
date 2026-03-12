//
//  BadgeService.swift
//  RevEye
//
//  Created by user on 09/03/2026.
//  Rewritten 10/03/2026 — Firebase is now the single source of truth.
//  Local SQLite is just a display cache, wiped on logout.

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

final class BadgeService: ObservableObject {
    static let shared = BadgeService()

    @Published var badges: [Badge] = Badge.all   // starts with all locked
    @Published var isLoading = false

    private let firestore = Firestore.firestore()
    private let db = DatabaseManager.shared
    private var userId: String? { Auth.auth().currentUser?.uid }

    private init() {
        refreshBadges()
    }

    // MARK: - Refresh (called on login, on BadgesView appear, after award)

    /// Fetches earned badges from Firestore for the current user,
    /// updates the local DB cache, and publishes to the UI.
    /// If offline / no user, shows all badges as locked.
    func refreshBadges() {
        guard let uid = userId else {
            print("BadgeService: no user, showing all locked")
            DispatchQueue.main.async { self.badges = Badge.all }
            return
        }

        isLoading = true
        print("BadgeService: fetching badges for \(uid)")

        firestore.collection("users").document(uid)
            .collection("badges").getDocuments { [weak self] snapshot, error in
                guard let self else { return }

                defer { DispatchQueue.main.async { self.isLoading = false } }

                if let error {
                    print("BadgeService Firebase error: \(error.localizedDescription)")
                    // Fall back to local cache
                    let local = self.db.fetchAllBadges()
                    DispatchQueue.main.async { self.badges = local }
                    return
                }

                // Parse earned badges from Firestore
                let earnedFromFirebase = snapshot?.documents.compactMap { doc -> (id: String, earnedAt: String)? in
                    guard let earnedAt = doc.data()["earnedAt"] as? String else { return nil }
                    return (id: doc.documentID, earnedAt: earnedAt)
                } ?? []

                print("BadgeService: \(earnedFromFirebase.count) earned badges from Firebase")

                // Reset local cache and rebuild from Firebase data
                self.db.resetAllBadges()
                if !earnedFromFirebase.isEmpty {
                    self.db.mergeBadgesFromFirebase(earnedFromFirebase)
                }

                let updated = self.db.fetchAllBadges()
                DispatchQueue.main.async { self.badges = updated }
            }
    }

    /// Clears all local badge state. Called on logout.
    func clearLocal() {
        db.resetAllBadges()
        DispatchQueue.main.async { self.badges = Badge.all }
        print("BadgeService: local state cleared")
    }

    // MARK: - Awarding

    /// Awards a badge: writes to Firestore FIRST (source of truth),
    /// then updates local cache and published state.
    /// Returns the Badge if this was a NEW earn, nil if already earned.
    @discardableResult
    func award(_ badgeId: String) -> Badge? {
        // Quick check: if already earned in published state, skip
        if badges.first(where: { $0.id == badgeId })?.earned == true {
            return nil
        }

        guard let uid = userId else {
            print("BadgeService.award(\(badgeId)): no user, skipping")
            return nil
        }

        let earnedAt = ISO8601DateFormatter().string(from: Date())
        print("BadgeService.award(\(badgeId)): awarding...")

        // Write to Firestore (source of truth)
        firestore.collection("users").document(uid)
            .collection("badges").document(badgeId)
            .setData(["earnedAt": earnedAt]) { error in
                if let error {
                    print("  Firestore write error: \(error.localizedDescription)")
                } else {
                    print("  Badge \(badgeId) saved to Firestore")
                }
            }

        // Also save locally for immediate display
        db.earnBadge(id: badgeId)
        let updated = db.fetchAllBadges()
        let earnedBadge = updated.first(where: { $0.id == badgeId })
        DispatchQueue.main.async { self.badges = updated }

        print("  Badge awarded: \(earnedBadge?.title ?? "nil")")
        return earnedBadge
    }

    // MARK: - Check helpers called from HomeView

    func checkFirstPhoto()  { award("first_photo") }
    func checkFirstVideo()  { award("first_video") }
    func checkFirstSync()   { award("first_sync")  }

    @discardableResult
    func checkAfterPhotoSave(confidence: Double, allDetections: [Detection]) -> [Badge] {
        var newlyEarned: [Badge] = []
        if let b = award("first_save")       { newlyEarned.append(b) }
        newlyEarned += checkDetectionCount(allDetections.count)
        if let b = checkHighConfidence(confidence) { newlyEarned.append(b) }
        if let b = checkNightOwl()           { newlyEarned.append(b) }
        if let b = checkStreak()             { newlyEarned.append(b) }
        newlyEarned += checkUniqueMakes(detections: allDetections)
        return newlyEarned
    }

    @discardableResult
    func checkAfterVideoDetection(allDetections: [Detection]) -> [Badge] {
        var newlyEarned: [Badge] = []
        if let b = award("video_detection")  { newlyEarned.append(b) }
        newlyEarned += checkDetectionCount(allDetections.count)
        if let b = checkStreak()             { newlyEarned.append(b) }
        newlyEarned += checkUniqueMakes(detections: allDetections)
        return newlyEarned
    }

    @discardableResult
    func checkAfterAudioUpload() -> [Badge] {
        var newlyEarned: [Badge] = []
        let count = db.audioSampleCount()
        if let b = award("first_audio")            { newlyEarned.append(b) }
        if count >= 5, let b = award("audio_5")    { newlyEarned.append(b) }
        return newlyEarned
    }

    // MARK: - Private helpers

    private func checkDetectionCount(_ count: Int) -> [Badge] {
        var earned: [Badge] = []
        if count >= 5,  let b = award("detections_5")  { earned.append(b) }
        if count >= 25, let b = award("detections_25") { earned.append(b) }
        if count >= 50, let b = award("detections_50") { earned.append(b) }
        return earned
    }

    private func checkHighConfidence(_ confidence: Double) -> Badge? {
        confidence >= 0.60 ? award("high_confidence") : nil
    }

    private func checkNightOwl() -> Badge? {
        let hour = Calendar.current.component(.hour, from: Date())
        return (hour >= 0 && hour < 5) ? award("night_owl") : nil
    }

    private func checkStreak() -> Badge? {
        let streak = db.currentStreak()
        return streak >= 3 ? award("streak_3") : nil
    }

    private func checkUniqueMakes(detections: [Detection]) -> [Badge] {
        let makes = Set(detections.map { $0.vehicleLabel.components(separatedBy: " ").first ?? "" })
        var earned: [Badge] = []
        if makes.count >= 5,  let b = award("unique_makes_5")  { earned.append(b) }
        if makes.count >= 10, let b = award("unique_makes_10") { earned.append(b) }
        return earned
    }
}
