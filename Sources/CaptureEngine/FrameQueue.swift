import Foundation
import CoreMedia

/// Thread-safe fixed-size queue with automatic oldest-frame dropping.
/// Used in the capture pipeline to prevent backpressure from slow frame processing.
final class FrameQueue {

    /// Maximum number of frames to hold before dropping oldest
    private let maxDepth: Int

    /// Queue storage with thread-safe access
    private var frames: [CapturedFrame] = []
    private let lock = NSLock()

    /// Number of frames currently in the queue
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return frames.count
    }

    /// Whether the queue is at capacity
    var isFull: Bool {
        lock.lock()
        defer { lock.unlock() }
        return frames.count >= maxDepth
    }

    /// Initializes a frame queue with a maximum depth.
    /// - Parameter maxDepth: Maximum frames to hold (default 3, per SCK best practices).
    init(maxDepth: Int = 3) {
        self.maxDepth = max(1, maxDepth)
    }

    /// Adds a frame to the queue. If the queue is full, the oldest frame is dropped.
    /// - Parameter frame: The captured frame to enqueue.
    /// - Returns: The dropped frame if the queue was full, nil otherwise.
    @discardableResult
    func enqueue(_ frame: CapturedFrame) -> CapturedFrame? {
        lock.lock()
        defer { lock.unlock() }

        var dropped: CapturedFrame? = nil

        if frames.count >= maxDepth {
            dropped = frames.removeFirst()
        }

        frames.append(frame)
        return dropped
    }

    /// Removes and returns the oldest frame from the queue.
    /// - Returns: The oldest frame, or nil if the queue is empty.
    func dequeue() -> CapturedFrame? {
        lock.lock()
        defer { lock.unlock() }

        guard !frames.isEmpty else { return nil }
        return frames.removeFirst()
    }

    /// Removes all frames from the queue.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        frames.removeAll()
    }
}

// MARK: - CapturedFrame

/// A captured frame containing pixel data and metadata.
struct CapturedFrame {
    let pixelBuffer: CVPixelBuffer
    let timestamp: CMTime
    let contentRect: CGRect
    let scaleFactor: CGFloat
}
