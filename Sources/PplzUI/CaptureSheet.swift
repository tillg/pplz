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
            if let imageData { profile = await ProfileReader.read(imageData: imageData) ?? CapturedProfile() }
            if let shared = link.flatMap(LinkedInLink.profileID(in:)) { profile.linkedInID = shared }
            linkedIn = profile.linkedInID.isEmpty ? "" : LinkedInLink.url(forProfileID: profile.linkedInID)
            choice = bestGuess
            phase = .review
        }
    }

    // MARK: Step 1 — what was read, and who it is

    private var review: some View {
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
                if imageData == nil {
                    Text("A profile link was shared. Choose whose it is.").font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let problem = ProfileReader.modelProblem {
                    Text("\(problem) Please fill in the fields yourself.").font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FormField(title: "Name", text: $profile.name)
                    .onChange(of: profile.name) { if !hasChosen { choice = bestGuess } }
                FormField(title: "Title", text: $profile.namePrefix, prompt: "e.g. Dr.")
                FormField(title: "Job title", text: $profile.jobTitle)
                FormField(title: "Company", text: $profile.company)
                FormField(title: "City", text: $profile.city)
                FormField(title: "Country", text: $profile.country)
                FormField(title: "LinkedIn", text: $linkedIn, prompt: "Profile link")
                who
            }
        }
    }

    private var who: some View {
        Section("Who is this?") {
            ForEach(candidates, id: \.key) { entry in
                choiceRow(entry.key, title: entry.name, detail: entry.eventCount > 0 ? "met \(entry.eventCount)×" : "in your contacts",
                          label: "Existing person \(entry.name)")
            }
            choiceRow(Self.newPerson, title: "New person", detail: "", label: "New person")
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
        profile.linkedInID = LinkedInLink.profileID(in: linkedIn) ?? ""
        return profile
    }

    /// The proposals, plus — for a link shared alone — the person whose card is open: most likely the
    /// one whose screenshot was captured a moment ago.
    private var candidates: [PersonEntry] {
        let proposed = model.captureCandidates(for: edited)
        guard imageData == nil, let open = model.card?.entry, !proposed.contains(where: { $0.key == open.key }) else { return proposed }
        return proposed + [open]
    }

    /// The first proposal is preselected only when it is certain enough: the same LinkedIn profile or the same name.
    private var bestGuess: String {
        guard let first = candidates.first else { return Self.newPerson }
        let same = PeopleDirectory.nameWithoutTitles(first.name).compare(
            PeopleDirectory.nameWithoutTitles(profile.name), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        return same || candidates.count == 1 ? first.key : Self.newPerson
    }

    private var canSave: Bool {
        guard phase == .review else { return false }
        if choice == Self.newPerson { return !PeopleDirectory.nameWithoutTitles(profile.name).isEmpty }
        return candidates.contains { $0.key == choice }
    }

    private func save() {
        let profile = edited
        let target: PeopleModel.CaptureTarget = choice == Self.newPerson ? .new : .existing(key: choice)
        Task {
            guard let id = await model.saveCapture(profile, as: target) else { dismiss(); return }
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
                Section("Recent events in pplz") {
                    ForEach(recent) { item in
                        eventRow(title: item.title.isEmpty ? item.format.displayName : item.title, date: item.start,
                                 symbol: item.format.symbol) {
                            if let savedID { await model.addPerson(savedID, toEvent: item.id) }
                        }
                    }
                }
            }
            if !calendar.isEmpty || calendarProblem != nil {
                Section("From your calendar") {
                    ForEach(calendar) { entry in
                        eventRow(title: entry.title, date: entry.start, symbol: "calendar") {
                            if let savedID { await model.logCalendarEntry(entry, with: savedID) }
                        }
                    }
                    if let calendarProblem { Text(calendarProblem).font(.footnote).foregroundStyle(.secondary) }
                }
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
            }
        }
    }

    private func eventRow(title: String, date: Date, symbol: String, action: @escaping () async -> Void) -> some View {
        Button {
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
        .accessibilityLabel("Add to \(title)")
    }

    private func loadCalendar() async {
        guard model.usesContacts else { return }   // the same switch keeps tests and demos away from personal data
        do {
            // entries that are events in pplz already are offered above, not twice
            let known = Set(model.events.map { "\($0.title)|\($0.start.timeIntervalSince1970)" })
            calendar = try await SystemCalendar.recentEntries().filter { !known.contains($0.id) }
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
