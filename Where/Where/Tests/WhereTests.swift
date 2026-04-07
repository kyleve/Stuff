import Testing
import WhereData

@Test
func appDependenciesBuildYearSnapshot() async {
    let controller = YearProgressController()
    let years = await controller.availableYears()

    #expect(!years.isEmpty)
}
