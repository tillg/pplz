import PplzCore
import SwiftUI

extension EventFormat {
    var symbol: String {
        switch self {
        case .liveMeeting: "person.2.fill"
        case .webCall: "video.fill"
        case .phoneCall: "phone.fill"
        case .largerGathering: "person.3.fill"
        case .writtenExchange: "envelope.fill"
        }
    }
}

struct EventListRow: View {
    let event: EventSnapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: event.format.symbol).foregroundStyle(.pink).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title.isEmpty ? event.format.displayName : event.title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        ([event.start.formatted(.dateTime.day().month(.abbreviated))] + event.participants.map(\.name)).joined(separator: " · ")
    }
}

/// One event: when, where, who, what was said and what is still to do.
struct EventDetailView: View {
    let event: EventSnapshot
    let onShowPerson: (UUID) -> Void
    let onComplete: (UUID) -> Void
    let onAddFollowUp: (String) -> Void

    @State private var newFollowUp = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                facts
                if !event.participants.isEmpty { participants }
                followUps
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(LinearGradient(colors: [.pink.opacity(0.75), .pink], startPoint: .top, endPoint: .bottom))
                Image(systemName: event.format.symbol).font(.system(size: 28)).foregroundStyle(.white)
            }
            .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title.isEmpty ? event.format.displayName : event.title)
                    .font(.title.weight(.semibold)).textSelection(.enabled)
                Text(event.format.displayName).foregroundStyle(.secondary)
            }
        }
    }

    private var facts: some View {
        let rows: [(String, String)] =
            [("when", when)]
            + (event.place.isEmpty ? [] : [("place", event.place)])
            + (event.tags.isEmpty ? [] : [("tags", event.tags.joined(separator: ", "))])
            + (event.notes.isEmpty ? [] : [("notes", event.notes)])
            + event.links.map { ("link", $0) }
        return FieldGroup {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider() }
                FieldRow(label: row.0, value: row.1)
            }
        }
    }

    private var when: String {
        let start = event.start.formatted(date: .long, time: .shortened)
        guard let end = event.end else { return start }
        return start + " – " + end.formatted(date: .long, time: .shortened)
    }

    private var participants: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("People")
            FieldGroup {
                ForEach(Array(event.participants.enumerated()), id: \.element.id) { index, person in
                    if index > 0 { Divider() }
                    Button { onShowPerson(person.id) } label: {
                        HStack {
                            Text(person.name)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .help("Show \(person.name)")
                }
            }
        }
    }

    private var followUps: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Follow-ups")
            FieldGroup {
                ForEach(Array(event.followUps.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    HStack(spacing: 10) {
                        Button { onComplete(item.id) } label: {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(item.done ? Color.secondary : Color.pink)
                        }
                        .buttonStyle(.plain)
                        .disabled(item.done)
                        .help(item.done ? "Done" : "Mark as done")
                        Text(item.text).strikethrough(item.done).foregroundStyle(item.done ? .secondary : .primary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                if !event.followUps.isEmpty { Divider() }
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle").font(.title3).foregroundStyle(.secondary)
                    TextField("Add a follow-up", text: $newFollowUp)
                        .textFieldStyle(.plain)
                        .onSubmit(addFollowUp)
                    if !newFollowUp.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Add", action: addFollowUp).buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func addFollowUp() {
        onAddFollowUp(newFollowUp)
        newFollowUp = ""
    }
}

/// Edits an event's own fields. Participants are not changed here.
struct EditEventSheet: View {
    let onSave: (PeopleModel.EventEdit) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edit: PeopleModel.EventEdit

    init(edit: PeopleModel.EventEdit, onSave: @escaping (PeopleModel.EventEdit) -> Void) {
        self.onSave = onSave
        _edit = State(initialValue: edit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit event").font(.title3.weight(.semibold))
            Form {
                Picker("Format", selection: $edit.format) {
                    ForEach(EventFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                TextField("Title", text: $edit.title)
                DatePicker("Start", selection: $edit.start)
                Toggle("Has an end", isOn: $edit.hasEnd)
                if edit.hasEnd {
                    DatePicker("End", selection: $edit.end, in: edit.start...)
                }
                TextField("Place", text: $edit.place)
                TextField("Tags", text: $edit.tags, prompt: Text("Separated by commas"))
                TextField("Notes", text: $edit.notes, axis: .vertical).lineLimit(3...6)
                TextField("Links", text: $edit.links, prompt: Text("One per line"), axis: .vertical).lineLimit(2...4)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(edit)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .sheetWidth(460)
        .tint(.pink)
    }
}
