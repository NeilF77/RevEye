// SuggestionView.swift
// RevEye
//
// Shows the top 3 ML predictions as selectable options when the model is not
// confident, or when the user taps "Not right?" to correct a prediction.
// Also offers a "None of these / Unknown" option.

import SwiftUI

struct SuggestionView: View {
    // The classification result with top 3 predictions
    let output: ClassificationOutput
    let headerText: String
    // Called when the user picks one of the suggestions
    let onSelect: (String, Double) -> Void
    // Called when the user taps "None of these / Unknown"
    let onSaveUnknown: (() -> Void)?
    // Called when the user decides not to save at all
    let onSkip: (() -> Void)?

    @State private var picked: Int? = nil
    @State private var done = false

    init(output: ClassificationOutput,
         headerText: String = "Which of these looks right?",
         onSelect: @escaping (String, Double) -> Void,
         onSaveUnknown: (() -> Void)? = nil,
         onSkip: (() -> Void)? = nil) {
        self.output = output
        self.headerText = headerText
        self.onSelect = onSelect
        self.onSaveUnknown = onSaveUnknown
        self.onSkip = onSkip
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RE.s16) {

            VStack(alignment: .leading, spacing: RE.s4) {
                Text(headerText)
                    .font(REFont.label)
                    .foregroundColor(REColors.textSec)

                Text("Pick the closest match below, or choose 'Unknown' if none are right.")
                    .font(REFont.small)
                    .foregroundColor(REColors.textDim)
            }

                        // Show each of the top 3 ML predictions as a selectable option
                        ForEach(Array(output.top3.prefix(3).enumerated()), id: \.offset) { i, pred in
                optionRow(i, pred.label, pred.confidence, i == 0)
            }

            notSureRow

            if !done {
                VStack(spacing: RE.s8) {
                    if picked != nil {
                        Button(picked == -1 ? "Save as Unknown" : "Save Selection") {
                            confirm()
                        }
                        .buttonStyle(REPrimaryButton(color: REColors.accent))
                    }

                    if let onSkip {
Button {
                            onSkip()
                        } label: {
                            Text("Don't Save")
                                .font(REFont.label)
                                .foregroundColor(REColors.destructiveText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                }
            }

            if done {
                HStack(spacing: RE.s8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(REColors.success)
                        .font(.system(size: 14))
                    Text(picked == -1 ? "Saved as unknown" : "Saved - thanks for helping RevEye learn!")
                        .font(REFont.caption)
                        .foregroundColor(REColors.success)
                }
            }
        }
    }

    private func optionRow(_ index: Int, _ label: String, _ conf: Double, _ isTop: Bool) -> some View {
        let sel = picked == index
        let confColor = REColors.displayConf(conf)
        let rankLabel = isTop ? "Best match" : (index == 1 ? "2nd guess" : "3rd guess")

        return Button { if !done { picked = index } } label: {
            HStack(spacing: RE.s12) {
                Circle()
                    .stroke(sel ? REColors.accent : REColors.textDim, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().fill(sel ? REColors.accent : Color.clear).frame(width: 10, height: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(REFont.body)
                        .foregroundColor(REColors.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(rankLabel)
                        .font(REFont.small)
                        .foregroundColor(isTop ? confColor : REColors.textDim)
                }

                Spacer()

                Text("\(Int(conf * 100))%")
                    .font(REFont.label)
                    .foregroundColor(confColor)
                    .monospacedDigit()
            }
            .padding(.vertical, RE.s12)
            .padding(.horizontal, RE.s12)
            .background(sel ? REColors.accent.opacity(0.06) : Color.clear)
            .cornerRadius(RE.r8)
        }
        .disabled(done)
    }

    private var notSureRow: some View {
        let sel = picked == -1
        return Button { if !done { picked = -1 } } label: {
            HStack(spacing: RE.s12) {
                Circle()
                    .stroke(sel ? REColors.confNone : REColors.textDim, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().fill(sel ? REColors.confNone : Color.clear).frame(width: 10, height: 10))
                Text("None of these / Unknown")
                    .font(REFont.body)
                    .foregroundColor(REColors.textSec)
                Spacer()
            }
            .padding(.vertical, RE.s8)
            .padding(.horizontal, RE.s12)
        }
        .disabled(done)
    }

    private func confirm() {
        guard let i = picked else { return }
        done = true
        if i == -1 {
            onSaveUnknown?()
        } else if i < output.top3.count {
            let p = output.top3[i]
            onSelect(p.label, p.confidence)
        }
    }
}
