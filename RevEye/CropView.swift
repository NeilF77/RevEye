//
//  CropView.swift
//  RevEye
//
//  Pinch-to-zoom + drag crop sheet for library photos

import SwiftUI

struct CropView: View {
    let image: UIImage
    let onCropped: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            REColors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") { onCancel() }
                        .font(REFont.label)
                        .foregroundColor(REColors.textDim)
                    Spacer()
                    Text("Crop Photo")
                        .font(REFont.heading)
                        .foregroundColor(REColors.text)
                    Spacer()
                    Button("Use Photo") { cropAndReturn() }
                        .font(REFont.label)
                        .foregroundColor(REColors.accent)
                }
                .padding(.horizontal, RE.s16)
                .padding(.vertical, RE.s12)

                Spacer()

                // Crop area
                GeometryReader { geo in
                    let size = geo.size
                    ZStack {
                        Color.black

                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            let newScale = lastScale * value
                                            scale = min(max(newScale, 1.0), 5.0)
                                        }
                                        .onEnded { _ in
                                            lastScale = scale
                                        },
                                    DragGesture()
                                        .onChanged { value in
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                        .onEnded { _ in
                                            lastOffset = offset
                                        }
                                )
                            )
                    }
                    .clipped()
                    .cornerRadius(RE.r12)
                }
                .padding(.horizontal, RE.s16)

                Spacer()

                // Hint
                Text("Pinch to zoom · Drag to position")
                    .font(REFont.small)
                    .foregroundColor(REColors.textDim)
                    .padding(.bottom, RE.s8)

                // Use Photo button (big)
                Button {
                    cropAndReturn()
                } label: {
                    Text("Use Photo")
                }
                .buttonStyle(REPrimaryButton())
                .padding(.horizontal, RE.s16)
                .padding(.bottom, RE.s32)
            }
        }
    }

    private func cropAndReturn() {
        // Render the visible area as a new UIImage
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600))
        let cropped = renderer.image { ctx in
            let imgSize = image.size
            let fitScale: CGFloat
            let canvasSize: CGFloat = 600

            // Compute scaledToFit size within 600x600
            let aspectW = canvasSize / imgSize.width
            let aspectH = canvasSize / imgSize.height
            fitScale = min(aspectW, aspectH)

            let drawW = imgSize.width * fitScale * scale
            let drawH = imgSize.height * fitScale * scale
            let drawX = (canvasSize - drawW) / 2 + offset.width
            let drawY = (canvasSize - drawH) / 2 + offset.height

            image.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
        }
        onCropped(cropped)
    }
}