//
//  AuthService.swift
//  RevEye
//
//  Created by user on 07/02/2026.
//  Updated 10/03/2026 — wipes all local data on logout, syncs from Firebase on login

import Foundation
import Combine
import FirebaseAuth

final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var user: User? = Auth.auth().currentUser

    private init() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let previousUid = self?.user?.uid
            self?.user = user

            if let user, user.uid != previousUid {
                // New user just logged in — sync their data from Firebase
                print("Auth: user signed in (\(user.uid)) — syncing from Firebase")
                BadgeService.shared.refreshBadges()
            }
        }
    }

    func signIn(email: String, password: String, completion: @escaping (Error?) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { _, error in
            completion(error)
        }
    }

    func signUp(email: String, password: String, completion: @escaping (Error?) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { _, error in
            completion(error)
        }
    }

    func signOut() {
        do {
            // Wipe ALL local data before signing out.
            // Detections, badges, audio samples — everything.
            // Firebase is the source of truth; local DB is just a cache.
            DatabaseManager.shared.resetAllUserData()
            BadgeService.shared.clearLocal()
            print("Auth: all local data wiped, signing out")

            try Auth.auth().signOut()
            self.user = nil
        } catch {
            print("Error signing out: \(error)")
        }
    }
}
