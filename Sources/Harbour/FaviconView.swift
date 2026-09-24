import SwiftUI
import AppKit

/// Fetches the favicon for a domain via Google's s2 service.
/// Shows a neutral placeholder while loading and a letter tile if the request
/// fails. Icons are cached in memory so lists don't flicker when rows are
/// rebuilt (e.g. switching from setup to the active session).
struct FaviconView: View {
    let domain: String
    var size: CGFloat = 20

    @State private var image: NSImage?
    @State private var failed = false

    private static let palette: [Color] = [
        Color(red: 0xc9/255, green: 0x7a/255, blue: 0x4a/255),
        Color(red: 0x2b/255, green: 0x40/255, blue: 0x66/255),
        Color(red: 0x5a/255, green: 0x6b/255, blue: 0x85/255),
        Color(red: 0x8e/255, green: 0x5a/255, blue: 0x3c/255),
        Color(red: 0x3f/255, green: 0x6e/255, blue: 0x73/255),
        Color(red: 0xb4/255, green: 0x45/255, blue: 0x2f/255),
        Color(red: 0x6a/255, green: 0x5a/255, blue: 0x8c/255),
    ]

    private var fallbackColor: Color {
        var h: Int = 0
        for c in domain.unicodeScalars { h = (h &* 31) &+ Int(c.value) }
        return Self.palette[abs(h) % Self.palette.count]
    }

    private var url: URL? {
        let sz = Int(size * 2) * 2  // request 2x scale for Retina
        var comps = URLComponents(string: "https://www.google.com/s2/favicons")
        comps?.queryItems = [
            URLQueryItem(name: "domain", value: domain),
            URLQueryItem(name: "sz", value: String(max(32, sz))),
        ]
        return comps?.url
    }

    private var radius: CGFloat { max(4, size * 0.22) }

    var body: some View {
        ZStack {
            if let image = image ?? FaviconCache.shared.image(for: domain) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
                    )
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size - 4, height: size - 4)
                    .transition(.opacity)
            } else if failed {
                fallbackTile
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.cream)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.2), value: image != nil)
        .task(id: domain) { await load() }
        .accessibilityHidden(true)
    }

    private var fallbackTile: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fallbackColor)
            .overlay(
                Text(String(domain.prefix(1)).uppercased())
                    .font(.system(size: size * 0.55, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
            )
    }

    @MainActor
    private func load() async {
        if let cached = FaviconCache.shared.image(for: domain) {
            image = cached
            return
        }
        if FaviconCache.shared.hasFailed(domain) {
            failed = true
            return
        }
        guard let url else { failed = true; return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            // Google answers unknown hosts with a 404 and a generic globe.
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let img = NSImage(data: data) else {
                FaviconCache.shared.markFailed(domain)
                failed = true
                return
            }
            FaviconCache.shared.store(img, for: domain)
            image = img
        } catch {
            // Cancelled because the row went away: don't remember as failed.
            if !Task.isCancelled { failed = true }
        }
    }
}

@MainActor
private final class FaviconCache {
    static let shared = FaviconCache()
    private var images: [String: NSImage] = [:]
    private var failures: Set<String> = []

    func image(for domain: String) -> NSImage? { images[domain] }
    func hasFailed(_ domain: String) -> Bool { failures.contains(domain) }
    func store(_ image: NSImage, for domain: String) { images[domain] = image }
    func markFailed(_ domain: String) { failures.insert(domain) }
}
