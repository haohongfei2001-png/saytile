import XCTest

@MainActor
final class ReaderUITests: XCTestCase {
    private let transcript = "星期五下午三点，讨论原音备份。"

    private func article(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "archive.text").firstMatch
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLaunchWithoutTestData() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["此候选尚未连接 iCloud"].waitForExistence(timeout: 15))
        XCTAssertFalse(article(in: app).exists)
    }

    func testSearchAndPlaySavedRecording() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--public-reader-fixture", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let text = article(in: app)
        XCTAssertTrue(text.waitForExistence(timeout: 15))
        XCTAssertTrue([text.value as? String, text.label].contains(transcript))
        capture("Archive", app: app)

        let play = app.buttons["回听"], stop = app.buttons["停止回听"]
        XCTAssertTrue(play.isHittable)
        play.tap()
        XCTAssertTrue(stop.waitForExistence(timeout: 10), app.debugDescription)
        capture("Playback", app: app)
        stop.tap()
        XCTAssertTrue(play.waitForExistence(timeout: 10), "Manual stop should restore the playback action.")
        play.tap()
        XCTAssertTrue(stop.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(play.waitForExistence(timeout: 45), "The player delegate should finish the complete fixture.")

        let search = app.searchFields.firstMatch
        if !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.isHittable)
        search.tap()
        search.typeText("unmatched")
        XCTAssertTrue(text.waitForNonExistence(timeout: 5))
        XCTAssertFalse(play.exists)
        capture("Search", app: app)

        let clear = search.buttons.firstMatch
        XCTAssertTrue(clear.isHittable)
        clear.tap()
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(play.isHittable)
    }
}
