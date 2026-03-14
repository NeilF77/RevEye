//
//  MainTabView.swift
//  RevEye
//
//  UI overhaul v8

import SwiftUI

struct MainTabView: View {
    @StateObject private var scanVM = ScanViewModel()
    @State private var detections: [Detection] = DatabaseManager.shared.fetchAllDetections()

    var body: some View {
        TabView {
            ScanView(vm: scanVM)
                .tabItem {
                    Image(systemName: "viewfinder")
                    Text("Scan")
                }

            HistoryView(detections: $detections)
                .tabItem {
                    Image(systemName: "clock")
                    Text("History")
                }

            ProfileView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Profile")
                }
        }
        .tint(REColors.accent)
    }
}
