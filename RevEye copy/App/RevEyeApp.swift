// RevEyeApp.swift
// RevEye
//
// The main entry point for the app. Decides what to show based on whether
// the user has completed onboarding and whether they are logged in.

import SwiftUI
import Firebase

@main
struct RevEyeApp: App {
    // Wire up the AppDelegate so Firebase gets configured on launch
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

// RootView handles the top-level routing logic. It checks two things:
// 1. Has the user seen the onboarding screens? If not, show OnboardingView.
// 2. Is the user logged in? If not, show LoginView.
// Otherwise, show the main app (MainTabView).
struct RootView: View {
    @ObservedObject private var auth = AuthService.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if auth.user == nil {
                // Not logged in - show onboarding or login
                if hasCompletedOnboarding {
                    LoginView()
                } else {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                }
            } else {
                // Logged in - show the main app
                MainTabView()
                    .onAppear {
                        // If they logged in before finishing onboarding, mark it done
                        if !hasCompletedOnboarding { hasCompletedOnboarding = true }
                    }
            }
        }
    }
}
