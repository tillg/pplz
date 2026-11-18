import PplzUI
import SwiftUI

@main
struct PplziOSApp: App {
    @State private var model = PeopleModel(configuration: .init(defaults: .standard))

    var body: some Scene {
        WindowGroup {
            PeopleView(model: model, defaults: .standard)
                .onOpenURL { url in
                    // pplz://person/<id> — the link pplz puts into contacts (SPEC §3.2)
                    Task { await model.open(url) }
                }
        }
    }
}
