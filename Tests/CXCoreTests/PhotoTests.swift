import CoreGraphics
import Foundation
import ImageIO
import SQLite3
import Testing
@testable import CXCore

/// A drawn picture: a blue background with a red square where a face would be.
func drawnPicture(width: Int, height: Int, red: CGRect) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)       // y grows downwards, as for face boxes
    context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1); context.fill(red)
    return context.makeImage()!
}

func jpeg(_ image: CGImage) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

func decoded(_ data: Data) throws -> CGImage {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
}

/// Colour of the pixel at (x, y), counted from the top left.
func rgb(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
}

/// Only the area around a face is kept (SPEC §2.1).
@Suite struct FaceCropTests {
    @Test func theCropReachesFortyPercentOfTheFaceBeyondItOnEachSide() {
        let rect = FacePhoto.cropRect(face: CGRect(x: 400, y: 300, width: 100, height: 120), imageWidth: 1000, imageHeight: 800)
        #expect(rect == CGRect(x: 360, y: 252, width: 180, height: 216))
    }

    @Test func theCropStaysInsideThePicture() {
        let rect = FacePhoto.cropRect(face: CGRect(x: 10, y: 700, width: 100, height: 90), imageWidth: 1000, imageHeight: 800)
        #expect(rect == CGRect(x: 0, y: 664, width: 150, height: 136))
    }

    @Test func aCropIsTheDrawnAreaAroundTheFace() throws {
        let image = drawnPicture(width: 1000, height: 800, red: CGRect(x: 400, y: 300, width: 100, height: 100))
        let crop = try decoded(try #require(FacePhoto.crop(image, face: CGRect(x: 400, y: 300, width: 100, height: 100))))
        #expect(crop.width == 180 && crop.height == 180)
        #expect(rgb(crop, 90, 90).r > 240 && rgb(crop, 90, 90).b < 15)    // the face in the middle (JPEG is lossy) …
        #expect(rgb(crop, 10, 10).b > 200 && rgb(crop, 10, 10).r < 50)  // … the margin around it
        #expect(rgb(crop, 170, 170).b > 200)
    }

    @Test func aLargeCropIsScaledDownToAThousandAndTwentyFourPixels() throws {
        let image = drawnPicture(width: 4000, height: 3000, red: CGRect(x: 1000, y: 500, width: 1000, height: 1250))
        let crop = try decoded(try #require(FacePhoto.crop(image, face: CGRect(x: 1000, y: 500, width: 1000, height: 1250))))
        #expect(crop.height == 1024)                                   // 1800 × 2250 scaled by the long side
        #expect(crop.width == 819)
    }

    @Test func aSmallCropIsNotEnlarged() throws {
        let image = drawnPicture(width: 300, height: 300, red: CGRect(x: 100, y: 100, width: 50, height: 50))
        let crop = try decoded(try #require(FacePhoto.crop(image, face: CGRect(x: 100, y: 100, width: 50, height: 50))))
        #expect(crop.width == 90 && crop.height == 90)
    }

    @Test func aPictureWithoutAFaceIsRefused() async throws {
        let data = jpeg(drawnPicture(width: 600, height: 400, red: CGRect(x: 200, y: 100, width: 100, height: 100)))
        await #expect(throws: CXError.invalid("No face found in this picture.")) { try await FacePhoto.faceCrops(in: data) }
    }

    @Test func somethingThatIsNoPictureIsRefused() async throws {
        await #expect(throws: CXError.invalid("This is not a picture cardXchange can read.")) { try await FacePhoto.faceCrops(in: Data("hello".utf8)) }
    }

    @Test func severalFacesAreOrderedLeftToRight() {
        let faces = [CGRect(x: 500, y: 100, width: 80, height: 80), CGRect(x: 100, y: 120, width: 90, height: 90),
                     CGRect(x: 110, y: 130, width: 40, height: 40)]       // the last is a second box for the second face
        #expect(FacePhoto.distinct(faces) == [CGRect(x: 100, y: 120, width: 90, height: 90), CGRect(x: 500, y: 100, width: 80, height: 80)])
    }
}

@Suite struct PhotoStoreTests {
    @Test func photosAreListedNewestFirstAndCanBeDeleted() throws {
        let (store, _) = try makeStore()
        let anna = try store.createPerson(name: "Anna Example")
        let first = try store.addPhotos([jpeg(drawnPicture(width: 90, height: 60, red: .zero))], toPerson: anna)
        let second = try store.addPhotos([jpeg(drawnPicture(width: 40, height: 50, red: .zero))], toPerson: anna)
        let photos = try store.photos(of: anna)
        #expect(photos.map(\.id) == second + first)
        #expect(photos.map(\.pixelWidth) == [40, 90] && photos.map(\.pixelHeight) == [50, 60])
        #expect(try store.photo(first[0]).data == jpeg(drawnPicture(width: 90, height: 60, red: .zero)))

        try store.deletePhoto(second[0])
        #expect(try store.photos(of: anna).map(\.id) == first)
        #expect(throws: CXError.self) { try store.photo(second[0]) }
    }

    @Test func aContactPersonGetsItsCXRecordWithTheFirstPhoto() throws {
        let (store, _) = try makeStore()
        let id = try store.ensurePerson(for: ContactSummary(identifier: "c-1", name: "Ben Sample"))
        try store.addPhotos([jpeg(drawnPicture(width: 10, height: 10, red: .zero))], toPerson: id)
        #expect(try store.photos(of: id).count == 1)
        #expect(try store.card(for: PersonEntry(id: id, contactIdentifier: "c-1", name: "Ben Sample", eventCount: 0, lastMet: nil, tags: []),
                               contact: nil).photos.count == 1)
    }

    @Test func photosOfOnePersonStayWithThem() throws {
        let (store, _) = try makeStore()
        let anna = try store.createPerson(name: "Anna Example"), ben = try store.createPerson(name: "Ben Sample")
        try store.addPhotos([jpeg(drawnPicture(width: 10, height: 10, red: .zero))], toPerson: anna)
        #expect(try store.photos(of: ben).isEmpty)
    }

    @Test func noPictureNoPhoto() throws {
        let (store, _) = try makeStore()
        let anna = try store.createPerson(name: "Anna Example")
        #expect(throws: CXError.invalid("There is no picture to add.")) { try store.addPhotos([Data()], toPerson: anna) }
        #expect(throws: CXError.self) { try store.addPhotos([Data([1])], toPerson: UUID()) }
        #expect(try store.photos(of: anna).isEmpty)
    }
}

/// A store as it was before photos existed, copied from a CLI run (invented people). The apps
/// open the user's synced store with the new schema: it must migrate and keep everything.
@Suite struct SchemaMigrationTests {
    @Test func aStoreFromBeforePhotosOpensKeepsItsDataAndTakesPhotos() throws {
        let fixture = try #require(Bundle.module.url(forResource: "Fixtures/before-photos", withExtension: "store"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cx-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("copy.store")
        try FileManager.default.copyItem(at: fixture, to: url)

        var store = try CXStore(url: url)
        let anna = try #require(try store.persons().first { $0.name == "Anna Example" })
        #expect(try store.persons().map(\.name) == ["Anna Example", "Ben Sample"])
        #expect(anna.eventCount == 2 && anna.tags == ["cologne", "friend"] && anna.notes == "Likes tea")
        #expect(try store.events().map(\.title) == ["Dinner", "Catch-up", "Web sync"])
        #expect(try store.photos(of: anna.id).isEmpty)

        try store.addPhotos([jpeg(drawnPicture(width: 30, height: 30, red: .zero))], toPerson: anna.id)
        store = try CXStore(url: url)                                       // a fresh open reads it back from disk
        #expect(try store.photos(of: anna.id).count == 1)
        #expect(try store.person(anna.id).eventCount == 2)
    }
    /// The fixture is only worth something while it has the old schema; opening it directly with a newer
    /// build migrates it in place. Tests work on a copy, and this notices if someone opened the original.
    @Test func fixtureStillHasTheOldSchema() throws {
        let fixture = try #require(Bundle.module.url(forResource: "Fixtures/before-photos", withExtension: "store"))
        var database: OpaquePointer?
        try #require(sqlite3_open_v2("file:\(fixture.path)?immutable=1", &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(database, "SELECT count(*) FROM sqlite_master WHERE name = 'ZPERSONPHOTO'", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        try #require(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 0)
    }
}
