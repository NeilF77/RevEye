//
//  LoginView.swift
//  RevEye
//
//  Created by user on 07/02/2026.
//  Rethemed 12/03/2026 — dark blue + orange to match app

import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        ZStack {
            REColors.bgPrimary.ignoresSafeArea()

            VStack(spacing: RESpacing.xl) {
                Spacer()

                // ── Branding ──────────────────────────────────
                VStack(spacing: RESpacing.sm) {
                    // App icon / scan ring motif
                    ZStack {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [REColors.brandBlue, REColors.accent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 4
                            )
                            .frame(width: 80, height: 80)
                        Image(systemName: "car.fill")
                            .font(.system(size: 28))
                            .foregroundColor(REColors.brandBlue)
                    }

                    Text("RevEye")
                        .font(REFonts.largeTitle)
                        .foregroundColor(REColors.textPrimary)

                    Text("Vehicle Identifier")
                        .font(REFonts.caption)
                        .foregroundColor(REColors.textMuted)
                }

                Spacer().frame(height: RESpacing.xl)

                // ── Input Fields ──────────────────────────────
                VStack(spacing: RESpacing.md) {
                    HStack(spacing: RESpacing.md) {
                        Image(systemName: "envelope")
                            .foregroundColor(REColors.textMuted)
                            .frame(width: 20)
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundColor(REColors.textPrimary)
                    }
                    .padding(RESpacing.md)
                    .background(REColors.bgElevated)
                    .cornerRadius(RERadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: RERadius.md)
                            .stroke(REColors.brandBlueDark, lineWidth: 1)
                    )

                    HStack(spacing: RESpacing.md) {
                        Image(systemName: "lock")
                            .foregroundColor(REColors.textMuted)
                            .frame(width: 20)
                        SecureField("Password", text: $password)
                            .foregroundColor(REColors.textPrimary)
                    }
                    .padding(RESpacing.md)
                    .background(REColors.bgElevated)
                    .cornerRadius(RERadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: RERadius.md)
                            .stroke(REColors.brandBlueDark, lineWidth: 1)
                    )
                }

                // ── Error Message ─────────────────────────────
                if let msg = errorMessage {
                    Text(msg)
                        .font(REFonts.caption)
                        .foregroundColor(REColors.error)
                        .multilineTextAlignment(.center)
                }

                // ── Login Button ──────────────────────────────
                Button {
                    login()
                } label: {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Sign In")
                    }
                }
                .buttonStyle(REPrimaryButton(color: REColors.brandBlue))
                .disabled(isLoading || email.isEmpty || password.isEmpty)

                // ── Register Link ─────────────────────────────
                Button {
                    register()
                } label: {
                    HStack(spacing: RESpacing.xs) {
                        Text("New here?")
                            .foregroundColor(REColors.textMuted)
                        Text("Create account")
                            .foregroundColor(REColors.accent)
                            .fontWeight(.medium)
                    }
                    .font(REFonts.callout)
                }

                Spacer()
            }
            .padding(.horizontal, RESpacing.xl)
        }
    }

    // MARK: - Actions

    private func login() {
        errorMessage = nil
        isLoading = true
        AuthService.shared.signIn(email: email, password: password) { error in
            isLoading = false
            if let error { errorMessage = error.localizedDescription }
        }
    }

    private func register() {
        errorMessage = nil
        isLoading = true
        AuthService.shared.signUp(email: email, password: password) { error in
            isLoading = false
            if let error { errorMessage = error.localizedDescription }
        }
    }
}
