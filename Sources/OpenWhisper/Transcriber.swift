import Foundation

/// Sends audio straight to OpenAI's transcription endpoint. No other servers involved.
enum Transcriber {
    static let models = ["gpt-transcribe", "gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"]

    static func transcribe(fileURL: URL, apiKey: String, model: String) async throws -> String {
        let boundary = "OpenWhisper-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        field("model", model)
        field("response_format", "json")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n")
        append("Content-Type: audio/m4a\r\n\r\n")
        body.append(try Data(contentsOf: fileURL))
        append("\r\n--\(boundary)--\r\n")

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            throw TranscriptionError.api(status: status, message: apiError?.error.message)
        }
        return try JSONDecoder().decode(TranscriptionResponse.self, from: data).text
    }

    private struct TranscriptionResponse: Decodable { let text: String }
    private struct APIErrorResponse: Decodable {
        struct Inner: Decodable { let message: String }
        let error: Inner
    }
}

enum TranscriptionError: LocalizedError {
    case api(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .api(401, _): return "Invalid OpenAI API key"
        case .api(429, _): return "OpenAI rate limit or quota hit"
        case let .api(status, message): return message ?? "OpenAI error \(status)"
        }
    }
}
