//
//  Home.swift
//  RevEye
//
//  Created by user on 10/11/2025.
//
import SwiftUI
import PhotosUI

struct HomeView: View {
    
    @State private var selectedVideoURL: URL?
    @State private var showVideoPicker = false
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil


    
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

                    if let selectedImageData,
                       let uiImage = UIImage(data: selectedImageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 250)
                            .cornerRadius(10)
                            .padding(.top, 20)
                    }
                    
                    Spacer()
                }
                .padding()
                .onChange(of: selectedItem) { newItem in
                    loadImage(from: newItem)
                }
            }
        }
        
        private func loadImage(from item: PhotosPickerItem?) {
            guard let item = item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        selectedImageData = data
                    }
                }
            }
        }
    }

