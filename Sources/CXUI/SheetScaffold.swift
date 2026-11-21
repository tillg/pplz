import SwiftUI

/// The frame around every edit sheet: a title, the form, Cancel and a confirm button —
/// laid out the Mac way on the Mac and as a navigation bar on iPhone and iPad.
/// The titles are keys of CXUI's string catalog.
struct SheetScaffold<Content: View>: View {
    let title: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    var canConfirm = true
    var width: CGFloat = 460
    /// False for a sheet with more than one step: confirming then leaves it open.
    var dismissesOnConfirm = true
    let onConfirm: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            Text(title, bundle: .module).font(.title3.weight(.semibold))
            Form { content }
            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: .module), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action: confirm) { Text(confirmTitle, bundle: .module) }
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
                .navigationTitle(Text(title, bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel", bundle: .module)) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(action: confirm) { Text(confirmTitle, bundle: .module) }.disabled(!canConfirm) }
                }
        }
        .tint(.pink)
        #endif
    }

    private func confirm() {
        onConfirm()
        if dismissesOnConfirm { dismiss() }
    }
}

/// A text field that always shows what it is for. On the Mac the form puts the title to the left;
/// on iPhone a bare field would only show its grey placeholder, so the title is shown above it.
/// Title and prompt are keys of CXUI's string catalog.
struct FormField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var prompt: LocalizedStringKey? = nil
    /// More than one line of height, for longer text.
    var lines: ClosedRange<Int>? = nil

    var body: some View {
        #if os(macOS)
        field
        #else
        VStack(alignment: .leading, spacing: 3) {
            Text(title, bundle: .module).font(.caption).foregroundStyle(.secondary)
            field
        }
        .accessibilityElement(children: .contain)
        #endif
    }

    @ViewBuilder private var field: some View {
        if let lines {
            TextField(text: $text, prompt: prompt.map { Text($0, bundle: .module) }, axis: .vertical) { Text(title, bundle: .module) }
                .lineLimit(lines)
                .accessibilityLabel(Text(title, bundle: .module))
        } else {
            TextField(text: $text, prompt: prompt.map { Text($0, bundle: .module) }) { Text(title, bundle: .module) }
                .accessibilityLabel(Text(title, bundle: .module))
        }
    }
}
