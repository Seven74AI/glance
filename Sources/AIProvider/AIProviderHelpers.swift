import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Image Format Detection

/// Image format for transport encoding selection.
public enum ImageFormat: Sendable {
    case png
    case jpeg
}

/// Detect image format from magic bytes at the start of the data.
/// - Parameter data: Image data to inspect.
/// - Returns: `.png` if the PNG signature is detected, `.jpeg` otherwise.
public func detectImageFormat(_ data: Data) -> ImageFormat {
    guard data.count >= 4 else { return .jpeg }
    // PNG magic bytes: 0x89 0x50 0x4E 0x47
    if data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 {
        return .png
    }
    return .jpeg
}

// MARK: - Response Validation

/// Validate an HTTP response, throwing `ProviderError` for non-200 status codes.
/// - Parameters:
///   - response: The HTTP response to validate.
///   - data: Response body data for error message extraction.
/// - Throws: `ProviderError` on non-200 status codes.
public func validateResponse(_ response: HTTPURLResponse, data: Data) throws {
    switch response.statusCode {
    case 200:
        return
    case 401, 403:
        let message = parseErrorMessage(data)
        throw ProviderError.unauthorized(message ?? "Authentication failed (HTTP \(response.statusCode))")
    case 429:
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
        throw ProviderError.rateLimited(retryAfterSeconds: retryAfter)
    case 400..<500:
        let message = parseErrorMessage(data)
        throw ProviderError.serverError(statusCode: response.statusCode, message: message)
    default:
        let message = parseErrorMessage(data)
        throw ProviderError.serverError(statusCode: response.statusCode, message: message)
    }
}

// MARK: - Error Message Parsing

/// Extract an error message from a JSON error response body.
/// Supports the common `{"error": {"message": "..."}}` format used by
/// Anthropic, OpenAI, and Gemini APIs.
/// - Parameter data: Response body data.
/// - Returns: The error message string, or nil if it couldn't be extracted.
public func parseErrorMessage(_ data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let error = json["error"] as? [String: Any],
          let message = error["message"] as? String else {
        return nil
    }
    return message
}

// MARK: - Timeout

/// Execute an async operation with a timeout.
///
/// Wraps the operation in a `ThrowingTaskGroup` with a competing sleep task.
/// Uses `withTaskCancellationHandler` to propagate cancellation to the
/// underlying task (e.g., `URLSession.data(for:)`), so in-flight network
/// requests are properly cancelled on timeout rather than leaking to
/// completion.
///
/// - Parameters:
///   - seconds: Timeout duration in seconds.
///   - operation: The async throwing operation to execute.
/// - Returns: The operation's result.
/// - Throws: `ProviderError.networkTimeout` if the operation doesn't complete
///   within the timeout, or any error thrown by the operation itself.
public func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await withTaskCancellationHandler {
                try await operation()
            } onCancel: {
                // Task cancellation propagates to URLSession.data(for:)
                // via Swift concurrency runtime, cancelling the in-flight
                // request rather than leaking it to completion.
            }
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw ProviderError.networkTimeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
