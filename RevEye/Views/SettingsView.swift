// SettingsView.swift
// RevEye
//
// Settings screen with account management (change name, view email), audio
// data summary, cloud sync status with manual sync button, app info, privacy
// policy link, database inspector, sign out, and delete account.

import SwiftUI
import FirebaseAuth

struct SettingsView: View {
    // State for sync progress, name change, and account deletion
    @State private var isSyncing = false
    @State private var syncMsg: String?
    @State private var unsyncedCount = 0
    @State private var audioCount = 0
    @State private var showChangeNameAlert = false
    @State private var newDisplayName = ""
    @State private var nameMsg: String?
    @State private var showDeleteAccountConfirm = false
    @State private var deleteAccountError: String?

    private let db = DatabaseManager.shared

    // Read the current user's info from Firebase Auth
    private var userEmail: String { Auth.auth().currentUser?.email ?? "Not signed in" }
    private var userName: String { Auth.auth().currentUser?.displayName ?? "-" }

    
    // Settings layout - scrollable list of sections: Account, Audio Data,
    // Cloud Sync, Data summary, About, Legal, Developer tools, and account actions.
    var body: some View {
        ZStack {
            REColors.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: RE.s24) {

                    
                    // Account section - tappable name field with pencil icon
                    sectionHeader("Account")
                    VStack(spacing: 0) {
                        Button { showChangeNameAlert = true } label: {
                            HStack(spacing: RE.s12) {
                                Image(systemName: "person").font(.system(size: 14)).foregroundColor(REColors.textDim).frame(width: 20)
                                Text("Name").font(REFont.body).foregroundColor(REColors.textSec)
                                Spacer()
                                Text(userName).font(REFont.body).foregroundColor(REColors.text).lineLimit(1)
                                Image(systemName: "pencil").font(.system(size: 11)).foregroundColor(REColors.textDim)
                            }
                            .padding(.horizontal, RE.s16).padding(.vertical, RE.s12)
                        }
                        if let msg = nameMsg {
                            Text(msg)
                                .font(REFont.small)
                                .foregroundColor(REColors.confGreen)
                                .padding(.horizontal, RE.s16)
                                .padding(.bottom, RE.s8)
                        }
                        Divider().background(REColors.bgInput)
                        infoRow("envelope", "Email", userEmail)
                    }
                    .background(REColors.bgCard).cornerRadius(RE.r12)

                    
                    // Audio data section - shows contribution count
                    sectionHeader("Audio Data")
                    VStack(spacing: RE.s12) {
                        HStack(spacing: RE.s12) {
                            Image(systemName: "waveform")
                                .font(.system(size: 18))
                                .foregroundColor(REColors.blueLight)
                            Text(audioCount == 0 ? "No audio samples" : "\(audioCount) sample\(audioCount == 1 ? "" : "s") contributed")
                                .font(REFont.body).foregroundColor(REColors.text)
                            Spacer()
                        }
                    }
                    .padding(RE.s16).background(REColors.bgCard).cornerRadius(RE.r12)

                    
                    // Cloud sync section - shows pending count with manual sync button
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
                                    Text(isSyncing ? "Syncing..." : "Sync Now")
                                }
                            }
                            .buttonStyle(REPrimaryButton())
                            .disabled(isSyncing)
                        }
                    }
                    .padding(RE.s16).background(REColors.bgCard).cornerRadius(RE.r12)

                    
                    // Data summary showing total counts
                    sectionHeader("Data")
                    VStack(spacing: 0) {
                        dataRow("car.fill", "\(db.fetchAllDetections().count) detections")
                        Divider().background(REColors.bgInput)
                        dataRow("waveform", "\(audioCount) audio samples")
                        Divider().background(REColors.bgInput)
                        dataRow("trophy.fill", "\(BadgeService.shared.badges.filter { $0.earned }.count) badges earned")
                    }
                    .background(REColors.bgCard).cornerRadius(RE.r12)

                    
                    // App version and ML model info
                    sectionHeader("About")
                    VStack(spacing: 0) {
                        infoRow("app", "App", "RevEye")
                        Divider().background(REColors.bgInput)
                        infoRow("number", "Version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        Divider().background(REColors.bgInput)
                        infoRow("cpu", "Model", "EfficientNet-B4 (196 classes)")
                    }
                    .background(REColors.bgCard).cornerRadius(RE.r12)

                    sectionHeader("Legal")
                    NavigationLink { PrivacyPolicyView() } label: {
                        HStack(spacing: RE.s12) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 14)).foregroundColor(REColors.textDim).frame(width: 20)
                            Text("Privacy Policy")
                                .font(REFont.body).foregroundColor(REColors.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11)).foregroundColor(REColors.textDim)
                        }
                        .padding(.horizontal, RE.s16).padding(.vertical, RE.s12)
                    }
                    .background(REColors.bgCard).cornerRadius(RE.r12)

                    sectionHeader("Developer")
                    NavigationLink { DatabaseInspector() } label: {
                        HStack(spacing: RE.s12) {
                            Image(systemName: "cylinder.split.1x2")
                                .font(.system(size: 14)).foregroundColor(REColors.blueLight).frame(width: 20)
                            Text("Local Database")
                                .font(REFont.body).foregroundColor(REColors.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11)).foregroundColor(REColors.textDim)
                        }
                        .padding(.horizontal, RE.s16).padding(.vertical, RE.s12)
                    }
                    .background(REColors.bgCard).cornerRadius(RE.r12)

                    // Sign out button
                    Button("Sign Out") { AuthService.shared.signOut() }
                        .buttonStyle(REPrimaryButton(color: REColors.accent))
                        .padding(.top, RE.s8)

                    
                    // Delete account button - destructive red, requires confirmation
                    Button("Delete Account") { showDeleteAccountConfirm = true }
                        .buttonStyle(REDestructiveButton())

                    if let err = deleteAccountError {
                        Text(err)
                            .font(REFont.small)
                            .foregroundColor(REColors.error)
                            .padding(.horizontal, RE.s4)
                    }

                    Spacer().frame(height: RE.s48)
                }
                .padding(.horizontal, RE.s16)
                .padding(.top, RE.s8)
            }
        }
        .navigationTitle("Settings")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { refreshData() }
                // Alert with text field for changing the user's display name
                .alert("Change Display Name", isPresented: $showChangeNameAlert) {
            TextField("New name", text: $newDisplayName)
            Button("Save") { changeName() }
            Button("Cancel", role: .cancel) { newDisplayName = "" }
        } message: {
            Text("Enter your new display name.")
        }
                // Confirmation dialog before permanently deleting the account
                .alert("Delete Account?", isPresented: $showDeleteAccountConfirm) {
            Button("Delete Permanently", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account and all associated data. This action cannot be undone.")
        }
    }

    // Data

    // Reload sync count, audio count, and duration from the database
    private func refreshData() {
        unsyncedCount = db.fetchUnsyncedDetections().count
        audioCount = db.audioSampleCount()
    }

    // Change Name

    private func changeName() {
        let trimmed = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let user = Auth.auth().currentUser else { return }

        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = trimmed
        changeRequest.commitChanges { error in
            if let error {
                print("Name change error: \(error.localizedDescription)")
                nameMsg = "Failed to update name"
            } else {
                nameMsg = "Name updated!"
                newDisplayName = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    nameMsg = nil
                }
            }
        }
    }

    // Delete Account

    // Permanently deletes the user's account. Order matters:
    //   1. Clear their Firestore data while we still have a valid auth token.
    //   2. Delete the Firebase Auth user itself.
    //   3. Wipe local SQLite and saved images.
    // If step 2 fails (Firebase sometimes requires a recent sign-in for
    // sensitive operations) the error is surfaced so the user can sign
    // out, sign back in, and try again.
    private func deleteAccount() {
        guard let user = Auth.auth().currentUser else { return }
        // Capture the uid up front: after user.delete() the current user is
        // gone, and ImageStore needs the uid to find this account's folder.
        let uid = user.uid

        FirebaseService.shared.deleteAllCloudData { cloudError in
            if let cloudError {
                deleteAccountError = "Failed to clear cloud data: \(cloudError.localizedDescription)"
                return
            }
            user.delete { error in
                if let error {
                    deleteAccountError = "Failed: \(error.localizedDescription). You may need to sign out and sign back in first."
                    print("Delete account error: \(error.localizedDescription)")
                    return
                }
                db.resetAllUserData()
                BadgeService.shared.clearLocal()
                ImageStore.deleteAll(forUid: uid)
                AuthService.shared.user = nil
            }
        }
    }

    // Components

    // Reusable section header label used throughout settings
    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(REFont.label).foregroundColor(REColors.textDim).padding(.top, RE.s4)
    }

    // Reusable row showing an icon, label, and value
    private func infoRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: RE.s12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(REColors.textDim).frame(width: 20)
            Text(label).font(REFont.body).foregroundColor(REColors.textSec)
            Spacer()
            Text(value).font(REFont.body).foregroundColor(REColors.text).lineLimit(1)
        }
        .padding(.horizontal, RE.s16).padding(.vertical, RE.s12)
    }

    // Simpler row for the data summary section
    private func dataRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: RE.s12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(REColors.blueLight).frame(width: 20)
            Text(text).font(REFont.body).foregroundColor(REColors.text)
            Spacer()
        }
        .padding(.horizontal, RE.s16).padding(.vertical, RE.s12)
    }

    // Sync

    // Manually triggers upload of all unsynced detections to Firebase
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
            refreshData()
            syncMsg = ok == unsynced.count ? "All synced!" : "\(ok)/\(unsynced.count) synced"
        }
    }
}
