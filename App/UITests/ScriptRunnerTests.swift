import XCTest

/// Drives the app through a list of steps and records what the screen shows after them.
/// It lets a developer — or a coding agent — click through the real app from the command line:
///
///     scripts/ui.sh "-select|Anna Example" "tap:Log Event;screenshot:sheet;tree:sheet"
///
/// Steps, separated by `;`:
///   tap:<label, identifier or placeholder>   type:<text>   clear   swipeUp   swipeDown   back   wait:<seconds>
///   screenshot:<name>   tree:<name>   (the accessibility tree as text)
final class ScriptRunnerTests: XCTestCase {
    @MainActor
    func testRunScript() throws {
        let environment = ProcessInfo.processInfo.environment
        let app = XCUIApplication()
        app.launchArguments = (environment["PPLZ_APP_ARGS"] ?? "").split(separator: "|").map(String.init)
        app.launch()

        for step in (environment["PPLZ_UI_SCRIPT"] ?? "screenshot:start").split(separator: ";") {
            let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
            let argument = parts.count > 1 ? parts[1] : ""
            switch parts[0] {
            case "tap":
                // controls first: a field and the caption above it can carry the same label
                let predicate = NSPredicate(format: "label == %@ OR identifier == %@ OR placeholderValue == %@", argument, argument, argument)
                let candidates = [app.buttons, app.textFields, app.textViews, app.searchFields, app.switches, app.descendants(matching: .any)]
                    .map { $0.matching(predicate).firstMatch }
                _ = candidates.last!.waitForExistence(timeout: 5)
                guard let element = candidates.first(where: \.exists) else {
                    XCTFail("Nothing on screen is called \"\(argument)\"")
                    continue
                }
                element.tap()
            case "type":
                app.typeText(argument)
            case "clear":
                app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
            case "swipeUp":
                app.swipeUp()
            case "swipeDown":
                app.swipeDown()
            case "back":
                app.navigationBars.buttons.firstMatch.tap()
            case "wait":
                Thread.sleep(forTimeInterval: Double(argument) ?? 1)
            case "screenshot":
                Thread.sleep(forTimeInterval: 0.7)   // let animations finish
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = argument
                attachment.lifetime = .keepAlways
                add(attachment)
            case "tree":
                let attachment = XCTAttachment(string: app.debugDescription)
                attachment.name = argument + "-tree"
                attachment.lifetime = .keepAlways
                add(attachment)
            default:
                XCTFail("Unknown step \"\(step)\"")
            }
        }
    }
}
