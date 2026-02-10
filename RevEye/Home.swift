//
//  Home.swift
//  RevEye
//
//  Created by user on 10/11/2025.
//

import SwiftUI
import PhotosUI
import UIKit
import AVKit
import AVFoundation

/// Main home view for the RevEye app
/// Provides functionality to capture/select images and videos, classify vehicles, and save detections
struct HomeView: View {
    
    // MARK: - State Properties
    
    /// URL of the selected video from the photo library
    @State private var selectedVideoURL: URL?
    
    /// Controls the presentation of the video picker sheet
    @State private var showVideoPicker = false
    
    /// Currently selected item from PhotosPicker
    @State private var selectedItem: PhotosPickerItem? = nil
    
    /// Raw image data of the selected/captured image
    @State private var selectedImageData: Data? = nil
    
    /// Controls the presentation of the camera picker sheet
    @State private var showCamera = false
    
    /// The car classification engine that processes images
    @StateObject private var classifier = CarClassifier()
    
    /// Status message shown to the user (e.g. errors, confirmations)
    @State private var statusMessage: String? = nil
    
    // reference to SQLite manager
    private let db = DatabaseManager.shared
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // App title
                    Text("RevEye")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top, 16)
                    
                    // MARK: - Capture & Select Section
                    VStack(spacing: 16) {
                        // Camera Button
                        Button(action: {
                            print("Camera button tapped")
                            showCamera = true
                        }) {
                            Text("Take Photo")
                                .font(.title2)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .sheet(isPresented: $showCamera) {
                            // Custom ImagePicker for camera capture
                            ImagePicker(sourceType: .camera) { uiImage in
                                if let data = uiImage.jpegData(compressionQuality: 0.9) {
                                    selectedImageData = data
                                }
                                classifier.classify(image: uiImage)
                                statusMessage = "Classified photo. Review result before saving."
                            }
                        }
                        
                        // Gallery Button
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Text("Select Photo")
                                .font(.title2)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        
                        // Video Upload Button
                        Button("Upload Video") {
                            showVideoPicker = true
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .sheet(isPresented: $showVideoPicker) {
                            VideoPicker { url in
                                self.selectedVideoURL = url
                                print("Video selected at URL: \(url)")
                                
                                // Extract audio from the selected video
                                AudioExtractor.extract(from: url) { audioURL in
                                    if let audioURL = audioURL {
                                        print("Extracted audio at: \(audioURL)")
                                    }
                                }
                            }
                        }
                    }
                    
                    // MARK: - Save Detection Button
                    VStack(spacing: 8) {
                        Button("Save detection locally") {
                            if let output = classifier.lastOutput {
                                // Confidence threshold: 70%
                                if output.confidence < 0.7 {
                                    statusMessage = "Result uncertain (confidence below 70%). Try another photo before saving."
                                    print("Low confidence: \(output.confidence)")
                                    return
                                }
                                
                                if let detection = saveDetection(for: nil,
                                                                 label: output.label,
                                                                 confidence: output.confidence) {
                                    
                                    FirebaseService.shared.uploadDetection(detection)
                                    statusMessage = "Detection saved and queued for sync."
                                }
                                
                                let all = DatabaseManager.shared.fetchAllDetections()
                                print("All detections in DB")
                                for d in all {
                                    print("id=\(d.id ?? -1), label=\(d.vehicleLabel), conf=\(d.confidence)")
                                }
                                print("end list")
                            } else {
                                statusMessage = "No classification result yet. Take or select a photo first."
                                print("No classification output yet")
                            }
                        }
                    }
                    
                    // Status message
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    
                    // MARK: - Image Preview and Results
                    if let selectedImageData,
                       let uiImage = UIImage(data: selectedImageData) {
                        VStack(spacing: 8) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 250)
                                .cornerRadius(10)
                            
                            Text("Detected: \(classifier.result)")
                                .font(.headline)
                        }
                        .padding(.top, 16)
                    }
                    
                    // MARK: - Video Preview
                    if let videoURL = selectedVideoURL {
                        VideoPlayer(player: AVPlayer(url: videoURL))
                            .frame(height: 250)
                            .cornerRadius(10)
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            // Monitor changes to the PhotosPicker selection
            .onChange(of: selectedItem) { newItem in
                loadImage(from: newItem)
            }
            .navigationTitle("RevEye")
            .toolbar {
                NavigationLink("Collection") {
                    CollectionView()
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Loads an image from a PhotosPickerItem asynchronously
    /// - Parameter item: The selected PhotosPickerItem
    private func loadImage(from item: PhotosPickerItem?) {
        guard let item = item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    selectedImageData = data
                    
                    if let uiImage = UIImage(data: data) {
                        classifier.classify(image: uiImage)
                        statusMessage = "Classified photo. Review result before saving."
                    }
                }
            }
        }
    }
    
    /// Saves a vehicle detection to the local database
    /// - Parameters:
    ///   - imageURL: URL of the associated image (currently a placeholder)
    ///   - label: The detected vehicle label (e.g., car make/model)
    ///   - confidence: Confidence score of the detection (0.0 to 1.0)
    /// - Returns: Detection object with assigned ID if successful, nil otherwise
    private func saveDetection(for imageURL: URL?, label: String, confidence: Double) -> Detection? {
        let formatter = ISO8601DateFormatter()
        
        let detectionToInsert = Detection(
            id: nil,
            vehicleLabel: label,
            confidence: confidence,
            timestamp: formatter.string(from: Date()),
            synced: 0
        )
        
        if let newId = db.insertDetection(detectionToInsert) {
            return Detection(
                id: newId,
                vehicleLabel: detectionToInsert.vehicleLabel,
                confidence: detectionToInsert.confidence,
                timestamp: detectionToInsert.timestamp,
                synced: 0
            )
        } else {
            return nil
        }
    }
}
