import PplzUI
import SwiftUI

@main
struct PplzMacApp: App {
    @State private var model = PeopleModel(configuration: .init(defaults: .standard))

    var body: some Scene {
        // One window, like Contacts: a clicked pplz:// link shows the person in it
        // (a window group would open a new window for every link).
        Window("pplz", id: "main") {
            PeopleView(model: model, defaults: .standard)
                .frame(minWidth: 720, minHeight: 460)
                .onOpenURL { url in
                    // pplz://person/<id> — the link pplz puts into contacts (SPEC §3.2)
                    Task { await model.open(url) }
                }
        }
        .defaultSize(width: 980, height: 660)
    }
}
