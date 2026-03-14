//
//  SettingsView.swift
//  RevEye
//
//  Created by user on 14/03/2026.
//


//
//  SettingsView.swift
//  RevEye
//
//  Created 13/03/2026 — settings page

import SwiftUI
import FirebaseAuth

struct SettingsView: View {
    @State private var isSyncing = false
    @State private var syncMsg: String?
    @State private var unsyncedCount = 0

    private let db = DatabaseManager.shared

    private var userEmail: String {
        Auth.auth().currentUser?.email ?? "Not signed in"
    }

    private var userName: String {
        Auth.auth().currentUser?.displayName ?? "—"
    }

    var body: some View {
        ZStack {
            REColors.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: RE.s24) {

                    // ── Account ───────────────────────────
                    sectionHeader("Account")

                    VStack(spacing: 0) {
                        infoRow("person", "Name", userName)
                        Divider().background(REColors.bgInput)
                        infoRow("envelope", "Email", userEmail)
                    }
                    .background(REColors.bgCard)
                    .cornerRadius(RE.r12)

                    // ── Cloud Sync ────────────────────────
                    sectionHeader("Cloud Sync")

                    VStack(spacing: RE.s12) {
                        HStack(spacing: RE.s12) {
                            Image(systemName: unsyncedCount == 0 ? "checkmark.icloud" : "icloud.and.arrow.up")
                                .font(.system(size: 18))
                                .foregroundColor(unsyncedCount == 0 ? REColors.success : REColors.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(unsyncedCount == 0 ? "All synced" : "\(unsyncedCount) pending")
                                    .font(REFont.body).foregroundColor(REColors.text)
                                Text("Detections sync to Firebase automatically when online")
                                    .font(REFont.small).foregroundColor(REColors.textDim)
                            }
                            Spacer()
                        }

                        if let m = syncMsg {
                            Text(m).font(REFont.small).foregroundColor(REColors.textDim)
                        }

                        if unsyncedCount > 0 {
                            Button {
                                syncNow()
                            } label: {
                                HStack(spacing: RE.s8) {
                                    if isSyncing { ProgressView().tint(.white) }
                                    else { Image(systemName: "arrow.triangle.2.circlepath") }
                                    Text(isSyncing ? "Syncing…" : "Sync Now")
                                }
                            }
                            .buttonStyle(REPrimaryButton())
                            .disabled(isSyncing)
                        }
                    }
                    .padding(RE.s16)
                    .background(REColors.bgCard)
                    .cornerRadius(RE.r12)

                    // ── Data ──────────────────────────────
                    sectionHeader("Data")

                    VStack(spacing: 0) {
                        dataRow("car.fill", "\(db.fetchAllDetections().count) detections")
                        Divider().background(REColors.bgInput)
                        dataRow("waveform", "\(db.audioSampleCount()) audio samples")
                        Divider().background(REColors.bgInput)
                        dataRow("trophy.fill", "\(BadgeService.shared.badges.filter { $0.earned }.count) badges earned")
                    }
                    .background(REColors.bgCard)
                    .cornerRadius(RE.r12)

                    // ── About ─────────────────────────────
                    sectionHeader("About")

                    VStack(spacing: 0) {
                        infoRow("app", "App", "RevEye")
                        Divider().background(REColors.bgInput)
                        infoRow("number", "Version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        Divider().background(REColors.bgInput)
                        infoRow("cpu", "Model", "EfficientNet-B4 (196 classes)")
                    }
                    .background(REColors.bgCard)
                    .cornerRadius(RE.r12)

                    // ── Sign Out ──────────────────────────
                    Button("Sign Out") { AuthService.shared.signOut() }
                        .buttonStyle(REDestructiveButton())
                        .padding(.top, RE.s8)

                    Spacer().frame(height: RE.s48)
                }
                .padding(.horizontal, RE.s16)
                .padding(.top, RE.s8)
            }
        }
        .navigationTitle("Settings")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            unsyncedCount = db.fetchUnsyncedDetections().count
        }
    }

    // MARK: - Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(REFont.label)
            .foregroundColor(REColors.textDim)
            .padding(.top, RE.s4)
    }

    private func infoRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: RE.s12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(REColors.textDim)
                .frame(width: 20)
            Text(label)
                .font(REFont.body)
                .foregroundColor(REColors.textSec)
            Spacer()
            Text(value)
                .font(REFont.body)
                .foregroundColor(REColors.text)
                .lineLimit(1)
        }
        .padding(.horizontal, RE.s16)
        .padding(.vertical, RE.s12)
    }

    private func dataRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: RE.s12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(REColors.blueLight)
                .frame(width: 20)
            Text(text)
                .font(REFont.body)
                .foregroundColor(REColors.text)
            Spacer()
        }
        .padding(.horizontal, RE.s16)
        .padding(.vertical, RE.s12)
    }

    // MARK: - Sync

    private func syncNow() {
        let unsynced = db.fetchUnsyncedDetections()
        guard !unsynced.isEmpty else { syncMsg = "All synced"; return }
        isSyncing = true; syncMsg = nil
        let g = DispatchGroup(); var ok = 0
        for d in unsynced {
            g.enter()
            FirebaseService.shared.uploadDetection(d) { s in if s { ok += 1 }; g.leave() }
        }
        g.notify(queue: .main) {
            isSyncing = false
            unsyncedCount = db.fetchUnsyncedDetections().count
            syncMsg = "\(ok)/\(unsynced.count) synced"
        }
    }
}