//
//  CollectionView.swift
//  RevEye
//
//  Created 14/03/2026 — collection/garage view grouped by make

import SwiftUI

struct CollectionView: View {
    private let db = DatabaseManager.shared
    @State private var detections: [Detection] = []

    private var makes: [(make: String, models: [(label: String, confidence: Double, count: Int)])] {
        var labelData: [String: (confidence: Double, count: Int)] = [:]
        for d in detections {
            let existing = labelData[d.vehicleLabel]
            labelData[d.vehicleLabel] = (
                confidence: max(existing?.confidence ?? 0, d.confidence),
                count: (existing?.count ?? 0) + 1
            )
        }

        var grouped: [String: [(label: String, confidence: Double, count: Int)]] = [:]
        for (label, data) in labelData {
            let make = label.components(separatedBy: " ").first ?? "Unknown"
            grouped[make, default: []].append((label: label, confidence: data.confidence, count: data.count))
        }

        return grouped.map { (make: $0.key, models: $0.value.sorted { $0.confidence > $1.confidence }) }
            .sorted { $0.make < $1.make }
    }

    private var uniqueModels: Int { Set(detections.map { $0.vehicleLabel }).count }
    private var uniqueMakes: Int { Set(detections.compactMap { $0.vehicleLabel.components(separatedBy: " ").first }).count }

    var body: some View {
        ZStack {
            REColors.bg.ignoresSafeArea()

            if detections.isEmpty {
                VStack(spacing: RE.s16) {
                    Image(systemName: "car.2.fill")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundColor(REColors.textDim)
                    Text("Your garage is empty")
                        .font(REFont.heading).foregroundColor(REColors.textSec)
                    Text("Scan vehicles to build your collection")
                        .font(REFont.caption).foregroundColor(REColors.textDim)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: RE.s24) {

                        // Summary pills
                        HStack(spacing: RE.s8) {
                            summaryPill("\(uniqueModels)", "Models", REColors.blue)
                            summaryPill("\(uniqueMakes)", "Makes", REColors.accent)
                            summaryPill("\(detections.count)", "Scans", REColors.confGreen)
                        }
                        .padding(.horizontal, RE.s16)
                        .padding(.top, RE.s8)

                        // Makes
                        ForEach(makes, id: \.make) { group in
                            makeSection(group.make, group.models)
                        }
                    }
                    .padding(.bottom, RE.s48)
                }
            }
        }
        .navigationTitle("My Garage")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { detections = db.fetchAllDetections() }
    }

    private func summaryPill(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: RE.s4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(REFont.small)
                .foregroundColor(REColors.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, RE.s12)
        .background(REColors.bgCard)
        .cornerRadius(RE.r12)
    }

    private func makeSection(_ make: String, _ models: [(label: String, confidence: Double, count: Int)]) -> some View {
        VStack(alignment: .leading, spacing: RE.s8) {
            HStack {
                Text(make)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(REColors.text)
                Spacer()
                Text("\(models.count) model\(models.count == 1 ? "" : "s")")
                    .font(REFont.small)
                    .foregroundColor(REColors.textDim)
            }
            .padding(.horizontal, RE.s16)

            ForEach(models, id: \.label) { model in
                modelRow(model)
                    .padding(.horizontal, RE.s16)
            }
        }
    }

    private func modelRow(_ model: (label: String, confidence: Double, count: Int)) -> some View {
        let confColor = REColors.displayConf(model.confidence)

        return HStack(spacing: RE.s12) {
            // Confidence indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(confColor)
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.label)
                    .font(REFont.body)
                    .foregroundColor(REColors.text)
                    .lineLimit(1)
                HStack(spacing: RE.s8) {
                    Text("Best: \(Int(model.confidence * 100))%")
                        .font(REFont.small)
                        .foregroundColor(confColor)
                    if model.count > 1 {
                        Text("·").foregroundColor(REColors.textDim)
                        Text("Scanned \(model.count)x")
                            .font(REFont.small)
                            .foregroundColor(REColors.textDim)
                    }
                }
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(confColor.opacity(0.6))
        }
        .padding(.vertical, RE.s8)
        .padding(.horizontal, RE.s12)
        .background(REColors.bgCard)
        .cornerRadius(RE.r8)
    }
}
