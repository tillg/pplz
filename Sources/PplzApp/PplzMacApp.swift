import PplzCore
import PplzUI
import SwiftUI

@main
struct PplzMacApp: App {
    @State private var model = PeopleModel(configuration: PplzMacApp.configuration(.standard))

    var body: some Scene {
        // One window, like Contacts: a clicked pplz:// link shows the person in it
        // (a window group would open a new window for every link).
        Window("pplz", id: "main") {
            PeopleView(model: model, showLogSheet: UserDefaults.standard.bool(forKey: "showLog"),
                       showEditSheet: UserDefaults.standard.bool(forKey: "showEdit"))
                .task {
                    // `-mode events` opens the events list with the newest event selected
                    if UserDefaults.standard.string(forKey: "mode") == "events" {
                        await model.reload()
                        model.mode = .events
                        model.selectedEventID = model.events.first?.id
                    }
                }
                .frame(minWidth: 720, minHeight: 460)
                .onOpenURL { url in
                    // pplz://person/<id> — the link pplz puts into contacts (SPEC §3.2)
                    Task { await model.open(url) }
                }
        }
        .defaultSize(width: 980, height: 660)
    }

    /// Launch options, given the macOS way as `-key value` pairs (plain arguments would be taken
    /// for documents to open): `-store <path>`, `-noContacts YES`, `-select <name or id>`, `-showLog YES`, `-showEdit YES`, `-mode events`.
    static func configuration(_ defaults: UserDefaults) -> PeopleModel.Configuration {
        PeopleModel.Configuration(
            storeURL: defaults.string(forKey: "store").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                ?? PplzStore.defaultURL(),
            usesContacts: !defaults.bool(forKey: "noContacts"),
            initialSelection: defaults.string(forKey: "select"))
    }
}
