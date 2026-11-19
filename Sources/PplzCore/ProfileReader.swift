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

    /// Reads what it can; never fails — whatever could not be read stays empty.
    public static func read(_ image: CGImage) async -> CapturedProfile {
        let lines = (try? await ProfileImage.text(in: image)) ?? []
        var profile = (try? await fields(from: lines)) ?? CapturedProfile()
        profile.linkedInID = LinkedInLink.profileID(in: lines.joined(separator: "\n")) ?? ""
        if let picture = try? await ProfileImage.picture(in: image) { profile.picture = png(picture) }
        return profile
    }

    public static func read(imageData: Data) async -> CapturedProfile? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return await read(image)
    }

    /// The fields the language model finds in the recognised text; empty without a model.
    static func fields(from lines: [String]) async throws -> CapturedProfile {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *), SystemLanguageModel.default.isAvailable, !lines.isEmpty {
            let session = LanguageModelSession(instructions: """
                You extract a person's contact details from the text of a screenshot of their profile page \
                (usually LinkedIn). The text also contains clutter: the clock, menus, buttons, banner text, \
                other people. Use only what the text says about the profile's owner. \
                Leave a field empty rather than guessing.
                """)
            let found = try await session.respond(
                to: "Text recognised in the screenshot, top to bottom:\n" + lines.joined(separator: "\n"),
                generating: ProfileFields.self).content
            return CapturedProfile(name: found.name.trimmed, namePrefix: found.namePrefix.trimmed, jobTitle: found.jobTitle.trimmed,
                                   company: found.company.trimmed, city: found.city.trimmed, country: found.country.trimmed)
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
    @Guide(description: "The person's first and last name, without academic titles such as Dr. or Prof.")
    var name: String
    @Guide(description: "Academic title in front of the name, e.g. Dr. or Prof. Dr.; empty if none")
    var namePrefix: String
    @Guide(description: "The person's current role, a few words, e.g. Partner or Head of Sales; empty if unknown")
    var jobTitle: String
    @Guide(description: "The company or organisation the person currently works for; empty if unknown")
    var company: String
    @Guide(description: "The city where the person is based; empty if only a country or nothing is given")
    var city: String
    @Guide(description: "The country where the person is based; empty if unknown")
    var country: String
}
#endif
