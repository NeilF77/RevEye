//
//  BadgeService.swift
//  RevEye
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// BadgeService sits on top of DatabaseManager.
// DatabaseManager owns all local reads/writes.
// BadgeService handles:
//   - awarding badges (writes to DB + Firestore)
//   - fetching from Firebase on login to sync cross-device
//   - publishing badge state to the UI via @Published
final class BadgeService: ObservableObject {
    static let shared = BadgeService()

    @Published var badges: [Badge] = []

    private let firestore = Firestore.firestore()
    private let db = DatabaseManager.shared
    private var userId: String? { Auth.auth().currentUser?.uid }

    private init() {
        badges = db.fetchAllBadges()
        fetchFromFirebase()
    }

    // MARK: - Firebase sync

    /// Pulls earned badges from Firestore, merges into local DB, refreshes published state.
    /// Call on login and whenever BadgesView appears.
    func fetchFromFirebase() {
        guard let uid = userId else { return }
        firestore.collection("users").document(uid)
            .collection("badges").getDocuments { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                let earned = docs.compactMap { doc -> (id: String, earnedAt: String)? in
                    guard let earnedAt = doc.data()["earnedAt"] as? String else { return nil }
                    return (id: doc.documentID, earnedAt: earnedAt)
                }
                self.db.mergeBadgesFromFirebase(earned)
                DispatchQueue.main.async { self.badges = self.db.fetchAllBadges() }
            }
    }

    // MARK: - Awarding

    /// Awards a badge, saves locally, syncs to Firestore.
    /// Returns the Badge if this was a new earn (for toast display), nil otherwise.
    @discardableResult
    func award(_ badgeId: String) -> Badge? {
        let wasNew = db.earnBadge(id: badgeId)
        guard wasNew else { return nil }

        // Refresh published state
        DispatchQueue.main.async { self.badges = self.db.fetchAllBadges() }

        // Sync to Firestore so other devices pick it up
        guard let uid = userId,
              let badge = badges.first(where: { $0.id == badgeId }),
              let earnedAt = badge.earnedAt else { return badges.first(where: { $0.id == badgeId }) }

        firestore.collection("users").document(uid)
            .collection("badges").document(badgeId)
            .setData(["earnedAt": earnedAt]) { error in
                if let error { print("Badge Firestore sync error: \(error.localizedDescription)") }
            }

        return db.fetchAllBadges().first(where: { $0.id == badgeId })
    }

    // MARK: - Check helpers called from HomeView

    func checkFirstPhoto()  { award("first_photo") }
    func checkFirstVideo()  { award("first_video") }
    func checkFirstSync()   { award("first_sync")  }

    /// Run after every photo save.
    @discardableResult
    func checkAfterPhotoSave(confidence: Double, allDetections: [Detection]) -> [Badge] {
        var newlyEarned: [Badge] = []
        if let b = award("first_save")      { newlyEarned.append(b) }
        newlyEarned += checkDetectionCount(allDetections.count)
        if let b = checkHighConfidence(confidence) { newlyEarned.append(b) }
        if let b = checkNightOwl()          { newlyEarned.append(b) }
        newlyEarned += checkUniqueMakes(detections: allDetections)
        return newlyEarned
    }

    /// Run after a video scan finds at least one detection.
    @discardableResult
    func checkAfterVideoDetection(allDetections: [Detection]) -> [Badge] {
        var newlyEarned: [Badge] = []
        if let b = award("video_detection") { newlyEarned.append(b) }
        newlyEarned += checkDetectionCount(allDetections.count)
        newlyEarned += checkUniqueMakes(detections: allDetections)
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
        confidence >= 0.95 ? award("high_confidence") : nil
    }

    private func checkNightOwl() -> Badge? {
        let hour = Calendar.current.component(.hour, from: Date())
        return (hour >= 0 && hour < 5) ? award("night_owl") : nil
    }

    private func checkUniqueMakes(detections: [Detection]) -> [Badge] {
        let makes = Set(detections.map { $0.vehicleLabel.components(separatedBy: " ").first ?? "" })
        var earned: [Badge] = []
        if makes.count >= 5,  let b = award("unique_makes_5")  { earned.append(b) }
        if makes.count >= 10, let b = award("unique_makes_10") { earned.append(b) }
        return earned
    }
}