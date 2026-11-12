import Foundation

// Minimal Spotify Web API client (no third-party libraries). Only endpoints
// still available to Development Mode apps (Feb 2026 rules) are used.

struct SpotifyImage: Decodable, Hashable { let url: String }
struct SpotifyArtistRef: Decodable, Hashable { let name: String }
struct SpotifyCount: Decodable, Hashable { let total: Int }
struct SpotifyUser: Decodable, Hashable { let id: String; let display_name: String? }

struct SpotifyAlbum: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let images: [SpotifyImage]?
    let artists: [SpotifyArtistRef]?
    var imageURL: URL? { images?.first.flatMap { URL(string: $0.url) } }
    var artistNames: String { (artists ?? []).map(\.name).joined(separator: ", ") }
}

struct SpotifyTrack: Decodable, Identifiable, Hashable {
    let id: String?
    let name: String
    let uri: String
    let duration_ms: Int?
    let artists: [SpotifyArtistRef]?
    let album: SpotifyAlbum?
    var stableID: String { id ?? uri }
    var artistNames: String { (artists ?? []).map(\.name).joined(separator: ", ") }
    var imageURL: URL? { album?.imageURL }
}

struct SpotifyPlaylist: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let images: [SpotifyImage]?
    let owner: SpotifyUser?
    let collaborative: Bool?
    /// The track count moved from `tracks` to `items` in 2026; read either.
    let tracks: SpotifyCount?
    let items: SpotifyCount?
    var imageURL: URL? { images?.first.flatMap { URL(string: $0.url) } }
    var count: Int? { items?.total ?? tracks?.total }
}

struct SpotifyPage<Item: Decodable>: Decodable {
    let items: [Item]
    let next: String?
    let total: Int?
}

/// Search results: playlists can come back as `null` entries.
struct SpotifySearchResponse: Decodable {
    let tracks: SpotifyPage<SpotifyTrack>?
    let albums: SpotifyPage<SpotifyAlbum>?
    let playlists: SpotifyPage<SpotifyPlaylist?>?
}

/// A playlist entry or saved track: the track sits under `track` (old) or
/// `item` (2026 `/items` endpoints).
struct SpotifyTrackEntry: Decodable {
    let track: SpotifyTrack?
    let item: SpotifyTrack?
    var value: SpotifyTrack? { item ?? track }
}

enum SpotifyAPIError: Error, Equatable {
    case notSignedIn, unauthorized, forbidden, notFound, rateLimited(retryAfter: Int?), http(Int), decoding

    var message: String {
        switch self {
        case .notSignedIn, .unauthorized: return "Tu sesión de Spotify caducó. Vuelve a conectar."
        case .forbidden: return "Spotify no permite esto a las apps en modo desarrollo."
        case .notFound: return "Spotify no encontró ese contenido."
        case .rateLimited(let seconds):
            return "Spotify pide esperar un momento" + (seconds.map { " (\($0) s)" } ?? "") + " antes de volver a intentarlo."
        case .http(let code): return "Spotify respondió con un error (\(code))."
        case .decoding: return "No se pudo leer la respuesta de Spotify."
        }
    }

    static func from(status: Int, retryAfter: String?) -> SpotifyAPIError? {
        switch status {
        case 200..<300: return nil
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 429: return .rateLimited(retryAfter: retryAfter.flatMap(Int.init))
        default: return .http(status)
        }
    }
}

struct SpotifyWebAPI {
    static let base = URL(string: "https://api.spotify.com/v1/")!
    /// Development Mode caps search at 10 results per page.
    static let searchLimit = 10

    /// Current token, and a forced renewal for a 401.
    let token: () async -> String?
    let renewedToken: () async -> String?
    var session: URLSession = .shared

    static func searchURL(query: String, offset: Int = 0) -> URL {
        var components = URLComponents(url: base.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track,album,playlist"),
            URLQueryItem(name: "limit", value: String(searchLimit)),
            URLQueryItem(name: "offset", value: String(max(0, offset))),
        ]
        return components.url!
    }

    func me() async throws -> SpotifyUser {
        try await get(Self.base.appendingPathComponent("me"))
    }

    /// All the user's playlists (followed and own), 50 per page.
    func myPlaylists() async throws -> [SpotifyPlaylist] {
        var url: URL? = URL(string: "me/playlists?limit=50", relativeTo: Self.base)
        var all: [SpotifyPlaylist] = []
        while let next = url, all.count < 500 {
            let page: SpotifyPage<SpotifyPlaylist> = try await get(next)
            all += page.items
            url = page.next.flatMap(URL.init(string:))
        }
        return all
    }

    /// Tracks of an own or collaborative playlist (Spotify refuses others).
    func playlistTracks(_ id: String) async throws -> [SpotifyTrack] {
        let page: SpotifyPage<SpotifyTrackEntry> = try await get(
            URL(string: "playlists/\(id)/items?limit=100", relativeTo: Self.base)!)
        return page.items.compactMap(\.value)
    }

    /// "Tus me gusta". May be unavailable in Development Mode (→ `.forbidden`).
    func savedTracks() async throws -> [SpotifyTrack] {
        let page: SpotifyPage<SpotifyTrackEntry> = try await get(
            URL(string: "me/tracks?limit=50", relativeTo: Self.base)!)
        return page.items.compactMap(\.value)
    }

    func search(_ query: String, offset: Int = 0) async throws -> SpotifySearchResponse {
        try await get(Self.searchURL(query: query, offset: offset))
    }

    /// Saves tracks or albums (by URI) to the user's library.
    func saveToLibrary(uris: [String]) async throws {
        var components = URLComponents(url: Self.base.appendingPathComponent("me/library"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "uris", value: uris.joined(separator: ","))]
        _ = try await send(components.url!, method: "PUT")
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let data = try await send(url, method: "GET")
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw SpotifyAPIError.decoding }
    }

    /// One retry with a renewed token after a 401.
    private func send(_ url: URL, method: String) async throws -> Data {
        guard let first = await token() else { throw SpotifyAPIError.notSignedIn }
        let (data, status, retry) = try await perform(url, method: method, token: first)
        if status == 401, let renewed = await renewedToken() {
            let (data, status, retry) = try await perform(url, method: method, token: renewed)
            if let error = SpotifyAPIError.from(status: status, retryAfter: retry) { throw error }
            return data
        }
        if let error = SpotifyAPIError.from(status: status, retryAfter: retry) { throw error }
        return data
    }

    private func perform(_ url: URL, method: String, token: String) async throws -> (Data, Int, String?) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        return (data, http?.statusCode ?? 0, http?.value(forHTTPHeaderField: "Retry-After"))
    }
}
