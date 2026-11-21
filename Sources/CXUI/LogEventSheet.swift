import CXCore
import SwiftUI

/// "I just talked to …": logs a meeting or call in a few seconds. Who comes first — typing two
/// letters finds a person, the people met most recently are offered right away — and format and
/// time are already filled in.
struct LogEventSheet: View {
    let people: [PersonEntry]
    let knownTags: [String]
    let onLog: (PeopleModel.LogInput, [String], [String]) -> Void

    @State private var input: PeopleModel.LogInput
    @State private var chosen: [PersonEntry]
    @State private var pendingTag = ""

    init(people: [PersonEntry], preselected: [PersonEntry], format: EventFormat, knownTags: [String],
         onLog: @escaping (PeopleModel.LogInput, [String], [String]) -> Void) {
        self.people = people
        self.knownTags = knownTags
        self.onLog = onLog
        _input = State(initialValue: PeopleModel.LogInput(format: format))
        _chosen = State(initialValue: preselected)
    }

    var body: some View {
        SheetScaffold(title: "Log event", confirmTitle: "Log", canConfirm: !chosen.isEmpty, width: 460, onConfirm: log) {
            PeoplePickerField(people: people, chosen: $chosen)
            Picker(String(localized: "Format", bundle: .module), selection: $input.format) {
                ForEach(EventFormat.allCases, id: \.self) { Text($0.name()).tag($0) }
            }
            DatePicker(String(localized: "When", bundle: .module), selection: $input.start)
            FormField(title: "Title", text: $input.title, prompt: "Optional, e.g. Dinner at Luigi's")
            FormField(title: "Place", text: $input.place, prompt: "Optional")
            FormField(title: "Notes", text: $input.notes, prompt: "What you talked about", lines: 2...6)
            TagField(title: "Tags", text: $input.tags, pending: $pendingTag, known: knownTags)
        }
    }

    private func log() {
        var input = input
        input.tags = TagInput.adding(pendingTag, to: input.tags, known: knownTags)   // typed but not added yet
        onLog(input, chosen.filter { !$0.isNew }.map(\.key), chosen.filter(\.isNew).map(\.name))
    }
}

/// "Who": the chosen people as chips and a field that finds more — two typed letters are enough,
/// and until someone is chosen the people met most recently are offered right away.
struct PeoplePickerField: View {
    let people: [PersonEntry]
    @Binding var chosen: [PersonEntry]
    /// Puts the cursor into the name field even if people are chosen already.
    var startsSearching = false

    @State private var query = ""
    @FocusState private var isSearching: Bool

    var body: some View {
        Group {
            #if os(macOS)
            LabeledContent(String(localized: "Who", bundle: .module)) { content }
            #else
            VStack(alignment: .leading, spacing: 6) {
                Text("Who", bundle: .module).font(.caption).foregroundStyle(.secondary)
                content
            }
            .accessibilityElement(children: .contain)
            #endif
        }
        .onAppear { isSearching = chosen.isEmpty || startsSearching }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !chosen.isEmpty {
                FlowLayout {
                    ForEach(chosen, id: \.key) { entry in
                        Button { chosen.removeAll { $0.key == entry.key } } label: {
                            HStack(spacing: 4) {
                                Text(entry.name)
                                Image(systemName: "xmark").font(.caption2.weight(.bold))
                            }
                            .chip(filled: true)
                        }
                        .accessibilityLabel(String(localized: "Remove \(entry.name)", bundle: .module))
                    }
                }
            }
            TextField(String(localized: "Who", bundle: .module), text: $query, prompt: chosen.isEmpty ? Text("Type a name", bundle: .module) : Text("Add another person", bundle: .module))
                .labelsHidden()
                .autocorrectionDisabled()
                .focused($isSearching)
                .accessibilityLabel(String(localized: "Find a person", bundle: .module))
                .onSubmit {
                    if let first = suggestions.first {
                        add(first)
                    } else if let name = newPersonName {
                        add(.new(named: name))
                    }
                }
            ForEach(suggestions, id: \.key) { entry in
                Button { add(entry) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.plus").foregroundStyle(.pink)
                        Text(entry.name)
                        if !entry.nickname.isEmpty { Text(entry.nickname).foregroundStyle(.secondary) }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "Add \(entry.name)", bundle: .module))
            }
            if let name = newPersonName {
                Button { add(.new(named: name)) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.plus").foregroundStyle(.pink)
                        Text("New person “\(name)”", bundle: .module)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "New person \(name)", bundle: .module))
                .help(String(localized: "Someone who is not in your contacts: \(name) is added to cardXchange only", bundle: .module))
            }
        }
        .buttonStyle(.plain)
    }

    /// The recently met people are only offered until someone is chosen; after that the list would be in the way.
    private var suggestions: [PersonEntry] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty && !chosen.isEmpty { return [] }
        return PeopleDirectory.suggestions(for: query, in: people, excluding: Set(chosen.map(\.key)))
    }

    /// Set when the typed text could become a new person (nobody of that name exists or is chosen).
    private var newPersonName: String? {
        PeopleDirectory.newPersonName(for: query, in: people, chosen: chosen.map(\.name))
    }

    private func add(_ entry: PersonEntry) {
        chosen.append(entry)
        query = ""
    }
}

extension PersonEntry {
    /// Typed into the people picker as a new name; neither a contact nor a person in cardXchange yet.
    var isNew: Bool { id == nil && contactIdentifier == nil }
}
