// AppDelegate.swift
// RevEye
//
// Sets up Firebase when the app first launches. This needs to happen before
// any Firebase services (auth, database, storage) can be used.

import UIKit
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Initialise Firebase SDK - must be called before any other Firebase code
        FirebaseApp.configure()
        return true
    }
}
