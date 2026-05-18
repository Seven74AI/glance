import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Mock URLProtocol for testing AI providers without real network calls.
public final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    // Swift 6: nonisolated(unsafe) for test-only mutable global state
    public nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    public enum MockError: Error {
        case noHandlerSet
    }

    public override class func canInit(with request: URLRequest) -> Bool { true }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: MockError.noHandlerSet)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    public override func stopLoading() {}

    public static func createMockSession(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        MockURLProtocol.requestHandler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    public static func makeResponse(url: URL, statusCode: Int, body: [String: Any], headers: [String: String]? = nil) -> (HTTPURLResponse, Data) {
        let data = try! JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
        return (response, data)
    }
}
