import AppKit
import CXCore
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
            // the standard About window with the version text of the Settings: "V. 0.2.693 - 2026-11-20 14:07"
            CommandGroup(replacing: .appInfo) {
                Button("About cardXchange") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationVersion: AppVersion.text(info: Bundle.main.infoDictionary),
                        .version: "",
                    ])
                }
            }
            // ⌘V does the same while no text field has the focus
            CommandGroup(after: .pasteboard) {
                Button("Paste Screenshot or Business Card") { model.offerCaptureFromClipboard() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            WhatsNewCommand()
        }
        // issue #15: the table of the user-visible features, sortable by a click on a column header
        Window("What’s New", id: WhatsNewView.windowID) {
            WhatsNewView()
                .frame(minWidth: 600, minHeight: 300)
        }
        .defaultSize(width: 900, height: 600)
        Settings {
            SettingsView(model: model)
                .frame(width: 480, height: 560)
        }
    }
}

/// Help → What’s New… opens the What’s New window.
private struct WhatsNewCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("What’s New…") { openWindow(id: WhatsNewView.windowID) }
        }
    }
}
