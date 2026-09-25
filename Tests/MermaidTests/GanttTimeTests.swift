import Foundation
import Testing
@testable import Mermaid

func civil(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0,
           _ second: Int = 0, _ ms: Int = 0) -> CivilDateTime {
    CivilDateTime(year: year, month: month, day: day, hour: hour, minute: minute, second: second, millisecond: ms)!
}

@Suite("Gantt time: civil dates")
struct CivilDateTimeTests {
    @Test func roundTripsComponentsAcrossEras() {
        for (y, m, d) in [(1970, 1, 1), (2000, 2, 29), (1969, 12, 31), (1600, 3, 1), (2024, 12, 31), (-44, 3, 15)] {
            let c = civil(y, m, d, 13, 45, 7, 250).components
            let actual: [Int] = [c.year, c.month, c.day, c.hour, c.minute, c.second, c.millisecond]
            #expect(actual == [y, m, d, 13, 45, 7, 250])
        }
    }

    @Test func weekdaysAndDayOfYear() {
        #expect(civil(1970, 1, 1).components.weekday == 4)
        #expect(civil(2024, 1, 7).components.weekday == 0)
        #expect(civil(1969, 12, 31).components.weekday == 3)
        #expect(civil(2024, 12, 31).components.dayOfYear == 366)
        #expect(civil(2023, 3, 1).components.dayOfYear == 60)
    }

    @Test func rejectsInvalidComponents() {
        #expect(CivilDateTime(year: 2023, month: 2, day: 29) == nil)
        #expect(CivilDateTime(year: 2023, month: 13, day: 1) == nil)
        #expect(CivilDateTime(year: 2023, month: 1, day: 1, hour: 24) == nil)
    }

    @Test func addsUnitsWithDayjsSemantics() {
        let start = civil(2024, 1, 31, 10)
        #expect(start.adding(1, .month) == civil(2024, 2, 29, 10))
        #expect(start.adding(13, .month) == civil(2025, 2, 28, 10))
        #expect(civil(2024, 2, 29).adding(1, .year) == civil(2025, 2, 28))
        #expect(start.adding(1.5, .day) == civil(2024, 2, 2, 10))
        #expect(start.adding(1.5, .hour) == civil(2024, 1, 31, 11, 30))
        #expect(start.adding(2, .week) == civil(2024, 2, 14, 10))
        #expect(start.adding(1.9, .month) == civil(2024, 2, 29, 10))
        #expect(start.adding(-1, .day) == civil(2024, 1, 30, 10))
        #expect(start.adding(250, .millisecond).components.millisecond == 250)
    }

    @Test func convertsFoundationDatesInAZone() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let utc = CivilDateTime(date, timeZone: try #require(TimeZone(identifier: "UTC")))
        #expect(utc == civil(2023, 11, 14, 22, 13, 20))
        let tokyo = CivilDateTime(date, timeZone: try #require(TimeZone(identifier: "Asia/Tokyo")))
        #expect(tokyo == civil(2023, 11, 15, 7, 13, 20))
    }
}
