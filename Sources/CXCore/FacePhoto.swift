import CoreGraphics
import Foundation
import ImageIO

/// Turns a picture into what cardXchange keeps of it: only the area around a face (SPEC §2.1). Face
/// recognition later needs nothing else, and the rest of a photo is not ours to keep. On the device only.
public enum FacePhoto {
    /// The area around each face in the picture as JPEG, left to right. Refuses a picture without a face
    /// — only face crops are kept. Several faces: the caller asks the user which one.
    public static func faceCrops(in imageData: Data) async throws -> [Data] {
        // a photo is turned upright first
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 4096]
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CXError.invalid("This is not a picture cardXchange can read.")
        }
        let crops = distinct(try await ProfileImage.faceBoxes(in: image)).compactMap { crop(image, face: $0) }
        guard !crops.isEmpty else { throw CXError.invalid("No face found in this picture.") }
        return crops
    }

    /// The faces, left to right, each once.
    static func distinct(_ faces: [CGRect]) -> [CGRect] {
        ProfileImage.distinctFaces(faces).sorted { $0.minX < $1.minX }
    }

    /// 40 % of the face's size on each side around it, kept inside the picture.
    static func cropRect(face: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect {
        face.insetBy(dx: -face.width * 0.4, dy: -face.height * 0.4)
            .intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            .integral
    }

    /// The crop around `face` (origin top left) as JPEG, scaled down so that its long side is at most 1024 pixels.
    static func crop(_ image: CGImage, face: CGRect) -> Data? {
        let rect = cropRect(face: face, imageWidth: image.width, imageHeight: image.height)
        guard !rect.isEmpty, var crop = image.cropping(to: rect) else { return nil }
        let scale = min(1, 1024 / max(rect.width, rect.height))
        if scale < 1 {
            let width = Int((rect.width * scale).rounded()), height = Int((rect.height * scale).rounded())
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let scaled = context.makeImage() else { return nil }
            crop = scaled
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, crop, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
