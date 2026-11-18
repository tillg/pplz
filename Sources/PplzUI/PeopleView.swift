import PplzCore
import SwiftUI

/// The main window: people on the left, the selected person's card on the right —
/// laid out like the Contacts app, tinted pink (SPEC §4.7).
public struct PeopleView: View {
    @Bindable var model: PeopleModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLogging: Bool
    @State private var isEditing: Bool

    /// `showLogSheet` / `showEditSheet` open a sheet right away (used to check the sheets' layout).
    public init(model: PeopleModel, showLogSheet: Bool = false, showEditSheet: Bool = false) {
        self.model = model
        _isLogging = State(initialValue: showLogSheet)
        _isEditing = State(initialValue: showEditSheet)
    }

    public var body: some View {
        NavigationSplitView {
            Group {
                switch model.mode {
                case .people: peopleList
                case .events: eventsList
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Show", selection: $model.mode) {
                    ForEach(PeopleModel.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 10).padding(.bottom, 8)
            }
            .searchable(text: $model.search, placement: .sidebar, prompt: "Search")
            .navigationSplitViewColumnWidth(min: 230, ideal: 290)
        } detail: {
            switch model.mode {
            case .people: personDetail
            case .events: eventDetail
            }
        }
        .navigationTitle("pplz")
        .sheet(isPresented: Binding(get: { isLogging && model.card != nil }, set: { isLogging = $0 })) {
            LogEventSheet(personName: model.card?.entry.name ?? "") { input in
                Task { await model.logEvent(input) }
            }
        }
        .sheet(isPresented: Binding(get: { isEditing && model.card != nil }, set: { isEditing = $0 })) {
            EditPersonSheet(personName: model.card?.entry.name ?? "", edit: model.personEdit) { edit in
                Task { await model.save(edit) }
            }
        }
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
        .alert("pplz", isPresented: .constant(model.errorMessage != nil)) {
            Button("Try again") { Task { await model.reload() } }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

extension PeopleView {
    private var peopleList: some View {
        List(selection: $model.selection) {
            ForEach(model.sections) { section in
                Section(section.title) {
                    ForEach(section.entries, id: \.key) { entry in
                        PersonRow(entry: entry)
                    }
                }
            }
        }
        .overlay {
            if model.isLoading {
                ProgressView()
            } else if model.sections.isEmpty {
                ContentUnavailableView(model.search.isEmpty ? "No people yet" : "No results", systemImage: "person.2")
            }
        }
    }

    private var eventsList: some View {
        List(selection: $model.selectedEventID) {
            ForEach(model.eventSections) { section in
                Section(section.title) {
                    ForEach(section.events) { event in
                        EventListRow(event: event).tag(event.id)
                    }
                }
            }
        }
        .overlay {
            if model.eventSections.isEmpty {
                ContentUnavailableView(model.search.isEmpty ? "No events yet" : "No results", systemImage: "calendar",
                                       description: Text(model.search.isEmpty ? "Log one from a person's card." : ""))
            }
        }
    }

    @ViewBuilder private var personDetail: some View {
        if let card = model.card {
            PersonCardView(card: card)
                .toolbar {
                    Button("Log Event", systemImage: "plus") { isLogging = true }
                        .help("Log a meeting or call with \(card.entry.name)")
                    Button("Edit", systemImage: "pencil") { isEditing = true }
                        .help("Edit tags, notes, how you met and the keep-in-touch rhythm")
                    if !card.entry.isPplzOnly {
                        Button("Open in Contacts", systemImage: "person.crop.square") { model.openInContacts() }
                            .help("Show this card in the Contacts app")
                    }
                }
        } else {
            ContentUnavailableView("No person selected", systemImage: "person.crop.circle")
        }
    }

    @ViewBuilder private var eventDetail: some View {
        if let event = model.selectedEvent {
            EventDetailView(event: event,
                            onShowPerson: { id in Task { await model.showPerson(id) } },
                            onComplete: { id in Task { await model.completeFollowUp(id) } })
        } else {
            ContentUnavailableView("No event selected", systemImage: "calendar")
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
