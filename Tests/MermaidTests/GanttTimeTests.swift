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

@Suite("Gantt time: dayjs formats")
struct DayjsFormatTests {
    let reference = civil(2024, 6, 15)

    func parse(_ text: String, _ format: String) -> CivilDateTime? {
        DayjsFormat(format).parse(text, reference: reference)
    }

    @Test func parsesCommonFormats() {
        #expect(parse("2014-01-06", "YYYY-MM-DD") == civil(2014, 1, 6))
        #expect(parse("06-01-2014", "DD-MM-YYYY") == civil(2014, 1, 6))
        #expect(parse("14/1/6", "YY/M/D") == civil(2014, 1, 6))
        #expect(parse("70/1/6", "YY/M/D") == civil(1970, 1, 6))
        #expect(parse("2024-01-05 09:30:15.120", "YYYY-MM-DD HH:mm:ss.SSS") == civil(2024, 1, 5, 9, 30, 15, 120))
        #expect(parse("March 3rd 2021", "MMMM Do YYYY") == civil(2021, 3, 3))
        #expect(parse("Jan 5, 2021 3:04 pm", "MMM D, YYYY h:mm a") == civil(2021, 1, 5, 15, 4))
        #expect(parse("12:15 AM", "hh:mm A") == civil(2024, 6, 15, 0, 15))
        #expect(parse("2021 Q3", "YYYY [Q]Q") == civil(2021, 7, 1))
        #expect(parse("2021-032", "YYYY-DDDD") == civil(2021, 2, 1))
        #expect(parse("20240105", "YYYYMMDD") == civil(2024, 1, 5))
    }

    @Test func defaultsMissingFieldsLikeDayjs() {
        // A time alone falls on the reference date.
        #expect(parse("17:49", "HH:mm") == civil(2024, 6, 15, 17, 49))
        // A year alone is January 1.
        #expect(parse("1913", "YYYY") == civil(1913, 1, 1))
        // A month without a year uses the reference year.
        #expect(parse("03", "MM") == civil(2024, 3, 1))
    }

    @Test func parsesTimestampsAndZones() {
        #expect(parse("86400", "X") == civil(1970, 1, 2))
        #expect(parse("1.5", "X") == CivilDateTime(milliseconds: 1500))
        #expect(parse("86400000", "x") == civil(1970, 1, 2))
        #expect(parse("2024-01-05T10:00+02:00", "YYYY-MM-DD[T]HH:mmZ") == civil(2024, 1, 5, 8))
        #expect(parse("2024-01-05T10:00Z", "YYYY-MM-DD[T]HH:mmZ") == civil(2024, 1, 5, 10))
    }

    @Test func strictParsingRejectsMismatches() {
        #expect(parse("2023-02-30", "YYYY-MM-DD") == nil)
        #expect(parse("2023-2-03", "YYYY-MM-DD") == nil)
        #expect(parse("2023-02-03x", "YYYY-MM-DD") == nil)
        #expect(parse("2023/02/03", "YYYY-MM-DD") == nil)
        #expect(parse("25:00", "HH:mm") == nil)
        #expect(parse("3d", "YYYY-MM-DD") == nil)
        #expect(parse("Foo 5", "MMM D") == nil)
    }

    @Test func formatsTokens() {
        let date = civil(2024, 1, 7, 15, 4, 5, 60)
        #expect(DayjsFormat("YYYY-MM-DD HH:mm:ss.SSS").format(date) == "2024-01-07 15:04:05.060")
        #expect(DayjsFormat("dddd ddd dd d").format(date) == "Sunday Sun Su 0")
        #expect(DayjsFormat("MMMM MMM M Do DDD").format(date) == "January Jan 1 7th 7")
        #expect(DayjsFormat("h:mm A a k").format(date) == "3:04 PM pm 15")
        #expect(DayjsFormat("[Week] W, Q, X").format(date) == "Week 1, 1, 1704639845")
        #expect(DayjsFormat("Do").format(civil(2024, 1, 22)) == "22nd")
        #expect(DayjsFormat("Do").format(civil(2024, 1, 13)) == "13th")
    }

    @Test func isoWeeksAtYearBoundaries() {
        #expect(DayjsFormat.isoWeek(civil(2021, 1, 3).components) == (2020, 53))
        #expect(DayjsFormat.isoWeek(civil(2024, 12, 30).components) == (2025, 1))
        #expect(DayjsFormat.isoWeek(civil(2020, 12, 31).components) == (2020, 53))
        #expect(DayjsFormat.isoWeek(civil(2024, 6, 15).components) == (2024, 24))
    }
}

@Suite("Gantt time: strftime")
struct StrftimeFormatTests {
    @Test func formatsD3Directives() {
        let date = civil(2024, 1, 7, 15, 4, 5, 60)
        #expect(StrftimeFormat("%Y-%m-%d").format(date) == "2024-01-07")
        #expect(StrftimeFormat("%a %A %b %B").format(date) == "Sun Sunday Jan January")
        #expect(StrftimeFormat("%H:%M:%S.%L %I%p").format(date) == "15:04:05.060 03PM")
        #expect(StrftimeFormat("[%e] %j %y %w %u").format(date) == "[ 7] 007 24 0 7")
        #expect(StrftimeFormat("%U %W %V %q").format(date) == "01 01 01 1")
        #expect(StrftimeFormat("%-d/%-m %_H %%").format(date) == "7/1 15 %")
        #expect(StrftimeFormat("%x %X").format(date) == "1/7/2024 3:04:05 PM")
        #expect(StrftimeFormat("%s %Q").format(civil(1970, 1, 2)) == "86400 86400000")
        #expect(StrftimeFormat("%k").format(date) == "%k")
    }
}

@Suite("Gantt time: intervals")
struct CalendarIntervalTests {
    @Test func parsesTickIntervals() {
        #expect(CalendarInterval(tickInterval: "1day", firstWeekday: 0) == CalendarInterval(.day))
        #expect(CalendarInterval(tickInterval: "2week", firstWeekday: 1) == CalendarInterval(.week(firstWeekday: 1), every: 2))
        #expect(CalendarInterval(tickInterval: "0day", firstWeekday: 0) == nil)
        #expect(CalendarInterval(tickInterval: "1decade", firstWeekday: 0) == nil)
        #expect(CalendarInterval(tickInterval: "day", firstWeekday: 0) == nil)
    }

    @Test func listsBoundariesInRange() {
        let days = CalendarInterval(.day, every: 2).dates(from: civil(2024, 1, 1, 12), through: civil(2024, 1, 8))
        #expect(days == [civil(2024, 1, 3), civil(2024, 1, 5), civil(2024, 1, 7)])
        let mondays = CalendarInterval(.week(firstWeekday: 1)).dates(from: civil(2024, 1, 1), through: civil(2024, 1, 20))
        #expect(mondays == [civil(2024, 1, 1), civil(2024, 1, 8), civil(2024, 1, 15)])
        let months = CalendarInterval(.month, every: 3).dates(from: civil(2024, 1, 15), through: civil(2024, 12, 31))
        #expect(months == [civil(2024, 4, 1), civil(2024, 7, 1), civil(2024, 10, 1)])
        let decades = CalendarInterval(.year, every: 10).dates(from: civil(1900, 1, 1), through: civil(1935, 1, 1))
        #expect(decades.map { $0.components.year } == [1900, 1910, 1920, 1930])
    }

    @Test func automaticIntervalsMatchD3() {
        #expect(CalendarInterval.automatic(from: civil(2014, 1, 1), to: civil(2014, 3, 1)) == CalendarInterval(.week(firstWeekday: 0)))
        #expect(CalendarInterval.automatic(from: civil(2014, 1, 1), to: civil(2014, 1, 11)) == CalendarInterval(.day))
        #expect(CalendarInterval.automatic(from: civil(2024, 1, 1, 17, 30), to: civil(2024, 1, 1, 18, 10)) == CalendarInterval(.minute, every: 5))
        #expect(CalendarInterval.automatic(from: civil(1900, 1, 1), to: civil(1935, 1, 1)) == CalendarInterval(.year, every: 5))
        #expect(CalendarInterval.automatic(from: CivilDateTime(milliseconds: 0), to: CivilDateTime(milliseconds: 71)) == CalendarInterval(.millisecond, every: 10))
    }

    @Test func tickStepsAreRound() {
        #expect(CalendarInterval.tickStep(0, 35, 10) == 5)
        #expect(CalendarInterval.tickStep(0, 1, 10) == 0.1)
        #expect(CalendarInterval.tickStep(0, 71, 10) == 10)
    }
}
