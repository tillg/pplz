import CXUI
import SwiftUI

@main
struct CardXchangeMacApp: App {
    @State private var model = PeopleModel(configuration: .init(defaults: .standard))

    var body: some Scene {
        // One window, like Contacts: a clicked cx:// link shows the person in it
        // (a window group would open a new window for every link).
        Window("cardXchange", id: "main") {
            PeopleView(model: model, defaults: .standard)
                .frame(minWidth: 720, minHeight: 460)
                .onOpenURL { url in
                    // cx://person/<id> — the link cardXchange puts into contacts (SPEC §3.2)
                    Task { await model.open(url) }
                }
        }
        .defaultSize(width: 980, height: 660)
        .commands {
            // ⌘V does the same while no text field has the focus
            CommandGroup(after: .pasteboard) {
                Button("Paste Screenshot or Business Card") { model.offerCaptureFromClipboard() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }
        Settings {
            SettingsView(model: model)
                .frame(width: 480, height: 560)
        }
    }
}
