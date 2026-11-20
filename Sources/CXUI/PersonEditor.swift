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
    private static let rhythms: [(String, Int?)] = [
        ("No rhythm", nil), ("Every 2 weeks", 14), ("Every month", 30), ("Every 3 months", 90),
        ("Every 6 months", 180), ("Every year", 365),
    ]

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
        .navigationTitle(entry.map { "Edit \($0.name)" } ?? "New Contact")
        .tint(.pink)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onClose) }
            ToolbarItem(placement: .confirmationAction) {
                Button(entry == nil ? "Create" : "Done", action: save).disabled(!canSave)
            }
        }
        .task { await load() }
        .onChange(of: contact) { keepEmptyRows() }
        .alert("Not saved", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
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
                    problem = "This contact could not be read; only what cardXchange keeps can be edited."
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
        multiValue("phone", prompt: "Phone", labels: ContactLabels.phone, items: $contact.phones)
        Divider()
        multiValue("email", prompt: "Email", labels: ContactLabels.email, items: $contact.emails)
        Divider()
        multiValue("web address", prompt: "URL", labels: ContactLabels.url, items: $contact.urls)
        Divider()
        multiValue("social profile", prompt: "Profile address or user name", labels: ContactLabels.socialProfile, items: $contact.socialProfiles)
        Divider()
        EditRow {
            RowLabel("birthday")
        } content: {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Birthday", text: $birthdayText, prompt: Text("Day and month, with or without the year"))
                    .accessibilityLabel("Birthday")
                if !birthdayIsValid {
                    Text("Not a date. Write it like \(ContactEdit.Birthday(day: 2, month: 9, year: 1963).text(locale: .current)), or without the year.")
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
                    Text(contactNote.map { $0.isEmpty ? "No note" : $0 } ?? "cardXchange cannot read the note on this device")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("contact note")
                    Text("The note can only be changed in the Contacts app.").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func textRow(_ label: String, text: Binding<String>, name: String) -> some View {
        EditRow {
            RowLabel(label)
        } content: {
            TextField(name, text: text, prompt: Text(name)).accessibilityLabel(name)
        }
    }

    /// The rows of one kind. They are bound by identity, not by position: a row that is removed while its field has
    /// focus must not be looked up again. The empty row at the end has no remove button.
    @ViewBuilder private func multiValue(_ kind: String, prompt: String, labels: [String], items: Binding<[ContactEdit.Item]>) -> some View {
        ForEach(items) { $item in
            let position = items.wrappedValue.firstIndex { $0.id == item.id } ?? 0
            let number = "\(kind) \(position + 1)"
            let isWaiting = position == items.wrappedValue.count - 1 && item.value.trimmingCharacters(in: .whitespaces).isEmpty
            EditRow(removeName: "remove \(number)", onRemove: isWaiting ? nil : { items.wrappedValue.removeAll { $0.id == item.id } }) {
                LabelMenu(labels: labels, label: $item.label, name: "\(number) label")
            } content: {
                TextField(prompt, text: $item.value, prompt: Text(prompt)).accessibilityLabel("\(number) value")
            }
        }
    }

    @ViewBuilder private var addresses: some View {
        ForEach($contact.addresses) { $address in
            let position = contact.addresses.firstIndex { $0.id == address.id } ?? 0
            let number = "address \(position + 1)"
            let isWaiting = position == contact.addresses.count - 1 && Self.isEmpty(address)
            EditRow(removeName: "remove \(number)", onRemove: isWaiting ? nil : { contact.addresses.removeAll { $0.id == address.id } }) {
                LabelMenu(labels: ContactLabels.address, label: $address.label, name: "\(number) label")
            } content: {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Street", text: $address.street, prompt: Text("Street")).accessibilityLabel("\(number) street")
                    HStack(spacing: 12) {
                        TextField("Postal code", text: $address.postalCode, prompt: Text("Postal code"))
                            .accessibilityLabel("\(number) postal code")
                            .frame(width: 90)
                        TextField("City", text: $address.city, prompt: Text("City")).accessibilityLabel("\(number) city")
                    }
                    TextField("Country", text: $address.country, prompt: Text("Country")).accessibilityLabel("\(number) country")
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
            TextField("How we met", text: $person.howWeMet, prompt: Text("Where, when, through whom"), axis: .vertical)
                .lineLimit(1...4)
                .accessibilityLabel("How we met")
        }
        Divider()
        EditRow {
            RowLabel("notes")
        } content: {
            TextField("Notes", text: $person.notes, prompt: Text("Things to remember"), axis: .vertical)
                .lineLimit(2...8)
                .accessibilityLabel("Notes")
        }
        Divider()
        EditRow {
            RowLabel("keep in touch")
        } content: {
            Picker("Keep in touch", selection: $person.keepInTouchDays) {
                ForEach(rhythmOptions, id: \.1) { Text($0.0).tag($0.1) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private var rhythmOptions: [(String, Int?)] {
        guard let days = person.keepInTouchDays, !Self.rhythms.contains(where: { $0.1 == days }) else { return Self.rhythms }
        return Self.rhythms + [("Every \(days) days", days)]
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
                    Text(" ")
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
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8) }
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
            (Text(label.isEmpty ? "label" : ContactLabels.display(label)) + Text(" ") + Text(Image(systemName: "chevron.up.chevron.down")).font(.caption2))
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
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label(title, systemImage: systemImage).font(.headline).foregroundStyle(.pink)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }
}
