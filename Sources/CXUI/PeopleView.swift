import PhotosUI
import CXCore
import SwiftUI
import UniformTypeIdentifiers

/// The main window: people on the left, the selected person's card on the right —
/// laid out like the Contacts app, tinted pink (SPEC §4.7).
public struct PeopleView: View {
    @Bindable var model: PeopleModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: Sheet?
    @State private var isConfirmingDelete = false
    @State private var isConfirmingPersonDelete = false
    /// The event edit sheet was opened through "Add people".
    @State private var addsPeople = false
    /// A screenshot that is being captured (SPEC §4.4).
    @State private var capture: CapturedImage?
    /// Further things shared to cardXchange, captured one after the other.
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

    /// The person whose card is being edited in place.
    @State private var editedEntry: PersonEntry?

    public enum Sheet: String, Identifiable, Sendable {
        case log, quickLog, edit, editEvent, connect, editContact, newContact, recentlyDeleted, settings
        public var id: String { rawValue }
    }

    /// `initialSheet` opens a sheet right away (used to check the sheets' layout).
    public init(model: PeopleModel, initialSheet: Sheet? = nil) {
        self.model = model
        _sheet = State(initialValue: initialSheet)
    }

    /// Reads the launch options `-show log|quickLog|edit|editEvent|connect|editContact|newContact|recentlyDeleted|settings`, `-mode events|map` and `-capture <image file>`.
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
                #if os(iOS)
                // the Mac has its Settings window instead (cardXchange → Settings…)
                ToolbarItem {
                    Button("Settings", systemImage: "gearshape") { sheet = .settings }
                }
                #endif
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 290)
            .disabled(isEditing)     // an edit ends with Cancel or Done, not by wandering off
        } detail: {
            switch model.mode {
            case .people: personDetail
            case .events: eventDetail
            case .map: mapPane
            }
        }
        .navigationTitle("cardXchange")
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
            case .edit, .editContact:
                EmptyView()      // edited in place of the card, see `personDetail`
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
            case .newContact:
                NavigationStack { PersonEditor(model: model, entry: nil) { self.sheet = nil } }
                    #if os(macOS)
                    .frame(width: 520, height: 600)
                    #endif
            case .recentlyDeleted:
                RecentlyDeletedSheet(model: model)
            case .settings:
                SettingsView(model: model)
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
        .confirmationDialog("Delete \(model.card?.entry.name ?? "")?", isPresented: $isConfirmingPersonDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await model.deleteSelectedPerson() } }
        } message: {
            if model.card?.entry.isCXOnly == false {
                Text("The contact is deleted from Contacts now. cardXchange keeps a copy without the note, and the person's events, notes, tags and photos, for 30 days under Recently Deleted.")
            } else {
                Text("cardXchange keeps the person's events, notes, tags and photos for 30 days under Recently Deleted.")
            }
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
        .onReceive(NotificationCenter.default.publisher(for: CXStore.syncNotification).receive(on: DispatchQueue.main)) { note in
            if CXStore.broughtNewData(note) { Task { await model.reload() } }
        }
        .alert("cardXchange", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.dismissError() } })) {
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
    /// Queues what was shared to cardXchange from another app and starts the first capture. An open sheet is
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
        case .log, .connect: model.card == nil ? nil : sheet
        case .edit, .editContact: nil      // not a sheet: shown in place of the card
        case .newContact: model.usesContacts ? sheet : nil
        case .recentlyDeleted: sheet
        case .editEvent: model.selectedEvent == nil ? nil : sheet
        case .quickLog: model.entries.isEmpty ? nil : sheet
        #if os(iOS)
        case .settings: sheet
        #else
        case .settings: nil      // the Settings window
        #endif
        case nil: nil
        }
    }

    private var peopleList: some View {
        List(selection: $model.selection) {
            // on top, as the lists in Contacts: at the end of a long address book nobody would find it
            if !model.recentlyDeleted.isEmpty && model.search.isEmpty {
                Section {
                    Button { sheet = .recentlyDeleted } label: {
                        LabeledContent {
                            Text("\(model.recentlyDeleted.count)")
                        } label: {
                            Label("Recently Deleted", systemImage: "trash")
                        }
                    }
                }
            }
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
            } else if model.sections.isEmpty && (!model.search.isEmpty || model.recentlyDeleted.isEmpty) {
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
            .overlay(alignment: .bottom) {
                VStack(spacing: MapCapsule.spacing) {
                    // small, so that the map stays visible behind it (issue #9)
                    if let notice = model.mapNotice {
                        MapCapsule(text: mapNoticeText(notice), font: .callout, style: .primary)
                    }
                    if let status = model.locateStatus {
                        MapCapsule(text: Text(status), font: .caption, style: .secondary)
                    }
                }
                .padding(MapCapsule.margin)
            }
    }

    private func mapNoticeText(_ notice: MapNotice) -> Text {
        switch notice {
        case .nobodyLocated: Text("No one on the map yet. People with an address appear once it is located.")
        case .noResults: Text("No results")
        case .notLocated(matches: 1): Text("The match has no located address.")
        case .notLocated(let matches): Text("The \(matches) matches have no located address.")
        }
    }

    /// A line of text over the map, in a capsule.
    private struct MapCapsule: View {
        static let spacing: CGFloat = 4
        static let margin: CGFloat = 8
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 4

        var text: Text
        var font: Font
        var style: HierarchicalShapeStyle

        var body: some View {
            text
                .font(font).foregroundStyle(style)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Self.horizontalPadding).padding(.vertical, Self.verticalPadding)
                .background(.regularMaterial, in: Capsule())
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

    /// The pencil was pressed (or the app was started with `-show edit`): the editor takes the card's place.
    private var isEditing: Bool { sheet == .edit || sheet == .editContact }

    @ViewBuilder private var personDetail: some View {
        if isEditing {
            // the person is kept from the moment the editor opens: a reload of the card must not restart the editor
            if let entry = editedEntry {
                PersonEditor(model: model, entry: entry) {
                    sheet = nil
                    editedEntry = nil
                }
            } else {
                ProgressView().task(id: model.card?.entry) { editedEntry = model.card?.entry }
            }
        } else if let card = model.card {
            PersonCardView(card: card,
                           onConnect: { sheet = .connect },
                           onLogEvent: { sheet = .log },
                           onDisconnect: { id in Task { await model.disconnect(from: id) } },
                           onShowPerson: { id in Task { await model.showPerson(id) } },
                           onAddToContacts: card.entry.isCXOnly && model.usesContacts ? { addToContacts() } : nil,
                           onAddPhotos: { images in Task { await model.addPhotos(images) } },
                           onPastePhoto: pastePhoto,
                           onUsePhoto: model.canUseAsContactPicture ? { id in Task { await model.useAsContactPicture(id) } } : nil,
                           onDeletePhoto: { id in Task { await model.deletePhoto(id) } })
                .toolbar {
                    Button("Log Event", systemImage: "calendar.badge.plus") { sheet = .log }
                        .help("Log a meeting or call with \(card.entry.name)")
                    Button("Edit", systemImage: "pencil") { sheet = .edit }
                        .help(card.contact != nil ? "Edit the contact card and what cardXchange keeps about \(card.entry.name)"
                                                  : "Edit tags, notes, how you met and the keep-in-touch rhythm")
                    Button("Delete Person", systemImage: "trash") { isConfirmingPersonDelete = true }
                        .help("Delete \(card.entry.name); Recently Deleted keeps the person for 30 days")
                    #if os(macOS)
                    if !card.entry.isCXOnly {
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
                            isDeleted: model.isDeleted,
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
            if entry.isCXOnly {
                Text("cardXchange").font(.caption2.weight(.semibold)).foregroundStyle(.pink)
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
