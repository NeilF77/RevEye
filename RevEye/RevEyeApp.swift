//
//  RevEyeApp.swift
//  RevEye
//
//  Created by user on 10/11/2025.
//  Updated 12/03/2026 — routes to MainTabView (tab navigation)

import SwiftUI
import FirebaseCore

@main
struct RevEyeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var auth = AuthService.shared

    var body: some Scene {
        WindowGroup {
            if auth.user == nil {
                LoginView()
                    .preferredColorScheme(.dark)
            } else {
                MainTabView()
                    .preferredColorScheme(.dark)
            }
        }
    }
}
