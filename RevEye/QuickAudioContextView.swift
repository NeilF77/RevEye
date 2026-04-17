//
//  QuickAudioContextView.swift
//  RevEye
//
//  Compact half-sheet for quick audio context — 2-3 taps then submit

import SwiftUI

struct QuickAudioContextView: View {
    let vehicleLabel: String
    let onSubmit: (EngineAudible, RecordingContext, VehicleState, NoiseLevel) -> Void
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

                        // Header
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

                        // Questions as chip rows
                        chipQuestion("Can you hear the engine?",
                                     options: EngineAudible.allCases, selection: $engineAudible) { $0.label }

                        chipQuestion("How was it recorded?",
                                     options: RecordingContext.allCases, selection: $recordingContext) { $0.label }

                        chipQuestion("Vehicle was…",
                                     options: VehicleState.allCases, selection: $vehicleState) { $0.label }

                        chipQuestion("Background noise?",
                                     options: NoiseLevel.allCases, selection: $backgroundNoise) { $0.label }

                        // Submit
                        Button {
                            onSubmit(engineAudible, recordingContext, vehicleState, backgroundNoise)
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