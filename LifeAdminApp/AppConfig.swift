import Foundation

enum AppConfig {
    // The deployed Gemini proxy (server/gemini-proxy.js via api/extract.js, see vercel.json).
    // The iOS app never talks to Gemini directly and never holds the API key.
    static let geminiProxyEndpoint = URL(string: "https://life-admin-puce.vercel.app/v1/extract")!

    // Optional, sent as X-App-Secret to the proxy. Not a real secret — anything shipped in the
    // app binary can be extracted with `strings` — but it blocks scripted abuse of a public
    // endpoint that forwards to a paid API key. nil until a matching APP_SHARED_SECRET is also
    // set in the Vercel project's environment variables; see docs/GEMINI_CONFIGURATION.md.
    static let geminiProxySharedSecret: String? = nil
}
