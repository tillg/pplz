import Foundation
import PplzCore
import UniformTypeIdentifiers

/// What "Share → pplz" does with the things it is handed, on iPhone, iPad and Mac alike: a picture
/// or a link to a LinkedIn profile goes into the inbox that the extension shares with the app.
@MainActor
enum SharedItems {
    /// Puts what can be used into the inbox. `delivered` counts it; `received` describes everything
    /// that arrived, so that an unknown way of sharing can be reported and supported.
    static func deliver(_ items: [NSExtensionItem]) async -> (delivered: Int, received: [String]) {
        let providers = items.flatMap { $0.attachments ?? [] }
        var delivered = 0
        if let inbox = CaptureInbox.shared {
            for provider in providers {
                if let item = await item(from: provider), (try? inbox.add(item)) != nil { delivered += 1 }
            }
            // some apps put the link into the text that accompanies what they share
            if delivered == 0, let item = items.lazy.compactMap({ profileLink($0.attributedContentText?.string) }).first,
               (try? inbox.add(item)) != nil { delivered += 1 }
        }
        var received: [String] = []
        if delivered == 0 {
            for provider in providers { received.append(await description(of: provider)) }
            received += items.compactMap { $0.attributedContentText?.string }
        }
        return (delivered, received)
    }

    private static func item(from provider: NSItemProvider) async -> CaptureInbox.Item? {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    continuation.resume(returning: data.map { .image($0) })
                }
            }
        }
        if let link = profileLink(await url(from: provider)) { return link }
        return profileLink(await text(from: provider))
    }

    /// Only a link to a LinkedIn profile is worth handing over; any other text or address is not.
    private static func profileLink(_ text: String?) -> CaptureInbox.Item? {
        guard let text, LinkedInLink.profileID(in: text) != nil else { return nil }
        return .link(text)
    }

    private static func url(from provider: NSItemProvider) async -> String? {
        guard provider.canLoadObject(ofClass: URL.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url?.absoluteString) }
        }
    }

    private static func text(from provider: NSItemProvider) async -> String? {
        guard provider.canLoadObject(ofClass: String.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in continuation.resume(returning: text) }
        }
    }

    private static func description(of provider: NSItemProvider) async -> String {
        var content = await url(from: provider) ?? ""
        if content.isEmpty { content = await text(from: provider) ?? "" }
        return provider.registeredTypeIdentifiers.joined(separator: ", ") + (content.isEmpty ? "" : ": " + content.prefix(200))
    }
}
