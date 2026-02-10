//
//  AudioExtractor.swift
//  RevEye
//
//  Created by user on 29/11/2025.
//


import AVFoundation

struct AudioExtractor {
    static func extract(from videoURL: URL, completion: @escaping (URL?) -> Void) {
        let asset = AVAsset(url: videoURL)
        
        guard let exportSession = AVAssetExportSession(asset: asset,
                                                       presetName: AVAssetExportPresetAppleM4A) else {
            print("Unable to create AVAssetExportSession")
            completion(nil)
            return
        }
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio_\(UUID().uuidString).m4a")
        
        exportSession.outputFileType = .m4a
        exportSession.outputURL = outputURL
        
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
