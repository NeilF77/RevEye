// AudioExtractor.swift
// RevEye
//
// Extracts the audio track from a video file and saves it as an M4A file.
// Uses Apple's AVAssetExportSession which is built into iOS, so no third-party
// libraries are needed. FFmpegKit was originally planned but was abandoned
// because the library was archived and added 40MB to the app bundle.

import AVFoundation

struct AudioExtractor {

    // Extracts audio from a video and returns the URL of the saved M4A file.
    // Checks for an audio track first, then runs the export asynchronously.
    // Calls completion on the main thread with the output URL, or nil if it failed.
    static func extract(from videoURL: URL, completion: @escaping (URL?) -> Void) {
        let asset = AVAsset(url: videoURL)

    // Check that the video actually has an audio track before trying to export
        Task {
            let audioTracks = try? await asset.loadTracks(withMediaType: .audio)
            guard let tracks = audioTracks, !tracks.isEmpty else {
                print("AudioExtractor: No audio track found in video")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Audio track exists, proceed with extraction on main thread
            await MainActor.run {
                performExtraction(asset: asset, completion: completion)
            }
        }
    }

    // Async/await version of the extraction method for cleaner call sites.
    // Wraps the completion-based version using a checked continuation.
    static func extract(from videoURL: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { cont in
            extract(from: videoURL) { result in
                if let url = result {
                    cont.resume(returning: url)
                } else {
                    cont.resume(throwing: AudioExtractionError.extractionFailed)
                }
            }
        }
    }

    // Returns how long an audio file is in seconds. Used to display duration in the UI.
    static func duration(of audioURL: URL) -> Double {
        let asset = AVURLAsset(url: audioURL)
        return CMTimeGetSeconds(asset.duration)
    }

    // Does the actual export work. Creates an AVAssetExportSession configured
    // for M4A output, writes to a temp file, and checks the result.
    private static func performExtraction(asset: AVAsset, completion: @escaping (URL?) -> Void) {
        guard let exportSession = AVAssetExportSession(asset: asset,
                                                       presetName: AVAssetExportPresetAppleM4A) else {
            print("AudioExtractor: Unable to create AVAssetExportSession")
            completion(nil)
            return
        }

    // Generate a unique temp file path for the output
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reveye_audio_\(UUID().uuidString).m4a")

    // Remove any leftover file at this path
        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputFileType = .m4a
        exportSession.outputURL = outputURL

    // Run the export and handle the result
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    // Verify the output file is not empty
                    let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
                    let size = attrs?[.size] as? Int ?? 0
                    if size > 0 {
                        print("AudioExtractor: Success — \(outputURL.lastPathComponent) (\(size) bytes)")
                        completion(outputURL)
                    } else {
                        print("AudioExtractor: Output file is empty")
                        try? FileManager.default.removeItem(at: outputURL)
                        completion(nil)
                    }

                case .failed:
                    print("AudioExtractor: Failed — \(exportSession.error?.localizedDescription ?? "Unknown error")")
                    try? FileManager.default.removeItem(at: outputURL)
                    completion(nil)

                case .cancelled:
                    print("AudioExtractor: Cancelled")
                    try? FileManager.default.removeItem(at: outputURL)
                    completion(nil)

                default:
                    print("AudioExtractor: Unexpected status \(exportSession.status.rawValue)")
                    completion(nil)
                }
            }
        }
    }
}

// Custom error type for when extraction fails
enum AudioExtractionError: Error, LocalizedError {
    case extractionFailed
    case noAudioTrack

    var errorDescription: String? {
        switch self {
        case .extractionFailed: return "Could not extract audio from this video."
        case .noAudioTrack:     return "This video does not contain an audio track."
        }
    }
}
