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
    
    // reference to SQLite manager
    private let db = DatabaseManager.shared
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                // App title
                Text("RevEye")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // MARK: - Camera Button
                // Opens the device camera to take a photo
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
                        // Convert captured image to JPEG data and store it
                        if let data = uiImage.jpegData(compressionQuality: 0.9) {
                            selectedImageData = data
                        }
                        // Run the classification on the captured image
                        classifier.classify(image: uiImage)
                    }
                }
                
                // MARK: - Gallery Button
                // Opens the photo library to select an existing image
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Text("Select Photo")
                        .font(.title2)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                // MARK: - Video Upload Button
                // Opens the video picker to select a video from the library
                Button("Upload Video") {
                    showVideoPicker = true
                }
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
                
                // MARK: - Save Detection Button
                // Saves the last classification result to local database and syncs to Firebase
                Button("Save detection locally") {
                    // Check if there's a classification result available
                    if let output = classifier.lastOutput {
                        
                        // Save detection to local SQLite database
                        if let detection = saveDetection(for: nil,
                                                         label: output.label,
                                                         confidence: output.confidence) {
                            
                            // Upload the detection to Firebase for cloud storage
                            FirebaseService.shared.uploadDetection(detection)
                        }
                        
                        // Fetch and print all detections from local database (for debugging)
                        let all = DatabaseManager.shared.fetchAllDetections()
                        print("All detections in DB")
                        for d in all {
                            print("id=\(d.id ?? -1), label=\(d.vehicleLabel), conf=\(d.confidence)")
                        }
                        print("end list")
                    } else {
                        print("No classification output yet")
                    }
                }
                .padding(.top, 8)
                
                
                // MARK: - Image Preview and Results
                // Display the selected/captured image and classification result
                if let selectedImageData,
                   let uiImage = UIImage(data: selectedImageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 250)
                        .cornerRadius(10)
                        .padding(.top, 20)
                    
                    // Display the classification result
                    Text("Detected: \(classifier.result)")
                        .font(.headline)
                        .padding(.top, 10)
                }
                
                // MARK: - Video Preview
                // Display the selected video in a player
                if let videoURL = selectedVideoURL {
                    VideoPlayer(player: AVPlayer(url: videoURL))
                        .frame(height: 250)
                        .cornerRadius(10)
                        .padding(.top, 20)
                }
                
                Spacer()
            }
            
            .padding()
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
        .padding()
    }
    
    // MARK: - Helper Methods
    
    /// Loads an image from a PhotosPickerItem asynchronously
    /// - Parameter item: The selected PhotosPickerItem
    private func loadImage(from item: PhotosPickerItem?) {
        guard let item = item else { return }
        Task {
            // Attempt to load the image data
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    selectedImageData = data
                    
                    // Convert to UIImage and run classification
                    if let uiImage = UIImage(data: data) {
                        classifier.classify(image: uiImage)
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
        
        // Create ISO8601 timestamp for the detection
        let formatter = ISO8601DateFormatter()
        
        // Build Detection object without database ID
        let detectionToInsert = Detection(
            id: nil,
            vehicleLabel: label,
            confidence: confidence,
            timestamp: formatter.string(from: Date()),
            synced: 0  // Mark as not yet synced to cloud
        )
        
        // Insert into database and get the generated ID
        if let newId = DatabaseManager.shared.insertDetection(detectionToInsert) {
            // Return Detection with the database-assigned ID
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

