import XCTest

final class SimFrameUITests: XCTestCase {
    func testEmptyLibraryShowsOnboarding() {
        let app = XCUIApplication()
        let isolated = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        app.launchEnvironment["SIMFRAME_APP_SUPPORT"] = isolated.path
        app.launch()

        XCTAssertTrue(app.staticTexts["Bring your own Apple device frames"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Import Frame Folder…"].exists)
        XCTAssertTrue(app.buttons["Open Apple Design Resources"].exists)
    }
}

