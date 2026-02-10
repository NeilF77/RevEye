import Foundation
import FirebaseAuth

final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var user: User? = Auth.auth().currentUser

    private init() {
        // Observe auth state changes
        Auth.auth().addStateDidChangeListener { _, user in
            self.user = user
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
            try Auth.auth().signOut()
            self.user = nil
        } catch {
            print("Error signing out: \(error)")
        }
    }
}
