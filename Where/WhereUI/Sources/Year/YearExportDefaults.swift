import Foundation

/// Pure presentation defaults for a newly opened annual-export sheet.
enum YearExportDefaults {
    static func selectedYear(
        displayedYear: Int,
        now: Date,
        calendar: Calendar,
    ) -> Int {
        let currentYear = calendar.component(.year, from: now)
        guard displayedYear == currentYear else { return displayedYear }
        let month = calendar.component(.month, from: now)
        return month <= 3 ? currentYear - 1 : currentYear
    }

    static func availableYears(
        displayedYear: Int,
        now: Date,
        calendar: Calendar,
    ) -> [Int] {
        let currentYear = calendar.component(.year, from: now)
        var years = Set((currentYear - 5) ... currentYear)
        years.insert(displayedYear)
        return years.sorted(by: >)
    }
}
