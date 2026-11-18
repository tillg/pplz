import PplzCore
import SwiftUI

/// "I just talked to …": log a meeting or call with one person.
struct LogEventSheet: View {
    let personName: String
    let onLog: (PeopleModel.LogInput) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var input = PeopleModel.LogInput()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Log event with \(personName)").font(.title3.weight(.semibold))
            Form {
                Picker("Format", selection: $input.format) {
                    ForEach(EventFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                TextField("Title", text: $input.title, prompt: Text("Optional, e.g. Dinner at Luigi's"))
                DatePicker("When", selection: $input.start)
                TextField("Place", text: $input.place, prompt: Text("Optional"))
                TextField("Notes", text: $input.notes, prompt: Text("What you talked about"), axis: .vertical)
                    .lineLimit(3...6)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Log") {
                    onLog(input)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .sheetWidth(440)
        .tint(.pink)
    }
}
