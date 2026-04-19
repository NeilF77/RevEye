// LoginView.swift
// RevEye
//
// Email and password login screen. Validates inputs before attempting sign in
// via Firebase Authentication. Shows inline error messages on failure.

import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                REColors.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    Text("RevEye")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(REColors.text)
                    Text("Vehicle Identifier")
                        .font(REFont.caption)
                        .foregroundColor(REColors.textDim)
                        .padding(.top, RE.s4)

                    Spacer().frame(height: RE.s48)

                    VStack(spacing: RE.s12) {
                        field("envelope", "Email", $email, secure: false)
                        field("lock", "Password", $password, secure: true)
                    }
                    .padding(.horizontal, RE.s24)

                    if let e = errorMessage {
                        Text(e)
                            .font(REFont.caption)
                            .foregroundColor(REColors.error)
                            .padding(.top, RE.s12)
                            .padding(.horizontal, RE.s24)
                    }

                    Spacer().frame(height: RE.s32)

                    // Sign in button - validates fields then calls Firebase
                    Button { login() } label: {
                        if isLoading { ProgressView().tint(.white) }
                        else { Text("Sign In") }
                    }
                    .buttonStyle(REPrimaryButton())
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                    .padding(.horizontal, RE.s24)

                    // Link to sign up for new users
                    NavigationLink {
                        SignUpView()
                    } label: {
                        HStack(spacing: RE.s4) {
                            Text("New here?")
                                .foregroundColor(REColors.textDim)
                            Text("Create account")
                                .foregroundColor(REColors.accent)
                                .fontWeight(.medium)
                        }
                        .font(REFont.label)
                    }
                    .padding(.top, RE.s16)

                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func field(_ icon: String, _ placeholder: String, _ text: Binding<String>, secure: Bool) -> some View {
        HStack(spacing: RE.s12) {
            Image(systemName: icon)
                .foregroundColor(REColors.textDim)
                .frame(width: 16)
            if secure {
                SecureField(placeholder, text: text)
                    .foregroundColor(REColors.text)
            } else {
                TextField(placeholder, text: text)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(REColors.text)
            }
        }
        .padding(RE.s12)
        .background(REColors.bgInput)
        .cornerRadius(RE.r12)
    }

    private func login() {
        errorMessage = nil; isLoading = true
        AuthService.shared.signIn(email: email, password: password) { e in
            isLoading = false
            if let e { errorMessage = e.localizedDescription }
        }
    }
}
