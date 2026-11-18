import PplzCore
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

    private static let custom = "Custom…"
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a relationship for \(personName)").font(.title3.weight(.semibold))
            HStack {
                Picker("Relationship", selection: $role) {
                    ForEach(Self.roles, id: \.self) { Text($0).tag($0) }
                    Divider()
                    Text(Self.custom).tag(Self.custom)
                }
                .fixedSize()
                if role == Self.custom {
                    TextField("Relationship", text: $customRole, prompt: Text("e.g. mentor"))
                        .labelsHidden()
                }
            }
            TextField("Search people", text: $search)
            List(matches, id: \.key, selection: $selection) { entry in
                Text(entry.name)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(sentence).font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    if let selected { onConnect(chosenRole, selected) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil || chosenRole.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .tint(.pink)
    }

    private var sentence: String {
        guard let selected else { return "Pick the person." }
        return "\(selected.name) is \(personName)\u{2019}s \(chosenRole.isEmpty ? "…" : chosenRole)."
    }
}
