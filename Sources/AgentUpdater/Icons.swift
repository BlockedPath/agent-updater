import AppKit
import SwiftUI

/// Agent icons: the matching desktop app's icon when one is installed, else a downloaded logo
/// (cached on disk), else a monogram.
@MainActor
@Observable
final class IconStore {
    private(set) var images: [String: NSImage] = [:]
    private(set) var isAppIcon: Set<String> = []
    private var requested: Set<String> = []

    private let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentUpdater/icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        images = [:]
        isAppIcon = []
        requested = []
    }

    func load(name: String, app: String?, iconURL: String?) {
        guard !requested.contains(name) else { return }
        requested.insert(name)

        if let app, FileManager.default.fileExists(atPath: app) {
            images[name] = NSWorkspace.shared.icon(forFile: app)
            isAppIcon.insert(name)
            return
        }
        let cached = cacheDir.appendingPathComponent("\(name).png")
        if let image = NSImage(contentsOf: cached) {
            images[name] = Self.normalizedLogo(image)
            return
        }
        guard let iconURL, let url = URL(string: iconURL) else { return }
        Task {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data) else { return }
            try? data.write(to: cached)
            withAnimation(.easeOut(duration: 0.2)) { images[name] = Self.normalizedLogo(image) }
        }
    }

    /// Favicons often include a large transparent or plain white margin. Fit the actual mark,
    /// leaving the original disk asset intact; don't crop patterned or dark brand backgrounds.
    private static func normalizedLogo(_ image: NSImage) -> NSImage {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let width = source.width, height = source.height
        guard width > 2, height > 2, width <= 2048, height <= 2048 else { return image }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bounds: CGRect? = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                            | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = bytes.bindMemory(to: UInt8.self)
            let corners = [0, (width - 1) * 4, (height - 1) * width * 4, (width * height - 1) * 4]
            let transparent = corners.allSatisfy { data[$0 + 3] < 20 }
            let white = corners.allSatisfy { data[$0] > 235 && data[$0 + 1] > 235 && data[$0 + 2] > 235 && data[$0 + 3] > 235 }
            guard transparent || white else { return nil }
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    let visible = data[i + 3] > 32 && (transparent || min(data[i], data[i + 1], data[i + 2]) < 220)
                    if visible { minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y) }
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            // Convert the bottom-up bitmap coordinates to CGImage crop coordinates.
            let pad = max(1, Int(Double(max(maxX - minX + 1, maxY - minY + 1)) * 0.04))
            let x = max(0, minX - pad), y = max(0, height - 1 - maxY - pad)
            return CGRect(x: x, y: y, width: min(width - x, maxX - minX + 1 + pad * 2),
                          height: min(height - y, maxY - minY + 1 + pad * 2))
        }
        guard let bounds, bounds.width < CGFloat(width) * 0.95 || bounds.height < CGFloat(height) * 0.95,
              let cropped = source.cropping(to: bounds) else { return image }
        return NSImage(cgImage: cropped, size: bounds.size)
    }
}

struct AgentIcon: View {
    let name: String
    var app: String? = nil
    var iconURL: String? = nil
    var size: CGFloat = 28
    @Environment(IconStore.self) private var icons
    @Environment(\.colorScheme) private var colorScheme

    init(name: String, app: String? = nil, iconURL: String? = nil, size: CGFloat = 28) {
        self.name = name
        self.app = app
        self.iconURL = iconURL
        self.size = size
    }

    init(agent: Agent, size: CGFloat = 28) { self.init(name: agent.name, app: agent.app, iconURL: agent.iconURL, size: size) }
    init(catalog: CatalogAgent, size: CGFloat = 28) { self.init(name: catalog.name, iconURL: catalog.iconURL, size: size) }

    var body: some View {
        Group {
            if let image = icons.images[name] {
                if icons.isAppIcon.contains(name) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .scaleEffect(1.12)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(Color(white: colorScheme == .dark ? 0.92 : 0.99))
                        .overlay {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .padding(size * 0.13)
                        }
                        .clipShape(.rect(cornerRadius: size * 0.24))
                        .overlay { RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(.black.opacity(0.10)) }
                }
            } else {
                Monogram(name: name, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear { icons.load(name: name, app: app, iconURL: iconURL) }
    }
}

struct Monogram: View {
    let name: String
    var size: CGFloat = 28

    var body: some View {
        let hue = Double(name.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 360 }) / 360
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.95),
                                          Color(hue: hue, saturation: 0.75, brightness: 0.7)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Text(name.prefix(1).uppercased())
                    .font(.system(size: size * 0.48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
    }
}
