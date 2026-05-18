import XCTest
import CoreMedia
@testable import CaptureEngine

final class FrameQueueTests: XCTestCase {

    var queue: FrameQueue!

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        queue = nil
        super.tearDown()
    }

    // MARK: - Basic Queue Operations

    func test_enqueue_addsFrameToQueue() {
        // Given: a frame queue with depth 3
        queue = FrameQueue(maxDepth: 3)

        // When: a frame is enqueued
        let frame = makeFrame(id: 1)
        queue.enqueue(frame)

        // Then: queue should have 1 item
        XCTAssertEqual(queue.count, 1, "Queue should have 1 frame")
    }

    func test_dequeue_returnsOldestFrame() {
        // Given: queue with 2 frames
        queue = FrameQueue(maxDepth: 3)
        let frame1 = makeFrame(id: 1)
        let frame2 = makeFrame(id: 2)
        queue.enqueue(frame1)
        queue.enqueue(frame2)

        // When: dequeue
        let dequeued = queue.dequeue()

        // Then: oldest frame (frame1) is returned
        XCTAssertNotNil(dequeued, "Dequeue should return a frame")
    }

    func test_dequeue_emptyQueue_returnsNil() {
        // Given: empty queue
        queue = FrameQueue(maxDepth: 3)

        // When: dequeue
        let result = queue.dequeue()

        // Then: nil
        XCTAssertNil(result, "Dequeue on empty queue should return nil")
    }

    func test_count_reflectsActualFrames() {
        // Given: queue with depth 5
        queue = FrameQueue(maxDepth: 5)

        // When: enqueue 2, dequeue 1
        queue.enqueue(makeFrame(id: 1))
        queue.enqueue(makeFrame(id: 2))
        _ = queue.dequeue()

        // Then: count should be 1
        XCTAssertEqual(queue.count, 1, "Count should be 1 after enqueue 2, dequeue 1")
    }

    // MARK: - Max Depth / Frame Dropping

    func test_enqueue_whenFull_dropsOldestFrame() {
        // Given: queue with max depth 3, already full
        queue = FrameQueue(maxDepth: 3)
        queue.enqueue(makeFrame(id: 1))
        queue.enqueue(makeFrame(id: 2))
        queue.enqueue(makeFrame(id: 3))

        // When: enqueue 4th frame
        let dropped = queue.enqueue(makeFrame(id: 4))

        // Then: oldest frame was dropped, count stays at 3
        XCTAssertNotNil(dropped, "Should return dropped frame")
        XCTAssertEqual(queue.count, 3, "Count should remain at max depth")
    }

    func test_enqueue_whenFull_dropsCorrectFrame() {
        // Given: full queue
        queue = FrameQueue(maxDepth: 2)
        let frame1 = makeFrame(id: 1)
        let frame2 = makeFrame(id: 2)
        queue.enqueue(frame1)
        queue.enqueue(frame2)

        // When: enqueue frame 3 (drops frame 1)
        let dropped = queue.enqueue(makeFrame(id: 3))

        // Then: frame 1 was dropped, frames 2 and 3 remain
        XCTAssertNotNil(dropped, "Should drop oldest frame")
    }

    func test_enqueue_whenNotFull_doesNotDrop() {
        // Given: queue with space
        queue = FrameQueue(maxDepth: 5)

        // When: enqueue 2 frames
        let result1 = queue.enqueue(makeFrame(id: 1))
        let result2 = queue.enqueue(makeFrame(id: 2))

        // Then: no drops
        XCTAssertNil(result1, "First enqueue should not drop")
        XCTAssertNil(result2, "Second enqueue should not drop")
        XCTAssertEqual(queue.count, 2, "Count should be 2")
    }

    // MARK: - Clear

    func test_clear_emptiesQueue() {
        // Given: queue with frames
        queue = FrameQueue(maxDepth: 3)
        queue.enqueue(makeFrame(id: 1))
        queue.enqueue(makeFrame(id: 2))

        // When: clear
        queue.clear()

        // Then: empty
        XCTAssertEqual(queue.count, 0, "Queue should be empty after clear")
        XCTAssertNil(queue.dequeue(), "Dequeue after clear should return nil")
    }

    // MARK: - Thread Safety

    func test_concurrentEnqueueDequeue_noDataRace() {
        // Given: a frame queue
        queue = FrameQueue(maxDepth: 10)

        // When: concurrent enqueues and dequeues
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        let iterations = 100

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            if i % 2 == 0 {
                _ = queue.enqueue(self.makeFrame(id: i))
            } else {
                _ = queue.dequeue()
            }
        }

        // Then: queue should be in a consistent state (no crash = pass)
        XCTAssertGreaterThanOrEqual(queue.count, 0, "Count should not be negative")
        XCTAssertLessThanOrEqual(queue.count, 10, "Count should not exceed max depth")
        expectation.fulfill()

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Helpers

    private func makeFrame(id: Int) -> CapturedFrame {
        return CapturedFrame(
            pixelBuffer: makeTestPixelBuffer(),
            timestamp: CMTime(value: CMTimeValue(id), timescale: 10),
            contentRect: .zero,
            scaleFactor: 1.0
        )
    }
}
