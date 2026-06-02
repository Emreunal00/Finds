


import Foundation
import XCTest
@testable import FindsApp

class ChatBasicTests: XCTestCase {
    func testAddChatMessage() {
        var messages: [ChatMessage] = []
        let msg = ChatMessage(text: "merhaba", isMe: true, date: Date())
        messages.append(msg)
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].isMe)
    }
}
