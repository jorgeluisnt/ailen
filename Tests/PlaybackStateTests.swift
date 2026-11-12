import XCTest
@testable import Ailen

final class PlaybackStateTests: XCTestCase {

    func test_states_areDistinct() {
        let all: [PlayerManager.PlaybackState] = [.idle, .loading, .playing, .paused, .ended]
        for (i, a) in all.enumerated() {
            for (j, b) in all.enumerated() where i != j {
                XCTAssertNotEqual(a, b)
            }
        }
    }

    func test_state_equalsItself() {
        XCTAssertEqual(PlayerManager.PlaybackState.playing, .playing)
    }
}
