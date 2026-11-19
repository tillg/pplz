import UIKit

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
        let result = await SharedItems.deliver(extensionContext?.inputItems as? [NSExtensionItem] ?? [])
        guard result.delivered > 0 else {
            label.font = .preferredFont(forTextStyle: .footnote)
            label.text = (["pplz takes a screenshot of a profile or a profile link. Received:"] + result.received).joined(separator: "\n")
            view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
            return
        }
        // iOS has no official way for a share extension to open its app; if this does nothing,
        // the user opens pplz themselves and finds the capture waiting.
        let opened = openApp()
        label.text = opened ? "Opening pplz…" : "Saved. Open pplz to continue."
        try? await Task.sleep(for: .seconds(opened ? 0.4 : 1.6))
        close()
    }

    @objc private func close() { extensionContext?.completeRequest(returningItems: nil) }

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
