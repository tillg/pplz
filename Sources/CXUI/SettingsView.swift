import CXCore
import SwiftUI

/// The app's settings: who the user is, and which fields of their contact go on "My Card" (SPEC §4.8).
/// On the Mac it is the Settings window; on iPhone and iPad a sheet from the toolbar.
public struct SettingsView: View {
    @Bindable var model: PeopleModel
    @State private var path: [Page] = []
    @Environment(\.dismiss) private var dismiss

    enum Page: Hashable {
        case chooseMe, myCard
    }

    public init(model: PeopleModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    NavigationLink(value: Page.chooseMe) {
                        LabeledContent("Me", value: model.myCardEntry?.name ?? String(localized: "Not chosen"))
                    }
                } header: {
                    Text("My Card")
                } footer: {
                    Text("The person whose contact you pass on. On the Mac, the card marked “My Card” in Contacts is used until you choose.")
                }
                if let contact = model.myContact {
                    fieldSections(contact)
                    Section {
                        NavigationLink("Show My Card", value: Page.myCard)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .chooseMe:
                    ChooseMeView(entries: model.entries, chosen: model.myCardEntry?.key) { key in
                        path.removeAll()
                        Task { await model.chooseMe(key) }
                    }
                case .myCard:
                    if let card = model.myCard { MyCardView(card: card) }
                }
            }
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            #endif
        }
        .tint(.pink)
        .task { await model.loadMyCard() }
    }

    /// One toggle per field of the user's contact. The name is always passed on.
    @ViewBuilder private func fieldSections(_ contact: ContactEdit) -> some View {
        Section {
            Toggle(isOn: .constant(true)) { FieldLabel(title: "Name", value: [contact.givenName, contact.familyName].joined(separator: " ")) }
                .disabled(true)
            if !contact.organization.isEmpty {
                Toggle(isOn: $model.myCardFields.company) { FieldLabel(title: "Company", value: contact.organization) }
            }
            if !contact.jobTitle.isEmpty {
                Toggle(isOn: $model.myCardFields.jobTitle) { FieldLabel(title: "Job Title", value: contact.jobTitle) }
            }
            Toggle("Picture", isOn: $model.myCardFields.picture)
        } header: {
            Text("Passed On")
        } footer: {
            Text("Only the fields that are switched on go on your card.")
        }
        itemSection("Phone", contact.phones)
        itemSection("Email", contact.emails)
        itemSection("Web", contact.urls)
        itemSection("Social Profiles", contact.socialProfiles)
        if !contact.addresses.isEmpty {
            Section("Addresses") {
                ForEach(contact.addresses) { address in
                    Toggle(isOn: $model[passesOn: address.id]) {
                        FieldLabel(title: ContactLabels.display(address.label), value: MyCardView.text(of: address))
                    }
                }
            }
        }
    }

    @ViewBuilder private func itemSection(_ title: LocalizedStringKey, _ items: [ContactEdit.Item]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    Toggle(isOn: $model[passesOn: item.id]) { FieldLabel(title: ContactLabels.display(item.label), value: item.value) }
                }
            }
        }
    }
}

/// A field's value, with its label below it in small grey text, as in Contacts.
private struct FieldLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(value)
            if !title.isEmpty {
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The list of people, to choose the one who is the user.
private struct ChooseMeView: View {
    let entries: [PersonEntry]
    let chosen: String?
    let onChoose: (String) -> Void
    @State private var search = ""

    var body: some View {
        List(PeopleSections.matching(entries, search: search), id: \.key) { entry in
            Button {
                onChoose(entry.key)
            } label: {
                LabeledContent {
                    if entry.key == chosen { Image(systemName: "checkmark").accessibilityLabel("Chosen") }
                } label: {
                    Text(entry.name)
                }
            }
            .foregroundStyle(.primary)
        }
        .overlay {
            if entries.isEmpty { ContentUnavailableView("No people yet", systemImage: "person.2") }
        }
        .searchable(text: $search, prompt: "Search")
        .navigationTitle("Choose Me")
    }
}

/// "My Card": exactly what is passed on, nothing else.
struct MyCardView: View {
    let card: SharedCard

    private enum Layout {
        static let pictureSize: CGFloat = 96
    }

    var body: some View {
        Form {
            Section {
                VStack {
                    if let data = card.picture, let picture = Image(data: data) {
                        picture.resizable().scaledToFill()
                            .frame(width: Layout.pictureSize, height: Layout.pictureSize)
                            .clipShape(Circle())
                            .accessibilityLabel("Picture")
                    }
                    Text(name).font(.title2).bold()
                    if !subtitle.isEmpty {
                        Text(subtitle).foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
            rows("Phone", card.contact.phones)
            rows("Email", card.contact.emails)
            rows("Web", card.contact.urls)
            rows("Social Profiles", card.contact.socialProfiles)
            if !card.contact.addresses.isEmpty {
                Section("Addresses") {
                    ForEach(card.contact.addresses) { address in
                        LabeledContent(ContactLabels.display(address.label), value: Self.text(of: address))
                    }
                }
            }
            Section {
            } footer: {
                Text("This is all that a person gets when you pass on your card.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("My Card")
    }

    private var name: String { [card.contact.givenName, card.contact.familyName].filter { !$0.isEmpty }.joined(separator: " ") }
    private var subtitle: String { [card.contact.jobTitle, card.contact.organization].filter { !$0.isEmpty }.joined(separator: " · ") }

    @ViewBuilder private func rows(_ title: LocalizedStringKey, _ items: [ContactEdit.Item]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    LabeledContent(ContactLabels.display(item.label), value: item.value)
                }
            }
        }
    }

    /// An address on one line: "Musterstr. 1, 50667 Köln, Germany".
    static func text(of address: ContactEdit.Address) -> String {
        [address.street, [address.postalCode, address.city].filter { !$0.isEmpty }.joined(separator: " "), address.country]
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
