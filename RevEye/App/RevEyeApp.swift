// RevEyeApp.swift
// RevEye
//
// The main entry point for the app. Shows LoginView if nobody's signed in,
// otherwise MainTabView.

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

// Top level routing. Not logged in -> LoginView. Logged in -> MainTabView.
struct RootView: View {
    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        Group {
            if auth.user == nil {
                LoginView()
            } else {
                MainTabView()
            }
        }
    }
}
