// AuthService.swift
// RevEye
//
// Manages user authentication using Firebase. Provides sign in, sign up,
// and sign out functionality. On sign out, all local data is wiped so the
// next user starts fresh. This is a singleton accessed via AuthService.shared.

import Foundation
import Combine
import FirebaseAuth

final class AuthService: ObservableObject {
    static let shared = AuthService()

    // The currently logged-in Firebase user, or nil if not logged in.
    // Views observe this to decide whether to show login or the main app.
    @Published var user: User?

    private init() {
    // Grab the current user on app launch (may be nil if not logged in)
        self.user = Auth.auth().currentUser

    // Listen for auth state changes (login, logout, token refresh).
    // When a new user signs in, sync their badges from Firebase.
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let previousUid = self?.user?.uid
            self?.user = user

            // Only refresh badges if this is a genuinely different user
            if let user, user.uid != previousUid {
                BadgeService.shared.refreshBadges()
            }
        }
    }

    // Sign in with email and password
    func signIn(email: String, password: String, completion: @escaping (Error?) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { _, error in
            completion(error)
        }
    }

    // Create a new account with email and password
    func signUp(email: String, password: String, completion: @escaping (Error?) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { _, error in
            completion(error)
        }
    }

    // Sign out and wipe all local data. This ensures that if a different
    // person logs in on the same device, they don't see the previous user's data.
    func signOut() {
        do {
            // Clear local database, badge cache, and saved images
            DatabaseManager.shared.resetAllUserData()
            BadgeService.shared.clearLocal()
            ImageStore.deleteAll()

            try Auth.auth().signOut()
            self.user = nil
        } catch {
            print("Error signing out: \(error)")
        }
    }
}
