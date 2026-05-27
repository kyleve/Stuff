import Foundation
import SwiftUI
import Testing
import WhereCore
import WhereTesting
import WhereUI

@Test
@MainActor
func rootViewBuilds() throws {
    let vc = UIHostingController(rootView: RootView())
    try show(vc) { hosted in
        #expect(hosted.view != nil)
    }
}

@Test
@MainActor
func modelLoadsManualDaysIntoReport() async throws {
    let store = try SwiftDataStore.inMemory()
    let controller = WhereController(store: store, locationSource: ScriptedLocationSource())

    let calendar = Calendar(identifier: .gregorian)
    func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2025, month: month, day: day))!
    }
    try await controller.addManualDay(date: day(1, 5), regions: [.california])
    try await controller.addManualDay(date: day(3, 9), regions: [.california, .newYork])

    let model = WhereModel(controller: controller, year: 2025)
    await model.load()

    guard case let .loaded(report) = model.state else {
        Issue.record("Expected .loaded, got \(model.state)")
        return
    }
    #expect(report.year == 2025)
    #expect(report.days.count == 2)
    #expect(report.totals[.california] == 2)
    #expect(report.totals[.newYork] == 1)
}

@Test
@MainActor
func selectingDifferentYearReloads() async throws {
    let store = try SwiftDataStore.inMemory()
    let controller = WhereController(store: store, locationSource: ScriptedLocationSource())

    let calendar = Calendar(identifier: .gregorian)
    let date = calendar.date(from: DateComponents(year: 2024, month: 7, day: 4))!
    try await controller.addManualDay(date: date, regions: [.canada])

    let model = WhereModel(controller: controller, year: 2025)
    await model.load()
    if case let .loaded(report) = model.state {
        #expect(report.days.isEmpty)
    } else {
        Issue.record("Expected .loaded for 2025, got \(model.state)")
    }

    await model.selectYear(2024)
    #expect(model.year == 2024)
    guard case let .loaded(report) = model.state else {
        Issue.record("Expected .loaded for 2024, got \(model.state)")
        return
    }
    #expect(report.days.count == 1)
    #expect(report.totals[.canada] == 1)
}
