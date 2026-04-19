// OnboardingView.swift
// RevEye
//
// First-launch walkthrough. Explains the main app features (Scan, Identify,
// Listen, Collect, Share) on swipeable pages with a skip button.

import SwiftUI

struct OnboardingView: View {
    // Flipped to true when the user finishes or skips. RootView watches this
    // to switch over to the login/main screen.
    @Binding var hasCompletedOnboarding: Bool

    @State private var currentPage = 0

    // Each page has an SF Symbol icon, a title, a short blurb, and an
    // accent colour for the icon circle + button.
    private let pages: [(icon: String, title: String, subtitle: String, color: Color)] = [
        ("viewfinder",
         "Scan",
         "Point your camera at any vehicle and RevEye will identify it using AI.",
         REColors.blue),

        ("sparkles",
         "Identify",
         "Get the make, model, and year. If the model isn't sure, you can help it learn.",
         REColors.accent),

        ("waveform",
         "Listen",
         "RevEye captures engine audio from your videos. Tag what you hear and contribute to a research sound library.",
         REColors.confGreen),

        ("car.2.fill",
         "Collect",
         "Build your garage, earn car-themed badges, and track every vehicle you discover.",
         REColors.blueLight),

        ("square.and.arrow.up",
         "Share",
         "Show off your rarest finds and badges with friends. The more you share, the more you earn.",
         REColors.accent),
    ]

    private var pageCount: Int { pages.count }

    var body: some View {
        ZStack {
            REColors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Coloured circle behind the page icon.
                ZStack {
                    Circle()
                        .fill(pages[currentPage].color.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Image(systemName: pages[currentPage].icon)
                        .font(.system(size: 42, weight: .ultraLight))
                        .foregroundColor(pages[currentPage].color)
                }

                Spacer().frame(height: RE.s32)

                Text(pages[currentPage].title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(REColors.text)

                Spacer().frame(height: RE.s12)

                Text(pages[currentPage].subtitle)
                    .font(REFont.body)
                    .foregroundColor(REColors.textSec)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, RE.s48)

                Spacer()

                // Page indicator dots. The active one stretches into a capsule
                // so it stands out at a glance.
                HStack(spacing: RE.s8) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Capsule()
                            .fill(i == currentPage ? pages[currentPage].color : REColors.textDim.opacity(0.4))
                            .frame(width: i == currentPage ? 20 : 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: currentPage)
                    }
                }

                Spacer().frame(height: RE.s32)

                // Next / Get Started button. On the final page this finishes
                // onboarding; otherwise it advances to the next page.
                Button {
                    if currentPage < pageCount - 1 {
                        withAnimation(.easeInOut(duration: 0.25)) { currentPage += 1 }
                    } else {
                        hasCompletedOnboarding = true
                    }
                } label: {
                    Text(currentPage < pageCount - 1 ? "Next" : "Get Started")
                }
                .buttonStyle(REPrimaryButton(color: pages[currentPage].color))
                .padding(.horizontal, RE.s24)

                // Skip on all pages except the last.
                if currentPage < pageCount - 1 {
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
        // Left/right swipe as an alternative to the Next button.
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -30, currentPage < pageCount - 1 {
                        withAnimation(.easeInOut(duration: 0.25)) { currentPage += 1 }
                    } else if value.translation.width > 30, currentPage > 0 {
                        withAnimation(.easeInOut(duration: 0.25)) { currentPage -= 1 }
                    }
                }
        )
    }
}
