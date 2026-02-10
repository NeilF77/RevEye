//
//  LoginView.swift
//  RevEye
//
//  Created by user on 07/02/2026.
//


import SwiftUI

struct LoginView: View {
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?

    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("RevEye Login")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)

                SecureField("Password", text: $password)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)

                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button("Login") {
                    login()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)

                Button("Register") {
                    register()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray)
                .foregroundColor(.white)
                .cornerRadius(8)

                Spacer()
            }
            .padding()
        }
    }

    private func login() {
        errorMessage = nil
        AuthService.shared.signIn(email: email, password: password) { error in
            if let error = error {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func register() {
        errorMessage = nil
        AuthService.shared.signUp(email: email, password: password) { error in
            if let error = error {
                errorMessage = error.localizedDescription
            }
        }
    }
}
