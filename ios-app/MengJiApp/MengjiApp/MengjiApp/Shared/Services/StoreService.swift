import Foundation
import Combine
import StoreKit

@MainActor
final class StoreService: ObservableObject {
    static let shared = StoreService()

    @Published private(set) var product: Product?
    @Published private(set) var isLoading = false

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [APIConfig.iapProductId])
            product = products.first
        } catch {
            print("StoreKit load failed:", error)
        }
    }

    func purchase() async throws -> String {
        if product == nil { await loadProduct() }
        guard let product else { throw APIError.server("无法加载内购商品") }

        isLoading = true
        defer { isLoading = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            let jws = String(data: transaction.jsonRepresentation, encoding: .utf8) ?? ""
            await transaction.finish()
            return jws
        case .userCancelled:
            throw APIError.server("已取消购买")
        case .pending:
            throw APIError.server("购买待处理")
        @unknown default:
            throw APIError.server("购买失败")
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw APIError.server("交易验证失败")
        case .verified(let safe):
            return safe
        }
    }

    var displayPrice: String {
        product?.displayPrice ?? "¥8"
    }
}
