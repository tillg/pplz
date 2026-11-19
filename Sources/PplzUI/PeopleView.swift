import PhotosUI
import PplzCore
import SwiftUI
import UniformTypeIdentifiers

/// The main window: people on the left, the selected person's card on the right —
/// laid out like the Contacts app, tinted pink (SPEC §4.7).
public struct PeopleView: View {
    @Bindable var model: PeopleModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: Sheet?
    @State private var isConfirmingDelete = false
    /// The event edit sheet was opened through "Add people".
    @State private var addsPeople = false
    /// A screenshot that is being captured (SPEC §4.4).
    @State private var capture: CapturedImage?
    /// Further things shared to pplz, captured one after the other.
    @State private var waitingCaptures: [CapturedImage] = []
    @State private var isChoosingCapture = false
    @State private var logsAfterCapture = false
    #if os(iOS)
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isScanningCard = false
    /// The card that was just photographed; captured once the camera has closed.
    @State private var scannedCard: Data?
    #endif
    private struct CapturedImage: Identifiable {
        let id = UUID()
        var data: Data?
        var link: String?
    }
    #if os(iOS)
    /// The contact whose system card is shown.
    @State private var shownContact: ShownContact?
    private struct ShownContact: Identifiable { let id: String }
    #endif
    private var opensEvents = false
    private var opensMap = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    public enum Sheet: String, Identifiable, Sendable {
        case log, quickLog, edit, editEvent, connect, editContact, newContact
        public var id: String { rawValue }
    }

    /// `initialSheet` opens a sheet right away (used to check the sheets' layout).
    public init(model: PeopleModel, initialSheet: Sheet? = nil) {
        self.model = model
        _sheet = State(initialValue: initialSheet)
    }

    /// Reads the launch options `-show log|quickLog|edit|editEvent|connect|editContact|newContact`, `-mode events|map` and `-capture <image file>`.
    public init(model: PeopleModel, defaults: UserDefaults) {
        self.init(model: model, initialSheet: defaults.string(forKey: "show").flatMap(Sheet.init))
        opensEvents = defaults.string(forKey: "mode") == "events"
        opensMap = defaults.string(forKey: "mode") == "map"
        // `-capture <image file>` opens the capture sheet for that file (used to check the flow)
        if let path = defaults.string(forKey: "capture"), let data = FileManager.default.contents(atPath: path) {
            _capture = State(initialValue: CapturedImage(data: data))
        }
    }

    public var body: some View {
        NavigationSplitView {
            Group {
                switch model.mode {
                case .people: peopleList
                case .events: eventsList
                case .map: mapSidebar
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
                if model.usesContacts {
                    ToolbarItem {
                        Button("New Contact", systemImage: "person.badge.plus") { sheet = .newContact }
                            .help("Create a contact in Contacts")
                    }
                }
                ToolbarItem {
                    #if os(iOS)
                    Menu("Capture Profile", systemImage: "person.crop.rectangle.badge.plus") {
                        if CardCamera.isAvailable {
                            Button("Scan Business Card", systemImage: "camera") { isScanningCard = true }
                        }
                        Button("Choose Photo", systemImage: "photo") { isChoosingCapture = true }
                    }
                    #else
                    Button("Capture Profile", systemImage: "person.crop.rectangle.badge.plus") { isChoosingCapture = true }
                        .help("Read a screenshot of someone's profile or a photo of a business card")
                    #endif
                }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 290)
        } detail: {
            switch model.mode {
            case .people: personDetail
            case .events: eventDetail
            case .map: mapPane
            }
        }
        .navigationTitle("pplz")
        #if os(macOS)
        .fileImporter(isPresented: $isChoosingCapture, allowedContentTypes: [.image]) { result in
            guard let url = try? result.get() else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { capture = CapturedImage(data: data) }
        }
        #else
        .photosPicker(isPresented: $isChoosingCapture, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { capture = CapturedImage(data: data) }
            }
        }
        // the capture sheet opens only after the camera has closed: two covers at once lose one
        .fullScreenCover(isPresented: $isScanningCard, onDismiss: {
            if let card = scannedCard {
                scannedCard = nil
                model.offerCapture(card)
            }
        }) {
            CardCamera { scannedCard = $0 }.ignoresSafeArea()
        }
        #endif
        // a screenshot dragged onto the window, or pasted, is captured like one that was shared
        .onDrop(of: [.image], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in model.offerCapture(data) }
                }
            }
            return !providers.isEmpty
        }
        #if os(macOS)
        .onPasteCommand(of: [.image, .fileURL]) { _ in model.offerCaptureFromClipboard() }
        #endif
        .sheet(item: $capture, onDismiss: {
            if logsAfterCapture {
                logsAfterCapture = false
                sheet = .log
            } else {
                checkInbox()      // the next one that was shared, if any
            }
        }) { image in
            CaptureSheet(model: model, imageData: image.data, link: image.link, onNewEvent: { logsAfterCapture = true })
        }
        .sheet(item: Binding(get: { sheetIfPossible }, set: { sheet = $0 })) { sheet in
            switch sheet {
            case .log:
                LogEventSheet(people: model.entries, preselected: model.card.map { [$0.entry] } ?? [],
                              format: model.suggestedFormat, knownTags: model.knownTags) { input, keys, new in
                    Task { await model.logEvent(input, with: keys, newPeople: new) }
                }
            case .quickLog:
                LogEventSheet(people: model.entries, preselected: [], format: model.suggestedFormat, knownTags: model.knownTags) { input, keys, new in
                    Task { await model.logEvent(input, with: keys, newPeople: new) }
                }
            case .edit:
                EditPersonSheet(personName: model.card?.entry.name ?? "", knownTags: model.knownTags, edit: model.personEdit) { edit in
                    Task { await model.save(edit) }
                }
            case .editEvent:
                if let edit = model.eventEdit {
                    EditEventSheet(people: model.entries, participants: model.selectedEventPeople, addsPeople: addsPeople, knownTags: model.knownTags, edit: edit) { edit, keys, new in
                        Task { await model.save(edit, participants: keys, newPeople: new) }
                    }
                }
            case .connect:
                ConnectSheet(personName: model.card?.title ?? "", candidates: model.connectionCandidates) { role, other in
                    Task { await model.connect(role: role, to: other) }
                }
            case .editContact:
                ContactEditSheet(model: model, isEditing: true)
            case .newContact:
                ContactEditSheet(model: model, isEditing: false)
            }
        }
        .sheet(item: Binding(get: { model.faceChoice }, set: { if $0 == nil { Task { await model.chooseFace(nil) } } })) { choice in
            FaceChoiceSheet(personName: choice.entry.name, crops: choice.crops) { index in Task { await model.chooseFace(index) } }
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
            if opensMap { model.mode = .map }
        }
        #if os(macOS)
        // Reload whenever the app comes to the front, so changes made by the CLI show up.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.reload() }
        }
        #else
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.reload() }
                checkInbox()
            }
        }
        #endif
        .onChange(of: model.captureRequests) { checkInbox() }
        .onChange(of: sheet) { _, open in if open == nil { checkInbox() } }
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
    /// Queues what was shared to pplz from another app and starts the first capture. An open sheet is
    /// left alone — its input is the user's; the inbox waits until it has closed.
    private func checkInbox() {
        guard sheet == nil, capture == nil else { return }
        waitingCaptures += model.takeOfferedCaptures().map { CapturedImage(data: $0) }
        if let items = try? CaptureInbox.shared?.takeAll() {
            waitingCaptures += CaptureInbox.requests(from: items).map { CapturedImage(data: $0.image, link: $0.link) }
        }
        if !waitingCaptures.isEmpty { capture = waitingCaptures.removeFirst() }
    }

    /// Creates the contact and shows it right away, ready to be filled in.
    private func addToContacts() {
        Task {
            guard let identifier = await model.addSelectedPersonToContacts() else { return }
            #if os(macOS)
            _ = identifier
            model.openInContacts()
            #else
            shownContact = ShownContact(id: identifier)
            #endif
        }
    }

    /// A sheet only opens once the thing it edits is loaded.
    private var sheetIfPossible: Sheet? {
        switch sheet {
        case .log, .edit, .connect: model.card == nil ? nil : sheet
        case .editContact: model.card?.contact == nil ? nil : sheet
        case .newContact: model.usesContacts ? sheet : nil
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

    /// The people list; on an iPhone, where the detail column is never shown without a selection, the map itself.
    @ViewBuilder private var mapSidebar: some View {
        #if os(iOS)
        if sizeClass == .compact { mapPane } else { peopleList }
        #else
        peopleList
        #endif
    }

    private var mapPane: some View {
        PersonMap(pins: model.mapPins, focus: model.selection, fitID: model.search, onOpen: { model.openPerson(key: $0) })
            .overlay {
                if model.mapPins.isEmpty {
                    ContentUnavailableView(model.search.isEmpty ? "No one on the map yet" : "No results", systemImage: "map",
                                           description: Text(model.search.isEmpty ? "People with an address appear here once it is located." : ""))
                        .background(.background)
                }
            }
            .overlay(alignment: .bottom) {
                if let status = model.locateStatus {
                    Text(status)
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8)
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
                           onShowPerson: { id in Task { await model.showPerson(id) } },
                           onAddToContacts: card.entry.isPplzOnly && model.usesContacts ? { addToContacts() } : nil,
                           onAddPhotos: { images in Task { await model.addPhotos(images) } },
                           onPastePhoto: pastePhoto,
                           onUsePhoto: model.canUseAsContactPicture ? { id in Task { await model.useAsContactPicture(id) } } : nil,
                           onDeletePhoto: { id in Task { await model.deletePhoto(id) } })
                .toolbar {
                    Button("Log Event", systemImage: "calendar.badge.plus") { sheet = .log }
                        .help("Log a meeting or call with \(card.entry.name)")
                    if card.contact != nil {
                        Menu("Edit", systemImage: "pencil") {
                            Button("Edit Contact…") { sheet = .editContact }
                            Button("Edit pplz Details…") { sheet = .edit }
                        }
                        .help("Edit the contact's fields, or what pplz keeps about \(card.entry.name)")
                    } else {
                        Button("Edit", systemImage: "pencil") { sheet = .edit }
                            .help("Edit tags, notes, how you met and the keep-in-touch rhythm")
                    }
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

    private var pastePhoto: (() -> Void)? {
        #if os(macOS)
        { Task { await model.addPhotoFromClipboard() } }
        #else
        nil
        #endif
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
