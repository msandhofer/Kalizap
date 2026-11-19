import Testing
import Foundation
@testable import Kalizap

@Suite("ClaudeModelResolver")
struct ClaudeModelResolverTests {

    private static let modelsJSON = Data("""
    {"data":[
      {"type":"model","id":"claude-opus-5-5","created_at":"2026-10-01T00:00:00Z"},
      {"type":"model","id":"claude-sonnet-5-5","created_at":"2026-09-01T00:00:00Z"},
      {"type":"model","id":"claude-haiku-5-5","created_at":"2026-08-01T00:00:00Z"},
      {"type":"model","id":"claude-sonnet-5","created_at":"2026-05-01T00:00:00Z"},
      {"type":"model","id":"claude-haiku-4-5-20251001","created_at":"2025-10-01T00:00:00Z"}
    ],"has_more":false}
    """.utf8)

    @Test("picks the newest model id of each family from the models list")
    func picksNewestPerFamily() throws {
        let ids = try ClaudeModelResolver.newestModelIDs(fromModelsResponse: Self.modelsJSON)
        #expect(ids[.haiku] == "claude-haiku-5-5")
        #expect(ids[.sonnet] == "claude-sonnet-5-5")
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "ClaudeModelResolverTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test("uses the built-in model id before anything was resolved")
    func fallsBackToBuiltIn() {
        let sut = ClaudeModelResolver(defaults: makeDefaults(), session: MockURLSession())
        #expect(sut.modelID(for: .haiku) == "claude-haiku-5-5")
        #expect(sut.modelID(for: .sonnet) == "claude-sonnet-5-5")
    }

    @Test("refresh resolves newest ids and remembers them across instances")
    func refreshResolvesAndPersists() async {
        let defaults = makeDefaults()
        let session = MockURLSession()
        session.responseData = Data("""
        {"data":[{"id":"claude-haiku-6","created_at":"2027-03-01T00:00:00Z"},
                 {"id":"claude-haiku-5-5","created_at":"2026-08-01T00:00:00Z"}]}
        """.utf8)

        await ClaudeModelResolver(defaults: defaults, session: session).refresh(apiKey: "k")

        let fresh = ClaudeModelResolver(defaults: defaults, session: MockURLSession())
        #expect(fresh.modelID(for: .haiku) == "claude-haiku-6")
        #expect(fresh.modelID(for: .sonnet) == "claude-sonnet-5-5")
    }

    @Test("failed refresh keeps the previously resolved id")
    func failedRefreshKeepsCache() async {
        let defaults = makeDefaults()
        let ok = MockURLSession()
        ok.responseData = Data(#"{"data":[{"id":"claude-haiku-6","created_at":"2027-03-01T00:00:00Z"}]}"#.utf8)
        await ClaudeModelResolver(defaults: defaults, session: ok).refresh(apiKey: "k")

        let failing = MockURLSession()
        failing.responseStatus = 401
        let sut = ClaudeModelResolver(defaults: defaults, session: failing)
        await sut.refresh(apiKey: "bad")

        #expect(sut.modelID(for: .haiku) == "claude-haiku-6")
    }
}
