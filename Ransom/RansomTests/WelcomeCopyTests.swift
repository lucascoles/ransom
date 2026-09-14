import Foundation
import Testing
@testable import Ransom

/// The words on the post-paywall welcome.
///
/// Both lines are built from what the user typed during intake, so both have a
/// case where they typed nothing, and that case is the one worth pinning down.
@Suite("Welcome copy")
struct WelcomeCopyTests {

    @Test("A name is used when there is one")
    func headlineWithName() {
        #expect(WelcomeCelebration.headline(firstName: "Lucas") == "Proud of you, Lucas.")
    }

    @Test("No name drops the name rather than leaving a dangling comma")
    func headlineWithoutName() {
        #expect(WelcomeCelebration.headline(firstName: "") == "Proud of you.")
    }

    @Test("A name made of spaces counts as no name")
    func headlineWithBlankName() {
        #expect(WelcomeCelebration.headline(firstName: "   ") == "Proud of you.")
        #expect(WelcomeCelebration.headline(firstName: "  Lucas ") == "Proud of you, Lucas.")
    }

    @Test("The daily saving becomes days in a year")
    func sublineInDays() {
        // 2h 50m a day is 1,034 hours a year, which is 43 whole days.
        #expect(WelcomeCelebration.subline(minutesSavedPerDay: 170)
                == "That's 43 days of your year coming back.\nLet's go get them.")
    }

    @Test("A small saving is told in hours, not as zero or one day")
    func sublineInHours() {
        // 5 minutes a day is 30 hours a year: one whole day, so hours read better.
        #expect(WelcomeCelebration.subline(minutesSavedPerDay: 5)
                == "That's 30 hours of your year coming back.\nLet's go get them.")
    }

    @Test("No saving means no number")
    func sublineWithNoSaving() {
        #expect(WelcomeCelebration.subline(minutesSavedPerDay: 0)
                == "Every set buys back your time.\nLet's go get it.")
        #expect(WelcomeCelebration.subline(minutesSavedPerDay: -10)
                == "Every set buys back your time.\nLet's go get it.")
    }
}
