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

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        print("Firebase configured")
        return true
    }
}
