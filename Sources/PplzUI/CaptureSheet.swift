import PplzCore
import SwiftUI

/// A captured profile on its way into pplz: the screenshot is read on the device, the fields are shown
/// for correction, the user says who it is (someone known or a new person) and — after saving —
/// which event the person belongs to.
struct CaptureSheet: View {
    let model: PeopleModel
    /// The screenshot, if one was shared.
    let imageData: Data?
    /// A profile link shared alone or along with the screenshot.
    var link: String? = nil
    /// "New event" was chosen: the caller opens the quick log for the person just saved.
    let onNewEvent: () -> Void

    private enum Phase { case reading, review, event }
    private static let newPerson = "\u{0}new"

    @State private var phase = Phase.reading
    @State private var profile = CapturedProfile()
    @State private var linkedIn = ""
    @State private var choice = CaptureSheet.newPerson
    /// Once the user has chosen who it is, pplz stops preselecting.
    @State private var hasChosen = false
    /// The screenshot itself, shown for comparing with what was read.
    @State private var screenshot: Image?
    /// Looking for someone pplz did not propose.
    @State private var search = ""
    @State private var searched: PersonEntry?
    @State private var readingProblem: String?
    /// A save or an event choice is under way: further taps are ignored.
    @State private var isBusy = false
    @State private var savedName = ""
    @State private var savedID: UUID?
    @State private var calendar: [CalendarEntry] = []
    @State private var calendarProblem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch phase {
            case .reading, .review: review
            case .event: event
            }
        }
        .task {
            guard phase == .reading else { return }
            screenshot = imageData.flatMap(Image.init(data:))
            if model.entries.isEmpty { await model.reload() }     // opened by a share before the list was loaded
            if let imageData, let reading = await ProfileReader.read(imageData: imageData) {
                profile = reading.profile
                readingProblem = reading.problem
            }
            // the address read from the screenshot is about this person for sure; a shared link only fills the gap
            if profile.linkedInID.isEmpty, let shared = link.flatMap(LinkedInLink.profileID(in:)) { profile.linkedInID = shared }
            linkedIn = profile.linkedInID.isEmpty ? "" : LinkedInLink.url(forProfileID: profile.linkedInID)
            choice = bestGuess
            phase = .review
        }
    }

    // MARK: Step 1 — what was read, and who it is

    private var review: some View {
        ScrollViewReader { proxy in
            #if os(macOS)
            // the screenshot beside the fields, to check them against it
            HStack(alignment: .top, spacing: 0) {
                if let screenshot {
                    screenshot.resizable().scaledToFit().frame(width: 400).frame(maxHeight: 640, alignment: .top)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding([.leading, .vertical], 20)
                        .accessibilityLabel("Screenshot")
                }
                reviewForm(proxy)
            }
            #else
            reviewForm(proxy)
            #endif
        }
    }

    private func reviewForm(_ proxy: ScrollViewProxy) -> some View {
        SheetScaffold(title: "Captured profile", confirmTitle: "Save", canConfirm: canSave, dismissesOnConfirm: false, onConfirm: save) {
            if phase == .reading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading the screenshot…").foregroundStyle(.secondary)
                }
            } else {
                if let picture = profile.picture.flatMap(Image.init(data:)) {
                    picture.resizable().scaledToFill().frame(width: 96, height: 96).clipShape(Circle())
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Profile picture")
                }
                #if !os(macOS)
                if let screenshot {
                    DisclosureGroup("Screenshot") { screenshot.resizable().scaledToFit().accessibilityLabel("Screenshot") }
                }
                #endif
                if imageData == nil {
                    Text("A profile link was shared. Choose whose it is, or search for the person below.").font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let problem = readingProblem {
                    Text("\(problem) Please fill in the fields yourself.").font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
                FormField(title: "First name", text: $profile.givenName)
                FormField(title: "Last name", text: $profile.familyName)
                    .onChange(of: profile.name) { if !hasChosen { choice = bestGuess } }
                FormField(title: "Title", text: $profile.namePrefix, prompt: "e.g. Dr.")
                FormField(title: "Job title", text: $profile.jobTitle)
                FormField(title: "Company", text: $profile.company)
                FormField(title: "City", text: $profile.city)
                FormField(title: "Country", text: $profile.country)
                FormField(title: "LinkedIn", text: $linkedIn, prompt: "Profile link or ID")
                who(proxy)
            }
        }
    }

    private func who(_ proxy: ScrollViewProxy) -> some View {
        Section("Who is this?") {
            ForEach(candidates, id: \.key) { entry in
                choiceRow(entry.key, title: entry.name, detail: entry.eventCount > 0 ? "met \(entry.eventCount)×" : "in your contacts",
                          label: "Existing person \(entry.name)")
            }
            choiceRow(Self.newPerson, title: "New person", detail: "", label: "New person")
            ForEach(searchResults, id: \.key) { entry in
                Button { searched = entry; choice = entry.key; hasChosen = true; search = "" } label: {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        Text(entry.name)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Found person \(entry.name)")
            }
            // below its results, so that the keyboard does not cover them
            TextField("Search people", text: $search)
                .autocorrectionDisabled()
                .accessibilityLabel("Search people")
                .id("search")
                // the results push the field down, behind the keyboard: bring it back
                .onChange(of: searchResults.count) { Task { @MainActor in withAnimation { proxy.scrollTo("search", anchor: .bottom) } } }
        }
    }

    private func choiceRow(_ key: String, title: String, detail: String, label: String) -> some View {
        Button { choice = key; hasChosen = true } label: {
            HStack {
                Image(systemName: choice == key ? "largecircle.fill.circle" : "circle").foregroundStyle(.pink)
                Text(title)
                if !detail.isEmpty { Text(detail).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(choice == key ? .isSelected : [])
    }

    private var edited: CapturedProfile {
        var profile = profile
        profile.linkedInID = LinkedInLink.profileID(typed: linkedIn) ?? ""
        return profile
    }

    /// The proposals, plus — for a link shared alone — the person whose card is open: most likely the
    /// one whose screenshot was captured a moment ago.
    private var candidates: [PersonEntry] {
        var proposed = model.captureCandidates(for: edited)
        if imageData == nil, let open = model.card?.entry, !proposed.contains(where: { $0.key == open.key }) { proposed.append(open) }
        if let searched, !proposed.contains(where: { $0.key == searched.key }) { proposed.append(searched) }
        return proposed
    }

    /// People matching what is typed into "Search people", without those already listed.
    private var searchResults: [PersonEntry] {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return PeopleDirectory.suggestions(for: search, in: model.entries, excluding: Set(candidates.map(\.key)))
    }

    /// Preselected is only what is certain (the same LinkedIn profile, or the one person of exactly
    /// that name); otherwise "New person" — which cannot be saved without a name, so a link shared
    /// alone always needs a deliberate choice.
    private var bestGuess: String { model.capturePreselection(for: edited) ?? Self.newPerson }

    private var canSave: Bool {
        guard phase == .review, !isBusy else { return false }
        if choice == Self.newPerson { return !PeopleDirectory.nameWithoutTitles(profile.name).isEmpty }
        return candidates.contains { $0.key == choice }
    }

    private func save() {
        let profile = edited
        let target: PeopleModel.CaptureTarget = choice == Self.newPerson ? .new : .existing(key: choice)
        isBusy = true
        Task {
            defer { isBusy = false }
            guard let id = await model.saveCapture(profile, as: target) else { return }   // the sheet stays; the error is shown
            savedID = id
            savedName = model.card?.entry.name ?? profile.name
            phase = .event
            await loadCalendar()
        }
    }

    // MARK: Step 2 — which event

    private var event: some View {
        SheetScaffold(title: "Which event?", confirmTitle: "No event", onConfirm: {}) {
            Text("\(savedName) is saved. Where did you meet?").foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            let recent = model.recentEvents()
            if !recent.isEmpty {
                Section {
                    ForEach(recent) { item in
                        eventRow(title: item.title.isEmpty ? item.format.displayName : item.title, date: item.start,
                                 symbol: item.format.symbol) {
                            if let savedID { await model.addPerson(savedID, toEvent: item.id) }
                        }
                    }
                } header: { eventHeader("Recent events in pplz") }
            }
            if !calendar.isEmpty || calendarProblem != nil {
                Section {
                    ForEach(calendar) { entry in
                        eventRow(title: entry.title, date: entry.start, symbol: "calendar") {
                            if let savedID { await model.logCalendarEntry(entry, with: savedID) }
                        }
                    }
                    if let calendarProblem { Text(calendarProblem).font(.footnote).foregroundStyle(.secondary) }
                } header: { eventHeader("From your calendar") }
            }
            Section {
                Button {
                    dismiss()
                    onNewEvent()
                } label: {
                    Label("New event", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.pink)
                .padding(.vertical, Self.rowPadding)
                .padding(.top, Self.rowPadding * 2)
            }
        }
    }

    /// The Mac's form sets rows tightly; iPhone and iPad space their list rows themselves.
    #if os(macOS)
    private static let rowPadding: CGFloat = 4
    #else
    private static let rowPadding: CGFloat = 0
    #endif

    private func eventHeader(_ title: String) -> some View {
        #if os(macOS)
        Text(title).font(.headline).padding(.top, 12).padding(.bottom, 2)
        #else
        Text(title)
        #endif
    }

    private func eventRow(title: String, date: Date, symbol: String, action: @escaping () async -> Void) -> some View {
        Button {
            guard !isBusy else { return }
            isBusy = true
            Task {
                await action()
                dismiss()
            }
        } label: {
            HStack {
                Image(systemName: symbol).foregroundStyle(.pink).frame(width: 22)
                Text(title)
                Spacer(minLength: 8)
                Text(date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, Self.rowPadding)
        .accessibilityLabel("Add to \(title)")
    }

    private func loadCalendar() async {
        guard model.usesContacts else { return }   // the same switch keeps tests and demos away from personal data
        do {
            // entries that are events in pplz already are offered above, not twice
            let known = Set(model.events.map { "\($0.title)|\($0.start.timeIntervalSince1970)" })
            calendar = try await SystemCalendar.recentEntries().filter { !known.contains($0.key) }
        } catch {
            calendarProblem = (error as? LocalizedError)?.errorDescription ?? "The calendar could not be read."
        }
    }
}

extension Image {
    /// An image from encoded data (PNG, JPEG, …); `nil` if the data is no image.
    init?(data: Data) {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        self.init(nsImage: image)
        #else
        guard let image = UIImage(data: data) else { return nil }
        self.init(uiImage: image)
        #endif
    }
}
