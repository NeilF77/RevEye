// MainTabView.swift
// RevEye
//
// The root tab bar for the main app. Three tabs: Scan, Garage, and Profile.
// Uses a selectedTab state so other views can programmatically switch tabs
// (e.g. the empty Garage state has a "Start Scanning" button).

import SwiftUI

struct MainTabView: View {
    // Shared view model for the scan screen, created once here
    @StateObject private var scanVM = ScanViewModel()

    // Observe badge service so we can show a notification dot on the Profile tab
    @ObservedObject private var badgeService = BadgeService.shared

    // Tracks the earned badge count the user last acknowledged in BadgesView
    @AppStorage("profileLastSeenBadgeCount") private var lastSeenBadgeCount: Int = 0

    // Which tab is currently selected (0 = Scan, 1 = Garage, 2 = Profile)
    @State private var selectedTab = 0

    // Number of badges earned since the user last opened BadgesView
    private var unseenBadgeCount: Int {
        max(0, badgeService.badges.filter { $0.earned }.count - lastSeenBadgeCount)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ScanView(vm: scanVM)
                .tabItem {
                    Image(systemName: "viewfinder")
                    Text("Scan")
                }
                .tag(0)

            NavigationView { GarageView() }
                .tabItem {
                    Image(systemName: "car.2.fill")
                    Text("Garage")
                }
                .tag(1)

            ProfileView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Profile")
                }
                .tag(2)
                .badge(unseenBadgeCount)
        }
        .tint(REColors.accent)
    // Make tab bar background visible on all screens
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            appearance.backgroundColor = UIColor(REColors.bg)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    // Listen for requests to switch to the Scan tab from other views
        .onReceive(NotificationCenter.default.publisher(for: .switchToScanTab)) { _ in
            selectedTab = 0
        }
    }
}

// Custom notification name used to switch to the Scan tab from anywhere in the app
extension Notification.Name {
    static let switchToScanTab = Notification.Name("switchToScanTab")
}
