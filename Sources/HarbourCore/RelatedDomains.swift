import Foundation

/// Expands blocked domains into the exact hostnames written to /etc/hosts.
///
/// /etc/hosts has no wildcards, so blocking `x.com` alone leaves `mobile.x.com`
/// reachable, and a page the browser restores from its own cache (a service
/// worker keeps the X app shell offline) still loads its scripts and images
/// from `twimg.com`. Each blocked domain therefore also covers:
///   - its `www.` form, as before;
///   - the `m.` and `mobile.` sites, for a registrable domain;
///   - for well-known sites, the sibling sites and content hosts it runs on.
///
/// Companions are only hosts that serve that one service, never a shared CDN
/// or a link shortener other sites use, so blocking them can't break a site the
/// user didn't block. They only reach /etc/hosts; IP rules stay limited to the
/// domains the user entered.
public enum RelatedDomains {

    struct Companions {
        /// Other names people open the same site under; visits count as
        /// attempts on the blocked entry.
        var sites: [String] = []
        /// Hosts the site's pages load data, scripts and media from. Blocked,
        /// but never counted: one cached page fetches dozens of them.
        var assets: [String] = []
    }

    private static let x = Companions(
        sites: ["x.com", "twitter.com", "mobile.twitter.com"],
        assets: ["api.x.com", "api.twitter.com",
                 "abs.twimg.com", "abs-0.twimg.com", "pbs.twimg.com",
                 "video.twimg.com", "ton.twimg.com"]
    )

    private static let threads = Companions(sites: ["threads.net", "threads.com"])

    /// Keyed by the bare domain the user blocks.
    static let companions: [String: Companions] = [
        "x.com": x,
        "twitter.com": x,
        "youtube.com": Companions(
            sites: ["youtu.be", "music.youtube.com"],
            assets: ["youtubei.googleapis.com", "i.ytimg.com", "s.ytimg.com", "yt3.ggpht.com"]
        ),
        "reddit.com": Companions(
            sites: ["old.reddit.com", "new.reddit.com", "redd.it"],
            assets: ["gql.reddit.com", "oauth.reddit.com", "i.redd.it", "v.redd.it",
                     "preview.redd.it", "external-preview.redd.it",
                     "www.redditstatic.com", "styles.redditmedia.com"]
        ),
        "instagram.com": Companions(
            assets: ["i.instagram.com", "static.cdninstagram.com", "scontent.cdninstagram.com"]
        ),
        "facebook.com": Companions(sites: ["web.facebook.com", "fb.com"]),
        "threads.net": threads,
        "threads.com": threads,
        "tiktok.com": Companions(sites: ["vm.tiktok.com", "vt.tiktok.com"]),
        "linkedin.com": Companions(assets: ["static.licdn.com", "media.licdn.com"]),
        "twitch.tv": Companions(assets: ["gql.twitch.tv", "static.twitchcdn.net"]),
    ]

    /// Hosts that only serve data, scripts or media for a site, never a page
    /// someone opens: every companion asset plus those the presets list
    /// explicitly (DomainPreset.videoStreaming). Blocked like any entry, but
    /// a request for one is never counted as an attempt.
    public static let assetHosts: Set<String> = Set(companions.values.flatMap(\.assets)).union([
        "ytimg.com", "i.ytimg.com", "s.ytimg.com",
        "yt3.ggpht.com", "yt3.googleusercontent.com",
        "googlevideo.com", "youtubei.googleapis.com",
        "nflxvideo.net",
    ])

    /// Exact hostnames to block for `domains`, sorted and deduplicated.
    /// Unsafe entries are dropped. With `includeRelated: false` only the bare
    /// and `www.` forms are produced (used for the secure DNS endpoints).
    public static func hostnames(for domains: [String], includeRelated: Bool = true) -> [String] {
        var names = Set<String>()
        for domain in domains {
            guard let bare = bareDomain(domain) else { continue }
            names.insert(bare)
            names.insert("www.\(bare)")
            guard includeRelated else { continue }
            names.formUnion(siteHostnames(forBare: bare))
            names.formUnion(companions[bare]?.assets ?? [])
        }
        return names.filter { DomainValidation.isSafeDomain($0) }.sorted()
    }

    /// The names a person can visit a blocked entry's site under: bare and
    /// `www.`, mobile sites, and sibling sites (with their `www.` forms).
    /// Asset hosts are not included. Used to attribute attempts.
    public static func siteHostnames(for domains: [String]) -> [String] {
        var names = Set<String>()
        for domain in domains {
            guard let bare = bareDomain(domain) else { continue }
            names.formUnion(siteHostnames(forBare: bare))
        }
        return names.filter { DomainValidation.isSafeDomain($0) }.sorted()
    }

    private static func siteHostnames(forBare bare: String) -> Set<String> {
        var names: Set<String> = [bare, "www.\(bare)"]
        if isRegistrable(bare) {
            names.insert("m.\(bare)")
            names.insert("mobile.\(bare)")
        }
        for site in companions[bare]?.sites ?? [] {
            names.insert(site)
            if isRegistrable(site) { names.insert("www.\(site)") }
        }
        return names
    }

    private static func bareDomain(_ raw: String) -> String? {
        let domain = raw.lowercased()
        guard DomainValidation.isSafeDomain(domain) else { return nil }
        return domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
    }

    /// Second-level public suffixes under which sites register (`bbc.co.uk`).
    /// Not the full Public Suffix List: just the common country forms, so a
    /// typical `example.co.uk` gets its mobile sites while an explicitly
    /// chosen subdomain (`news.example.com`) does not.
    static let multiLabelSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "ltd.uk", "plc.uk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au",
        "co.nz", "org.nz", "net.nz",
        "co.jp", "ne.jp", "or.jp", "ac.jp",
        "co.kr", "or.kr",
        "co.in", "net.in", "org.in", "gov.in",
        "co.za", "org.za",
        "co.il", "org.il",
        "com.br", "net.br", "org.br",
        "com.mx", "org.mx",
        "com.ar", "com.co", "com.pe", "com.ve", "com.uy",
        "com.tr", "org.tr",
        "com.cn", "net.cn", "org.cn",
        "com.hk", "com.tw", "com.sg", "com.my", "com.ph", "com.vn",
        "co.id", "or.id", "co.th", "in.th",
        "com.ua", "org.ua",
        "com.pl", "com.ru", "org.ru",
        "com.eg", "com.sa", "com.ng", "co.ke",
    ]

    /// `example.com` or `example.co.uk`, not `music.example.com` or a bare TLD.
    static func isRegistrable(_ host: String) -> Bool {
        let labels = host.split(separator: ".")
        switch labels.count {
        case 2: return !multiLabelSuffixes.contains(host)
        case 3: return multiLabelSuffixes.contains(labels.suffix(2).joined(separator: "."))
        default: return false
        }
    }
}
