import PplzCore
import UIKit
import UniformTypeIdentifiers

/// "Share → pplz" for a screenshot or a profile link. The extension only delivers: it puts what was
/// shared into the inbox that it shares with the app and opens pplz, which reads the screenshot and
/// asks who it is. (An extension cannot reach the app's database, and should not try.)
final class ShareViewController: UIViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = "Sending to pplz…"
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
        Task { await deliver() }
    }

    private func deliver() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var delivered = 0
        if let inbox = CaptureInbox.shared {
            for provider in providers {
                if let item = await item(from: provider), (try? inbox.add(item)) != nil { delivered += 1 }
            }
        }
        guard delivered > 0 else {
            label.text = "pplz takes a screenshot of a profile or a profile link."
            try? await Task.sleep(for: .seconds(2))
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        // iOS has no official way for a share extension to open its app; if this does nothing,
        // the user opens pplz themselves and finds the capture waiting.
        let opened = openApp()
        label.text = opened ? "Opening pplz…" : "Saved. Open pplz to continue."
        try? await Task.sleep(for: .seconds(opened ? 0.4 : 1.6))
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func item(from provider: NSItemProvider) async -> CaptureInbox.Item? {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return await data(from: provider, type: .image).map { .image($0) }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: Self.profileLink(url?.absoluteString)) }
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: String.self) { text, _ in continuation.resume(returning: Self.profileLink(text)) }
            }
        }
        return nil
    }

    /// Only a link to a LinkedIn profile is worth handing over; any other text or address is not.
    private static func profileLink(_ text: String?) -> CaptureInbox.Item? {
        guard let text, LinkedInLink.profileID(in: text) != nil else { return nil }
        return .link(text)
    }

    private func data(from provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in continuation.resume(returning: data) }
        }
    }

    /// Asks the hosting app's `UIApplication` — found through the responder chain — to open
    /// `pplz://capture`. That method is not available to extensions at compile time, so it is called
    /// through the Objective-C runtime. Works for a personal build; an App Store build would have to
    /// drop it and rely on "Open pplz to continue".
    private func openApp() -> Bool {
        guard let url = URL(string: "pplz://capture"), let applicationClass = NSClassFromString("UIApplication") else { return false }
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.isKind(of: applicationClass), let method = class_getInstanceMethod(applicationClass, selector) {
                typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                unsafeBitCast(method_getImplementation(method), to: Open.self)(current, selector, url as NSURL, [:] as NSDictionary, nil)
                return true
            }
            responder = current.next
        }
        return false
    }
}
