// AuthService.swift
// RevEye
//
// Manages user authentication using Firebase. Provides sign in, sign up,
// and sign out functionality. On sign out, local data is cleared. On sign
// in, badges and detection history are restored from Firebase so nothing
// is lost between sessions. This is a singleton accessed via AuthService.shared.

import Foundation
import Combine
import FirebaseAuth

final class AuthService: ObservableObject {
    static let shared = AuthService()

    // The currently logged-in Firebase user, or nil if not logged in.
    // Views observe this to decide whether to show login or the main app.
    @Published var user: User?

    private init() {
        // Grab the current user on app launch (may be nil if not logged in).
        self.user = Auth.auth().currentUser

        // Listen for auth state changes (login, logout, token refresh).
        // When a new user signs in, sync their badges and detections from Firebase.
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let previousUid = self?.user?.uid
            self?.user = user

            // Only refresh data if this is a genuinely different user
            if let user, user.uid != previousUid {
                BadgeService.shared.refreshBadges()
                FirebaseService.shared.downloadDetections()
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

    // Sign out and clear local data. When the user signs back in,
    // their badges and detection history will be restored from Firebase.
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
