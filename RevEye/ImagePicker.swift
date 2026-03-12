//
//  ImagePicker.swift
//  RevEye
//
//  Created by user on 29/11/2025.
//  Updated 12/03/2026 — supports both photo and video capture from camera

import SwiftUI
import UIKit

struct ImagePicker: UIViewControllerRepresentable {

    @Environment(\.presentationMode) var presentationMode

    var sourceType: UIImagePickerController.SourceType = .camera

    /// Called when the user takes a photo
    var onImagePicked: ((UIImage) -> Void)?
    /// Called when the user records a video
    var onVideoPicked: ((URL) -> Void)?

    // Legacy convenience init for photo-only usage
    init(sourceType: UIImagePickerController.SourceType = .camera, completion: @escaping (UIImage) -> Void) {
        self.sourceType = sourceType
        self.onImagePicked = completion
        self.onVideoPicked = nil
    }

    // Full init for photo + video
    init(sourceType: UIImagePickerController.SourceType = .camera,
         onImagePicked: ((UIImage) -> Void)? = nil,
         onVideoPicked: ((URL) -> Void)? = nil) {
        self.sourceType = sourceType
        self.onImagePicked = onImagePicked
        self.onVideoPicked = onVideoPicked
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator

        // Allow both photos and videos when opening camera
        if sourceType == .camera {
            picker.mediaTypes = ["public.image", "public.movie"]
            picker.videoMaximumDuration = 60 // 1 minute max for video
            picker.videoQuality = .typeMedium
        } else {
            picker.mediaTypes = ["public.image"]
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {

            let mediaType = info[.mediaType] as? String ?? ""

            if mediaType == "public.movie",
               let videoURL = info[.mediaURL] as? URL {
                // User recorded a video — copy to temp directory
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("camera_\(UUID().uuidString).mov")
                try? FileManager.default.copyItem(at: videoURL, to: tempURL)
                parent.onVideoPicked?(tempURL)
            } else if let image = info[.originalImage] as? UIImage {
                // User took a photo
                parent.onImagePicked?(image)
            }

            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
