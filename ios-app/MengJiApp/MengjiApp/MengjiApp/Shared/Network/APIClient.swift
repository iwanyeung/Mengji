import Foundation

enum APIConfig {
    /// 优先级：Scheme 环境变量 > Info.plist（Debug 由 Config/Debug.xcconfig 注入）> 默认
    static let baseURL: URL = {
        let url: URL
        if let env = ProcessInfo.processInfo.environment["MENGJI_API_BASE"],
           let parsed = URL(string: env), !env.isEmpty {
            url = parsed
        } else if let plist = Bundle.main.infoDictionary?["MENGJI_API_BASE"] as? String,
                  let parsed = URL(string: plist), !plist.isEmpty {
            url = parsed
        } else {
            #if targetEnvironment(simulator)
            url = URL(string: "http://127.0.0.1:3000")!
            #elseif DEBUG
            // 内测 Staging（CVM）；上架后由 Info.plist / Release 构建覆盖为正式域名
            url = URL(string: "http://49.233.91.206")!
            #else
            url = URL(string: "https://api.mengji.app")!
            #endif
        }
        print("[Mengji] API baseURL =", url.absoluteString)
        return url
    }()

    static let iapProductId = "com.mengji.visual.four_panel_once"
}

enum APIError: LocalizedError {
    case unauthorized
    case paymentRequired(productId: String)
    case server(String)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "请先登录"
        case .paymentRequired: return "需要购买后继续"
        case .server(let msg): return msg
        case .network(let err): return Self.userFacingNetworkMessage(err)
        }
    }

    private static func userFacingNetworkMessage(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain,
           ns.code == NSURLErrorCannotFindHost || ns.code == NSURLErrorDNSLookupFailed {
            return "无法连接梦悸服务器，请检查网络；内测包应使用已配置的后端地址"
        }
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorNotConnectedToInternet {
            return "当前无网络连接，请稍后重试"
        }
        return error.localizedDescription
    }
}

private struct APIPaymentErrorBody: Decodable {
    let productId: String?
}

private struct APIServerErrorBody: Decodable {
    let error: String?
}

struct APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        session = URLSession.shared
        decoder = JSONDecoder()
    }

    var authToken: String? {
        get { Self.authToken }
        set { Self.authToken = newValue }
    }

    static var authToken: String? {
        get { UserDefaults.standard.string(forKey: "mengji.api.token") }
        set { UserDefaults.standard.set(newValue, forKey: "mengji.api.token") }
    }

    static func clearAuthToken() {
        UserDefaults.standard.removeObject(forKey: "mengji.api.token")
    }

    func clearAuthToken() {
        Self.clearAuthToken()
    }

    func request<T: Decodable>(
        _ method: String,
        path: String,
        body: Encodable? = nil,
        query: [URLQueryItem] = []
    ) async throws -> T {
        var components = URLComponents(url: APIConfig.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.server("无效 URL") }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.server("无效响应")
        }

        if http.statusCode == 401 { throw APIError.unauthorized }
        if http.statusCode == 402 {
            let pe = try? decoder.decode(APIPaymentErrorBody.self, from: data)
            throw APIError.paymentRequired(productId: pe?.productId ?? APIConfig.iapProductId)
        }
        if http.statusCode >= 400 {
            let msg = (try? decoder.decode(APIServerErrorBody.self, from: data))?.error ?? "请求失败 (\(http.statusCode))"
            throw APIError.server(msg)
        }

        return try decoder.decode(T.self, from: data)
    }

    func uploadSegment(
        dreamId: UUID,
        index: Int,
        deviceTranscript: String,
        audioFileURL: URL?
    ) async throws {
        let components = URLComponents(url: APIConfig.baseURL.appendingPathComponent("api/dreams/\(dreamId.uuidString.lowercased())/segments"), resolvingAgainstBaseURL: false)!
        guard let url = components.url else { throw APIError.server("无效 URL") }

        let boundary = UUID().uuidString
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("index", "\(index)")
        appendField("deviceTranscript", deviceTranscript)

        if let audioFileURL, let audioData = try? Data(contentsOf: audioFileURL) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"segment.m4a\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw APIError.server("上传分段失败")
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    init(_ wrapped: Encodable) {
        encode = wrapped.encode
    }
    func encode(to encoder: Encoder) throws { try encode(encoder) }
}
