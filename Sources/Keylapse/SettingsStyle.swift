import SwiftUI
import Cocoa

/// The flower glyph, identical to the menu bar one: the pixel-art outline with a centre dot,
/// rendered once by scripts/render-icon.swift --pixel-glyph and shipped as FlowerGlyph.png.
enum Flower {
    /// 84 px on a 21-cell grid: drawn at 42 pt, every cell is 4 px on Retina and 2 px otherwise.
    static let image = load("FlowerGlyph")
    /// 34 px on a 17-cell grid: drawn at 17 pt for the chooser marker, 2 px cells on Retina.
    static let smallImage = load("FlowerGlyphSmall")
    static let size: CGFloat = 42
    static let smallSize: CGFloat = 17
    /// The app icon for the welcome page.
    static let appIcon: NSImage = resource("AppIcon", "icns").flatMap(NSImage.init(contentsOf:))
        ?? resource("AppIcon", "png").flatMap(NSImage.init(contentsOf:)) ?? NSApp.applicationIconImage

    /// A file from the bundle's Resources. The debug executable has no bundle, so there it
    /// falls back to the Resources folder next to the sources.
    private static func resource(_ name: String, _ type: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: type) { return url }
        #if DEBUG
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/\(name).\(type)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
        #else
        return nil
        #endif
    }

    private static func load(_ name: String) -> NSImage {
        let image = resource(name, "png").flatMap(NSImage.init(contentsOf:)) ?? NSImage(size: NSSize(width: 42, height: 42))
        image.isTemplate = true
        return image
    }

    /// The flower for the menu bar. While Keylapse is not working (paused, or setup incomplete)
    /// the dot in the middle gives way to two pause bars, so the menu bar itself says so.
    static func menuBarIcon(paused: Bool = false) -> NSImage {
        // 21 pt so the 21-cell grid lands on whole pixels, the same flower as in the window.
        let image = NSImage(size: NSSize(width: 21, height: 21))
        for name in ["FlowerTemplate", "FlowerTemplate@2x"] {
            guard let url = resource(name, "png"), let data = try? Data(contentsOf: url), let source = NSBitmapImageRep(data: data) else { continue }
            let representation = paused ? pausedVariant(of: source) : source
            representation.size = image.size
            image.addRepresentation(representation)
        }
        image.isTemplate = true
        image.accessibilityDescription = paused ? "Keylapse, not running" : "Keylapse"
        return image
    }

    /// The same pixel flower with its 5 × 5-cell centre dot replaced by two bars, each two cells
    /// wide and five tall with one cell between them, on the same 21-cell grid.
    private static func pausedVariant(of source: NSBitmapImageRep) -> NSBitmapImageRep {
        let pixels = source.pixelsWide
        let cell = CGFloat(pixels / 21)
        guard cell >= 1,
              let copy = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                                          hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: copy) else { return source }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .none
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        // The dot sits in cells 8…12 both ways, so the block is the same from top or bottom.
        context.cgContext.clear(CGRect(x: 8 * cell, y: 8 * cell, width: 5 * cell, height: 5 * cell))
        NSColor.white.setFill()
        NSRect(x: 8 * cell, y: 8 * cell, width: 2 * cell, height: 5 * cell).fill()
        NSRect(x: 11 * cell, y: 8 * cell, width: 2 * cell, height: 5 * cell).fill()
        NSGraphicsContext.restoreGraphicsState()
        return copy
    }

    /// Draws the small glyph in the given colour, centred on `centre`, with crisp cells.
    static func drawSmallGlyph(centre: CGPoint, color: NSColor = .white) {
        let rect = CGRect(x: (centre.x - smallSize / 2).rounded(), y: (centre.y - smallSize / 2).rounded(), width: smallSize, height: smallSize)
        NSGraphicsContext.current?.imageInterpolation = .none
        smallImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        color.setFill()
        rect.fill(using: .sourceAtop)
    }
}

/// Frosted glass behind every Keylapse window, like a desktop widget,
/// dimmed a little so text stays readable over bright wallpapers.
final class GlassView: NSVisualEffectView {
    static let dimming: CGFloat = 0.30

    override init(frame: NSRect = .zero) {
        super.init(frame: frame)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        let dim = NSView()
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(Self.dimming).cgColor
        dim.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dim)
        NSLayoutConstraint.activate([
            dim.leadingAnchor.constraint(equalTo: leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: trailingAnchor),
            dim.topAnchor.constraint(equalTo: topAnchor),
            dim.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    /// Hosts a view edge to edge on the glass.
    static func wrapping(_ view: NSView) -> GlassView {
        let glass = GlassView()
        view.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            view.topAnchor.constraint(equalTo: glass.topAnchor),
            view.bottomAnchor.constraint(equalTo: glass.bottomAnchor)
        ])
        return glass
    }
}

/// Every button that is not the next step: a grey capsule-cornered key with white lettering.
/// The system bordered style writes its title in the accent colour while the window is active,
/// which cannot be read on the glass; this keeps the look it has in an inactive window.
struct QuietButtonStyle: ButtonStyle {
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        QuietButtonBody(configuration: configuration, large: large)
    }

    private struct QuietButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let large: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: large ? 13 : 11, weight: .medium))
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.45))
                .padding(.horizontal, large ? 12 : 10)
                .frame(height: large ? 24 : 20)
                .background(.white.opacity(configuration.isPressed ? 0.34 : 0.2),
                            in: RoundedRectangle(cornerRadius: large ? 7 : 6, style: .continuous))
                .contentShape(Rectangle())
        }
    }
}
