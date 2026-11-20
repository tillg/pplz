import AppKit

/// "Share → cardXchange" on the Mac, e.g. from a screenshot's preview: puts the picture or profile link
/// into the inbox it shares with the app and opens cardXchange, which reads it and asks who it is.
final class ShareViewController: NSViewController {
    private let label = NSTextField(wrappingLabelWithString: "Sending to cardXchange…")

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await deliver() }
    }

    private func deliver() async {
        let result = await SharedItems.deliver(extensionContext?.inputItems as? [NSExtensionItem] ?? [])
        if result.delivered > 0, let url = URL(string: "cx://capture") {
            NSWorkspace.shared.open(url)
        } else {
            label.stringValue = (["cardXchange takes a screenshot of a profile or a profile link. Received:"] + result.received).joined(separator: "\n")
            try? await Task.sleep(for: .seconds(6))
        }
        extensionContext?.completeRequest(returningItems: nil)
    }
}
