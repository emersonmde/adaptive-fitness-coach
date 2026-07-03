import Foundation

/// Parallel Search MCP (search.parallel.ai/mcp) — the keyless web-search rung (CQ3b).
/// Pure JSON-RPC codec: request builders and response decoding live here (fixture-testable);
/// the Streamable-HTTP transport (POST, `Mcp-Session-Id` echo, SSE-vs-JSON bodies) is the
/// thin phone-side client. We speak plain JSON-RPC rather than pulling in an MCP framework —
/// two request shapes and one response shape don't justify a dependency.
public enum ParallelSearchProtocol {

    public static let endpoint = URL(string: "https://search.parallel.ai/mcp")!
    public static let sessionHeader = "Mcp-Session-Id"

    // MARK: - Requests

    public static func initializeRequest(id: Int = 1) -> Data {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-03-26",
                "capabilities": [:] as [String: Any],
                "clientInfo": ["name": "adaptive-fitness-coach", "version": "1.0"],
            ],
        ]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    public static func webSearchRequest(objective: String, queries: [String], id: Int) -> Data {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "tools/call",
            "params": [
                "name": "web_search",
                "arguments": [
                    "objective": objective,
                    "search_queries": queries,
                ] as [String: Any],
            ] as [String: Any],
        ]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    // MARK: - Responses

    public enum DecodeError: Error, Equatable {
        case notJSONRPC
        case rpcError(String)
        case unexpectedShape
    }

    /// Accepts either a plain JSON body or an SSE stream (`data: {...}` lines) — the server
    /// chooses per request; the codec shouldn't care. SSE is detected by line structure
    /// (a line *starting* with `data:` or `event:`), never by substring — a JSON body may
    /// legitimately contain "data:" inside a string.
    public static func extractJSONRPCBody(_ raw: Data) -> Data {
        guard let text = String(data: raw, encoding: .utf8) else { return raw }
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.contains(where: { $0.hasPrefix("data:") || $0.hasPrefix("event:") }) else {
            return raw
        }
        // SSE: each event's payload is one `data:` line; the final one carries the result.
        let dataLines = lines
            .filter { $0.hasPrefix("data:") }
            .map { $0.dropFirst("data:".count).trimmingCharacters(in: .whitespaces) }
        if let last = dataLines.last, let data = last.data(using: .utf8) {
            return data
        }
        return raw
    }

    /// Decodes a `tools/call web_search` response into excerpts. The tool returns its payload
    /// as JSON *text* inside `result.content[0].text` (MCP convention), so this parses twice.
    public static func decodeExcerpts(_ raw: Data) throws -> [SearchExcerpt] {
        let body = extractJSONRPCBody(raw)
        guard let envelope = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw DecodeError.notJSONRPC
        }
        if let error = envelope["error"] as? [String: Any] {
            throw DecodeError.rpcError((error["message"] as? String) ?? "unknown RPC error")
        }
        guard let result = envelope["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String,
              let payload = text.data(using: .utf8),
              let search = try? JSONDecoder().decode(SearchPayload.self, from: payload) else {
            throw DecodeError.unexpectedShape
        }
        return search.results.map { hit in
            SearchExcerpt(
                title: hit.title ?? hit.url ?? "untitled",
                url: hit.url.flatMap(URL.init(string:)),
                excerpt: hit.excerpts?.joined(separator: "\n") ?? ""
            )
        }
    }

    private struct SearchPayload: Decodable {
        var results: [Hit]
        struct Hit: Decodable {
            var url: String?
            var title: String?
            var excerpts: [String]?
        }
    }
}
