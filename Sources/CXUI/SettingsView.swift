import CXCore
import SwiftUI

/// The app's settings: who the user is, which fields of their contact go on "My Card" (SPEC §4.8), and the language (issue #13).
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
                        LabeledContent(String(localized: "Me", bundle: .module), value: model.myCardEntry?.name ?? String(localized: "Not chosen", bundle: .module))
                    }
                } header: {
                    Text("My Card", bundle: .module)
                } footer: {
                    Text("The person whose contact you pass on. On the Mac, the card marked “My Card” in Contacts is used until you choose.", bundle: .module)
                }
                if let contact = model.myContact {
                    fieldSections(contact)
                    Section {
                        NavigationLink(String(localized: "Show My Card", bundle: .module), value: Page.myCard)
                    }
                }
                Section {
                    Picker(String(localized: "Language", bundle: .module), selection: $model.language) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text("A new language applies the next time cardXchange starts.", bundle: .module)
                }
                Section(String(localized: "About", bundle: .module)) {
                    Text(verbatim: AppVersion.text(info: Bundle.main.infoDictionary))
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(String(localized: "Settings", bundle: .module))
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
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Done", bundle: .module)) { dismiss() } }
            }
            #endif
        }
        .tint(.pink)
        .task { await model.loadMyCard() }
    }

    /// One toggle per field of the user's contact. The name is always passed on.
    @ViewBuilder private func fieldSections(_ contact: ContactEdit) -> some View {
        Section {
            Toggle(isOn: .constant(true)) { FieldLabel(title: String(localized: "Name", bundle: .module), value: [contact.givenName, contact.familyName].joined(separator: " ")) }
                .disabled(true)
            if !contact.organization.isEmpty {
                Toggle(isOn: $model.myCardFields.company) { FieldLabel(title: String(localized: "Company", bundle: .module), value: contact.organization) }
            }
            if !contact.jobTitle.isEmpty {
                Toggle(isOn: $model.myCardFields.jobTitle) { FieldLabel(title: String(localized: "Job Title", bundle: .module), value: contact.jobTitle) }
            }
            Toggle(String(localized: "Picture", bundle: .module), isOn: $model.myCardFields.picture)
        } header: {
            Text("Passed On", bundle: .module)
        } footer: {
            Text("Only the fields that are switched on go on your card.", bundle: .module)
        }
        itemSection("Phone", contact.phones)
        itemSection("Email", contact.emails)
        itemSection("Web", contact.urls)
        itemSection("Social Profiles", contact.socialProfiles)
        if !contact.addresses.isEmpty {
            Section(String(localized: "Addresses", bundle: .module)) {
                ForEach(contact.addresses) { address in
                    Toggle(isOn: $model[passesOn: address.id]) {
                        FieldLabel(title: ContactLabels.display(address.label), value: MyCardView.text(of: address))
                    }
                }
            }
        }
    }

    /// `title` is a key of CXUI's string catalog.
    @ViewBuilder private func itemSection(_ title: LocalizedStringKey, _ items: [ContactEdit.Item]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    Toggle(isOn: $model[passesOn: item.id]) { FieldLabel(title: ContactLabels.display(item.label), value: item.value) }
                }
            } header: {
                Text(title, bundle: .module)
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
                    if entry.key == chosen { Image(systemName: "checkmark").accessibilityLabel(String(localized: "Chosen", bundle: .module)) }
                } label: {
                    Text(entry.name)
                }
            }
            .foregroundStyle(.primary)
        }
        .overlay {
            if entries.isEmpty { ContentUnavailableView(String(localized: "No people yet", bundle: .module), systemImage: "person.2") }
        }
        .searchable(text: $search, prompt: Text("Search", bundle: .module))
        .navigationTitle(String(localized: "Choose Me", bundle: .module))
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
                            .accessibilityLabel(String(localized: "Picture", bundle: .module))
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
                Section(String(localized: "Addresses", bundle: .module)) {
                    ForEach(card.contact.addresses) { address in
                        LabeledContent(ContactLabels.display(address.label), value: Self.text(of: address))
                    }
                }
            }
            Section {
            } footer: {
                Text("This is all that a person gets when you pass on your card.", bundle: .module)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "My Card", bundle: .module))
    }

    private var name: String { [card.contact.givenName, card.contact.familyName].filter { !$0.isEmpty }.joined(separator: " ") }
    private var subtitle: String { [card.contact.jobTitle, card.contact.organization].filter { !$0.isEmpty }.joined(separator: " · ") }

    /// `title` is a key of CXUI's string catalog.
    @ViewBuilder private func rows(_ title: LocalizedStringKey, _ items: [ContactEdit.Item]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    LabeledContent(ContactLabels.display(item.label), value: item.value)
                }
            } header: {
                Text(title, bundle: .module)
            }
        }
    }

    /// An address on one line: "Musterstr. 1, 50667 Köln, Germany".
    static func text(of address: ContactEdit.Address) -> String {
        [address.street, [address.postalCode, address.city].filter { !$0.isEmpty }.joined(separator: " "), address.country]
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
