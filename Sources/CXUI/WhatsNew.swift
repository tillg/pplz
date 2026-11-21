import Foundation
import SwiftUI

/// One user-visible feature in the list "What’s New" (issue #15). The rows are in `Resources/whats-new.json`.
/// The feature text stays English; the area name is translated.
struct WhatsNewEntry: Decodable, Identifiable, Hashable, Sendable {
    let date: Date
    let version: Version
    let area: Area
    let feature: String

    var id: String { version.text + " " + feature }

    /// The area name in the app's language; the area column sorts by it.
    var areaTitle: String { localized(area.title, locale: .app) }

    /// "0.2.97": the marketing version and the commit count, compared number by number.
    struct Version: Comparable, Hashable, Sendable {
        let text: String
        let numbers: [Int]

        init?(_ text: String) {
            let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else { return nil }
            self.text = text
            self.numbers = parts.compactMap { Int($0) }
            guard numbers.count == parts.count else { return nil }
        }

        static func < (lhs: Version, rhs: Version) -> Bool {
            lhs.numbers.lexicographicallyPrecedes(rhs.numbers)
        }

        static func == (lhs: Version, rhs: Version) -> Bool { lhs.numbers == rhs.numbers }

        func hash(into hasher: inout Hasher) { hasher.combine(numbers) }
    }

    enum Area: String, CaseIterable, Sendable {
        case people = "People", events = "Events", map = "Map", contacts = "Contacts", photos = "Photos"
        case capture = "Capture", settings = "Settings", languages = "Languages", commandLine = "Command line", app = "App"

        var title: LocalizedStringResource {
            switch self {
            case .people: LocalizedStringResource("People", bundle: .cxui)
            case .events: LocalizedStringResource("Events", bundle: .cxui)
            case .map: LocalizedStringResource("Map", bundle: .cxui)
            case .contacts: LocalizedStringResource("Contacts", bundle: .cxui)
            case .photos: LocalizedStringResource("Photos", bundle: .cxui)
            case .capture: LocalizedStringResource("Capture", bundle: .cxui, comment: "What’s New: the area of reading a screenshot or a business card")
            case .settings: LocalizedStringResource("Settings", bundle: .cxui)
            case .languages: LocalizedStringResource("Languages", bundle: .cxui)
            case .commandLine: LocalizedStringResource("Command line", bundle: .cxui, comment: "What’s New: the area of the cx command")
            case .app: LocalizedStringResource("App", bundle: .cxui, comment: "What’s New: the app as a whole")
            }
        }
    }

    private enum Keys: String, CodingKey { case date, version, area, feature }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let dateText = try container.decode(String.self, forKey: .date)
        // a date that does not give the same text back (2026-02-30) is not valid
        guard let date = try? WhatsNew.dayFormat.parse(dateText), WhatsNew.dayFormat.format(date) == dateText else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: container, debugDescription: "Not a date YYYY-MM-DD: \(dateText)")
        }
        let versionText = try container.decode(String.self, forKey: .version)
        guard let version = Version(versionText) else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "Not a version: \(versionText)")
        }
        let areaText = try container.decode(String.self, forKey: .area)
        guard let area = Area(rawValue: areaText) else {
            throw DecodingError.dataCorruptedError(forKey: .area, in: container, debugDescription: "Not an area: \(areaText)")
        }
        let feature = try container.decode(String.self, forKey: .feature).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !feature.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .feature, in: container, debugDescription: "No feature text")
        }
        self.date = date
        self.version = version
        self.area = area
        self.feature = feature
    }
}

/// Reading and sorting the list "What’s New".
enum WhatsNew {
    /// "2026-11-21" in the device's time zone, so that the shown day is the day in the file.
    static let dayFormat = Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash)

    /// The columns, for the table header and for the sort menu on a narrow screen.
    enum Column: CaseIterable, Identifiable {
        case date, version, area, feature

        var id: Self { self }

        var title: LocalizedStringResource {
            switch self {
            case .date: LocalizedStringResource("Date", bundle: .cxui)
            case .version: LocalizedStringResource("Version", bundle: .cxui)
            case .area: LocalizedStringResource("Area", bundle: .cxui, comment: "What’s New: the column with the part of the app")
            case .feature: LocalizedStringResource("Feature", bundle: .cxui, comment: "What’s New: the column with the description of the feature")
            }
        }

        func comparator(_ order: SortOrder) -> KeyPathComparator<WhatsNewEntry> {
            switch self {
            case .date: KeyPathComparator(\.date, order: order)
            case .version: KeyPathComparator(\.version, order: order)
            case .area: KeyPathComparator(\.areaTitle, order: order)
            case .feature: KeyPathComparator(\.feature, order: order)
            }
        }
    }

    static let newestFirst = [Column.date.comparator(.reverse)]

    static func entries(from data: Data) throws -> [WhatsNewEntry] {
        try JSONDecoder().decode([WhatsNewEntry].self, from: data)
    }

    /// The rows that the view shows, read once; a test checks that the file is valid.
    static let all = (try? bundled()) ?? []

    /// The rows of the file in CXUI's bundle.
    static func bundled() throws -> [WhatsNewEntry] {
        guard let url = Bundle.module.url(forResource: "whats-new", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try entries(from: Data(contentsOf: url))
    }

    /// Rows in the order of `order`; rows that are equal there go by version, in the same direction.
    static func sorted(_ rows: [WhatsNewEntry], using order: [KeyPathComparator<WhatsNewEntry>]) -> [WhatsNewEntry] {
        rows.sorted(using: order + [Column.version.comparator(order.first?.order ?? .reverse)])
    }
}

/// "What’s New" in the settings: a table that sorts by a click on a column header.
/// In a narrow place (iPhone, the Settings window on the Mac) a list with a sort menu takes the place of the table.
struct WhatsNewView: View {
    @State private var sortOrder = WhatsNew.newestFirst
    @State private var column = WhatsNew.Column.date
    @State private var order = SortOrder.reverse
    @State private var width: CGFloat = 0

    private enum Layout {
        /// Below this width the four columns do not fit, so the list takes the table's place.
        static let tableWidth: CGFloat = 540
    }

    /// Fixed widths for the short columns; the feature column takes the rest.
    private enum ColumnWidth {
        static let date: CGFloat = 110
        static let version: CGFloat = 70
        static let area: CGFloat = 120
    }

    var body: some View {
        content
            .navigationTitle(String(localized: "What’s New", bundle: .module))
    }

    @ViewBuilder private var content: some View {
        Group {
            if width >= Layout.tableWidth { wideTable } else { list }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    /// The settings sheet on iPad has a compact size class, but room for the table. A table in a compact size class
    /// shows only its first column, so the table gets a regular size class.
    private var wideTable: some View {
        #if os(iOS)
        table.environment(\.horizontalSizeClass, .regular)
        #else
        table
        #endif
    }

    private var table: some View {
        Table(WhatsNew.sorted(WhatsNew.all, using: sortOrder), sortOrder: $sortOrder) {
            TableColumn(localized(WhatsNew.Column.date.title, locale: .app), value: \.date) { Text($0.date, format: .dateTime.year().month().day()) }
                .width(ColumnWidth.date)
            TableColumn(localized(WhatsNew.Column.version.title, locale: .app), value: \.version) { Text(verbatim: $0.version.text) }
                .width(ColumnWidth.version)
            TableColumn(localized(WhatsNew.Column.area.title, locale: .app), value: \.areaTitle)
                .width(ColumnWidth.area)
            TableColumn(localized(WhatsNew.Column.feature.title, locale: .app), value: \.feature)
        }
    }

    private var list: some View {
        List(WhatsNew.sorted(WhatsNew.all, using: [column.comparator(order)])) { entry in
            VStack(alignment: .leading) {
                Text(verbatim: [entry.date.formatted(.dateTime.year().month().day()), entry.version.text, entry.areaTitle].joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.feature)
            }
            .accessibilityElement(children: .combine)
        }
        .toolbar {
            Menu {
                Picker(String(localized: "Sort By", bundle: .module), selection: $column) {
                    ForEach(WhatsNew.Column.allCases) { Text($0.title).tag($0) }
                }
                Picker(String(localized: "Order", bundle: .module), selection: $order) {
                    Text("Ascending", bundle: .module).tag(SortOrder.forward)
                    Text("Descending", bundle: .module).tag(SortOrder.reverse)
                }
            } label: {
                Label(String(localized: "Sort", bundle: .module), systemImage: "arrow.up.arrow.down")
            }
        }
    }
}
