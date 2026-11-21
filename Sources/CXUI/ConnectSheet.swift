import CXCore
import SwiftUI

/// Adds a relationship to the selected person, phrased as in Contacts: pick who, and what they are
/// to this person ("Ben is Anna's manager").
struct ConnectSheet: View {
    let personName: String
    let candidates: [PersonEntry]
    let onConnect: (String, PersonEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var role = "friend"
    @State private var customRole = ""
    @State private var search = ""
    @State private var selection: String?

    /// The tag of "Custom…" in the picker; no role is called so.
    private static let custom = "\u{0}custom"
    /// Apple's list, plus "colleague", which Contacts knows but does not offer in its menu.
    private static let roles = ContactMirror.appleRoles.filter { $0 != "other" } + ["colleague", "other"]

    private var matches: [PersonEntry] {
        PeopleSections.make(candidates, search: search).flatMap(\.entries)
    }

    private var selected: PersonEntry? { candidates.first { $0.key == selection } }

    private var chosenRole: String {
        (role == Self.custom ? customRole : role).trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        #if os(macOS)
        macBody
        #else
        SheetScaffold(title: "Relationship for \(personName)", confirmTitle: "Add",
                      canConfirm: selected != nil && !chosenRole.isEmpty,
                      onConfirm: { if let selected { onConnect(chosenRole, selected) } }) {
            Section {
                Picker(String(localized: "Relationship", bundle: .module), selection: $role) {
                    ForEach(Self.roles, id: \.self) { Text(RelationshipText.role($0)).tag($0) }
                    Text("Custom…", bundle: .module).tag(Self.custom)
                }
                if role == Self.custom {
                    FormField(title: "Custom relationship", text: $customRole, prompt: "e.g. mentor")
                }
            } footer: {
                Text(sentence)
            }
            Section(String(localized: "Person", bundle: .module)) {
                FormField(title: "Search people", text: $search)
                // a long address book is cut off here; searching narrows it down
                ForEach(matches.prefix(40), id: \.key) { entry in
                    Button {
                        selection = entry.key
                    } label: {
                        HStack {
                            Text(entry.name).foregroundStyle(.primary)
                            Spacer()
                            if selection == entry.key { Image(systemName: "checkmark").foregroundStyle(.pink) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        #endif
    }

    private var macBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a relationship for \(personName)", bundle: .module).font(.title3.weight(.semibold))
            HStack {
                Picker(String(localized: "Relationship", bundle: .module), selection: $role) {
                    ForEach(Self.roles, id: \.self) { Text(RelationshipText.role($0)).tag($0) }
                    Divider()
                    Text("Custom…", bundle: .module).tag(Self.custom)
                }
                .fixedSize()
                if role == Self.custom {
                    TextField(String(localized: "Relationship", bundle: .module), text: $customRole, prompt: Text("e.g. mentor", bundle: .module))
                        .labelsHidden()
                }
            }
            TextField(String(localized: "Search people", bundle: .module), text: $search)
            List(matches, id: \.key, selection: $selection) { entry in
                Text(entry.name)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(sentence).font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: .module), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Add", bundle: .module)) {
                    if let selected { onConnect(chosenRole, selected) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil || chosenRole.isEmpty)
            }
        }
        .padding(20)
        .sheetWidth(440)
        .tint(.pink)
    }

    private var sentence: String {
        guard let selected else { return String(localized: "Pick the person.", bundle: .module) }
        let role = chosenRole.isEmpty ? "…" : RelationshipText.role(chosenRole)
        return String(localized: "\(selected.name) is \(personName)’s \(role).", bundle: .module,
                      comment: "A relationship as a sentence: Ben is Anna’s manager. Placeholders: the other person, this person, the role")
    }
}
