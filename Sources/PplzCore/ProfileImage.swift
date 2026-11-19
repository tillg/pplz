import CoreGraphics
import Foundation
import Vision

/// Reads a screenshot of someone's profile (e.g. LinkedIn) on the device: the text in it and
/// the profile picture. Nothing leaves the device.
public enum ProfileImage {
    /// The lines of text in the image, top to bottom.
    public static func text(in image: CGImage) async throws -> [String] {
        try await lines(in: image).map(\.text)
    }

    /// The lines of text with the place of each in the image (origin top left).
    static func lines(in image: CGImage) async throws -> [(text: String, box: CGRect)] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        let size = CGSize(width: image.width, height: image.height)
        return try await request.perform(on: image).compactMap { line in
            line.topCandidates(1).first.map { ($0.string, line.boundingBox.toImageCoordinates(size, origin: .upperLeft)) }
        }
    }

    /// The profile picture, or `nil` if there is no face: the round picture around the owner's face
    /// if its ring is found, otherwise a square around the face. `nameLine` is where the owner's
    /// name stands; see `face(among:aboveLine:)`.
    public static func picture(in image: CGImage, aboveLine nameLine: CGRect? = nil) async throws -> CGImage? {
        guard let face = face(among: try await faceBoxes(in: image), aboveLine: nameLine) else { return nil }
        return image.cropping(to: roundPicture(aroundFace: face, in: image)
                              ?? pictureRect(aroundFace: face, width: image.width, height: image.height))
    }

    /// Every box Vision finds for a face in the image (origin top left); the same face usually
    /// comes up several times, see `distinctFaces`.
    static func faceBoxes(in image: CGImage) async throws -> [CGRect] {
        var faces: [CGRect] = []
        for band in tiles(width: image.width, height: image.height) {
            guard let part = image.cropping(to: band) else { continue }
            for face in try await DetectFaceRectanglesRequest().perform(on: part) {
                faces.append(face.boundingBox.toImageCoordinates(band.size, origin: .upperLeft).offsetBy(dx: band.minX, dy: band.minY))
            }
        }
        return faces
    }

    /// Several boxes for the same face count as the largest of them; largest first.
    static func distinctFaces(_ faces: [CGRect]) -> [CGRect] {
        var distinct: [CGRect] = []
        for face in faces.sorted(by: { $0.width * $0.height > $1.width * $1.height }) where !distinct.contains(where: { $0.intersects(face) }) {
            distinct.append(face)
        }
        return distinct
    }

    /// The owner's face: on a profile page the picture stands right above the name, so of the faces
    /// above the name line the lowest one is taken — a banner further up can contain faces, or things
    /// that look like one, and the faces below belong to other people. Several boxes for the same face
    /// count as the largest of them. Without a name line (or a face above it) the largest face wins.
    static func face(among faces: [CGRect], aboveLine nameLine: CGRect?) -> CGRect? {
        let distinct = distinctFaces(faces)
        if let nameLine, let above = distinct.filter({ $0.midY < nameLine.minY }).max(by: { $0.maxY < $1.maxY }) { return above }
        return distinct.first
    }

    /// The round profile picture the face is part of, found by its white ring: left and right of the
    /// face for the centre, then up and down through the centre for the size. `nil` when no ring is
    /// found (dark mode, another layout).
    static func roundPicture(aroundFace face: CGRect, in image: CGImage) -> CGRect? {
        guard let pixels = Pixels(image) else { return nil }
        let reach = Int(face.width * 5)
        let row = Int(face.midY)
        guard let left = pixels.edge(from: Int(face.minX), step: -1, reach: reach, row: row),
              let right = pixels.edge(from: Int(face.maxX), step: 1, reach: reach, row: row) else { return nil }
        let column = (left + right) / 2
        guard let top = pixels.edge(from: Int(face.minY), step: -1, reach: reach, column: column),
              let bottom = pixels.edge(from: Int(face.maxY), step: 1, reach: reach, column: column) else { return nil }
        let side = CGFloat(bottom - top + 1)
        guard side >= face.width, side <= face.width * 8, CGFloat(right - left) <= side + 2 else { return nil }
        let rect = CGRect(x: CGFloat(column) - (side / 2).rounded(), y: CGFloat(top), width: side, height: side)
        return CGRect(x: 0, y: 0, width: image.width, height: image.height).contains(rect) ? rect : nil
    }

    /// The image's pixels, for looking at single ones.
    private struct Pixels {
        let width: Int, height: Int
        let bytes: [UInt8]

        init?(_ image: CGImage) {
            width = image.width; height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                      let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                return true
            }
            guard drawn else { return nil }
            self.bytes = bytes
        }

        func isWhite(_ x: Int, _ y: Int) -> Bool {
            let i = (y * width + x) * 4
            return bytes[i] >= 240 && bytes[i + 1] >= 240 && bytes[i + 2] >= 240
        }

        /// Walking from `start` along a row or a column: the last pixel before four white ones in a
        /// row — the picture's edge at its ring. `nil` if there is none within `reach` or the image.
        func edge(from start: Int, step: Int, reach: Int, row: Int? = nil, column: Int? = nil) -> Int? {
            var white = 0
            var position = start
            for _ in 0..<reach {
                let x = column ?? position, y = row ?? position
                guard x >= 0, y >= 0, x < width, y < height else { return nil }
                white = isWhite(x, y) ? white + 1 : 0
                if white == 4 { return position - step * 4 }
                position += step
            }
            return nil
        }
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
