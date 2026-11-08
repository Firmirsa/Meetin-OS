import Foundation

private final class BillingStub: URLProtocol {
    static var responseURL = "https://checkout.stripe.com/c/pay/test"
    static var status = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        precondition(request.url?.absoluteString == "https://fixture.invalid/api/account-billing")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        let body = Self.status == 200
            ? ["url": Self.responseURL]
            : ["error": "Session expirée"]
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONEncoder().encode(body))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main
struct BillingClientSmoke {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BillingStub.self]
        let client = AccountClient(baseURL: URL(string: "https://fixture.invalid")!,
                                   http: URLSession(configuration: configuration))
        for (manage, official) in [(false, "https://checkout.stripe.com/c/pay/test"),
                                   (true, "https://billing.stripe.com/p/session/test")] {
            BillingStub.responseURL = official
            let result = try await client.billing("fixture", manage: manage)
            precondition(result.absoluteString == official)
            for rejected in ["http://checkout.stripe.com/pay", "https://checkout.stripe.com.evil.test/pay",
                             "https://user@checkout.stripe.com/pay", "https://checkout.stripe.com:443/pay",
                             manage ? "https://checkout.stripe.com/pay" : "https://billing.stripe.com/pay"] {
                BillingStub.responseURL = rejected
                do {
                    _ = try await client.billing("fixture", manage: manage)
                    fatalError("Unsafe Stripe URL accepted")
                } catch let failure as AccountClient.Failure {
                    precondition(failure.message == "Le lien Stripe est invalide.")
                }
            }
        }
        BillingStub.status = 401
        do {
            _ = try await client.billing("fixture", manage: false)
            fatalError("401 accepted")
        } catch let failure as AccountClient.Failure {
            precondition(failure.status == 401)
        }
        let quota = try JSONDecoder().decode(AccountSummary.self, from: Data(
            #"{"email":"fixture@example.test","plan":"free","limitMs":900000,"remainingMs":600000,"resetsAt":"2026-12-01","checkoutAvailable":false,"canManageBilling":false}"#.utf8))
        precondition(quota.planName == "Gratuit" && !quota.checkoutAvailable && !quota.canManageBilling)
        print("Billing client smoke passed (simulated responses only).")
    }
}
