import PplzCore
import PplzUI
import SwiftUI

@main
struct PplzMacApp: App {
    @State private var model = PeopleModel(configuration: PplzMacApp.configuration(.standard))

    var body: some Scene {
        WindowGroup("pplz") {
            PeopleView(model: model)
                .frame(minWidth: 720, minHeight: 460)
                .onOpenURL { url in
                    // pplz://person/<id> — the link pplz puts into contacts (SPEC §3.2)
                    if url.scheme == "pplz", url.host() == "person" { model.select(matching: url.lastPathComponent) }
                }
        }
        .defaultSize(width: 980, height: 660)
    }

    /// Launch options, given the macOS way as `-key value` pairs (plain arguments would be taken
    /// for documents to open): `-store <path>`, `-noContacts YES`, `-select <name or id>`.
    static func configuration(_ defaults: UserDefaults) -> PeopleModel.Configuration {
        PeopleModel.Configuration(
            storeURL: defaults.string(forKey: "store").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                ?? PplzStore.defaultURL(),
            usesContacts: !defaults.bool(forKey: "noContacts"),
            initialSelection: defaults.string(forKey: "select"))
    }
}
