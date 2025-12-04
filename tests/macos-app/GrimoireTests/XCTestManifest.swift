import XCTest

#if !canImport(ObjectiveC)
    public func allTests() -> [XCTestCaseEntry] {
        return [
            testCase(NoteManagerTests.allTests),
            testCase(SearchManagerTests.allTests),
            testCase(ViewsTests.allTests),
            testCase(GrimoireAppTests.allTests),
        ]
    }
#endif
