import CXCore
import SwiftUI

/// The persons deleted in the last 30 days, to restore them or to delete them for good now (SPEC §3.4).
struct RecentlyDeletedSheet: View {
    let model: PeopleModel

    @Environment(\.dismiss) private var dismiss
    @State private var removing: DeletedPerson?

    #if os(macOS)
    private static let size = CGSize(width: 460, height: 420)
    #endif

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.recentlyDeleted, id: \.id) { person in
                        row(person)
                    }
                } footer: {
                    Text("cardXchange keeps a deleted person for 30 days, with their events, notes, tags and photos. Then it deletes them for good. A restored contact has no note.", bundle: .module)
                }
            }
            .overlay {
                if model.recentlyDeleted.isEmpty {
                    ContentUnavailableView(String(localized: "No recently deleted people", bundle: .module), systemImage: "trash")
                }
            }
            .navigationTitle(String(localized: "Recently Deleted", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Done", bundle: .module)) { dismiss() } }
            }
            .confirmationDialog(String(localized: "Delete for good?", bundle: .module), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                presenting: removing) { person in
                Button(String(localized: "Delete \(person.name) for Good", bundle: .module), role: .destructive) {
                    Task { await model.deleteForGood(person.id) }
                }
            } message: { _ in
                Text("The person's notes, tags and photos are deleted. Their events stay without them. This cannot be undone.", bundle: .module)
            }
        }
        .tint(.pink)
        // the alert of the main window does not show while this sheet is open
        .alert(String(localized: "cardXchange", bundle: .module), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.dismissError() } })) {
            Button(String(localized: "OK", bundle: .module)) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        #if os(macOS)
        .frame(width: Self.size.width, height: Self.size.height)
        #endif
    }

    private func row(_ person: DeletedPerson) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(person.name)
                Text("Deleted for good on \(person.removalDate, format: .dateTime.day().month().year())", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // borderless: two buttons in one row of a list must not act as one
            Button(String(localized: "Restore", bundle: .module)) { Task { await model.restore(person.id) } }
                .buttonStyle(.borderless)
            Button(String(localized: "Delete Now", bundle: .module), systemImage: "trash", role: .destructive) { removing = person }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }
}
