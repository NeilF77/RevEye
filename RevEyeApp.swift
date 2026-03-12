//
//  RevEyeApp.swift
//  RevEye
//
//  Created by user on 10/11/2025.
//

import SwiftUI
import FirebaseCore

@main
struct RevEyeApp: App {
    // Connects AppDelegate to SwiftUI app for Firebase initialization
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    // Observe auth state to decide which root view to show
    @StateObject private var auth = AuthService.shared

    var body: some Scene {
        WindowGroup {
            if auth.user == nil {
                LoginView()
            } else {
                HomeView()
            }
        }
    }
}
