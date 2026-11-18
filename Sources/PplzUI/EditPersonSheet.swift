import PplzCore
import SwiftUI

/// Edits what pplz stores about a person. The contact's own fields are edited in Contacts.
struct EditPersonSheet: View {
    let personName: String
    let onSave: (PeopleModel.PersonEdit) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edit: PeopleModel.PersonEdit

    /// Common rhythms; any other stored value is offered as "Every N days".
    private static let rhythms: [(String, Int?)] = [
        ("No rhythm", nil), ("Every 2 weeks", 14), ("Every month", 30), ("Every 3 months", 90),
        ("Every 6 months", 180), ("Every year", 365),
    ]

    init(personName: String, edit: PeopleModel.PersonEdit, onSave: @escaping (PeopleModel.PersonEdit) -> Void) {
        self.personName = personName
        self.onSave = onSave
        _edit = State(initialValue: edit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit \(personName)").font(.title3.weight(.semibold))
            Form {
                TextField("Tags", text: $edit.tags, prompt: Text("Separated by commas, e.g. client, sailing"))
                TextField("How we met", text: $edit.howWeMet, prompt: Text("Where, when, through whom"), axis: .vertical)
                    .lineLimit(2...4)
                TextField("Notes", text: $edit.notes, prompt: Text("Things to remember"), axis: .vertical)
                    .lineLimit(4...8)
                Picker("Keep in touch", selection: $edit.keepInTouchDays) {
                    ForEach(options, id: \.1) { Text($0.0).tag($0.1) }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(edit)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
        .tint(.pink)
    }

    private var options: [(String, Int?)] {
        guard let days = edit.keepInTouchDays, !Self.rhythms.contains(where: { $0.1 == days }) else { return Self.rhythms }
        return Self.rhythms + [("Every \(days) days", days)]
    }
}
