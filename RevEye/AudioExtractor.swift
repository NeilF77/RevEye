//
//  AudioExtractor.swift
//  RevEye
//
//  Created by user on 29/11/2025.
//

import AVFoundation

// Utility for extracting audio from video files
struct AudioExtractor {
    
    // Extracts audio track from a video and saves it as an M4A file
    // completion: Called with the URL of the extracted audio file, or nil if extraction fails
    static func extract(from videoURL: URL, completion: @escaping (URL?) -> Void) {
        // Load the video file as an AVAsset
        let asset = AVAsset(url: videoURL)
        
        // Create export session to extract audio in M4A format
        guard let exportSession = AVAssetExportSession(asset: asset,
                                                       presetName: AVAssetExportPresetAppleM4A) else {
            print("Unable to create AVAssetExportSession")
            completion(nil)
            return
        }
        
        // Generate unique temporary file path for the extracted audio
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio_\(UUID().uuidString).m4a")
        
        // Configure export session to output M4A audio
        exportSession.outputFileType = .m4a
        exportSession.outputURL = outputURL
        
        // Start async export process
        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                print("Audio extraction successful: \(outputURL)")
                completion(outputURL)
            default:
                print("Audio extraction failed: \(exportSession.error?.localizedDescription ?? "Unknown error")")
                completion(nil)
            }
        }
    }
}
