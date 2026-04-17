// SignUpView.swift
// RevEye
//
// Account registration screen. Collects email, password, confirm password,
// and display name. Validates all fields before creating the account via
// Firebase Authentication.

import SwiftUI
import FirebaseAuth

struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    // Form fields for registration
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    // Error message shown inline if registration fails
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            REColors.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: RE.s48)

                    Text("Create Account")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(REColors.text)
                        .padding(.bottom, RE.s4)
                    Text("Join RevEye to save your detections")
                        .font(REFont.caption)
                        .foregroundColor(REColors.textSec)

                    Spacer().frame(height: RE.s32)

                    VStack(spacing: RE.s12) {
                        field("person", "Name", $name, secure: false)
                        field("envelope", "Email", $email, secure: false)
                        field("lock", "Password", $password, secure: true)
                        field("lock.shield", "Confirm Password", $confirmPassword, secure: true)
                    }
                    .padding(.horizontal, RE.s24)

                    VStack(alignment: .leading, spacing: RE.s4) {
                        validationRow("At least 6 characters", met: password.count >= 6)
                        validationRow("Passwords match", met: !password.isEmpty && password == confirmPassword)
                    }
                    .padding(.horizontal, RE.s24)
                    .padding(.top, RE.s12)

                    if let e = errorMessage {
                        Text(e)
                            .font(REFont.caption)
                            .foregroundColor(REColors.error)
                            .multilineTextAlignment(.center)
                            .padding(.top, RE.s12)
                            .padding(.horizontal, RE.s24)
                    }

                    Spacer().frame(height: RE.s32)

                    
                    // Create account button
Button { createAccount() } label: {
                        if isLoading { ProgressView().tint(.white) }
                        else { Text("Create Account") }
                    }
                    .buttonStyle(REPrimaryButton())
                    .disabled(isLoading || !isFormValid)
                    .opacity(isFormValid ? 1 : 0.5)
                    .padding(.horizontal, RE.s24)

                    Button { dismiss() } label: {
                        HStack(spacing: RE.s4) {
                            Text("Already have an account?")
                                .foregroundColor(REColors.textDim)
                            Text("Sign In")
                                .foregroundColor(REColors.accent)
                                .fontWeight(.medium)
                        }
                        .font(REFont.label)
                    }
                    .padding(.top, RE.s16)

                    Spacer().frame(height: RE.s48)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: RE.s4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(REFont.label)
                    }
                    .foregroundColor(REColors.accent)
                }
            }
        }
    }

    // Validation

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.isEmpty &&
        password.count >= 6 &&
        password == confirmPassword
    }

    private func validationRow(_ text: String, met: Bool) -> some View {
        HStack(spacing: RE.s8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundColor(met ? REColors.success : REColors.textDim)
            Text(text)
                .font(REFont.small)
                .foregroundColor(met ? REColors.textSec : REColors.textDim)
        }
    }

    // Field

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
                    .foregroundColor(REColors.text)
                    .keyboardType(icon == "envelope" ? .emailAddress : .default)
                    .textInputAutocapitalization(icon == "envelope" ? .never : .words)
                    .autocorrectionDisabled()
            }
        }
        .padding(RE.s12)
        .background(REColors.bgInput)
        .cornerRadius(RE.r12)
    }

    // Create Account

    private func createAccount() {
        errorMessage = nil
        isLoading = true

        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        AuthService.shared.signUp(email: email, password: password) { error in
            if let error {
                isLoading = false
                errorMessage = error.localizedDescription
                return
            }

            if let user = Auth.auth().currentUser {
                let changeRequest = user.createProfileChangeRequest()
                changeRequest.displayName = trimmedName
                changeRequest.commitChanges { _ in
                    isLoading = false
                }
            } else {
                isLoading = false
            }
        }
    }
}