import PplzCore
import SwiftUI

/// Edits a contact's own fields, or enters a new contact: the same screen on the Mac, iPhone and iPad.
/// Not the note, and not pplz's link — those are not shown. Saving writes only what was changed.
struct ContactEditSheet: View {
    @Bindable var model: PeopleModel
    /// `false` for a new contact.
    let isEditing: Bool

    @State private var edit = ContactEdit()
    /// The fields as loaded; what the changes are measured against.
    @State private var original: ContactEdit?
    @State private var isLoaded = false
    @State private var isSaving = false
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold(title: isEditing ? "Edit Contact" : "New Contact", confirmTitle: isEditing ? "Save" : "Create",
                      canConfirm: isLoaded && edit.hasName && !isSaving, height: 620, dismissesOnConfirm: false, onConfirm: save) {
            if isLoaded {
                names
                multiValue("Phone", prompt: "Phone number", labels: ContactLabels.phone, items: $edit.phones)
                multiValue("Email", prompt: "Mail address", labels: ContactLabels.email, items: $edit.emails)
                multiValue("Web address", prompt: "Address", labels: ContactLabels.url, items: $edit.urls)
                multiValue("Social profile", prompt: "Profile address or user name", labels: ContactLabels.socialProfile, items: $edit.socialProfiles)
                addresses
                BirthdayField(birthday: $edit.birthday)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task {
            guard !isLoaded else { return }
            if isEditing {
                guard let loaded = await model.loadContactEdit() else {
                    problem = "This contact could not be read."
                    return
                }
                edit = loaded
                original = loaded
            } else {
                original = ContactEdit()
            }
            isLoaded = true
        }
        .alert("Contact not saved", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        } message: {
            Text(problem ?? "")
        }
    }

    private func save() {
        guard let original else { return }
        isSaving = true
        Task {
            let reason = isEditing ? await model.saveContactEdit(edit, original: original) : await model.createContact(edit)
            isSaving = false
            if let reason { problem = reason } else { dismiss() }
        }
    }

    @ViewBuilder private var names: some View {
        Section {
            FormField(title: "First name", text: $edit.givenName)
            FormField(title: "Last name", text: $edit.familyName)
            FormField(title: "Nickname", text: $edit.nickname)
            FormField(title: "Company", text: $edit.organization)
            FormField(title: "Job title", text: $edit.jobTitle)
        }
    }

    /// The rows of one kind, each with its label and a button to remove it, and a button to add one.
    /// The rows are bound by identity, not by position: a row that is removed while its field has focus must not be looked up again.
    @ViewBuilder private func multiValue(_ title: String, prompt: String, labels: [String], items: Binding<[ContactEdit.Item]>) -> some View {
        Section(title) {
            ForEach(items) { $item in
                let number = "\(title.lowercased()) \((items.wrappedValue.firstIndex { $0.id == item.id } ?? 0) + 1)"
                HStack(spacing: 8) {
                    LabelMenu(labels: labels, label: $item.label, name: "\(number) label")
                    TextField(prompt, text: $item.value, prompt: Text(prompt))
                        .labelsHidden()
                        .accessibilityLabel("\(number) value")
                    RemoveButton(name: "remove \(number)") { items.wrappedValue.removeAll { $0.id == item.id } }
                }
            }
            Button { items.wrappedValue.append(ContactEdit.Item(label: labels.first ?? "")) } label: {
                Label("add \(title.lowercased())", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.pink)
        }
    }

    @ViewBuilder private var addresses: some View {
        Section("Address") {
            ForEach($edit.addresses) { $address in
                let number = "address \((edit.addresses.firstIndex { $0.id == address.id } ?? 0) + 1)"
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        LabelMenu(labels: ContactLabels.address, label: $address.label, name: "\(number) label")
                        Spacer()
                        RemoveButton(name: "remove \(number)") { edit.addresses.removeAll { $0.id == address.id } }
                    }
                    TextField("Street", text: $address.street).accessibilityLabel("\(number) street")
                    HStack {
                        TextField("Postal code", text: $address.postalCode).accessibilityLabel("\(number) postal code")
                            .frame(maxWidth: 110)
                        TextField("City", text: $address.city).accessibilityLabel("\(number) city")
                    }
                    TextField("Country", text: $address.country).accessibilityLabel("\(number) country")
                }
                .padding(.vertical, 2)
            }
            Button { edit.addresses.append(ContactEdit.Address(label: ContactLabels.address[0])) } label: {
                Label("add address", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.pink)
        }
    }
}

/// The label of a row, chosen from the usual ones; a label the contact already has is kept in the list.
private struct LabelMenu: View {
    let labels: [String]
    @Binding var label: String
    let name: String
    /// What the label was when the form opened, so that a custom label stays offered after another was chosen.
    @State private var opened: String?

    var body: some View {
        Picker(name, selection: $label) {
            ForEach(ContactLabels.options(labels, including: opened ?? label), id: \.self) { Text(ContactLabels.display($0)).tag($0) }
            if label.isEmpty { Text("label").tag("") }
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(name)
        .onAppear { opened = label }
    }
}

private struct RemoveButton: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
    }
}

/// Day and month, and the year if wanted; a birthday without a year stays without one.
private struct BirthdayField: View {
    @Binding var birthday: ContactEdit.Birthday?

    var body: some View {
        Section("Birthday") {
            Toggle("Birthday", isOn: Binding(get: { birthday != nil }, set: { birthday = $0 ? ContactEdit.Birthday(day: 1, month: 1) : nil }))
            if let value = birthday {
                HStack {
                    Picker("Day", selection: Binding(get: { value.day }, set: { birthday?.day = $0 })) {
                        ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Month", selection: Binding(get: { value.month }, set: { birthday?.month = $0 })) {
                        ForEach(1...12, id: \.self) { Text(Calendar.current.monthSymbols[$0 - 1]).tag($0) }
                    }
                }
                Toggle("Year", isOn: Binding(get: { value.year != nil }, set: { birthday?.year = $0 ? 1980 : nil }))
                if let year = value.year {
                    TextField("Year", value: Binding(get: { year }, set: { birthday?.year = $0 }), format: .number.grouping(.never))
                        .accessibilityLabel("birthday year")
                }
            }
        }
    }
}
