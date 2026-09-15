import Foundation
import Testing
@testable import Ransom

/// The Progress tab's screen time cards: today against yesterday, and the week.
///
/// The cards are drawn by the report extension, which no test can host, so the
/// numbers and words they show are pinned down here instead.
@Suite("Screen time summary")
struct ScreenTimeSummaryTests {

    @Test("The comparison uses the real figures, not a rung")
    func changeFromRealFigures() {
        // The day this was found: 6h 20m today against 4h yesterday.
        #expect(ScreenTimeSummary.change(today: 380, yesterday: 240) == 58)
        #expect(ScreenTimeSummary.change(today: 120, yesterday: 240) == -50)
    }

    @Test("Nothing yesterday means no comparison, not +infinity")
    func noYesterday() {
        #expect(ScreenTimeSummary.change(today: 380, yesterday: 0) == nil)
    }

    @Test("Five percent either way is level, and figure and sentence agree")
    func directionBoundaries() {
        #expect(ScreenTimeSummary.direction(-6) == .down)
        #expect(ScreenTimeSummary.direction(-5) == .level)
        #expect(ScreenTimeSummary.direction(5) == .level)
        #expect(ScreenTimeSummary.direction(6) == .up)
        #expect(ScreenTimeSummary.line(5).hasPrefix("About level"))
        #expect(ScreenTimeSummary.line(6).hasPrefix("Up a bit"))
        #expect(ScreenTimeSummary.line(-6).hasPrefix("Under yesterday"))
    }

    @Test("The headline carries its sign")
    func headlineSign() {
        #expect(ScreenTimeSummary.headline(58) == "+58%")
        #expect(ScreenTimeSummary.headline(-12) == "-12%")
        #expect(ScreenTimeSummary.headline(0) == "0%")
    }

    @Test("No copy on these cards uses an em dash")
    func noEmDashes() {
        for change in [-60, -10, 0, 10, 60] {
            #expect(!ScreenTimeSummary.line(change).contains("\u{2014}"))
        }
    }

    @Test("The week's average leaves today out")
    func averageSkipsToday() {
        // Seven finished days of 3h, then a morning of 20 minutes.
        let week = ScreenTimeSummary.Week(days: Array(repeating: 0, count: 7) + Array(repeating: 180, count: 7) + [20])
        #expect(week.average == 180)
    }

    @Test("Days Screen Time has nothing for are gaps, not zeros")
    func zerosAreGaps() {
        let days = Array(repeating: 0, count: 11) + [200, 0, 100, 50]
        let week = ScreenTimeSummary.Week(days: days)
        #expect(week.chart == [nil, nil, nil, 200, nil, 100, 50])
        // Averaged over the two days that have a figure, not all seven.
        #expect(week.average == 150)
    }

    @Test("A change is only claimed with a week to compare against")
    func changeNeedsLastWeek() {
        let firstWeek = ScreenTimeSummary.Week(days: Array(repeating: 0, count: 8) + Array(repeating: 200, count: 7))
        #expect(firstWeek.change == nil)

        let twoWeeks = ScreenTimeSummary.Week(days: Array(repeating: 200, count: 7) + Array(repeating: 150, count: 7) + [30])
        #expect(twoWeeks.change == -25)
    }

    @Test("Minutes read as a clock")
    func clock() {
        #expect(ScreenTimeSummary.clock(45) == "45m")
        #expect(ScreenTimeSummary.clock(60) == "1h")
        #expect(ScreenTimeSummary.clock(380) == "6h 20m")
    }
}
