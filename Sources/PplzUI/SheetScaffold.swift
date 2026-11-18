import SwiftUI

/// The frame around every edit sheet: a title, the form, Cancel and a confirm button —
/// laid out the Mac way on the Mac and as a navigation bar on iPhone and iPad.
struct SheetScaffold<Content: View>: View {
    let title: String
    let confirmTitle: String
    var canConfirm = true
    var width: CGFloat = 460
    let onConfirm: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.weight(.semibold))
            Form { content }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canConfirm)
            }
        }
        .padding(20)
        .frame(width: width)
        .tint(.pink)
        #else
        NavigationStack {
            Form { content }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(confirmTitle, action: confirm).disabled(!canConfirm) }
                }
        }
        .tint(.pink)
        #endif
    }

    private func confirm() {
        onConfirm()
        dismiss()
    }
}

/// A text field that always shows what it is for. On the Mac the form puts the title to the left;
/// on iPhone a bare field would only show its grey placeholder, so the title is shown above it.
struct FormField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""
    /// More than one line of height, for longer text.
    var lines: ClosedRange<Int>? = nil

    var body: some View {
        #if os(macOS)
        field
        #else
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            field
        }
        .accessibilityElement(children: .contain)
        #endif
    }

    @ViewBuilder private var field: some View {
        if let lines {
            TextField(title, text: $text, prompt: prompt.isEmpty ? nil : Text(prompt), axis: .vertical)
                .lineLimit(lines)
                .accessibilityLabel(title)
        } else {
            TextField(title, text: $text, prompt: prompt.isEmpty ? nil : Text(prompt))
                .accessibilityLabel(title)
        }
    }
}
