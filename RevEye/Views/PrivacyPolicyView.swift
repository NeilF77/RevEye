// PrivacyPolicyView.swift
// RevEye
//
// Displays the app's privacy policy as scrollable text. Covers what data
// is collected, how it's stored, and how it's used for research.

import SwiftUI

struct PrivacyPolicyView: View {

    // Date shown at the top of the policy
    private let lastUpdated = "March 2026"

    var body: some View {
        ZStack {
            REColors.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: RE.s24) {

                    VStack(alignment: .leading, spacing: RE.s8) {
                        Text("Privacy Policy")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(REColors.text)
                        Text("Last updated: \(lastUpdated)")
                            .font(REFont.caption)
                            .foregroundColor(REColors.textDim)
                    }

                    policySection(
                        icon: "camera",
                        title: "Photos & Camera",
                        body: "RevEye accesses your camera and photo library only when you choose to scan a vehicle. Photos are processed on your device using the machine learning model. Saved detection images are stored locally on your device and are not uploaded to any server. No photos are shared with third parties."
                    )

                    policySection(
                        icon: "video",
                        title: "Videos",
                        body: "When you upload a video, frames are extracted and analysed on your device. The video file itself is not uploaded. If you choose to contribute audio, the audio track is extracted from the video on your device and may be uploaded to our database (see Audio Data below)."
                    )

                    policySection(
                        icon: "waveform",
                        title: "Audio Data",
                        body: "If you contribute audio from a video, the extracted audio clip and metadata (vehicle type, recording context, background noise level) are stored in our cloud database (Google Firebase). This data is used to build a research dataset of vehicle sounds. Audio contributions are anonymous — they are linked to your account ID but your name and email are not included in the dataset."
                    )

                    policySection(
                        icon: "icloud",
                        title: "Cloud Storage",
                        body: "RevEye uses Google Firebase for user authentication, detection sync, badge tracking, and audio sample storage. Your email address is stored securely by Firebase Authentication. Detection records (vehicle label, confidence score, timestamp) are synced to Firebase Firestore. All data is transmitted over encrypted connections (HTTPS)."
                    )

                    policySection(
                        icon: "person.circle",
                        title: "Your Account",
                        body: "You can view all your data within the app (Garage, Audio Library, Profile). You can delete individual detections or audio samples at any time. Signing out clears all local data from the device. To request deletion of your cloud data, contact the developer."
                    )

                    policySection(
                        icon: "hand.raised",
                        title: "Your Choices",
                        body: "All data contributions are voluntary. You can use RevEye to identify vehicles without saving detections or contributing audio. Camera and photo library access can be revoked at any time in your device Settings."
                    )

                    policySection(
                        icon: "graduationcap",
                        title: "Research Use",
                        body: "RevEye is a final year project at Technological University Dublin. Contributed audio data may be used for academic research into vehicle sound identification. No personally identifiable information is included in the research dataset."
                    )

                    policySection(
                        icon: "envelope",
                        title: "Contact",
                        body: "If you have questions about this privacy policy or your data, please contact the developer through Technological University Dublin."
                    )

                    Spacer().frame(height: RE.s48)
                }
                .padding(.horizontal, RE.s16)
                .padding(.top, RE.s8)
            }
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func policySection(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: RE.s8) {
            HStack(spacing: RE.s8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(REColors.accent)
                    .frame(width: 20)
                Text(title)
                    .font(REFont.heading)
                    .foregroundColor(REColors.text)
            }
            Text(body)
                .font(REFont.body)
                .foregroundColor(REColors.textSec)
                .lineSpacing(4)
        }
        .padding(RE.s16)
        .background(REColors.bgCard)
        .cornerRadius(RE.r12)
    }
}