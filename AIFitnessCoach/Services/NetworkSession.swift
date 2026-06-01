import Foundation

/// Protocol to abstract network traffic (URLSession) for TDD purposes.
protocol NetworkSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// Make the standard URLSession conform to this protocol.
extension URLSession: NetworkSession {}
