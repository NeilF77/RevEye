//
//  RevEyeApp.swift
//  RevEye
//
//  Created by user on 10/11/2025.
//

import SwiftUI
import SwiftData
import FirebaseCore

@main
struct RevEyeApp: App {
    // Connects AppDelegate to SwiftUI app for Firebase initialization
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    // Observe auth state
    @StateObject private var auth = AuthService.shared
    
    // Sets up SwiftData container for persistent storage
    var sharedModelContainer: ModelContainer = {
        // Define the data models to be stored
        let schema = Schema([
            Item.self,
        ])
        // Configure storage (persistent, not in-memory)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            if auth.user == nil {
                LoginView()
            } else {
                HomeView()
            }
        }
                .modelContainer(sharedModelContainer)  // Inject SwiftData container into view hierarchy
        }
    }

