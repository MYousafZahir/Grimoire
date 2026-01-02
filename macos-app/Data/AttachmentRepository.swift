import Foundation

protocol AttachmentRepository {
    func uploadImage(data: Data, filename: String, mimeType: String?) async throws -> String
}

enum AttachmentRepositoryError: Error, LocalizedError {
    case badStatus(Int, String?)
    case decoding
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let detail):
            if let detail, !detail.isEmpty { return "Request failed with status \(code): \(detail)" }
            return "Request failed with status \(code)"
        case .decoding:
            return "Failed to decode response"
        case .invalidURL:
            return "Invalid backend URL"
        }
    }
}

struct HTTPAttachmentRepository: AttachmentRepository {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://127.0.0.1:8000")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func uploadImage(data: Data, filename: String, mimeType: String?) async throws -> String {
        guard let url = URL(string: "attachments", relativeTo: baseURL) else {
            throw AttachmentRepositoryError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
        )
        if let mimeType, !mimeType.isEmpty {
            body.appendString("Content-Type: \(mimeType)\r\n")
        }
        body.appendString("\r\n")
        body.append(data)
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")

        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AttachmentRepositoryError.badStatus(-1, nil)
        }
        guard http.statusCode == 200 else {
            let detail = (try? JSONDecoder().decode(BackendErrorResponse.self, from: responseData).detail)
                ?? String(data: responseData, encoding: .utf8)
            throw AttachmentRepositoryError.badStatus(http.statusCode, detail)
        }

        struct UploadResponse: Codable {
            let url: String
        }
        guard let decoded = try? JSONDecoder().decode(UploadResponse.self, from: responseData) else {
            throw AttachmentRepositoryError.decoding
        }
        return decoded.url
    }
}

private struct BackendErrorResponse: Codable {
    let detail: String
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

