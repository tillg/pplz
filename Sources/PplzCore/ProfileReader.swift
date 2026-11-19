import CoreGraphics
import Foundation
import ImageIO
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns a screenshot of a profile into a `CapturedProfile`, entirely on the device: Vision reads
/// the text and finds the picture, Apple's on-device language model sorts the text into fields.
/// Without that model (older system, Apple Intelligence off) the fields stay empty for the user to fill in.
public enum ProfileReader {
    /// Why the fields could not be filled in automatically; `nil` when the model is ready.
    public static var modelProblem: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.deviceNotEligible): return "This device does not support Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled): return "Apple Intelligence is switched off in Settings."
            case .unavailable(.modelNotReady): return "The Apple Intelligence model is still downloading."
            case .unavailable: return "The Apple Intelligence model is not available."
            }
        }
        #endif
        return "Reading profiles needs iOS 26 / macOS 26 or later."
    }

    public struct Reading: Sendable {
        public var profile: CapturedProfile
        /// Why fields are empty although a model is there (e.g. it refused or the text was too long); `nil` if all went well.
        public var problem: String?
    }

    /// Reads what it can; never fails — whatever could not be read stays empty.
    public static func read(_ image: CGImage) async -> Reading {
        let found = (try? await ProfileImage.lines(in: image)) ?? []
        let lines = found.map(\.text)
        var reading = Reading(profile: CapturedProfile(), problem: modelProblem)
        do {
            reading.profile = try await fields(from: lines)
        } catch {
            reading.problem = "The fields could not be read automatically (\(error.localizedDescription))."
        }
        reading.profile.linkedInID = LinkedInLink.profileID(in: lines.joined(separator: "\n")) ?? ""
        let nameLine = nameLineIndex(in: lines).map { found[$0].box }
        if let picture = try? await ProfileImage.picture(in: image, aboveLine: nameLine) { reading.profile.picture = png(picture) }
        return reading
    }

    /// `nil` if the data is no image. A photo is turned upright first (screenshots already are).
    public static func read(imageData: Data) async -> Reading? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 4096]
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return await read(image)
    }

    /// The part of the recognised text that is about the profile's owner: from the name line — on
    /// LinkedIn the one carrying "1st", "2nd" or "3rd" — to just before the connections and buttons.
    /// The rest (banner, menus, About text, other people) only misleads the model. Text without these
    /// markers is kept whole.
    static func header(of lines: [String]) -> [String] { bounds(of: lines).lines }

    /// Where the owner is based: on LinkedIn the last line of the header, right above the connections.
    /// Taken by position because the model keeps mistaking the organisations line for it. Empty when the
    /// layout is not recognised (both ends of the header must be found) or the line does not look like a place.
    static func locationLine(in lines: [String]) -> String {
        let header = bounds(of: lines)
        guard header.isBounded, header.lines.count >= 3, let last = header.lines.last else { return "" }
        let looksLikeOrganisations = last.firstMatch(of: /\+\s*\d+\s+more/) != nil || last.count > 60
        return looksLikeOrganisations ? "" : last
    }

    /// The line with the owner's name: on LinkedIn the one ending in "1st", "2nd" or "3rd".
    static func nameLineIndex(in lines: [String]) -> Int? {
        lines.firstIndex { $0.firstMatch(of: /(?:^|[\s•·])(?:1st|2nd|3rd)\+?\s*$/) != nil }
    }

    /// What the model gave as academic title, kept only if it stands in the name line and is not
    /// the connection degree ("2nd"), which the model has taken for a title.
    static func title(_ prefix: String, nameLine: String) -> String {
        let prefix = prefix.trimmed
        let isDegree = prefix.wholeMatch(of: /(?i)(1st|2nd|3rd)\+?/) != nil
        return !isDegree && nameLine.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive]) != nil ? prefix : ""
    }

    private static func bounds(of lines: [String]) -> (lines: [String], isBounded: Bool) {
        let marker = nameLineIndex(in: lines)
        let start = marker ?? 0
        let rest = lines[start...]
        let end = rest.dropFirst().firstIndex { line in
            line.firstMatch(of: /(?i)(mutual connections?|\d+\+? connections|followers|^\W*connect$|^\W*message$|^\W*follow$|^about$)/) != nil
        }
        return (Array(lines[start..<(end ?? rest.endIndex)]), marker != nil && end != nil)
    }

    /// The role the headline gives for this employer: in "… - Partner at Duane Morris LLP" that is
    /// "Partner". Found by rule, because the model sometimes answers with the headline's first phrase.
    static func role(at company: String, in header: [String]) -> String? {
        let company = company.trimmed
        guard !company.isEmpty else { return nil }
        let text = header.dropFirst().joined(separator: " ")      // the first line is the name, not the headline
        for word in [" at ", " @ ", " bei "] {
            guard let found = text.range(of: word + company, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            // back to the previous separator of the headline
            let before = text[..<found.lowerBound]
            let start = before.lastIndex { "|•·,".contains($0) }.map { before.index(after: $0) } ?? before.startIndex
            var role = String(before[start...])
            if let dash = role.range(of: " - ", options: .backwards) ?? role.range(of: " – ", options: .backwards) {
                role = String(role[dash.upperBound...])
            }
            role = role.trimmed
            if !role.isEmpty, role.split(whereSeparator: \.isWhitespace).count <= 6 { return role }
        }
        return nil
    }

    public struct Place: Equatable, Sendable {
        public var city: String
        public var country: String
    }

    /// Takes a location line apart: "City, Region, Country" → city and country; a single name is a
    /// country, unless it says it is an area ("Greater Hamburg Area").
    static func place(_ line: String) -> Place {
        let text = (line.split(whereSeparator: { $0 == "•" || $0 == "·" }).first.map(String.init) ?? "").trimmed
        let parts = text.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
        guard let first = parts.first, let last = parts.last else { return Place(city: "", country: "") }
        if parts.count > 1 { return Place(city: first, country: last) }
        let isArea = first.range(of: "area|region|metropol", options: [.regularExpression, .caseInsensitive]) != nil
        return isArea ? Place(city: first, country: "") : Place(city: "", country: first)
    }

    /// The fields the language model finds in the recognised text; empty without a model.
    static func fields(from lines: [String]) async throws -> CapturedProfile {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *), SystemLanguageModel.default.isAvailable, !lines.isEmpty {
            let session = LanguageModelSession(instructions: """
                You extract a person's contact details from the text of a screenshot of their profile page, \
                usually LinkedIn. The text shows, from top to bottom: the owner's name (possibly with a title, \
                a badge and '1st', '2nd' or '3rd'), a headline describing what they do, sometimes a line with \
                organisations and schools, and one short line saying where they are based. \
                Use only what the text says. Leave a field empty rather than guessing.
                """)
            let found = try await session.respond(
                to: "Text recognised in the screenshot, top to bottom:\n" + header(of: lines).joined(separator: "\n"),
                generating: ProfileFields.self, options: GenerationOptions(sampling: .greedy)).content
            let place = place(locationLine(in: lines))
            let company = found.company.trimmed
            return CapturedProfile(name: found.name.trimmed, namePrefix: title(found.namePrefix, nameLine: header(of: lines).first ?? ""),
                                   jobTitle: role(at: company, in: header(of: lines)) ?? found.jobTitle.trimmed,
                                   company: company, city: place.city, country: place.country)
        }
        #endif
        return CapturedProfile()
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
@Generable
struct ProfileFields {
    @Guide(description: "The profile owner's first and last name, without academic titles such as Dr. or Prof.")
    var name: String
    @Guide(description: "Academic title in front of the name, e.g. Dr. or Prof. Dr.; empty if none")
    var namePrefix: String
    @Guide(description: "The owner's current role only, at most four words. The headline often lists several things; take the role that goes with the current employer: 'Partner at X' gives Partner. Empty if unknown")
    var jobTitle: String
    @Guide(description: "The current employer, as named in the headline after 'at' or '@', without a place name from the next line; empty if unknown")
    var company: String
}
#endif
