import CoreGraphics
import Foundation
import Vision

/// Reads a screenshot of someone's profile (e.g. LinkedIn) on the device: the text in it and
/// the profile picture. Nothing leaves the device.
public enum ProfileImage {
    /// The lines of text in the image, top to bottom.
    public static func text(in image: CGImage) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        return try await request.perform(on: image).compactMap { $0.topCandidates(1).first?.string }
    }

    /// The profile picture: a square around the largest face, or `nil` if there is no face.
    public static func picture(in image: CGImage) async throws -> CGImage? {
        var largest: CGRect?
        for band in tiles(width: image.width, height: image.height) {
            guard let part = image.cropping(to: band) else { continue }
            for face in try await DetectFaceRectanglesRequest().perform(on: part) {
                let box = face.boundingBox.toImageCoordinates(band.size, origin: .upperLeft)
                    .offsetBy(dx: band.minX, dy: band.minY)
                if box.width * box.height > (largest.map { $0.width * $0.height } ?? 0) { largest = box }
            }
        }
        return largest.flatMap { image.cropping(to: pictureRect(aroundFace: $0, width: image.width, height: image.height)) }
    }

    /// Square tiles at two sizes: the image's short side and half of it. A face that is tiny in a
    /// whole phone or tablet screenshot is large enough in one of them to be found.
    static func tiles(width: Int, height: Int) -> [CGRect] {
        let short = min(width, height)
        return tiles(width: width, height: height, side: short) + tiles(width: width, height: height, side: max(short / 2, 1))
    }

    /// Tiles of one size covering the image, each overlapping its neighbours by half, so that a face
    /// on a border is whole in one of them; the last row and column end at the image's edge.
    static func tiles(width: Int, height: Int, side: Int) -> [CGRect] {
        func starts(_ length: Int) -> [Int] {
            guard length > side else { return [0] }
            return Array(stride(from: 0, to: length - side, by: max(side / 2, 1))) + [length - side]
        }
        return starts(height).flatMap { y in starts(width).map { x in CGRect(x: x, y: y, width: side, height: side) } }
    }

    /// A square 2.4 times the face's width around its centre — room for hair and chin — moved back
    /// inside the image where it would stick out.
    static func pictureRect(aroundFace face: CGRect, width: Int, height: Int) -> CGRect {
        let side = min((face.width * 2.4).rounded(), CGFloat(min(width, height)))
        let x = min(max(face.midX - side / 2, 0), CGFloat(width) - side)
        let y = min(max(face.midY - side / 2, 0), CGFloat(height) - side)
        return CGRect(x: x.rounded(), y: y.rounded(), width: side, height: side)
    }
}
