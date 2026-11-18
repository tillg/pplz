import PplzCore
import SwiftUI

/// A person's card: the contact's own fields first, as in Contacts, then what pplz adds.
struct PersonCardView: View {
    let card: PersonCard
    @Environment(\.openURL) private var openURL
    var onConnect: () -> Void = {}
    var onDisconnect: (UUID) -> Void = { _ in }
    var onShowPerson: (UUID) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let contact = card.contact { contactFields(contact) }
                pplzFields
                connections
                history
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(.background)
    }

    /// The big header, as in Contacts: picture (or initials on pink), the nickname or name,
    /// full name / job / company below it, and the quick actions.
    private var header: some View {
        ZStack(alignment: .bottom) {
            if let picture {
                // a wide header crops a portrait picture: keep the top, where the face usually is
                picture.resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 400, alignment: .top)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
            } else {
                LinearGradient(colors: [.pink.opacity(0.72), .pink], startPoint: .top, endPoint: .bottom)
                    .frame(height: 250)
            }
            VStack(spacing: 6) {
                if picture == nil {
                    Text(PeopleSections.initials(card.entry.name))
                        .font(.system(size: 38, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 92, height: 92)
                        .background(.white.opacity(0.22), in: Circle())
                        .padding(.bottom, 6)
                }
                Text(card.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                if !card.subtitle.isEmpty {
                    Text(card.subtitle)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                if card.entry.isPplzOnly {
                    Text("Only in pplz — no card in Contacts")
                        .font(.callout).foregroundStyle(.white.opacity(0.9))
                }
                if !quickActions.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(quickActions, id: \.symbol) { action in
                            Button { openURL(action.url) } label: {
                                Image(systemName: action.symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(.white.opacity(0.24), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .help(action.help)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var picture: Image? {
        guard let data = card.contact?.imageData else { return nil }
        #if os(macOS)
        return NSImage(data: data).map(Image.init(nsImage:))
        #else
        return UIImage(data: data).map(Image.init(uiImage:))
        #endif
    }

    private struct QuickAction {
        var symbol: String
        var help: String
        var url: URL
    }

    /// Message, call, video and mail — for the first phone number and mail address.
    private var quickActions: [QuickAction] {
        guard let contact = card.contact else { return [] }
        var actions: [QuickAction] = []
        if let phone = contact.phones.first?.value {
            if let url = ContactAction.message.url(for: phone) { actions.append(.init(symbol: "message.fill", help: "Message", url: url)) }
            if let url = ContactAction.call.url(for: phone) { actions.append(.init(symbol: "phone.fill", help: "Call", url: url)) }
            if let url = ContactAction.video.url(for: phone) { actions.append(.init(symbol: "video.fill", help: "FaceTime", url: url)) }
        }
        if let mail = contact.emails.first?.value, let url = ContactAction.mail.url(for: mail) {
            actions.append(.init(symbol: "envelope.fill", help: "Mail", url: url))
        }
        return actions
    }

    /// One rounded group per kind of field, each row with its action on the right — as in Contacts.
    @ViewBuilder private func contactFields(_ contact: ContactDetails) -> some View {
        fieldGroup(contact.phones, fallbackLabel: "phone", symbol: "phone.fill", action: .call)
        fieldGroup(contact.emails, fallbackLabel: "email", symbol: "envelope.fill", action: .mail)
        fieldGroup(contact.addresses, fallbackLabel: "address", symbol: "mappin.and.ellipse", action: .map)
        fieldGroup(contact.urls + contact.socialProfiles, fallbackLabel: "url", symbol: "safari.fill", action: .web)
        if let birthday = contact.birthday {
            FieldGroup { FieldRow(label: "birthday", value: birthday) }
        }
    }

    @ViewBuilder private func fieldGroup(_ values: [LabeledValue], fallbackLabel: String, symbol: String, action: ContactAction) -> some View {
        if !values.isEmpty {
            FieldGroup {
                ForEach(Array(values.enumerated()), id: \.offset) { index, item in
                    if index > 0 { Divider() }
                    FieldRow(label: item.label.isEmpty ? fallbackLabel : item.label, value: item.value,
                             symbol: symbol, url: action.url(for: item.value))
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

    private var connections: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Connections")
            FieldGroup {
                ForEach(Array(card.connections.enumerated()), id: \.element.id) { index, connection in
                    if index > 0 { Divider() }
                    HStack(spacing: 8) {
                        Button { onShowPerson(connection.other.id) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(connection.displayLabel).font(.caption).foregroundStyle(.secondary)
                                Text(connection.other.name)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Show \(connection.other.name)")
                        Button { onDisconnect(connection.other.id) } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove the connections with \(connection.other.name)")
                    }
                    .padding(.vertical, 8)
                }
                if !card.connections.isEmpty { Divider() }
                Button(action: onConnect) {
                    Label("Add connection", systemImage: "plus.circle").frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.pink)
                .padding(.vertical, 9)
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
    /// Optional action on the right, e.g. call this number.
    var symbol: String? = nil
    var url: URL? = nil

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let symbol, let url {
                Button { openURL(url) } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.pink)
                        .frame(width: 28, height: 28)
                        .background(.pink.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
            }
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
            Image(systemName: event.format.symbol).foregroundStyle(.pink).frame(width: 22)
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
}
