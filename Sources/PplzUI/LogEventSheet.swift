import PplzCore
import SwiftUI

/// "I just talked to …": logs a meeting or call in a few seconds. Who comes first — typing two
/// letters finds a person, the people met most recently are offered right away — and format and
/// time are already filled in.
struct LogEventSheet: View {
    let people: [PersonEntry]
    let knownTags: [String]
    let onLog: (PeopleModel.LogInput, [String]) -> Void

    @State private var input: PeopleModel.LogInput
    @State private var chosen: [PersonEntry]
    @State private var pendingTag = ""

    init(people: [PersonEntry], preselected: [PersonEntry], format: EventFormat, knownTags: [String],
         onLog: @escaping (PeopleModel.LogInput, [String]) -> Void) {
        self.people = people
        self.knownTags = knownTags
        self.onLog = onLog
        _input = State(initialValue: PeopleModel.LogInput(format: format))
        _chosen = State(initialValue: preselected)
    }

    var body: some View {
        SheetScaffold(title: "Log event", confirmTitle: "Log", canConfirm: !chosen.isEmpty, width: 460, onConfirm: log) {
            PeoplePickerField(people: people, chosen: $chosen)
            Picker("Format", selection: $input.format) {
                ForEach(EventFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            DatePicker("When", selection: $input.start)
            FormField(title: "Title", text: $input.title, prompt: "Optional, e.g. Dinner at Luigi's")
            FormField(title: "Place", text: $input.place, prompt: "Optional")
            FormField(title: "Notes", text: $input.notes, prompt: "What you talked about", lines: 2...6)
            TagField(title: "Tags", text: $input.tags, pending: $pendingTag, known: knownTags)
        }
    }

    private func log() {
        var input = input
        input.tags = TagInput.adding(pendingTag, to: input.tags, known: knownTags)   // typed but not added yet
        onLog(input, chosen.map(\.key))
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
            LabeledContent("Who") { content }
            #else
            VStack(alignment: .leading, spacing: 6) {
                Text("Who").font(.caption).foregroundStyle(.secondary)
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
                        .accessibilityLabel("Remove \(entry.name)")
                    }
                }
            }
            TextField("Who", text: $query, prompt: Text(chosen.isEmpty ? "Type a name" : "Add another person"))
                .labelsHidden()
                .autocorrectionDisabled()
                .focused($isSearching)
                .accessibilityLabel("Find a person")
                .onSubmit { if let first = suggestions.first { add(first) } }
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
                .accessibilityLabel("Add \(entry.name)")
            }
        }
        .buttonStyle(.plain)
    }

    /// The recently met people are only offered until someone is chosen; after that the list would be in the way.
    private var suggestions: [PersonEntry] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty && !chosen.isEmpty { return [] }
        return PeopleDirectory.suggestions(for: query, in: people, excluding: Set(chosen.map(\.key)))
    }

    private func add(_ entry: PersonEntry) {
        chosen.append(entry)
        query = ""
    }
}
