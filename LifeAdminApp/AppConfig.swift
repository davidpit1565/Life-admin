import Foundation

enum AppConfig {
    // The deployed Gemini proxy (server/gemini-proxy.js via api/extract.js, see vercel.json).
    // The iOS app never talks to Gemini directly and never holds the API key.
    static let geminiProxyEndpoint = URL(string: "https://life-admin-puce.vercel.app/v1/extract")!
}
