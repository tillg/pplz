import PplzCore
import SwiftUI

/// Edits what pplz stores about a person. The contact's own fields are edited in Contacts.
struct EditPersonSheet: View {
    let personName: String
    let onSave: (PeopleModel.PersonEdit) -> Void

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
        SheetScaffold(title: "Edit \(personName)", confirmTitle: "Save", onConfirm: { onSave(edit) }) {
            FormField(title: "Tags", text: $edit.tags, prompt: "Separated by commas, e.g. client, sailing")
            FormField(title: "How we met", text: $edit.howWeMet, prompt: "Where, when, through whom", lines: 2...4)
            FormField(title: "Notes", text: $edit.notes, prompt: "Things to remember", lines: 4...8)
            Picker("Keep in touch", selection: $edit.keepInTouchDays) {
                ForEach(options, id: \.1) { Text($0.0).tag($0.1) }
            }
        }
    }

    private var options: [(String, Int?)] {
        guard let days = edit.keepInTouchDays, !Self.rhythms.contains(where: { $0.1 == days }) else { return Self.rhythms }
        return Self.rhythms + [("Every \(days) days", days)]
    }
}
