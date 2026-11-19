import PplzCore
import SwiftUI

/// Chooses tags: the chosen ones on top, a field to find or create one, and the existing tags to pick from.
/// `text` holds the chosen tags separated by commas; `pending` is what is typed but not added yet,
/// so that the sheet can still take it along when it is saved.
struct TagField: View {
    let title: String
    @Binding var text: String
    @Binding var pending: String
    let known: [String]

    var body: some View {
        #if os(macOS)
        LabeledContent(title) { content }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content
        }
        .accessibilityElement(children: .contain)
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            let chosen = TagInput.names(in: text)
            if !chosen.isEmpty {
                FlowLayout {
                    ForEach(chosen, id: \.self) { name in
                        Button { text = TagInput.removing(name, from: text) } label: {
                            HStack(spacing: 4) {
                                Text(name)
                                Image(systemName: "xmark").font(.caption2.weight(.bold))
                            }
                            .chip(filled: true)
                        }
                        .accessibilityLabel("Remove tag \(name)")
                    }
                }
            }
            TextField(title, text: $pending, prompt: Text("Find or create a tag"))
                .labelsHidden()
                .accessibilityLabel("Find or create a tag")
                .onSubmit(add)
            let suggestions = TagInput.suggestions(known: known, chosen: text, query: pending)
            let canCreate = TagInput.canCreate(pending, known: known, chosen: text)
            if !suggestions.isEmpty || canCreate {
                FlowLayout {
                    ForEach(suggestions, id: \.self) { name in
                        Button { text = TagInput.adding(name, to: text, known: known); pending = "" } label: {
                            Text(name).chip(filled: false)
                        }
                        .accessibilityLabel("Add tag \(name)")
                    }
                    if canCreate {
                        Button(action: add) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus").font(.caption2.weight(.bold))
                                Text("Create “\(pending.trimmingCharacters(in: .whitespaces))”")
                            }
                            .chip(filled: false)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func add() {
        text = TagInput.adding(pending, to: text, known: known)
        pending = ""
    }
}

private extension View {
    func chip(filled: Bool) -> some View {
        font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .foregroundStyle(filled ? Color.white : Color.pink)
            .background(filled ? Color.pink : Color.pink.opacity(0.14), in: Capsule())
            .contentShape(Capsule())
    }
}

/// Puts its children next to each other and wraps to a new line when the width is used up.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = place(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.maxX).max() ?? 0, height: rows.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, place(subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    private func place(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        return subviews.map { subview in
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            defer { x += size.width + spacing; rowHeight = max(rowHeight, size.height) }
            return CGRect(origin: CGPoint(x: x, y: y), size: size)
        }
    }
}
