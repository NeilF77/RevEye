//
//  ImagePicker.swift
//  RevEye
//
//  Updated 12/03/2026 — supports photo + video capture from camera

import SwiftUI
import UIKit

struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    var sourceType: UIImagePickerController.SourceType = .camera
    var onImagePicked: ((UIImage) -> Void)?
    var onVideoPicked: ((URL) -> Void)?

    init(sourceType: UIImagePickerController.SourceType = .camera, completion: @escaping (UIImage) -> Void) {
        self.sourceType = sourceType; self.onImagePicked = completion; self.onVideoPicked = nil
    }

    init(sourceType: UIImagePickerController.SourceType = .camera,
         onImagePicked: ((UIImage) -> Void)? = nil,
         onVideoPicked: ((URL) -> Void)? = nil) {
        self.sourceType = sourceType; self.onImagePicked = onImagePicked; self.onVideoPicked = onVideoPicked
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = sourceType; p.delegate = context.coordinator
        if sourceType == .camera {
            p.mediaTypes = ["public.image", "public.movie"]
            p.videoMaximumDuration = 60; p.videoQuality = .typeMedium
        } else { p.mediaTypes = ["public.image"] }
        return p
    }

    func updateUIViewController(_ u: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ p: ImagePicker) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let mt = info[.mediaType] as? String ?? ""
            if mt == "public.movie", let u = info[.mediaURL] as? URL {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cam_\(UUID().uuidString).mov")
                try? FileManager.default.copyItem(at: u, to: tmp)
                parent.onVideoPicked?(tmp)
            } else if let img = info[.originalImage] as? UIImage {
                parent.onImagePicked?(img)
            }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
