import XCTest

#if !canImport(ObjectiveC)
    public func allTests() -> [XCTestCaseEntry] {
        return [
            testCase(NoteStoreTests.allTests),
            testCase(BacklinksStoreTests.allTests),
            testCase(ViewsTests.allTests),
            testCase(GrimoireAppTests.allTests),
        ]
    }
#endif
