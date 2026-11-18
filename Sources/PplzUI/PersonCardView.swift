import PplzCore
import SwiftUI

/// A person's card: the contact's own fields first, as in Contacts, then what pplz adds.
struct PersonCardView: View {
    let card: PersonCard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let contact = card.contact { contactFields(contact) }
                pplzFields
                history
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
                Text(PeopleSections.initials(card.entry.name))
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.entry.name).font(.title.weight(.semibold)).textSelection(.enabled)
                if let contact = card.contact {
                    let line = [contact.jobTitle, contact.organization].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !line.isEmpty { Text(line).foregroundStyle(.secondary) }
                }
                if card.entry.isPplzOnly {
                    Text("Only in pplz — no card in Contacts").font(.callout).foregroundStyle(.pink)
                }
            }
        }
    }

    private func contactFields(_ contact: ContactDetails) -> some View {
        let rows: [(String, String)] =
            contact.phones.map { ($0.label.isEmpty ? "phone" : $0.label, $0.value) }
            + contact.emails.map { ($0.label.isEmpty ? "email" : $0.label, $0.value) }
            + contact.addresses.map { ($0.label.isEmpty ? "address" : $0.label, $0.value) }
            + contact.urls.map { ($0.label.isEmpty ? "url" : $0.label, $0.value) }
            + contact.socialProfiles.map { ($0.label.isEmpty ? "social" : $0.label, $0.value) }
            + (contact.birthday.map { [("birthday", $0)] } ?? [])
        return Group {
            if !rows.isEmpty {
                FieldGroup {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { Divider() }
                        FieldRow(label: row.0, value: row.1)
                    }
                }
            }
        }
    }

    @ViewBuilder private var pplzFields: some View {
        let stored = card.stored
        let rows: [(String, String)] =
            (card.entry.tags.isEmpty ? [] : [("tags", card.entry.tags.joined(separator: ", "))])
            + ((stored?.howWeMet.isEmpty ?? true) ? [] : [("how we met", stored!.howWeMet)])
            + ((stored?.notes.isEmpty ?? true) ? [] : [("notes", stored!.notes)])
            + card.connections.map { connection in
                connection.direction == .outgoing
                    ? (connection.kind, connection.other.name)
                    : ("connection", "\(connection.other.name) is \(connection.kind) this person")
            }
            + (stored?.keepInTouchDays.map { [("keep in touch", "every \($0) days")] } ?? [])
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle("pplz")
                FieldGroup {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { Divider() }
                        FieldRow(label: row.0, value: row.1)
                    }
                }
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("History")
            if card.history.isEmpty {
                Text("No events yet").foregroundStyle(.secondary).padding(.vertical, 4)
            } else {
                Text(summary).font(.callout).foregroundStyle(.secondary)
                FieldGroup {
                    ForEach(Array(card.history.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { Divider() }
                        EventRow(event: event, me: card.entry.id)
                    }
                }
            }
        }
    }

    private var summary: String {
        guard let last = card.history.first else { return "" }
        return "Met \(card.history.count)× · last \(last.start.formatted(date: .abbreviated, time: .omitted))"
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.headline).foregroundStyle(.pink)
    }
}

/// Rounded group of rows, as on a Contacts card.
struct FieldGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct FieldRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
}

struct EventRow: View {
    let event: EventSnapshot
    /// The person whose card this is; left out of the "with" line.
    let me: UUID?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.pink).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title.isEmpty ? event.format.displayName : event.title)
                if !details.isEmpty { Text(details).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            Text(event.start.formatted(date: .abbreviated, time: .omitted))
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var details: String {
        let others = event.participants.filter { $0.id != me }.map(\.name)
        return ([event.title.isEmpty ? nil : event.format.displayName, event.place.isEmpty ? nil : event.place,
                 others.isEmpty ? nil : "with " + others.joined(separator: ", ")] as [String?])
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var symbol: String {
        switch event.format {
        case .liveMeeting: "person.2.fill"
        case .webCall: "video.fill"
        case .phoneCall: "phone.fill"
        case .largerGathering: "person.3.fill"
        case .writtenExchange: "envelope.fill"
        }
    }
}
