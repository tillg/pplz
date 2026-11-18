import PplzCore
import SwiftUI

/// The main window: people on the left, the selected person's card on the right —
/// laid out like the Contacts app, tinted pink (SPEC §4.7).
public struct PeopleView: View {
    @Bindable var model: PeopleModel
    @Environment(\.scenePhase) private var scenePhase

    public init(model: PeopleModel) { self.model = model }

    public var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                ForEach(model.sections) { section in
                    Section(section.title) {
                        ForEach(section.entries, id: \.key) { entry in
                            PersonRow(entry: entry)
                        }
                    }
                }
            }
            .searchable(text: $model.search, placement: .sidebar, prompt: "Search")
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
            .overlay {
                if model.isLoading {
                    ProgressView()
                } else if model.sections.isEmpty {
                    ContentUnavailableView(model.search.isEmpty ? "No people yet" : "No results", systemImage: "person.2")
                }
            }
        } detail: {
            if let card = model.card {
                PersonCardView(card: card)
                    .toolbar {
                        if !card.entry.isPplzOnly {
                            Button("Open in Contacts", systemImage: "person.crop.square") { model.openInContacts() }
                                .help("Show this card in the Contacts app")
                        }
                    }
            } else {
                ContentUnavailableView("No person selected", systemImage: "person.crop.circle")
            }
        }
        .navigationTitle("pplz")
        .tint(.pink)
        .task { await model.reload() }
        #if os(macOS)
        // Reload whenever the app comes to the front, so changes made by the CLI show up.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.reload() }
        }
        #else
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.reload() } }
        }
        #endif
        .alert("pplz", isPresented: .constant(model.errorMessage != nil && model.sections.isEmpty)) {
            Button("Try again") { Task { await model.reload() } }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct PersonRow: View {
    let entry: PersonEntry

    var body: some View {
        HStack(spacing: 6) {
            Text(entry.name).lineLimit(1)
            Spacer(minLength: 4)
            if entry.isPplzOnly {
                Text("pplz").font(.caption2.weight(.semibold)).foregroundStyle(.pink)
            }
            if entry.eventCount > 0 {
                Text("\(entry.eventCount)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.pink.opacity(0.18), in: Capsule())
                    .foregroundStyle(.pink)
                    .help("Events with this person")
            }
        }
    }
}
