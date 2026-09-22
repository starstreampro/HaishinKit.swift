import Combine
import Foundation
import HaishinKit
import libsrt

struct SRTSocketURL {
    static let defaultPort: Int = 9710

    /// Query items in the order they appear in the URL (duplicates kept).
    private static func getQueryItems(_ url: URL) -> [(key: String, value: String)] {
        let url = url.absoluteString
        if !url.contains("?") {
            return []
        }
        let queryString = url.split(separator: "?")[1]
        let queries = queryString.split(separator: "&")
        var items: [(key: String, value: String)] = []
        for q in queries {
            let query = q.split(separator: "=", maxSplits: 1)
            if query.count == 2 {
                items.append((key: String(query[0]), value: String(query[1])))
            }
        }
        return items
    }

    /// Query items keyed by name (last occurrence wins), for single-value lookups.
    private static func getQueryDictionary(_ url: URL) -> [String: String] {
        var dictionary: [String: String] = [:]
        for item in getQueryItems(url) {
            dictionary[item.key] = item.value
        }
        return dictionary
    }

    /// Returns the options in the order they must be applied to a socket.
    ///
    /// `SRTO_TRANSTYPE` resets libsrt's preset group (latency, peerlatency, rcvlatency,
    /// tlpktdrop, snddropdelay, messageapi, nakreport, payloadsize, linger, congestion)
    /// to the transtype's defaults, so it has to be applied before any of them. Everything
    /// else keeps the order it was written in the URL, which is what srt-live-transmit
    /// and ffmpeg do as well.
    static func applyOrder(_ options: [SRTSocketOption]) -> [SRTSocketOption] {
        let transtype = options.filter { $0.name == .transtype }
        let others = options.filter { $0.name != .transtype }
        return transtype + others
    }

    let url: URL
    let mode: SRTMode
    let options: [SRTSocketOption]

    var remote: sockaddr_in? {
        guard let host = url.host else {
            return nil
        }
        return .init(host, port: url.port ?? Self.defaultPort)
    }

    var local: sockaddr_in? {
        let queryItems = Self.getQueryDictionary(url)
        let adapter = queryItems["adapter"] ?? "0.0.0.0"
        if let port = queryItems["port"] {
            return .init(adapter, port: Int(port) ?? url.port ?? Self.defaultPort)
        }
        return .init(adapter, port: url.port ?? Self.defaultPort)
    }

    init?(_ url: URL?) {
        guard let url, let scheme = url.scheme, scheme == "srt" else {
            return nil
        }
        var options: [SRTSocketOption] = []
        for item in Self.getQueryItems(url) {
            guard let name = SRTSocketOption.Name(rawValue: item.key) else {
                continue
            }
            if let option = try? SRTSocketOption(name: name, value: item.value) {
                options.append(option)
            }
        }
        let queryItems = Self.getQueryDictionary(url)
        self.url = url
        self.mode = {
            switch queryItems["mode"] {
            case "client", "caller":
                return .caller
            case "server", "listener":
                return .listener
            case "rendezvous":
                return .rendezvous
            default:
                if queryItems["adapter"] != nil {
                    return .rendezvous
                }
                if url.host?.isEmpty == true {
                    return .listener
                }
                return .caller
            }
        }()
        self.options = Self.applyOrder(options)
    }
}
