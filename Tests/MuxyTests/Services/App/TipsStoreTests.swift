import Foundation
import Testing

@testable import Muxy

@Suite("TipsStore")
@MainActor
struct TipsStoreTests {
    @Test("catalog decodes description-only tips")
    func catalogDecodesDescriptions() throws {
        let tips = try TipCatalog.decode(Data(#"[{"description":" First tip "},{"description":"Second tip"}]"#.utf8))

        #expect(tips == [try MuxyTip(description: "First tip"), try MuxyTip(description: "Second tip")])
    }

    @Test("catalog rejects empty collections")
    func catalogRejectsEmptyCollection() {
        #expect(throws: DecodingError.self) {
            try TipCatalog.decode(Data("[]".utf8))
        }
    }

    @Test("catalog rejects blank descriptions")
    func catalogRejectsBlankDescription() {
        #expect(throws: DecodingError.self) {
            try TipCatalog.decode(Data(#"[{"description":"   "}]"#.utf8))
        }
    }

    @Test("catalog rejects fields other than description")
    func catalogRejectsUnknownFields() {
        #expect(throws: DecodingError.self) {
            try TipCatalog.decode(Data(#"[{"description":"Tip","name":"Extra"}]"#.utf8))
        }
    }

    @Test("bundled catalog contains only description fields")
    func bundledCatalogSchema() throws {
        let url = RepositoryRoot.find().appendingPathComponent("Muxy/Resources/tips.json")
        let data = try Data(contentsOf: url)
        let objects = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        #expect(!objects.isEmpty)
        #expect(objects.allSatisfy { Set($0.keys) == ["description"] })
        #expect(try TipCatalog.decode(data).count == objects.count)
    }

    @Test("module resource bundle contains the tips catalog")
    func moduleBundleContainsCatalog() {
        #expect(!TipCatalog.load(bundle: .module).isEmpty)
    }

    @Test("starting tip is selected once during initialization")
    func startingTipIsStable() throws {
        var selections = 0
        let store = TipsStore(tips: try tips()) { count in
            selections += 1
            #expect(count == 3)
            return 1
        }

        #expect(store.currentTip?.description == "Second")
        #expect(store.currentTip?.description == "Second")
        #expect(selections == 1)
    }

    @Test("navigation wraps in catalog order")
    func navigationWraps() throws {
        let store = TipsStore(tips: try tips()) { _ in 0 }

        store.showPrevious()
        #expect(store.currentTip?.description == "Third")
        #expect(store.position == 3)

        store.showNext()
        #expect(store.currentTip?.description == "First")
        #expect(store.position == 1)
    }

    @Test("empty stores ignore navigation")
    func emptyStoreIgnoresNavigation() {
        let store = TipsStore(tips: []) { _ in
            Issue.record("Empty stores must not request a starting index")
            return 0
        }

        store.showNext()
        store.showPrevious()

        #expect(store.currentTip == nil)
        #expect(store.position == 0)
    }

    private func tips() throws -> [MuxyTip] {
        [
            try MuxyTip(description: "First"),
            try MuxyTip(description: "Second"),
            try MuxyTip(description: "Third"),
        ]
    }
}
