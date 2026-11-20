import CXUI
import SwiftUI

@main
struct CardXchangeiOSApp: App {
    @State private var model = PeopleModel(configuration: .init(defaults: .standard))

    var body: some Scene {
        WindowGroup {
            PeopleView(model: model, defaults: .standard)
                .onOpenURL { url in
                    // cx://person/<id> — the link cardXchange puts into contacts (SPEC §3.2)
                    Task { await model.open(url) }
                }
        }
    }
}
