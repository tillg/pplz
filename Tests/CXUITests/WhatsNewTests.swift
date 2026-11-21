import Foundation
import Testing
@testable import CXUI

/// The list of new features in the settings (issue #15).
@Suite struct WhatsNewTests {
    private func entries(_ json: String) throws -> [WhatsNewEntry] {
        try WhatsNew.entries(from: Data(json.utf8))
    }

    private func entry(_ date: String, _ version: String, _ area: String = "Map", _ feature: String = "A feature") -> String {
        #"{"date": "\#(date)", "version": "\#(version)", "area": "\#(area)", "feature": "\#(feature)"}"#
    }

    @Test func aRowGivesDateVersionAreaAndFeature() throws {
        let rows = try entries("[\(entry("2026-11-21", "0.2.97", "Map", "Own position above all pins"))]")

        #expect(rows.count == 1)
        #expect(rows[0].date == DateComponents(calendar: .current, year: 2026, month: 11, day: 21).date)
        #expect(rows[0].version.text == "0.2.97")
        #expect(rows[0].area == .map)
        #expect(rows[0].feature == "Own position above all pins")
    }

    @Test func anInvalidDateIsRefused() {
        #expect(throws: (any Error).self) { try entries("[\(entry("2026-02-30", "0.1.5"))]") }
        #expect(throws: (any Error).self) { try entries("[\(entry("21.11.2026", "0.1.5"))]") }
    }

    @Test func anUnknownAreaAnEmptyFeatureOrAnOddVersionIsRefused() {
        #expect(throws: (any Error).self) { try entries("[\(entry("2026-11-21", "0.1.5", "Garden"))]") }
        #expect(throws: (any Error).self) { try entries("[\(entry("2026-11-21", "0.1.5", "Map", " "))]") }
        #expect(throws: (any Error).self) { try entries("[\(entry("2026-11-21", "0.x.5"))]") }
        #expect(throws: (any Error).self) { try entries("[\(entry("2026-11-21", ""))]") }
    }

    @Test func versionsCompareByNumberNotByText() throws {
        let nine = try #require(WhatsNewEntry.Version("0.2.9"))
        let ten = try #require(WhatsNewEntry.Version("0.2.10"))
        let one = try #require(WhatsNewEntry.Version("0.1.84"))

        #expect(nine < ten)
        #expect(one < nine)
    }

    @Test func newestFirstIsTheDefaultAndTheVersionBreaksATie() throws {
        let rows = try entries("[\(entry("2026-11-19", "0.1.30")), \(entry("2026-11-21", "0.2.9")), \(entry("2026-11-21", "0.2.10"))]")

        let sorted = WhatsNew.sorted(rows, using: WhatsNew.newestFirst)

        #expect(sorted.map(\.version.text) == ["0.2.10", "0.2.9", "0.1.30"])
    }

    @Test func eachColumnSortsBothWays() throws {
        let rows = try entries("[\(entry("2026-11-19", "0.1.30", "People", "b")), \(entry("2026-11-21", "0.2.9", "Map", "a")), \(entry("2026-11-20", "0.2.10", "Events", "c"))]")

        #expect(WhatsNew.sorted(rows, using: [WhatsNew.Column.version.comparator(.forward)]).map(\.version.text) == ["0.1.30", "0.2.9", "0.2.10"])
        #expect(WhatsNew.sorted(rows, using: [WhatsNew.Column.feature.comparator(.reverse)]).map(\.feature) == ["c", "b", "a"])
        #expect(WhatsNew.sorted(rows, using: [WhatsNew.Column.date.comparator(.forward)]).map(\.feature) == ["b", "c", "a"])
        #expect(WhatsNew.sorted(rows, using: [WhatsNew.Column.area.comparator(.forward)]).map(\.area)
                == [.events, .map, .people])
    }

    @Test func theBundledListIsValid() throws {
        let rows = try WhatsNew.bundled()

        #expect(rows.count >= 20)
        #expect(rows.allSatisfy { !$0.feature.isEmpty })
    }
}
