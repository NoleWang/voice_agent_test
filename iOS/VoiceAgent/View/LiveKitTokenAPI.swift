import Foundation

struct LiveKitTokenResponse: Decodable {
    let token: String
    let url: String?   // optional, if backend sends it
}

enum LiveKitTokenAPI {
//    static let baseURL = "http://127.0.0.1:8000"
    static let baseURL = "http://192.168.1.24:8000"
    static let path = "/livekit/token"

    static func fetchToken(room: String, identity: String, name: String) async throws -> LiveKitTokenResponse {
        guard let url = URL(string: baseURL + path) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = [
            "room": room,
            "identity": identity,
            "name": name
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "LiveKitTokenAPI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Token server error \(http.statusCode): \(body)"])
        }

        return try JSONDecoder().decode(LiveKitTokenResponse.self, from: data)
    }
}
