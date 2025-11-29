//
//  Home.swift
//  RevEye
//
//  Created by user on 10/11/2025.
//
import SwiftUI
import PhotosUI
import UIKit

struct HomeView: View {
    
    @State private var selectedVideoURL: URL?
    @State private var showVideoPicker = false
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @StateObject private var classifier = CarClassifier()


    
    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                Text("RevEye")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // Camera Button
                Button(action: {
                    print("Camera button tapped")
                }) {
                    Text("Take Photo")
                        .font(.title2)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
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
                
                Button("Upload Video") {
                    showVideoPicker = true
                }
                .sheet(isPresented: $showVideoPicker) {
                    VideoPicker { url in
                        self.selectedVideoURL = url
                        print("Video selected at URL: \(url)")
                    }
                }
                
                Button("Save detection locally") {
                    print("button tapped")

                    if let output = classifier.lastOutput {
                        let fakeURL = URL(fileURLWithPath: "/tmp/reveye_dummy.jpg")
                        saveDetection(for: fakeURL, label: output.label, confidence: output.confidence)

                        // Fetch ALL detections and print them
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



                    if let selectedImageData,
                       let uiImage = UIImage(data: selectedImageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 250)
                            .cornerRadius(10)
                            .padding(.top, 20)
                        
                        Text("Detected: \(classifier.result)")
                            .font(.headline)
                            .padding(.top, 10)
                    }
                    
                    Spacer()
                }
                .padding()
                .onChange(of: selectedItem) { newItem in
                    loadImage(from: newItem)
                }
            }
        .padding()
        }
        
        private func loadImage(from item: PhotosPickerItem?) {
            guard let item = item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        selectedImageData = data
                        
                        if let uiImage = UIImage(data: data) {
                            classifier.classify(image: uiImage)
                        }
                    }
                }
            }
        }
    private func saveDetection(for imageURL: URL?, label: String, confidence: Double) {
        guard let imageURL = imageURL else {
            print("No image URL to save")
            return
        }

        let formatter = ISO8601DateFormatter()
        let detection = Detection(
            id: nil,
            localFilePath: imageURL.path,
            vehicleLabel: label,
            confidence: confidence,
            timestamp: formatter.string(from: Date()),
            synced: 0
        )

        _ = DatabaseManager.shared.insertDetection(detection)
    }
}

