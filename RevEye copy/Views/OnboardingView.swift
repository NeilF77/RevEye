// OnboardingView.swift
// RevEye
//
// First-launch walkthrough with 5 screens explaining the app: Scan, Identify,
// Listen (audio feature), Collect (badges), and Share. Supports swipe
// navigation and a skip button.

import SwiftUI

struct OnboardingView: View {
    // When set to true, the app switches from onboarding to login/main
    @Binding var hasCompletedOnboarding: Bool
    // Which onboarding page is currently shown
    @State private var currentPage = 0

    // The 5 onboarding screens with their icon, title, subtitle, and accent colour
    private let pages: [(icon: String, title: String, subtitle: String, color: Color)] = [
        ("viewfinder",
         "Scan",
         "Point your camera at any vehicle and RevEye will identify it using AI.",
         REColors.blue),

        ("sparkles",
         "Identify",
         "Get the make, model, and year — even when our model isn't sure, you can help it learn.",
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
        
                // Coloured circle background behind the page icon
ZStack {
            REColors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

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

                
                // Page indicator dots - the active one is wider (capsule shape)
HStack(spacing: RE.s8) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Capsule()
                            .fill(i == currentPage ? pages[currentPage].color : REColors.textDim.opacity(0.4))
                            .frame(width: i == currentPage ? 20 : 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: currentPage)
                    }
                }

                Spacer().frame(height: RE.s32)

                
                // Next / Get Started button
Button {
                    
                // Skip button on all pages except the last one
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
                // Swipe left/right to navigate between pages
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
