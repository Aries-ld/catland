import XCTest
@testable import Catland

final class FormatTests: XCTestCase {
    func testCount() {
        XCTAssertEqual(Format.count(999), "999")
        XCTAssertEqual(Format.count(12_345), "1.2万")
        XCTAssertEqual(Format.count(230_000_000), "2.3亿")
    }

    func testCaptionDedupesTitle() {
        XCTAssertEqual(Format.caption(title: "美女", text: "美女 大长腿 #美女[话题]#"), "美女 大长腿 #美女#")
        XCTAssertEqual(Format.caption(title: "标题", text: "正文"), "标题\n正文")
        XCTAssertEqual(Format.caption(title: nil, text: "正文"), "正文")
        XCTAssertEqual(Format.caption(title: "标题", text: nil), "标题")
    }

    func testAspectDefaultsToPortrait() throws {
        let json = #"{"key":"x:1","platform":"x","id":"1","url":"u","kind":"video","title":null,"text":null,"author":null,"createdAt":null,"cover":null,"stats":{"views":null,"likes":1,"comments":null,"collects":null,"shares":null},"video":{"url":"v","headers":{},"width":1920,"height":1080,"duration":3},"images":[],"expiresAt":0,"resolvedAt":0,"liked":true}"#
        let card = try JSONDecoder().decode(FeedCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.aspect, 1920.0 / 1080.0, accuracy: 0.001)
        XCTAssertEqual(card.liked, true)
        XCTAssertNil(card.collected)
    }
}

final class NotchGeometryTests: XCTestCase {
    func testActiveRectCentersOnScreenTop() {
        let g = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchSize: CGSize(width: 200, height: 32), hasNotch: true)
        let c = g.activeRect(expanded: false)
        XCTAssertEqual(c.midX, 756)
        XCTAssertEqual(c.maxY, 982)
        XCTAssertEqual(c.width, 290)
        XCTAssertEqual(g.activeRect(expanded: true).size, NotchGeometry.expandedSize)
    }
}
