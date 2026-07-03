import Foundation
import AdaptiveCore

/// Rung 2a transport: Parallel Search MCP over plain Streamable HTTP — keyless, no account,
/// no MCP framework (two request shapes don't justify a dependency; the codec lives in the
/// package). Session id is captured from `initialize` and cached; a 404 (expired session)
/// re-initializes once. **No secrets anywhere** — the CQ3 distribution constraint.
final class ParallelSearchClient: NutritionWebSearcher, @unchecked Sendable {
    private let lock = NSLock()
    private var sessionID: String?
    private var nextRequestID = 2

    func search(objective: String, queries: [String]) async throws -> [SearchExcerpt] {
        let session = try await ensureSession()
        let requestID: Int = {
            lock.lock(); defer { lock.unlock() }
            let id = nextRequestID
            nextRequestID += 1
            return id
        }()

        let body = ParallelSearchProtocol.webSearchRequest(objective: objective, queries: queries, id: requestID)
        let (data, response) = try await post(body, sessionID: session)

        // Session expired server-side → one re-initialize, one retry.
        if (response as? HTTPURLResponse)?.statusCode == 404 {
            lock.lock(); sessionID = nil; lock.unlock()
            let fresh = try await ensureSession()
            let (retryData, _) = try await post(body, sessionID: fresh)
            return try ParallelSearchProtocol.decodeExcerpts(retryData)
        }
        do {
            return try ParallelSearchProtocol.decodeExcerpts(data)
        } catch {
            // Undecodable body (observed on device: instant non-JSON refusals under a burst
            // of queries — the keyless tier rate-limiting). One breath, one fresh session,
            // one retry; a second failure falls through the ladder (never blocks the user).
            try await Task.sleep(for: .milliseconds(700))
            lock.lock(); sessionID = nil; lock.unlock()
            let fresh = try await ensureSession()
            let (retryData, _) = try await post(body, sessionID: fresh)
            return try ParallelSearchProtocol.decodeExcerpts(retryData)
        }
    }

    private func ensureSession() async throws -> String {
        lock.lock()
        let cached = sessionID
        lock.unlock()
        if let cached { return cached }

        let (_, response) = try await post(ParallelSearchProtocol.initializeRequest(), sessionID: nil)
        guard let http = response as? HTTPURLResponse,
              let id = http.value(forHTTPHeaderField: ParallelSearchProtocol.sessionHeader) else {
            throw URLError(.badServerResponse)
        }
        lock.lock()
        sessionID = id
        lock.unlock()
        return id
    }

    private func post(_ body: Data, sessionID: String?) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: ParallelSearchProtocol.endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: ParallelSearchProtocol.sessionHeader)
        }
        return try await URLSession.shared.data(for: request)
    }
}
