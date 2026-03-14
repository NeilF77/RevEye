//
//  OnboardingView.swift
//  RevEye
//
//  Created 14/03/2026 — lightweight 3-screen first-launch onboarding

import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    private let pages: [(icon: String, title: String, subtitle: String)] = [
        ("viewfinder", "Scan", "Point your camera at any vehicle and RevEye will identify it using AI."),
        ("sparkles", "Identify", "Get the make, model, and year — even when our model isn't sure, you can help it learn."),
        ("car.2.fill", "Collect", "Build your garage, earn badges, and track every vehicle you discover.")
    ]

    var body: some View {
        ZStack {
            REColors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(REColors.bgCard)
                        .frame(width: 120, height: 120)
                    Image(systemName: pages[currentPage].icon)
                        .font(.system(size: 42, weight: .ultraLight))
                        .foregroundColor(currentPage == 1 ? REColors.accent : REColors.blue)
                }

                Spacer().frame(height: RE.s32)

                // Title
                Text(pages[currentPage].title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(REColors.text)

                Spacer().frame(height: RE.s12)

                // Subtitle
                Text(pages[currentPage].subtitle)
                    .font(REFont.body)
                    .foregroundColor(REColors.textSec)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RE.s48)

                Spacer()

                // Dots
                HStack(spacing: RE.s8) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i == currentPage ? REColors.accent : REColors.textDim.opacity(0.4))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer().frame(height: RE.s32)

                // Button
                Button {
                    if currentPage < 2 {
                        withAnimation(.easeInOut(duration: 0.25)) { currentPage += 1 }
                    } else {
                        hasCompletedOnboarding = true
                    }
                } label: {
                    Text(currentPage < 2 ? "Next" : "Get Started")
                }
                .buttonStyle(REPrimaryButton())
                .padding(.horizontal, RE.s24)

                // Skip
                if currentPage < 2 {
                    Button("Skip") {
                        hasCompletedOnboarding = true
                    }
                    .font(REFont.label)
                    .foregroundColor(REColors.textDim)
                    .padding(.top, RE.s12)
                }

                Spacer().frame(height: RE.s48)
            }
        }
    }
}
