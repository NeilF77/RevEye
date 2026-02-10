//
//  AppDelegate.swift
//  RevEye
//
//  Created by user on 28/11/2025.
//


//  AppDelegate.swift
//  RevEye
//
//  Created by user on 28/11/2025.
//
// Firebase starter code gotten from firebase website

import UIKit
import FirebaseCore

// AppDelegate handles app lifecycle events - needed because SwiftUI doesn't provide direct access to these
class AppDelegate: NSObject, UIApplicationDelegate {
    // Called automatically when app launches - perfect place for Firebase setup
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // Initialize Firebase - reads GoogleService-Info.plist to connect to our Firebase project. Must happen before any Firestore/Auth calls or the app will crash
        FirebaseApp.configure()
        print("Firebase configured")
        return true
    }
}
