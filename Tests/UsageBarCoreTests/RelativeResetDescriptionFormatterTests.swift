import XCTest
@testable import UsageBarCore

final class RelativeResetDescriptionFormatterTests: XCTestCase {
    func testTextShowsDaysAndHoursWhenAtLeastOneDayRemains() {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let resetAt = now.addingTimeInterval(184_800)

        let text = RelativeResetDescriptionFormatter.text(until: resetAt, now: now)

        XCTAssertEqual(text, "2日3時間後")
    }

    func testTextShowsHoursAndMinutesWhenAtLeastOneHourRemains() {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let resetAt = now.addingTimeInterval(15_120)

        let text = RelativeResetDescriptionFormatter.text(until: resetAt, now: now)

        XCTAssertEqual(text, "4時間12分後")
    }

    func testTextShowsMinutesWhenAtLeastOneMinuteRemains() {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let resetAt = now.addingTimeInterval(930)

        let text = RelativeResetDescriptionFormatter.text(until: resetAt, now: now)

        XCTAssertEqual(text, "15分後")
    }

    func testTextShowsSecondsWhenLessThanOneMinuteRemains() {
        let now = Date(timeIntervalSince1970: 1_785_196_800)
        let resetAt = now.addingTimeInterval(45)

        let text = RelativeResetDescriptionFormatter.text(until: resetAt, now: now)

        XCTAssertEqual(text, "45秒後")
    }
}
