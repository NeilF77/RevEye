// AudioContextSheet.swift
// RevEye
//
// A compact modal sheet that appears after a video scan. Asks the user
// 4 quick questions about the audio: can they hear the engine, how was
// it recorded, what was the vehicle doing, and background noise level.

import SwiftUI

struct AudioContextSheet: View {
    // The vehicle name to display at the top of the form
    let vehicleLabel: String
    // Called with the user's answers when they tap Submit
    let onSubmit: (EngineAudible, RecordingContext, VehicleState, NoiseLevel) -> Void
    // Called when the user taps Skip to close without contributing
    let onSkip: () -> Void

    @State private var engineAudible: EngineAudible = .unsure
    @State private var recordingContext: RecordingContext = .outsideNear
    @State private var vehicleState: VehicleState = .unknown
    @State private var backgroundNoise: NoiseLevel = .moderate

    var body: some View {
        NavigationView {
            ZStack {
                REColors.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: RE.s16) {

                        
                        // Header showing waveform icon and vehicle name
                        HStack(spacing: RE.s12) {
                            Image(systemName: "waveform")
                                .font(.system(size: 18))
                                .foregroundColor(REColors.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Audio from this video")
                                    .font(REFont.heading)
                                    .foregroundColor(REColors.text)
                                Text(vehicleLabel)
                                    .font(REFont.caption)
                                    .foregroundColor(REColors.textDim)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.top, RE.s8)

                        
                        // Four quick questions about the audio recording conditions
                        chipQuestion("Can you hear the engine?",
                                     options: EngineAudible.allCases, selection: $engineAudible) { $0.label }

                        // If user says no engine sound, skip the detail questions
                        if engineAudible != .no {
                            chipQuestion("How was it recorded?",
                                         options: RecordingContext.allCases, selection: $recordingContext) { $0.label }

                            chipQuestion("Vehicle was...",
                                         options: VehicleState.allCases, selection: $vehicleState) { $0.label }

                            chipQuestion("Background noise?",
                                         options: NoiseLevel.allCases, selection: $backgroundNoise) { $0.label }
                        }

                        // Submit button
                        Button {
                            if engineAudible == .no {
                                onSubmit(.no, .other, .unknown, .moderate)
                            } else {
                                onSubmit(engineAudible, recordingContext, vehicleState, backgroundNoise)
                            }
                        } label: {
                            HStack(spacing: RE.s8) {
                                Image(systemName: "waveform.badge.plus")
                                Text("Submit Audio")
                            }
                        }
                        .buttonStyle(REPrimaryButton(color: REColors.accent))
                        .padding(.top, RE.s8)
                    }
                    .padding(.horizontal, RE.s16)
                }
            }
            .navigationTitle("Audio Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { onSkip() }
                        .foregroundColor(REColors.textDim)
                }
            }
        }
    }

    // Reusable chip-based question component. Shows a label and a row of
    // selectable chip buttons that highlight when tapped.
    private func chipQuestion<T: Hashable>(_ title: String, options: [T],
                                            selection: Binding<T>,
                                            label: @escaping (T) -> String) -> some View {
        VStack(alignment: .leading, spacing: RE.s8) {
            Text(title)
                .font(REFont.label)
                .foregroundColor(REColors.textSec)

            FlowLayout(spacing: RE.s8) {
                ForEach(options, id: \T.self) { option in
                    let selected = selection.wrappedValue == option
                    Button { selection.wrappedValue = option } label: {
                        Text(label(option))
                            .font(REFont.caption)
                            .foregroundColor(selected ? .white : REColors.textSec)
                            .padding(.horizontal, RE.s12)
                            .padding(.vertical, RE.s8)
                            .background(selected ? REColors.accent : REColors.bgInput)
                            .cornerRadius(100)
                    }
                }
            }
        }
    }
}

// FlowLayout
// Custom layout that wraps chips onto the next line when they don't fit.
// Used instead of a fixed grid so chip rows adapt to screen width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(proposal: proposal, subviews: subviews)
        for (i, pos) in r.positions.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxW = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            positions.append(CGPoint(x: x, y: y))
            rowH = max(rowH, s.height)
            x += s.width + spacing
            maxX = max(maxX, x)
        }
        return (positions, CGSize(width: maxX, height: y + rowH))
    }
}
