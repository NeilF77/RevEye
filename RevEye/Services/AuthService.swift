//
//  AuthService.swift
//  RevEye
//
//  Created by user on 07/02/2026.
//  Updated 14/03/2026 — clears saved images on logout

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
            DatabaseManager.shared.resetAllUserData()
            BadgeService.shared.clearLocal()
            ImageStore.deleteAll()
            print("Auth: all local data + images wiped, signing out")

            try Auth.auth().signOut()
            self.user = nil
        } catch {
            print("Error signing out: \(error)")
        }
    }
}
