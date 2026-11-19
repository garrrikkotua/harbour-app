import Foundation

/// Expands blocked domains into the exact hostnames written to /etc/hosts.
///
/// /etc/hosts has no wildcards, so blocking `x.com` alone leaves `mobile.x.com`
/// reachable, and a page the browser restores from its own cache (a service
/// worker keeps the X app shell offline) still loads its scripts and images
/// from `twimg.com`. Each blocked domain therefore also covers:
///   - its `www.` form, as before;
///   - the `m.` and `mobile.` sites, for a registrable domain (one dot);
///   - for well-known sites, the companion hosts the site runs on.
///
/// Companions are only hosts that serve that one service, never a shared CDN
/// or a link shortener other sites use, so blocking them can't break a site the
/// user didn't block. They only reach /etc/hosts; IP rules stay limited to the
/// domains the user entered.
public enum RelatedDomains {

    private static let xHosts = [
        "x.com", "twitter.com",
        "mobile.x.com", "mobile.twitter.com",
        "api.x.com", "api.twitter.com",
        "abs.twimg.com", "abs-0.twimg.com", "pbs.twimg.com",
        "video.twimg.com", "ton.twimg.com",
    ]

    /// Companion hosts keyed by the bare domain the user blocks.
    static let companions: [String: [String]] = [
        "x.com": xHosts,
        "twitter.com": xHosts,
        "youtube.com": [
            "youtu.be", "music.youtube.com", "youtubei.googleapis.com",
            "i.ytimg.com", "s.ytimg.com", "yt3.ggpht.com",
        ],
        "reddit.com": [
            "old.reddit.com", "new.reddit.com", "gql.reddit.com", "oauth.reddit.com",
            "redd.it", "i.redd.it", "v.redd.it", "preview.redd.it",
            "external-preview.redd.it", "www.redditstatic.com", "styles.redditmedia.com",
        ],
        "instagram.com": ["i.instagram.com", "static.cdninstagram.com", "scontent.cdninstagram.com"],
        "facebook.com": ["web.facebook.com", "fb.com", "www.fb.com"],
        "threads.net": ["threads.com", "www.threads.com"],
        "threads.com": ["threads.net", "www.threads.net"],
        "tiktok.com": ["vm.tiktok.com", "vt.tiktok.com"],
        "linkedin.com": ["static.licdn.com", "media.licdn.com"],
        "twitch.tv": ["gql.twitch.tv", "static.twitchcdn.net"],
    ]

    /// Exact hostnames to block for `domains`, sorted and deduplicated.
    /// Unsafe entries are dropped. With `includeRelated: false` only the bare
    /// and `www.` forms are produced (used for the secure DNS endpoints).
    public static func hostnames(for domains: [String], includeRelated: Bool = true) -> [String] {
        var names = Set<String>()
        for raw in domains {
            let domain = raw.lowercased()
            guard DomainValidation.isSafeDomain(domain) else { continue }
            let bare = domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
            names.insert(bare)
            names.insert("www.\(bare)")
            guard includeRelated else { continue }
            if isRegistrable(bare) {
                names.insert("m.\(bare)")
                names.insert("mobile.\(bare)")
            }
            for host in companions[bare] ?? [] {
                names.insert(host)
                // A sibling site (twitter.com for x.com) also gets its www. form.
                if isRegistrable(host) { names.insert("www.\(host)") }
            }
        }
        return names.filter { DomainValidation.isSafeDomain($0) }.sorted()
    }

    /// `example.com`, not `music.example.com` or a bare TLD.
    private static func isRegistrable(_ host: String) -> Bool {
        host.filter { $0 == "." }.count == 1
    }
}
