import PplzCore
import SwiftUI

/// "I just talked to …": log a meeting or call with one person.
struct LogEventSheet: View {
    let personName: String
    let onLog: (PeopleModel.LogInput) -> Void

    @State private var input = PeopleModel.LogInput()

    var body: some View {
        SheetScaffold(title: "Log event with \(personName)", confirmTitle: "Log", width: 440, onConfirm: { onLog(input) }) {
            Picker("Format", selection: $input.format) {
                ForEach(EventFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            FormField(title: "Title", text: $input.title, prompt: "Optional, e.g. Dinner at Luigi's")
            DatePicker("When", selection: $input.start)
            FormField(title: "Place", text: $input.place, prompt: "Optional")
            FormField(title: "Notes", text: $input.notes, prompt: "What you talked about", lines: 3...6)
        }
    }
}
