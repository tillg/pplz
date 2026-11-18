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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                facts
                if !event.participants.isEmpty { participants }
                if !event.followUps.isEmpty { followUps }
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
            }
        }
    }
}
