import PplzCore
import SwiftUI

/// The main window: people on the left, the selected person's card on the right —
/// laid out like the Contacts app, tinted pink (SPEC §4.7).
public struct PeopleView: View {
    @Bindable var model: PeopleModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: Sheet?
    @State private var isConfirmingDelete = false
    /// The event edit sheet was opened through "Add people".
    @State private var addsPeople = false
    #if os(iOS)
    /// The contact whose system card is shown.
    @State private var shownContact: ShownContact?
    private struct ShownContact: Identifiable { let id: String }
    #endif
    private var opensEvents = false

    public enum Sheet: String, Identifiable, Sendable {
        case log, quickLog, edit, editEvent, connect
        public var id: String { rawValue }
    }

    /// `initialSheet` opens a sheet right away (used to check the sheets' layout).
    public init(model: PeopleModel, initialSheet: Sheet? = nil) {
        self.model = model
        _sheet = State(initialValue: initialSheet)
    }

    /// Reads the launch options `-show log|quickLog|edit|editEvent|connect` and `-mode events`.
    public init(model: PeopleModel, defaults: UserDefaults) {
        self.init(model: model, initialSheet: defaults.string(forKey: "show").flatMap(Sheet.init))
        opensEvents = defaults.string(forKey: "mode") == "events"
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
            .toolbar {
                ToolbarItem {
                    Button("New Event", systemImage: "calendar.badge.plus") { sheet = .quickLog }
                        .help("Log a meeting or call you just had")
                }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 290)
        } detail: {
            switch model.mode {
            case .people: personDetail
            case .events: eventDetail
            }
        }
        .navigationTitle("pplz")
        .sheet(item: Binding(get: { sheetIfPossible }, set: { sheet = $0 })) { sheet in
            switch sheet {
            case .log:
                LogEventSheet(people: model.entries, preselected: model.card.map { [$0.entry] } ?? [],
                              format: model.suggestedFormat, knownTags: model.knownTags) { input, keys in
                    Task { await model.logEvent(input, with: keys) }
                }
            case .quickLog:
                LogEventSheet(people: model.entries, preselected: [], format: model.suggestedFormat, knownTags: model.knownTags) { input, keys in
                    Task { await model.logEvent(input, with: keys) }
                }
            case .edit:
                EditPersonSheet(personName: model.card?.entry.name ?? "", knownTags: model.knownTags, edit: model.personEdit) { edit in
                    Task { await model.save(edit) }
                }
            case .editEvent:
                if let edit = model.eventEdit {
                    EditEventSheet(people: model.entries, participants: model.selectedEventPeople, addsPeople: addsPeople, knownTags: model.knownTags, edit: edit) { edit, keys in
                        Task { await model.save(edit, participants: keys) }
                    }
                }
            case .connect:
                ConnectSheet(personName: model.card?.title ?? "", candidates: model.connectionCandidates) { role, other in
                    Task { await model.connect(role: role, to: other) }
                }
            }
        }
        .confirmationDialog("Delete this event?", isPresented: $isConfirmingDelete) {
            Button("Delete Event", role: .destructive) { Task { await model.deleteSelectedEvent() } }
        } message: {
            Text("Its follow-ups are deleted too. This cannot be undone.")
        }
        .tint(.pink)
        .task {
            await model.reload()
            if opensEvents {
                model.mode = .events
                model.selectedEventID = model.events.first?.id
            }
        }
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
        // Changes from another device show up as soon as iCloud has delivered them.
        .onReceive(NotificationCenter.default.publisher(for: PplzStore.syncNotification).receive(on: DispatchQueue.main)) { note in
            if PplzStore.broughtNewData(note) { Task { await model.reload() } }
        }
        .alert("pplz", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.dismissError() } })) {
            Button("OK") { model.dismissError() }
            if model.sections.isEmpty {
                Button("Try again") { Task { await model.reload() } }
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

extension PeopleView {
    /// A sheet only opens once the thing it edits is loaded.
    private var sheetIfPossible: Sheet? {
        switch sheet {
        case .log, .edit, .connect: model.card == nil ? nil : sheet
        case .editEvent: model.selectedEvent == nil ? nil : sheet
        case .quickLog: model.entries.isEmpty ? nil : sheet
        case nil: nil
        }
    }

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
            PersonCardView(card: card,
                           onConnect: { sheet = .connect },
                           onDisconnect: { id in Task { await model.disconnect(from: id) } },
                           onShowPerson: { id in Task { await model.showPerson(id) } })
                .toolbar {
                    Button("Log Event", systemImage: "calendar.badge.plus") { sheet = .log }
                        .help("Log a meeting or call with \(card.entry.name)")
                    Button("Edit", systemImage: "pencil") { sheet = .edit }
                        .help("Edit tags, notes, how you met and the keep-in-touch rhythm")
                    #if os(macOS)
                    if !card.entry.isPplzOnly {
                        Button("Open in Contacts", systemImage: "person.crop.square") { model.openInContacts() }
                            .help("Show this card in the Contacts app")
                    }
                    #else
                    if let identifier = card.entry.contactIdentifier, card.contact != nil {
                        Button("Contact card", systemImage: "person.crop.square") { shownContact = ShownContact(id: identifier) }
                    }
                    #endif
                }
                #if os(iOS)
                // changes made on the contact card show up when it closes
                .sheet(item: $shownContact, onDismiss: { Task { await model.reload() } }) { ContactCardSheet(identifier: $0.id) }
                #endif
        } else {
            ContentUnavailableView("No person selected", systemImage: "person.crop.circle")
        }
    }

    @ViewBuilder private var eventDetail: some View {
        if let event = model.selectedEvent {
            EventDetailView(event: event,
                            onShowPerson: { id in Task { await model.showPerson(id) } },
                            onAddPeople: { addsPeople = true; sheet = .editEvent },
                            onComplete: { id in Task { await model.completeFollowUp(id) } },
                            onAddFollowUp: { text in Task { await model.addFollowUp(text) } })
                .toolbar {
                    Button("Edit", systemImage: "pencil") { addsPeople = false; sheet = .editEvent }
                        .help("Edit this event")
                    Button("Delete", systemImage: "trash") { isConfirmingDelete = true }
                        .help("Delete this event")
                }
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
