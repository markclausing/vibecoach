import Foundation

/// Protocol om netwerkverkeer (URLSession) abstract te maken voor TDD doeleinden
protocol NetworkSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// Conform de standaard URLSession aan dit protocol
extension URLSession: NetworkSession {}
