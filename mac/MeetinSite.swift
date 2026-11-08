import Foundation

// Adresse du site : https partout, http uniquement en local.
enum MeetinSite {
    static let defaultAddress = "https://meetin-os.vercel.app"

    static func baseURL(_ raw: String) -> URL? {
        guard let base = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = base.host, base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil, base.path.isEmpty || base.path == "/",
              base.scheme == "https" || (base.scheme == "http" && ["localhost", "127.0.0.1"].contains(host))
        else { return nil }
        return base
    }

    static func subscriptionURL(_ raw: String) -> URL? {
        guard let base = baseURL(raw), var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        parts.path = "/onboarding"
        parts.fragment = "subscription"
        return parts.url
    }
}
