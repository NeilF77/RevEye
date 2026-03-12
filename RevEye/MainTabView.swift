//
//  MainTabView.swift
//  RevEye
//
//  Created 12/03/2026 — UI overhaul
//  Bottom tab navigation: Scan (centre), History, Profile.
//  Scan is always one tap away from any screen.

import SwiftUI

struct MainTabView: View {
    @StateObject private var scanVM = ScanViewModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ScanView(vm: scanVM)
                .tabItem {
                    Image(systemName: "viewfinder")
                    Text("Scan")
                }
                .tag(0)

            HistoryView(detections: $scanVM.savedDetections)
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("History")
                }
                .tag(1)

            ProfileView()
                .tabItem {
                    Image(systemName: "person.circle")
                    Text("Profile")
                }
                .tag(2)
        }
        .accentColor(REColors.accent)
        .onAppear {
            // Style the tab bar to match theme
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(REColors.bgPrimary)

            // Unselected items
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor(REColors.textMuted)
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor(REColors.textMuted)
            ]
            // Selected items
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor(REColors.accent)
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor(REColors.accent)
            ]

            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
