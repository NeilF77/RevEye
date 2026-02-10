//
//  VideoPicker.swift
//  RevEye
//
//  Created by user on 16/11/2025.
//

import SwiftUI
import PhotosUI

// Wraps PHPickerViewController for selecting videos in SwiftUI
struct VideoPicker: UIViewControllerRepresentable {
    // Environment variable to dismiss the picker
    @Environment(\.presentationMode) private var presentationMode
    
    // Callback to return the selected video URL
    var onVideoPicked: (URL) -> Void

    // Creates and configures the PHPickerViewController
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos  // Only show videos
        config.selectionLimit = 1  // Allow only one video selection

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    // Updates the picker 
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    // Creates the coordinator that handles picker delegate methods
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // Handles PHPickerViewController delegate callbacks
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker

        init(_ parent: VideoPicker) {
            self.parent = parent
        }

        // Called when user finishes selecting videos
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Dismiss the picker
            parent.presentationMode.wrappedValue.dismiss()

            guard let provider = results.first?.itemProvider else { return }

            // Load the video file from the provider
            provider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, error in
                guard let url = url else { return }

                // Copy video to temporary directory (original is in Photos library sandbox)
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: tempURL)

                // Return the temporary URL on main thread
                DispatchQueue.main.async {
                    self.parent.onVideoPicked(tempURL)
                }
            }
        }
    }
}
