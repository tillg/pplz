import CXCore
import SwiftUI

/// Edits a person in place of the card, laid out like the edit view of Contacts: a label, the value, a button to
/// remove the row, and an empty row of each kind to add one. Two labelled groups say where the fields are kept:
/// in the contact card or in cardXchange. The contact's note is shown but cannot be changed, and cardXchange's link is not shown.
/// Also enters a new contact. Saving writes only what was changed.
struct PersonEditor: View {
    @Bindable var model: PeopleModel
    /// The person being edited; `nil` for a new contact.
    let entry: PersonEntry?
    let onClose: () -> Void

    @State private var contact = ContactEdit()
    /// The contact's fields as loaded, what the changes are measured against; `nil` for a person without a contact.
    @State private var originalContact: ContactEdit?
    @State private var person = PeopleModel.PersonEdit()
    @State private var originalPerson = PeopleModel.PersonEdit()
    @State private var pendingTag = ""
    /// The birthday as text, and as it was when loaded: it is only read again if it was edited.
    @State private var birthdayText = ""
    @State private var originalBirthdayText = ""
    /// The contact's note, shown but not editable; `nil` where cardXchange cannot read it.
    @State private var contactNote: String?
    @State private var isLoaded = false
    @State private var isSaving = false
    @State private var problem: String?

    /// Common rhythms; any other stored value is offered as "Every N days".
    private static var rhythms: [(String, Int?)] {
        [(String(localized: "No rhythm", bundle: .module), nil), (String(localized: "Every 2 weeks", bundle: .module), 14), (String(localized: "Every month", bundle: .module), 30),
         (String(localized: "Every 3 months", bundle: .module), 90), (String(localized: "Every 6 months", bundle: .module), 180), (String(localized: "Every year", bundle: .module), 365)]
    }

    var body: some View {
        ScrollView {
            if isLoaded {
                VStack(alignment: .leading, spacing: 7) {
                    if originalContact != nil { contactGroup }
                    if entry != nil { cxGroup }
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(40)
            }
        }
        #if os(macOS)
        .textFieldStyle(.plain)
        #else
        .navigationBarBackButtonHidden()
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationTitle(entry.map { String(localized: "Edit \($0.name)", bundle: .module) } ?? String(localized: "New Contact", bundle: .module))
        .tint(.pink)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel", bundle: .module), action: onClose) }
            ToolbarItem(placement: .confirmationAction) {
                Button(entry == nil ? String(localized: "Create", bundle: .module) : String(localized: "Done", bundle: .module), action: save).disabled(!canSave)
            }
        }
        .task { await load() }
        .onChange(of: contact) { keepEmptyRows() }
        .alert(String(localized: "Not saved", bundle: .module), isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button(String(localized: "OK", bundle: .module)) { problem = nil }
        } message: {
            Text(problem ?? "")
        }
    }

    // MARK: Loading and saving

    private func load() async {
        guard !isLoaded else { return }
        if let entry {
            person = model.personEdit
            originalPerson = person
            if entry.contactIdentifier != nil, model.usesContacts {
                if let loaded = await model.loadContactEdit() {
                    contact = loaded
                    originalContact = loaded
                    birthdayText = loaded.birthday?.text(locale: .current) ?? ""
                    originalBirthdayText = birthdayText
                    contactNote = await model.loadContactNote()
                } else {
                    problem = String(localized: "This contact could not be read; only what cardXchange keeps can be edited.", bundle: .module)
                }
            }
        } else {
            originalContact = ContactEdit()
        }
        keepEmptyRows()
        isLoaded = true
    }

    private var birthdayIsValid: Bool {
        let text = birthdayText.trimmingCharacters(in: .whitespaces)
        return birthdayText == originalBirthdayText || text.isEmpty || ContactEdit.Birthday.parse(text, locale: .current) != nil
    }

    private var canSave: Bool {
        isLoaded && !isSaving && birthdayIsValid && (originalContact == nil || contact.hasName)
    }

    private func save() {
        var contact = contact
        if birthdayText != originalBirthdayText {
            contact.birthday = ContactEdit.Birthday.parse(birthdayText.trimmingCharacters(in: .whitespaces), locale: .current)
        }
        var person = person
        person.tags = TagInput.adding(pendingTag, to: person.tags, known: model.knownTags)   // a tag typed but not added yet
        isSaving = true
        Task {
            let reason: String?
            if let entry {
                reason = await model.saveEdit(for: entry, contact: originalContact == nil ? nil : contact, originalContact: originalContact,
                                              person: person, originalPerson: originalPerson)
            } else {
                reason = await model.createContact(contact)
            }
            isSaving = false
            if let reason { problem = reason } else { onClose() }
        }
    }

    /// One empty row of each kind is always there to type in, as in Contacts; the save ignores the ones left empty.
    private func keepEmptyRows() {
        guard originalContact != nil else { return }
        func needsRow(_ items: [ContactEdit.Item]) -> Bool { items.last.map { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty } ?? true }
        func nextLabel(_ labels: [String], used: [String]) -> String { labels.first { !used.contains($0) } ?? labels.first ?? "" }
        if needsRow(contact.phones) { contact.phones.append(.init(label: nextLabel(ContactLabels.phone, used: contact.phones.map(\.label)))) }
        if needsRow(contact.emails) { contact.emails.append(.init(label: nextLabel(ContactLabels.email, used: contact.emails.map(\.label)))) }
        if needsRow(contact.urls) { contact.urls.append(.init(label: nextLabel(ContactLabels.url, used: contact.urls.map(\.label)))) }
        if needsRow(contact.socialProfiles) {
            contact.socialProfiles.append(.init(label: nextLabel(ContactLabels.socialProfile, used: contact.socialProfiles.map(\.label))))
        }
        if contact.addresses.last.map({ !Self.isEmpty($0) }) ?? true {
            contact.addresses.append(.init(label: nextLabel(ContactLabels.address, used: contact.addresses.map(\.label))))
        }
    }

    private static func isEmpty(_ address: ContactEdit.Address) -> Bool {
        [address.street, address.postalCode, address.city, address.country].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: The contact card

    @ViewBuilder private var contactGroup: some View {
        if entry != nil {
            GroupHeader(title: "Contact card", detail: "Saved in Apple Contacts", systemImage: "person.crop.square.fill")
        }
        textRow("first name", text: $contact.givenName, name: "First name")
        textRow("last name", text: $contact.familyName, name: "Last name")
        textRow("nickname", text: $contact.nickname, name: "Nickname")
        textRow("company", text: $contact.organization, name: "Company")
        textRow("job title", text: $contact.jobTitle, name: "Job title")
        Divider()
        multiValue(String(localized: "phone", bundle: .module), prompt: "Phone", labels: ContactLabels.phone, items: $contact.phones)
        Divider()
        multiValue(String(localized: "email", bundle: .module), prompt: "Email", labels: ContactLabels.email, items: $contact.emails)
        Divider()
        multiValue(String(localized: "web address", bundle: .module), prompt: "URL", labels: ContactLabels.url, items: $contact.urls)
        Divider()
        multiValue(String(localized: "social profile", bundle: .module), prompt: "Profile address or user name", labels: ContactLabels.socialProfile, items: $contact.socialProfiles)
        Divider()
        EditRow {
            RowLabel("birthday")
        } content: {
            VStack(alignment: .leading, spacing: 2) {
                TextField(String(localized: "Birthday", bundle: .module), text: $birthdayText, prompt: Text("Day and month, with or without the year", bundle: .module))
                    .accessibilityLabel(String(localized: "Birthday", bundle: .module))
                if !birthdayIsValid {
                    Text("Not a date. Write it like \(ContactEdit.Birthday(day: 2, month: 9, year: 1963).text(locale: .current)), or without the year.", bundle: .module)
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
        Divider()
        addresses
        if entry != nil {
            Divider()
            EditRow {
                RowLabel("note")
            } content: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(contactNote.map { $0.isEmpty ? String(localized: "No note", bundle: .module) : $0 }
                         ?? String(localized: "cardXchange cannot read the note on this device", bundle: .module))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "contact note", bundle: .module))
                    Text("The note can only be changed in the Contacts app.", bundle: .module).font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// `label` and `name` are keys of CXUI's string catalog.
    private func textRow(_ label: LocalizedStringKey, text: Binding<String>, name: LocalizedStringKey) -> some View {
        EditRow {
            RowLabel(label)
        } content: {
            TextField(text: text, prompt: Text(name, bundle: .module)) { Text(name, bundle: .module) }
                .accessibilityLabel(Text(name, bundle: .module))
        }
    }

    /// The rows of one kind. They are bound by identity, not by position: a row that is removed while its field has
    /// focus must not be looked up again. The empty row at the end has no remove button.
    /// `kind` is in the user's language, `prompt` a key of CXUI's string catalog.
    @ViewBuilder private func multiValue(_ kind: String, prompt: LocalizedStringKey, labels: [String], items: Binding<[ContactEdit.Item]>) -> some View {
        ForEach(items) { $item in
            let position = items.wrappedValue.firstIndex { $0.id == item.id } ?? 0
            let number = "\(kind) \(position + 1)"
            let isWaiting = position == items.wrappedValue.count - 1 && item.value.trimmingCharacters(in: .whitespaces).isEmpty
            EditRow(removeName: String(localized: "remove \(number)", bundle: .module), onRemove: isWaiting ? nil : { items.wrappedValue.removeAll { $0.id == item.id } }) {
                LabelMenu(labels: labels, label: $item.label, name: String(localized: "\(number) label", bundle: .module))
            } content: {
                TextField(text: $item.value, prompt: Text(prompt, bundle: .module)) { Text(prompt, bundle: .module) }
                    .accessibilityLabel(String(localized: "\(number) value", bundle: .module))
            }
        }
    }

    @ViewBuilder private var addresses: some View {
        ForEach($contact.addresses) { $address in
            let position = contact.addresses.firstIndex { $0.id == address.id } ?? 0
            let number = String(localized: "address \(position + 1)", bundle: .module)
            let isWaiting = position == contact.addresses.count - 1 && Self.isEmpty(address)
            EditRow(removeName: String(localized: "remove \(number)", bundle: .module), onRemove: isWaiting ? nil : { contact.addresses.removeAll { $0.id == address.id } }) {
                LabelMenu(labels: ContactLabels.address, label: $address.label, name: String(localized: "\(number) label", bundle: .module))
            } content: {
                VStack(alignment: .leading, spacing: 4) {
                    TextField(String(localized: "Street", bundle: .module), text: $address.street, prompt: Text("Street", bundle: .module)).accessibilityLabel(String(localized: "\(number) street", bundle: .module))
                    HStack(spacing: 12) {
                        TextField(String(localized: "Postal code", bundle: .module), text: $address.postalCode, prompt: Text("Postal code", bundle: .module))
                            .accessibilityLabel(String(localized: "\(number) postal code", bundle: .module))
                            .frame(width: 90)
                        TextField(String(localized: "City", bundle: .module), text: $address.city, prompt: Text("City", bundle: .module)).accessibilityLabel(String(localized: "\(number) city", bundle: .module))
                    }
                    TextField(String(localized: "Country", bundle: .module), text: $address.country, prompt: Text("Country", bundle: .module)).accessibilityLabel(String(localized: "\(number) country", bundle: .module))
                }
            }
        }
    }

    // MARK: What cardXchange keeps

    @ViewBuilder private var cxGroup: some View {
        GroupHeader(title: "cardXchange", detail: "Kept by cardXchange only", systemImage: "heart.fill")
            .padding(.top, originalContact == nil ? 0 : 14)
        EditRow {
            RowLabel("tags")
        } content: {
            TagField(title: "Tags", text: $person.tags, pending: $pendingTag, known: model.knownTags, showsTitle: false)
        }
        Divider()
        EditRow {
            RowLabel("how we met")
        } content: {
            TextField(String(localized: "How we met", bundle: .module), text: $person.howWeMet, prompt: Text("Where, when, through whom", bundle: .module), axis: .vertical)
                .lineLimit(1...4)
                .accessibilityLabel(String(localized: "How we met", bundle: .module))
        }
        Divider()
        EditRow {
            RowLabel("notes")
        } content: {
            TextField(String(localized: "Notes", bundle: .module), text: $person.notes, prompt: Text("Things to remember", bundle: .module), axis: .vertical)
                .lineLimit(2...8)
                .accessibilityLabel(String(localized: "Notes", bundle: .module))
        }
        Divider()
        EditRow {
            RowLabel("keep in touch")
        } content: {
            Picker(String(localized: "Keep in touch", bundle: .module), selection: $person.keepInTouchDays) {
                ForEach(rhythmOptions, id: \.1) { Text($0.0).tag($0.1) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private var rhythmOptions: [(String, Int?)] {
        guard let days = person.keepInTouchDays, !Self.rhythms.contains(where: { $0.1 == days }) else { return Self.rhythms }
        return Self.rhythms + [(String(localized: "Every \(days) days", bundle: .module), days)]
    }
}

/// One line of the editor: the remove button (or its space), the label right-aligned in its column, the value.
private struct EditRow<Label: View, Content: View>: View {
    var removeName = ""
    var onRemove: (() -> Void)? = nil
    @ViewBuilder let label: Label
    @ViewBuilder let content: Content

    #if os(macOS)
    private let labelWidth: CGFloat = 110
    #else
    private let labelWidth: CGFloat = 96
    #endif

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if let onRemove {
                    Button(action: onRemove) { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(removeName)
                } else {
                    Text(verbatim: " ")
                }
            }
            .frame(width: 18)
            label.frame(width: labelWidth, alignment: .trailing)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The label of a row that has no choice of label.
private struct RowLabel: View {
    /// A key of CXUI's string catalog.
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View { Text(text, bundle: .module).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8) }
}

/// The label of a row, chosen from the usual ones; a label the contact already has is kept in the list.
private struct LabelMenu: View {
    let labels: [String]
    @Binding var label: String
    let name: String
    /// What the label was when the form opened, so that a custom label stays offered after another was chosen.
    @State private var opened: String?

    var body: some View {
        Menu {
            ForEach(ContactLabels.options(labels, including: opened ?? label), id: \.self) { option in
                Button(ContactLabels.display(option)) { label = option }
            }
        } label: {
            // one text, so that the Mac keeps the arrows behind the word
            (Text(label.isEmpty ? String(localized: "label", bundle: .module) : ContactLabels.display(label)) + Text(verbatim: " ") + Text(Image(systemName: "chevron.up.chevron.down")).font(.caption2))
                .lineLimit(1)
                .foregroundStyle(.pink)
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        #endif
        .fixedSize()
        .accessibilityLabel(name)
        .onAppear { opened = label }
    }
}

/// Says where the fields below it are kept: in the contact card or in cardXchange.
private struct GroupHeader: View {
    /// Title and detail are keys of CXUI's string catalog.
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label { Text(title, bundle: .module) } icon: { Image(systemName: systemImage) }.font(.headline).foregroundStyle(.pink)
            Text(detail, bundle: .module).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }
}
