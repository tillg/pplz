import CXCore
import SwiftUI

/// A person's card: the contact's own fields first, as in Contacts, then what cardXchange adds.
struct PersonCardView: View {
    let card: PersonCard
    @Environment(\.openURL) private var openURL
    var onConnect: () -> Void = {}
    var onLogEvent: () -> Void = {}
    var onDisconnect: (UUID) -> Void = { _ in }
    var onShowPerson: (UUID) -> Void = { _ in }
    /// Set for a person who exists only in cardXchange and can get a card in Contacts.
    var onAddToContacts: (() -> Void)? = nil
    var onAddPhotos: ([Data]) -> Void = { _ in }
    /// Set where the clipboard can be pasted as a photo (Mac).
    var onPastePhoto: (() -> Void)? = nil
    /// Set for a person whose contact may get a photo as its picture.
    var onUsePhoto: ((UUID) -> Void)? = nil
    var onDeletePhoto: (UUID) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let onAddToContacts {
                    Button(action: onAddToContacts) {
                        Label(String(localized: "Add to Contacts", bundle: .module), systemImage: "person.crop.circle.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.pink)
                    .help(String(localized: "Create a card in Contacts for \(card.entry.name), to enter phone, mail, address and picture", bundle: .module))
                }
                if let contact = card.contact { contactFields(contact) }
                cxFields
                PhotosGroup(photos: card.photos, onAdd: onAddPhotos, onPaste: onPastePhoto, onUse: onUsePhoto, onDelete: onDeletePhoto)
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
                // The picture fills a box of fixed height and the card's width; as an overlay it cannot
                // widen the card (a landscape picture would otherwise push the content off screen).
                // Cropping keeps the top, where the face usually is.
                Color.clear
                    .frame(maxWidth: .infinity).frame(height: 400)
                    .overlay(alignment: .top) { picture.resizable().scaledToFill() }
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
                if card.entry.isCXOnly {
                    Text("Only in cardXchange — no card in Contacts", bundle: .module)
                        .font(.callout).foregroundStyle(.white.opacity(0.9))
                }
                if let contact = card.contact, !contact.availableQuickActions.isEmpty {
                    HStack(spacing: 14) {
                        ForEach(contact.availableQuickActions, id: \.self) { action in
                            QuickActionButton(action: action, choices: contact.choices(for: action))
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

    /// One rounded group per kind of field, each row with its action on the right — as in Contacts.
    @ViewBuilder private func contactFields(_ contact: ContactDetails) -> some View {
        fieldGroup(contact.phones, fallbackLabel: String(localized: "phone", bundle: .module, comment: "Label of a phone number without a label"), symbol: "phone.fill", action: .call)
        fieldGroup(contact.emails, fallbackLabel: String(localized: "email", bundle: .module, comment: "Label of an email address without a label"), symbol: "envelope.fill", action: .mail)
        fieldGroup(contact.addresses, fallbackLabel: String(localized: "address", bundle: .module, comment: "Label of a postal address without a label"), symbol: "mappin.and.ellipse", action: .map)
        fieldGroup(contact.urls + contact.socialProfiles, fallbackLabel: String(localized: "url", bundle: .module, comment: "Label of a web address without a label"), symbol: "safari.fill", action: .web)
        if let birthday = contact.birthdayLine() {
            FieldGroup { FieldRow(label: String(localized: "birthday", bundle: .module), value: birthday) }
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

    @ViewBuilder private var cxFields: some View {
        let stored = card.stored
        let rows: [(String, String)] =
            (card.entry.tags.isEmpty ? [] : [(String(localized: "tags", bundle: .module), card.entry.tags.joined(separator: ", "))])
            + ((stored?.howWeMet.isEmpty ?? true) ? [] : [(String(localized: "how we met", bundle: .module), stored!.howWeMet)])
            + ((stored?.notes.isEmpty ?? true) ? [] : [(String(localized: "notes", bundle: .module), stored!.notes)])
            + (stored?.keepInTouchDays.map { [(String(localized: "keep in touch", bundle: .module), String(localized: "every \($0) days", bundle: .module))] } ?? [])
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(verbatim: "cardXchange")
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
                                Text(connection.label()).font(.caption).foregroundStyle(.secondary)
                                Text(connection.other.name)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Show \(connection.other.name)", bundle: .module))
                        Button { onDisconnect(connection.other.id) } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Remove the connections with \(connection.other.name)", bundle: .module))
                    }
                    .padding(.vertical, 8)
                }
                // related names that are on the contact card only: cardXchange has no connection for them
                ForEach(Array(card.relatedNamesOnlyInContacts.enumerated()), id: \.offset) { index, related in
                    if index > 0 || !card.connections.isEmpty { Divider() }
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(related.label).font(.caption).foregroundStyle(.secondary)
                            Text(related.value)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("in Contacts", bundle: .module).font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                }
                if !card.connections.isEmpty || !card.relatedNamesOnlyInContacts.isEmpty { Divider() }
                Button(action: onConnect) {
                    Label(String(localized: "Add connection", bundle: .module), systemImage: "person.badge.plus").frame(maxWidth: .infinity, alignment: .leading)
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
            FieldGroup {
                Button(action: onLogEvent) {
                    Label(String(localized: "Add event", bundle: .module), systemImage: "calendar.badge.plus").frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.pink)
                .padding(.vertical, 9)
            }
            if card.history.isEmpty {
                Text("No events yet", bundle: .module).foregroundStyle(.secondary).padding(.vertical, 4)
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
        return String(localized: "Met \(card.history.count)× · last \(last.start.formatted(date: .abbreviated, time: .omitted))", bundle: .module,
                      comment: "How often the user met the person, and the date of the last event")
    }
}

/// A big round button with a caption, as in Contacts: with one value it acts at once, with several it asks which.
struct QuickActionButton: View {
    let action: QuickAction
    let choices: [QuickActionChoice]
    @Environment(\.openURL) private var openURL
    @State private var choosing = false

    private var symbol: String {
        switch action {
        case .message: "message.fill"
        case .call: "phone.fill"
        case .video: "video.fill"
        case .mail: "envelope.fill"
        }
    }

    private var caption: String {
        switch action {
        case .message: String(localized: "message", bundle: .module, comment: "Caption of a quick action button, as in Contacts")
        case .call: String(localized: "call", bundle: .module, comment: "Caption of a quick action button, as in Contacts")
        case .video: String(localized: "video", bundle: .module, comment: "Caption of a quick action button, as in Contacts")
        case .mail: String(localized: "mail", bundle: .module, comment: "Caption of a quick action button, as in Contacts")
        }
    }

    var body: some View {
        Button {
            if choices.count == 1 { openURL(choices[0].url) } else { choosing = true }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(.white.opacity(0.24), in: Circle())
                Text(caption).font(.caption2).foregroundStyle(.white.opacity(0.9))
            }
            .frame(minWidth: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(caption)
        .accessibilityLabel(caption)
        .confirmationDialog(caption, isPresented: $choosing, titleVisibility: .visible) {
            ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                Button(choice.label + "  " + choice.value) { openURL(choice.url) }
            }
        }
    }
}

struct SectionTitle: View {
    let text: Text
    /// `key` is a key of CXUI's string catalog.
    init(_ key: LocalizedStringKey) { text = Text(key, bundle: .module) }
    init(verbatim: String) { text = Text(verbatim: verbatim) }

    var body: some View {
        text.font(.headline).foregroundStyle(.pink)
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
                Text(event.title.isEmpty ? event.format.name() : event.title)
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
        return ([event.title.isEmpty ? nil : event.format.name(), event.place.isEmpty ? nil : event.place,
                 others.isEmpty ? nil : String(localized: "with \(others.formatted())", bundle: .module, comment: "The other people of an event, as a list")] as [String?])
            .compactMap { $0 }.joined(separator: " · ")
    }
}

extension View {
    /// Sheets have a fixed width on the Mac; on iPhone and iPad the system sizes them.
    func sheetWidth(_ width: CGFloat) -> some View {
        #if os(macOS)
        frame(width: width)
        #else
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #endif
    }
}
