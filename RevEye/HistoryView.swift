//
//  HistoryView.swift
//  RevEye
//
//  UI overhaul v8 — no floating sync button, integrated banner only

import SwiftUI

struct HistoryView: View {
    @Binding var detections: [Detection]
    @State private var isSyncing = false
    @State private var syncMsg: String?
    private let db = DatabaseManager.shared

    private var unsyncedCount: Int { detections.filter { $0.synced == 0 }.count }

    private var grouped: [(String, [Detection])] {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        let iso = ISO8601DateFormatter()

        var dict: [String: [Detection]] = [:]
        var order: [String] = []

        for det in detections {
            let key: String
            if let date = iso.date(from: det.timestamp) {
                key = fmt.string(from: date)
            } else { key = "Unknown" }
            if dict[key] == nil { order.append(key) }
            dict[key, default: []].append(det)
        }
        return order.map { ($0, dict[$0]!) }
    }

    var body: some View {
        NavigationView {
            ZStack {
                REColors.bg.ignoresSafeArea()

                if detections.isEmpty {
                    emptyView
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: RE.s24) {

                            // Sync banner — only when items are pending
                            if unsyncedCount > 0 {
                                syncBanner.padding(.horizontal, RE.s16)
                            }

                            ForEach(grouped, id: \.0) { month, dets in
                                VStack(alignment: .leading, spacing: RE.s12) {
                                    Text(month)
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundColor(REColors.text)
                                        .padding(.horizontal, RE.s16)
                                        .padding(.top, RE.s8)

                                    ForEach(dets) { det in
                                        NavigationLink {
                                            DetectionDetailView(detection: det) {
                                                if let id = det.id {
                                                    db.deleteDetection(id: id)
                                                    detections = db.fetchAllDetections()
                                                }
                                            }
                                        } label: {
                                            detRow(det)
                                        }
                                        .padding(.horizontal, RE.s16)
                                    }
                                }
                            }
                        }
                        .padding(.top, RE.s8)
                        .padding(.bottom, RE.s48)
                    }
                }
            }
            .navigationTitle("History")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { detections = db.fetchAllDetections() }
        }
    }

    private var emptyView: some View {
        VStack(spacing: RE.s16) {
            Image(systemName: "viewfinder")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundColor(REColors.textDim)
            Text("No detections yet")
                .font(REFont.heading).foregroundColor(REColors.textSec)
            Text("Scan your first vehicle to start your collection")
                .font(REFont.caption).foregroundColor(REColors.textDim)
        }
    }

    private var syncBanner: some View {
        HStack(spacing: RE.s12) {
            Image(systemName: "icloud.and.arrow.up")
                .foregroundColor(REColors.accent).font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(unsyncedCount) detection\(unsyncedCount == 1 ? "" : "s") not synced")
                    .font(REFont.label).foregroundColor(REColors.text)
                if let m = syncMsg {
                    Text(m).font(REFont.small).foregroundColor(REColors.textDim)
                }
            }

            Spacer()

            Button {
                syncAll()
            } label: {
                if isSyncing {
                    ProgressView().tint(REColors.bg)
                        .frame(width: 60, height: 28)
                } else {
                    Text("Sync")
                        .font(REFont.small).fontWeight(.semibold)
                        .foregroundColor(REColors.bg)
                        .padding(.horizontal, RE.s12).padding(.vertical, RE.s4)
                        .background(REColors.accent).cornerRadius(100)
                }
            }
            .disabled(isSyncing)
        }
        .padding(RE.s12)
        .background(REColors.bgCard)
        .cornerRadius(RE.r12)
    }

    private func detRow(_ det: Detection) -> some View {
        let confColor = REColors.displayConf(det.confidence)
        let hasImage = det.id != nil && ImageStore.exists(for: det.id!)

        return HStack(spacing: RE.s12) {
            if hasImage, let id = det.id, let img = ImageStore.load(for: id) {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: 48, height: 36)
                    .cornerRadius(RE.r8).clipped()
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(confColor)
                    .frame(width: 3, height: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: RE.s4) {
                    Text(det.vehicleLabel)
                        .font(REFont.body).foregroundColor(REColors.text).lineLimit(1)
                    if det.audioSampleId != nil {
                        Image(systemName: "waveform")
                            .font(.system(size: 9)).foregroundColor(REColors.blueLight)
                    }
                }
                HStack(spacing: RE.s8) {
                    Text("\(Int(det.confidence * 100))%")
                        .font(REFont.small).foregroundColor(confColor)
                    Text("·").foregroundColor(REColors.textDim)
                    Text(fmtDate(det.timestamp))
                        .font(REFont.small).foregroundColor(REColors.textDim)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11)).foregroundColor(REColors.textDim)
        }
        .padding(.vertical, RE.s8)
    }

    private func syncAll() {
        let un = db.fetchUnsyncedDetections()
        guard !un.isEmpty else { syncMsg = "All synced"; return }
        isSyncing = true; syncMsg = nil
        let g = DispatchGroup(); var ok = 0
        for d in un { g.enter(); FirebaseService.shared.uploadDetection(d) { s in if s { ok += 1 }; g.leave() } }
        g.notify(queue: .main) {
            detections = db.fetchAllDetections()
            isSyncing = false
            syncMsg = ok == un.count ? "All synced!" : "\(ok)/\(un.count) synced"
        }
    }

    private func fmtDate(_ iso: String) -> String {
        let p = ISO8601DateFormatter()
        guard let d = p.date(from: iso) else { return iso }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: d)
    }
}
