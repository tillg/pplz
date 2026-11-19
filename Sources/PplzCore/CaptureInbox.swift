import Foundation

/// A folder in which things shared to pplz (a screenshot, a profile link) wait until the app picks
/// them up. The share extension writes, the app reads; both reach it through the App Group.
public struct CaptureInbox: Sendable {
    public static let appGroup = "group.com.tillg.pplz"

    public enum Item: Equatable, Sendable {
        case image(Data)
        case link(String)
    }

    /// One capture to run: a screenshot, a profile link, or both.
    public struct Request: Equatable, Sendable {
        public var image: Data?
        public var link: String?

        public init(image: Data? = nil, link: String? = nil) {
            self.image = image
            self.link = link
        }
    }

    /// What to capture from the things that were waiting: the latest screenshot and the latest link.
    public static func request(from items: [Item]) -> Request? {
        var request = Request()
        for item in items {
            switch item {
            case .image(let data): request.image = data
            case .link(let text): request.link = text
            }
        }
        return request == Request() ? nil : request
    }

    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// The inbox shared between the app and its share extension; `nil` without the App Group.
    public static var shared: CaptureInbox? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            .map { CaptureInbox(directory: $0.appendingPathComponent("Inbox", isDirectory: true)) }
    }

    public func add(_ item: Item, at date: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // the name sorts by arrival; the ID keeps two things shared in the same instant apart
        let name = String(format: "%017.6f-%@", date.timeIntervalSince1970, UUID().uuidString)
        switch item {
        case .image(let data): try data.write(to: directory.appendingPathComponent(name + ".image"), options: .atomic)
        case .link(let text): try Data(text.utf8).write(to: directory.appendingPathComponent(name + ".link"), options: .atomic)
        }
    }

    /// Everything that is waiting, oldest first; each item is removed as it is handed out.
    public func takeAll() throws -> [Item] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["image", "link"].contains($0.pathExtension) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { file in
            let data = try Data(contentsOf: file)
            try FileManager.default.removeItem(at: file)
            return file.pathExtension == "image" ? .image(data) : .link(String(decoding: data, as: UTF8.self))
        }
    }
}
