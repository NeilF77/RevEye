// MediaPickers.swift
// RevEye
//
// UIKit wrappers that let SwiftUI present the camera and photo library.
// ImagePicker handles both camera capture (photo + video) and photo library
// with optional cropping. VideoPicker uses PHPicker for video-only selection.

import SwiftUI
import PhotosUI

// Wraps UIImagePickerController for camera and photo library access.
// When allowsEditing is true, iOS shows its built-in crop screen.
struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    var sourceType: UIImagePickerController.SourceType = .camera
    var allowsEditing: Bool = false
    var onImagePicked: ((UIImage) -> Void)?
    var onVideoPicked: ((URL) -> Void)?

    // Convenience init for simple photo-only use
    init(sourceType: UIImagePickerController.SourceType = .camera, completion: @escaping (UIImage) -> Void) {
        self.sourceType = sourceType; self.onImagePicked = completion; self.onVideoPicked = nil
    }

    // Full init with all options
    init(sourceType: UIImagePickerController.SourceType = .camera,
         allowsEditing: Bool = false,
         onImagePicked: ((UIImage) -> Void)? = nil,
         onVideoPicked: ((URL) -> Void)? = nil) {
        self.sourceType = sourceType; self.allowsEditing = allowsEditing
        self.onImagePicked = onImagePicked; self.onVideoPicked = onVideoPicked
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = allowsEditing
        // Camera supports both photo and video; library is photo-only
        if sourceType == .camera {
            picker.mediaTypes = ["public.image", "public.movie"]
            picker.videoMaximumDuration = 60
            picker.videoQuality = .typeMedium
        } else {
            picker.mediaTypes = ["public.image"]
        }
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ p: ImagePicker) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let mediaType = info[.mediaType] as? String ?? ""

            if mediaType == "public.movie", let url = info[.mediaURL] as? URL {
                // Video was captured - copy to temp directory since the original is sandboxed
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cam_\(UUID().uuidString).mov")
                try? FileManager.default.copyItem(at: url, to: tmp)
                parent.onVideoPicked?(tmp)
            } else if let img = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                // Photo selected - prefer the cropped version if editing was enabled
                parent.onImagePicked?(img)
            }

            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// Wraps PHPickerViewController for selecting videos from the photo library.
// Used separately from ImagePicker because PHPicker has better video filtering.
struct VideoPicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) private var presentationMode
    var onVideoPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker
        init(_ p: VideoPicker) { parent = p }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentationMode.wrappedValue.dismiss()
            guard let provider = results.first?.itemProvider else { return }

            // Load the video file and copy it to a temp location we control
            provider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, _ in
                guard let url else { return }
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: tmp)
                DispatchQueue.main.async { self.parent.onVideoPicked(tmp) }
            }
        }
    }
}
