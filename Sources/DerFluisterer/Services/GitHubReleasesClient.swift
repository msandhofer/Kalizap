import Foundation

public struct GitHubReleasesClient: Sendable {
    private let owner: String
    private let repo: String
    private let session: any HTTPDataSending

    public init(
        owner: String,
        repo: String,
        session: any HTTPDataSending = URLSession.shared
    ) {
        self.owner = owner
        self.repo = repo
        self.session = session
    }

    /// Liefert den Tag-Namen der neuesten Release, oder nil bei 404/Netzwerkfehler/Parse-Fehler.
    /// Fehler werden silent in nil uebersetzt (Ticket-Anforderung).
    public func fetchLatestReleaseTag() async throws -> String? {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                return nil
            }
            return tag
        } catch {
            return nil
        }
    }
}
