import Foundation
import Testing
@testable import CXCore

/// The guards of the rename from cardXchange (`docs/changes/01_rename_to_cardxchange/02-data-migration.md` §2.4).
@Suite struct RenameGuardTests {
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cx-guard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func theDefaultStoreHasTheNewName() {
        let base = URL(fileURLWithPath: "/tmp/support")
        #expect(CXStore.defaultURL(environment: [:], base: base).path == "/tmp/support/cardxchange/cardxchange.store")
        #expect(CXStore.defaultURL(environment: ["CX_STORE": "/tmp/x.store"], base: base).path == "/tmp/x.store")
        #expect(CXStore.defaultURL(environment: ["PPLZ_STORE": "/tmp/x.store"], base: base).path == "/tmp/support/cardxchange/cardxchange.store")
    }

    @Test func anOldVariableStopsTheCommand() {
        for old in ["PPLZ_STORE", "PPLZ_NO_CONTACTS"] {
            #expect(throws: CXError.self) { try CXStore.checkOldVariables([old: "1"]) }
        }
        #expect(throws: CXError.invalid("PPLZ_NO_CONTACTS is set, but cx no longer reads it. Use CX_NO_CONTACTS, and remove PPLZ_NO_CONTACTS from your shell profile.")) {
            try CXStore.checkOldVariables(["PPLZ_NO_CONTACTS": "1", "CX_NO_CONTACTS": "1"])
        }
        #expect(throws: Never.self) { try CXStore.checkOldVariables(["CX_STORE": "/tmp/x.store", "HOME": "/Users/x"]) }
    }

    @Test func aDefaultStoreNextToUnmigratedDataIsRefused() throws {
        let base = try folder()
        try FileManager.default.createDirectory(at: base.appendingPathComponent("pplz"), withIntermediateDirectories: true)
        #expect(throws: CXError.self) { try CXStore.checkMigrated(CXStore.defaultURL(environment: [:], base: base), base: base) }
        // a store given by path is not the default store
        #expect(throws: Never.self) { try CXStore.checkMigrated(base.appendingPathComponent("other.store"), base: base) }
    }

    @Test func aMigratedOrFreshDefaultStoreIsAccepted() throws {
        let base = try folder()
        let store = CXStore.defaultURL(environment: [:], base: base)
        #expect(throws: Never.self) { try CXStore.checkMigrated(store, base: base) }   // no old folder: a fresh start
        try FileManager.default.createDirectory(at: base.appendingPathComponent("pplz"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: store)
        #expect(throws: Never.self) { try CXStore.checkMigrated(store, base: base) }   // migrated; the old folder is a backup
    }

    @Test func aRenamedOldFolderIsNoReasonToStop() throws {
        let base = try folder()
        try FileManager.default.createDirectory(at: base.appendingPathComponent("pplz.migrated-2026-11-20"), withIntermediateDirectories: true)
        #expect(throws: Never.self) { try CXStore.checkMigrated(CXStore.defaultURL(environment: [:], base: base), base: base) }
    }
}
