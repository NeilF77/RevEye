// GarageView.swift
// RevEye
//
// The Garage tab showing all saved detections. Supports searching by name,
// sorting by date/confidence/make, and filtering between identified and
// unknown vehicles. Grouped by month when sorted by date. Includes a sync
// banner for unsynced detections and an empty state with a "Start Scanning" button.

import SwiftUI
import AVFoundation
// Sort options for the garage list
private enum SortOption: String, CaseIterable {
    case dateFound = "Date Found"
    case confidence = "Confidence"
    case make = "Make A-Z"
}
// Filter between identified vehicles and unknown ones
private enum GarageFilter: String, CaseIterable {
    case identified = "Identified"
    case unknown = "Unknown"
}

struct GarageView: View {
    // Database reference and local state for the view
    private let db = DatabaseManager.shared
    // All detections loaded from the database
    @State private var detections: [Detection] = []
    @State private var searchText = ""
    @State private var sortBy: SortOption = .dateFound
    @State private var filter: GarageFilter = .identified

    // Audio playback state
    @State private var playingDetectionId: Int64? = nil
    @State private var audioPlayer: AVAudioPlayer?
    @State private var showAudioMissing = false

    private static let unknownLabels: Set<String> = ["Unknown Vehicle", "Unknown"]

    // Splits detections into identified (has a real vehicle label) and unknown
    private var identifiedDetections: [Detection] {
        detections.filter { !Self.unknownLabels.contains($0.vehicleLabel) }
    }

    private var unknownDetections: [Detection] {
        detections.filter { Self.unknownLabels.contains($0.vehicleLabel) }
    }

    private var activeDetections: [Detection] {
        filter == .identified ? identifiedDetections : unknownDetections
    }

    // Applies search text and sort order to the active detection list
    private var filteredDetections: [Detection] {
        var result = activeDetections

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter { $0.vehicleLabel.lowercased().contains(q) }
        }

        switch sortBy {
        case .dateFound:
            result.sort { $0.timestamp > $1.timestamp }
        case .confidence:
            result.sort { $0.confidence > $1.confidence }
        case .make:
            result.sort {
                let m0 = $0.vehicleLabel.components(separatedBy: " ").first ?? ""
                let m1 = $1.vehicleLabel.components(separatedBy: " ").first ?? ""
                return m0 == m1 ? $0.vehicleLabel < $1.vehicleLabel : m0 < m1
            }
        }

        return result
    }

    // Groups detections by month for the date-sorted view
    private var groupedByMonth: [(String, [Detection])] {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        let iso = ISO8601DateFormatter()

        var dict: [String: [Detection]] = [:]
        var order: [String] = []

        for det in filteredDetections {
            let key: String
            if let date = iso.date(from: det.timestamp) {
                key = fmt.string(from: date)
            } else { key = "Unknown" }
            if dict[key] == nil { order.append(key) }
            dict[key, default: []].append(det)
        }
        return order.map { ($0, dict[$0]!) }
    }

    private var uniqueModels: Int { Set(identifiedDetections.map { $0.vehicleLabel }).count }
    private var uniqueMakes: Int {
        Set(identifiedDetections.compactMap { $0.vehicleLabel.components(separatedBy: " ").first }).count
    }

    private var unsyncedCount: Int { detections.filter { $0.synced == 0 }.count }
    @State private var isSyncing = false
    @State private var syncMsg: String?

    var body: some View {
        ZStack {
            REColors.bg.ignoresSafeArea()

            
            // Empty state - shown when the user hasn't saved any detections yet
if detections.isEmpty {
                VStack(spacing: RE.s16) {
                    Image(systemName: "car.2.fill")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundColor(REColors.textDim)
                    Text("Your garage is empty")
                        .font(REFont.heading).foregroundColor(REColors.textSec)
                    Text("Scan your first vehicle to start your collection")
                        .font(REFont.caption).foregroundColor(REColors.textDim)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, RE.s32)
                    Button {
                        NotificationCenter.default.post(name: .switchToScanTab, object: nil)
                    } label: {
                        
HStack(spacing: RE.s8) {
                            Image(systemName: "viewfinder")
                            Text("Start Scanning")
                        }
                    }
                    .buttonStyle(REPrimaryButton())
                    .padding(.horizontal, RE.s48)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: RE.s16) {

                        
HStack(spacing: RE.s8) {
                            summaryPill("\(uniqueModels)", "Models", REColors.blue)
                            summaryPill("\(uniqueMakes)", "Makes", REColors.accent)
                            summaryPill("\(detections.count)", "Scans", REColors.confGreen)
                        }
                        .padding(.horizontal, RE.s16)
                        .padding(.top, RE.s8)

                        
                        // Sync banner - shown when detections haven't been uploaded yet
if unsyncedCount > 0 {
                            syncBanner.padding(.horizontal, RE.s16)
                        }

                        
                        // Filter toggle between Identified and Unknown vehicles
HStack(spacing: 0) {
                            filterTab(.identified, count: identifiedDetections.count)
                            filterTab(.unknown, count: unknownDetections.count)
                        }
                        .background(REColors.bgInput)
                        .cornerRadius(RE.r12)
                        .padding(.horizontal, RE.s16)

                        if filter == .identified {
                            
HStack(spacing: RE.s12) {
                                
HStack(spacing: RE.s8) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 14))
                                        .foregroundColor(REColors.textDim)
                                    TextField("Search vehicles…", text: $searchText)
                                        .font(REFont.body)
                                        .foregroundColor(REColors.text)
                                    if !searchText.isEmpty {
                                        Button { searchText = "" } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(REColors.textDim)
                                        }
                                    }
                                }
                                .padding(RE.s12)
                                .background(REColors.bgInput)
                                .cornerRadius(RE.r12)

                                Menu {
                                    ForEach(SortOption.allCases, id: \.self) { option in
                                        Button {
                                            sortBy = option
                                        } label: {
                                            HStack {
                                                Text(option.rawValue)
                                                if sortBy == option {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "arrow.up.arrow.down")
                                        .font(.system(size: 14))
                                        .foregroundColor(REColors.accent)
                                        .padding(RE.s12)
                                        .background(REColors.bgInput)
                                        .cornerRadius(RE.r12)
                                }
                            }
                            .padding(.horizontal, RE.s16)

                                                        // Shows current sort mode as a label
Text("Sorted by \(sortBy.rawValue)")
                                .font(REFont.small)
                                .foregroundColor(REColors.textDim)
                                .padding(.horizontal, RE.s16)
                        }

                        
                        // No results message when search/filter returns nothing
if filteredDetections.isEmpty {
                            VStack(spacing: RE.s8) {
                                Text(filter == .unknown ? "No unknown vehicles" : "No results")
                                    .font(REFont.heading).foregroundColor(REColors.textSec)
                                if filter == .identified && !searchText.isEmpty {
                                    Text("Try a different search term")
                                        .font(REFont.caption).foregroundColor(REColors.textDim)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, RE.s32)
                        } else 
                        // When sorted by date, group detections by month
if sortBy == .dateFound {
                                                        // Date-grouped sections with month headers
ForEach(groupedByMonth, id: \.0) { month, dets in
                                VStack(alignment: .leading, spacing: RE.s8) {
                                    Text(month)
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(REColors.text)
                                        .padding(.horizontal, RE.s16)
                                        .padding(.top, RE.s4)

                                    ForEach(dets) { det in
                                        detRowWithAudio(det)
                                        .padding(.horizontal, RE.s16)
                                    }
                                }
                            }
                        } else {
                                                        // Flat list for confidence and make sorts
ForEach(filteredDetections) { det in
                                detRowWithAudio(det)
                                .padding(.horizontal, RE.s16)
                            }
                        }
                    }
                    .padding(.bottom, RE.s48)
                }
            }
        }
        .navigationTitle("My Garage")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { detections = db.fetchAllDetections() }
        .onDisappear { audioPlayer?.stop(); playingDetectionId = nil }
        .alert("Audio File Missing", isPresented: $showAudioMissing) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This audio file is no longer available. Try recording a new video to capture fresh audio.")
        }
    }

    // Audio Playback

    // Plays or stops an audio sample linked to a detection
    private func toggleAudioPlayback(for detectionId: Int64, audioSampleId: Int64) {
        if playingDetectionId == detectionId {
            audioPlayer?.stop()
            playingDetectionId = nil
            return
        }

        let allSamples = db.fetchAllAudioSamples()
        guard let sample = allSamples.first(where: { $0.id == audioSampleId }) else {
            showAudioMissing = true
            return
        }

        let url = URL(fileURLWithPath: sample.localFilePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            showAudioMissing = true
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            playingDetectionId = detectionId

            let duration = sample.audioDuration > 0 ? sample.audioDuration : 10
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.5) {
                if playingDetectionId == detectionId {
                    playingDetectionId = nil
                }
            }
        } catch {
            print("Garage playback error: \(error.localizedDescription)")
            playingDetectionId = nil
        }
    }

    // Detection Row

    // A single row in the detection list showing thumbnail, label, confidence, and date
    private func detRow(_ det: Detection) -> some View {
        let confColor = det.vehicleLabel == "Unknown Vehicle" ? REColors.textDim : REColors.displayConf(det.confidence)
        let hasImage = det.id != nil && ImageStore.exists(for: det.id!)

        return 
HStack(spacing: RE.s12) {
            if hasImage, let id = det.id, let img = ImageStore.load(for: id) {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: 56, height: 42)
                    .cornerRadius(RE.r8).clipped()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: RE.r8)
                        .fill(REColors.bgInput)
                        .frame(width: 56, height: 42)
                    Image(systemName: "car.fill")
                        .font(.system(size: 16))
                        .foregroundColor(REColors.textDim)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: RE.s4) {
                    Text(det.vehicleLabel)
                        .font(REFont.body).foregroundColor(REColors.text).lineLimit(1)
                }
                
HStack(spacing: RE.s8) {
                    if det.vehicleLabel != "Unknown Vehicle" {
                        Text("\(Int(det.confidence * 100))%")
                            .font(REFont.small).foregroundColor(confColor)
                        Text("·").foregroundColor(REColors.textDim)
                    }
                    Text(fmtDate(det.timestamp))
                        .font(REFont.small).foregroundColor(REColors.textDim)
                    if det.synced == 0 {
                        Text("·").foregroundColor(REColors.textDim)
                        Image(systemName: "icloud.slash")
                            .font(.system(size: 9)).foregroundColor(REColors.accent)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11)).foregroundColor(REColors.textDim)
        }
        .padding(.vertical, RE.s8)
        .padding(.horizontal, RE.s12)
        .background(REColors.bgCard)
        .cornerRadius(RE.r8)
    }

    // Detection Row with Audio — wraps NavigationLink + play button side by side
    // so tapping play doesn't trigger navigation
    private func detRowWithAudio(_ det: Detection) -> some View {
        HStack(spacing: 0) {
            NavigationLink {
                DetectionView(detection: det) {
                    if let id = det.id {
                        db.deleteDetection(id: id)
                        ImageStore.delete(for: id)
                        detections = db.fetchAllDetections()
                    }
                }
            } label: {
                detRow(det)
            }

            // Play button sits outside the NavigationLink so taps don't conflict
            if det.audioSampleId != nil, let detId = det.id {
                Button {
                    toggleAudioPlayback(for: detId, audioSampleId: det.audioSampleId!)
                } label: {
                    Image(systemName: playingDetectionId == detId ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(REColors.accent)
                        .padding(.leading, RE.s8)
                        .padding(.trailing, RE.s12)
                        .padding(.vertical, RE.s8)
                }
                .buttonStyle(.plain)
                .background(REColors.bgCard)
                .cornerRadius(RE.r8)
            }
        }
    }

    // Sync Banner

    // Banner shown when there are unsynced detections, with a sync button
    private var syncBanner: some View {
        
HStack(spacing: RE.s12) {
            Image(systemName: "icloud.and.arrow.up")
                .foregroundColor(REColors.accent).font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(unsyncedCount) not synced")
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
                    ProgressView().tint(REColors.bg).frame(width: 60, height: 28)
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
        .padding(RE.s12).background(REColors.bgCard).cornerRadius(RE.r12)
    }

    // Filter Tab

    // Tab button for switching between Identified and Unknown filters
    private func filterTab(_ tab: GarageFilter, count: Int) -> some View {
        let selected = filter == tab
        return Button {
            filter = tab
            if tab == .unknown { searchText = "" }
        } label: {
            HStack(spacing: RE.s4) {
                Text(tab.rawValue).font(REFont.label)
                if count > 0 {
                    Text("\(count)")
                        .font(REFont.small)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(selected ? REColors.accent.opacity(0.2) : REColors.textDim.opacity(0.2))
                        .cornerRadius(100)
                }
            }
            .foregroundColor(selected ? REColors.accent : REColors.textDim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, RE.s12)
            .background(selected ? REColors.bgCard : Color.clear)
            .cornerRadius(RE.r12)
        }
    }

    // Summary Pill

    // Small stat pill showing a count and label (e.g. "12 Models")
    private func summaryPill(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: RE.s4) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundColor(color)
            Text(label).font(REFont.small).foregroundColor(REColors.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, RE.s12)
        .background(REColors.bgCard)
        .cornerRadius(RE.r12)
    }

    // Sync

    // Uploads all unsynced detections to Firebase in parallel
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

    // Formatting

    // Formats an ISO 8601 timestamp into a readable date string
    private func fmtDate(_ iso: String) -> String {
        let p = ISO8601DateFormatter()
        guard let d = p.date(from: iso) else { return iso }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: d)
    }
}
