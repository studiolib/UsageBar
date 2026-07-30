import XCTest
@testable import UsageBarCore

final class UsageWindowDisplayFormatterTests: XCTestCase {
    func testResetAtTextOmitsYearAndShowsWeekday() {
        let resetAt = Date(timeIntervalSince1970: 1_785_556_800)
        let timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!

        let text = UsageWindowDisplayFormatter.resetAtText(resetAt, timeZone: timeZone)

        XCTAssertEqual(text, "リセット: 8月1日(土) 13:00")
    }

    func testResetAtTextShowsUnknownWhenResetDateIsMissing() {
        let text = UsageWindowDisplayFormatter.resetAtText(nil)

        XCTAssertEqual(text, "リセット: 不明")
    }

    func testResetDescriptionTextShowsUnknownWhenDescriptionIsUnknown() {
        let text = UsageWindowDisplayFormatter.resetDescriptionText("不明")

        XCTAssertEqual(text, "リセット時刻不明")
    }

    func testResetDescriptionTextAppendsResetSuffix() {
        let text = UsageWindowDisplayFormatter.resetDescriptionText("2時間15分後")

        XCTAssertEqual(text, "2時間15分後にリセット")
    }

    func testResetDescriptionTextCalculatesRelativeTextFromResetDate() {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let resetAt = now.addingTimeInterval(2 * 60 * 60 + 15 * 60)

        let text = UsageWindowDisplayFormatter.resetDescriptionText(resetAt: resetAt, now: now)

        XCTAssertEqual(text, "2時間15分後にリセット")
    }

    func testResetDescriptionTextShowsUnknownWhenResetDateIsMissing() {
        let text = UsageWindowDisplayFormatter.resetDescriptionText(resetAt: nil)

        XCTAssertEqual(text, "リセット時刻不明")
    }
}
