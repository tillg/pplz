import Testing
@testable import CXCore

@Suite struct AppVersionTests {
    @Test func showsVersionBuildAndBuildDate() {
        let info = ["CFBundleShortVersionString": "0.2", "CFBundleVersion": "693", "CXBuildDate": "2026-11-20 14:07"]
        #expect(AppVersion.text(info: info) == "V. 0.2.693 - 2026-11-20 14:07")
    }

    @Test func noBuildDateMeansNoDate() {
        #expect(AppVersion.text(info: ["CFBundleShortVersionString": "0.2", "CFBundleVersion": "693", "CXBuildDate": ""]) == "V. 0.2.693")
        #expect(AppVersion.text(info: ["CFBundleShortVersionString": "0.2", "CFBundleVersion": "693"]) == "V. 0.2.693")
    }

    @Test func noBuildNumberMeansOnlyTheVersion() {
        #expect(AppVersion.text(info: ["CFBundleShortVersionString": "0.2", "CXBuildDate": "2026-11-20 14:07"]) == "V. 0.2 - 2026-11-20 14:07")
    }

    @Test func noInfoMeansAQuestionMark() {
        #expect(AppVersion.text(info: [:]) == "V. ?")
        #expect(AppVersion.text(info: nil) == "V. ?")
    }
}
