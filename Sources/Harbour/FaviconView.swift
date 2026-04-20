import SwiftUI

/// Fetches the favicon for a domain via Google's s2 service.
/// Falls back to a letter tile if the request fails or returns nothing.
struct FaviconView: View {
    let domain: String
    var size: CGFloat = 20

    private static let palette: [Color] = [
        Color(red: 0xff/255, green: 0x3b/255, blue: 0x30/255),
        Color(red: 0xff/255, green: 0x95/255, blue: 0x00/255),
        Color(red: 0xff/255, green: 0xcc/255, blue: 0x00/255),
        Color(red: 0x34/255, green: 0xc7/255, blue: 0x59/255),
        Color(red: 0x5a/255, green: 0xc8/255, blue: 0xfa/255),
        Color(red: 0x00/255, green: 0x7a/255, blue: 0xff/255),
        Color(red: 0xaf/255, green: 0x52/255, blue: 0xde/255),
        Color(red: 0xff/255, green: 0x2d/255, blue: 0x55/255),
        Color(red: 0x58/255, green: 0x56/255, blue: 0xd6/255),
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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(4, size * 0.2))
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: max(4, size * 0.2))
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )

            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size - 4, height: size - 4)
                case .failure, .empty:
                    FallbackTile
                @unknown default:
                    FallbackTile
                }
            }
        }
        .frame(width: size, height: size)
    }

    private var FallbackTile: some View {
        RoundedRectangle(cornerRadius: max(4, size * 0.2))
            .fill(fallbackColor)
            .overlay(
                Text(String(domain.prefix(1)).uppercased())
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
    }
}
