//
//  Home.swift
//  RevEye
//
//  Created by user on 10/11/2025.
//
import SwiftUI

struct HomeView: View {
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
                Button(action: {
                    print("Select Photo button tapped")
                }) {
                    Text("Select Photo")
                        .font(.title2)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Spacer()
            }
            .padding()
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}


