import Foundation

/// A failed Supabase call with a message that is safe to show.
struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

/// Minimal REST client for Supabase Auth and the database. No SDK needed.
struct SupabaseAPI {
    private let base = URL(string: Secrets.supabaseURL)!
    private let key = Secrets.supabasePublishableKey

    func send(
        _ path: String,
        method: String = "GET",
        query: [String: String] = [:],
        body: Encodable? = nil,
        token: String? = nil,
        headers: [String: String] = [:]
    ) async throws -> Data {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token ?? key)", forHTTPHeaderField: "Authorization")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError(status: 0, message: "Can't reach Lapsy right now. Check your connection.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError(status: status, message: Self.friendly(data, status: status))
        }
        return data
    }

    private static func friendly(_ data: Data, status: Int) -> String {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let raw = (object?["msg"] ?? object?["error_description"] ?? object?["message"] ?? object?["error"]) as? String ?? ""
        let lower = raw.lowercased()
        if lower.contains("invalid login") { return "Wrong email or password." }
        if lower.contains("not confirmed") { return "Confirm your email first. Check your inbox for the link." }
        if lower.contains("already registered") || lower.contains("already been registered") {
            return "That email already has an account. Try signing in."
        }
        if lower.contains("password") && lower.contains("character") { return "Use a longer password (at least 8 characters)." }
        if lower.contains("rate limit") || status == 429 { return "Too many tries. Wait a minute and try again." }
        if lower.contains("valid email") || lower.contains("invalid format") { return "That email doesn't look right." }
        if lower.contains("relation") && lower.contains("does not exist") {
            return "The database isn't set up yet. Run the SQL file in Supabase first."
        }
        return raw.isEmpty ? "Something went wrong (\(status)). Try again." : raw
    }
}

private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
