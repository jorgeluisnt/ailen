import XCTest
@testable import Ailen

final class AlphabetIndexTests: XCTestCase {
    func test_letterFoldsAccentsKeepsÑAndGroupsTheRestUnderHash() {
        XCTAssertEqual(AlphabetIndex.letter(for: "Árbol"), "A")
        XCTAssertEqual(AlphabetIndex.letter(for: "éxito"), "E")
        XCTAssertEqual(AlphabetIndex.letter(for: "Ñandú"), "Ñ")
        XCTAssertEqual(AlphabetIndex.letter(for: "ñu"), "Ñ")
        XCTAssertEqual(AlphabetIndex.letter(for: "  bach"), "B")
        XCTAssertEqual(AlphabetIndex.letter(for: "2 Brothers"), "#")
        XCTAssertEqual(AlphabetIndex.letter(for: "(FlowActivo)"), "#")
        XCTAssertEqual(AlphabetIndex.letter(for: "ロック"), "#")
        XCTAssertEqual(AlphabetIndex.letter(for: nil), "#")
    }

    func test_anchorsKeepTheFirstItemPerLetter() {
        let titles = ["Abba", "Aqua", "Bach", "Ñu", "2Pac"]
        let anchors = AlphabetIndex.anchors(titles, letter: { (t: String) in AlphabetIndex.letter(for: t) }, id: { AnyHashable($0) })
        XCTAssertEqual(anchors["A"], AnyHashable("Abba"))
        XCTAssertEqual(anchors["B"], AnyHashable("Bach"))
        XCTAssertEqual(anchors["Ñ"], AnyHashable("Ñu"))
        XCTAssertEqual(anchors["#"], AnyHashable("2Pac"))
        XCTAssertNil(anchors["C"])
    }

    func test_emptyLetterJumpsToNextThenPrevious() {
        let available: Set<String> = ["B", "M", "#"]
        XCTAssertEqual(AlphabetIndex.target(for: "B", in: available), "B")
        XCTAssertEqual(AlphabetIndex.target(for: "C", in: available), "M")
        XCTAssertEqual(AlphabetIndex.target(for: "N", in: available), "#")
        XCTAssertEqual(AlphabetIndex.target(for: "A", in: ["M"]), "M")
        XCTAssertEqual(AlphabetIndex.target(for: "Z", in: ["M"]), "M", "nothing after → previous")
    }
}
