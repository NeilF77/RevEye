//
//  SuggestionPickerView.swift
//  RevEye
//
//  Created 12/03/2026 — UI overhaul
//  Top-3 predictions with confidence %, "Not sure" option, clean layout.

import SwiftUI

struct SuggestionPickerView: View {
    let output: ClassificationOutput
    let headerText: String
    let onSelect: (String, Double) -> Void
    let onSkip: (() -> Void)?

    @State private var selectedIndex: Int? = nil
    @State private var confirmed = false

    init(output: ClassificationOutput,
         headerText: String = "Which of these looks right?",
         onSelect: @escaping (String, Double) -> Void,
         onSkip: (() -> Void)? = nil) {
        self.output = output
        self.headerText = headerText
        self.onSelect = onSelect
        self.onSkip = onSkip
    }

    var body: some View {
        VStack(spacing: RESpacing.md) {
            // Header
            Text(headerText)
                .font(REFonts.callout)
                .foregroundColor(REColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Top-3 cards
            ForEach(Array(output.top3.prefix(3).enumerated()), id: \.offset) { index, prediction in
                suggestionRow(
                    index: index,
                    label: prediction.label,
                    confidence: prediction.confidence,
                    isTopPick: index == 0
                )
            }

            // Not sure
            Button {
                if !confirmed { selectedIndex = -1 }
            } label: {
                HStack(spacing: RESpacing.md) {
                    Image(systemName: selectedIndex == -1 ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(selectedIndex == -1 ? REColors.confNone : REColors.textMuted)
                    Text("I'm not sure / None of these")
                        .font(REFonts.body)
                        .foregroundColor(REColors.textSecondary)
                    Spacer()
                }
                .padding(RESpacing.md)
                .background(selectedIndex == -1 ? REColors.bgTertiary : Color.clear)
                .cornerRadius(RERadius.sm)
            }
            .disabled(confirmed)

            // Action buttons
            if !confirmed {
                HStack(spacing: RESpacing.md) {
                    // Skip / Don't save
                    if let onSkip {
                        Button("Don't Save") { onSkip() }
                            .buttonStyle(RESecondaryButton())
                    }

                    // Confirm
                    if selectedIndex != nil {
                        Button(selectedIndex == -1 ? "Save Best Guess" : "Confirm & Save") {
                            confirmSelection()
                        }
                        .buttonStyle(REPrimaryButton(color: REColors.accent))
                    }
                }
            }

            // Confirmed feedback
            if confirmed {
                HStack(spacing: RESpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(REColors.success)
                    Text("Saved — thanks for helping RevEye learn!")
                        .font(REFonts.caption)
                        .foregroundColor(REColors.success)
                }
                .padding(.top, RESpacing.xs)
            }
        }
    }

    // MARK: - Row

    private func suggestionRow(index: Int, label: String, confidence: Double, isTopPick: Bool) -> some View {
        let isSelected = selectedIndex == index
        return Button {
            if !confirmed { selectedIndex = index }
        } label: {
            HStack(spacing: RESpacing.md) {
                // Radio
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? REColors.accent : REColors.brandBlueDark)

                // Label
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(REFonts.body)
                        .fontWeight(.semibold)
                        .foregroundColor(REColors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                // Confidence + best match tag
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(confidence * 100))%")
                        .font(REFonts.title3)
                        .foregroundColor(REColors.forTier(ConfidenceTier.tier(for: confidence)))
                        .monospacedDigit()
                    if isTopPick {
                        Text("Best match")
                            .font(REFonts.caption2)
                            .foregroundColor(REColors.accent)
                    }
                }
            }
            .padding(RESpacing.md)
            .background(isSelected ? REColors.bgTertiary : REColors.bgElevated)
            .cornerRadius(RERadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: RERadius.md)
                    .stroke(isSelected ? REColors.accent.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
        }
        .disabled(confirmed)
    }

    // MARK: - Confirm

    private func confirmSelection() {
        guard let index = selectedIndex else { return }
        confirmed = true
        if index == -1 {
            let top = output.top3[0]
            onSelect(top.label, top.confidence)
        } else if index < output.top3.count {
            let pick = output.top3[index]
            onSelect(pick.label, pick.confidence)
        }
    }
}
