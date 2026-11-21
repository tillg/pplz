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
                    Text("cardXchange keeps a deleted person for 30 days, with their events, notes, tags and photos. Then it deletes them for good. A restored contact has no note.")
                }
            }
            .overlay {
                if model.recentlyDeleted.isEmpty {
                    ContentUnavailableView("No recently deleted people", systemImage: "trash")
                }
            }
            .navigationTitle("Recently Deleted")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete for good?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                presenting: removing) { person in
                Button("Delete \(person.name) for Good", role: .destructive) {
                    Task { await model.deleteForGood(person.id) }
                }
            } message: { _ in
                Text("The person's notes, tags and photos are deleted. Their events stay without them. This cannot be undone.")
            }
        }
        .tint(.pink)
        #if os(macOS)
        .frame(width: Self.size.width, height: Self.size.height)
        #endif
    }

    private func row(_ person: DeletedPerson) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(person.name)
                Text("Deleted for good on \(person.removalDate, format: .dateTime.day().month().year())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // borderless: two buttons in one row of a list must not act as one
            Button("Restore") { Task { await model.restore(person.id) } }
                .buttonStyle(.borderless)
            Button("Delete Now", systemImage: "trash", role: .destructive) { removing = person }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }
}
