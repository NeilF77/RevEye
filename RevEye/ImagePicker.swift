//
//  ImagePicker.swift
//  RevEye
//
//  Created by user on 29/11/2025.
//

import SwiftUI
import UIKit

// Wraps UIImagePickerController for use in SwiftUI
// Allows camera or photo library access to capture/select images
struct ImagePicker: UIViewControllerRepresentable {
    
    // MARK: - Properties
    
    // Environment variable to dismiss the picker
    @Environment(\.presentationMode) var presentationMode
    
    // Source type for the picker (camera or photo library)
    var sourceType: UIImagePickerController.SourceType = .camera
    
    // Callback to return the selected image
    var completion: (UIImage) -> Void

    // MARK: - UIViewControllerRepresentable Methods
    
    // Creates and configures the UIImagePickerController
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.mediaTypes = ["public.image"]  // Only allow images
        return picker
    }

    // Updates the picker (not needed for this implementation)
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    // Creates the coordinator that handles picker delegate methods
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator
    
    // Handles UIImagePickerController delegate callbacks
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        // Called when user selects an image
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            // Extract the selected image
            if let image = info[.originalImage] as? UIImage {
                parent.completion(image)
            }
            // Dismiss the picker
            parent.presentationMode.wrappedValue.dismiss()
        }

        // Called when user cancels the picker
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
