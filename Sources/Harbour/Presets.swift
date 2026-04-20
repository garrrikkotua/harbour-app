import Foundation

enum DomainPreset: String, CaseIterable, Identifiable {
    case socialMedia = "Social Media"
    case videoStreaming = "Video & Streaming"
    case newsForums = "News & Forums"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .socialMedia: return "bubble.left.and.bubble.right"
        case .videoStreaming: return "play.tv"
        case .newsForums: return "newspaper"
        }
    }

    var domains: [String] {
        switch self {
        case .socialMedia:
            return [
                "twitter.com", "x.com",
                "facebook.com", "instagram.com", "threads.net",
                "tiktok.com", "snapchat.com",
                "linkedin.com", "bsky.app", "mastodon.social",
            ]
        case .videoStreaming:
            // YouTube serves from dozens of subdomains on multiple CDNs:
            //   - youtube.com (site)
            //   - i.ytimg.com / s.ytimg.com (thumbnails, player JS)
            //   - yt3.ggpht.com / yt3.googleusercontent.com (avatars)
            //   - youtubei.googleapis.com (API)
            //   - *.googlevideo.com (actual video stream — wildcard, only
            //     catchable by blocking the apex)
            // /etc/hosts doesn't support wildcards, so anything behind
            // rrN.sn-XXX.googlevideo.com needs pfctl IP-layer blocking.
            return [
                "youtube.com", "m.youtube.com", "music.youtube.com",
                "tv.youtube.com", "studio.youtube.com",
                "youtube-nocookie.com", "youtu.be",
                "i.ytimg.com", "s.ytimg.com", "ytimg.com",
                "yt3.ggpht.com", "yt3.googleusercontent.com",
                "googlevideo.com", "youtubei.googleapis.com",
                "netflix.com", "nflxvideo.net",
                "twitch.tv",
                "hulu.com", "disneyplus.com", "hbomax.com", "max.com",
                "primevideo.com",
            ]
        case .newsForums:
            return [
                "reddit.com", "news.ycombinator.com",
                "9gag.com", "buzzfeed.com",
                "quora.com", "medium.com",
            ]
        }
    }
}
