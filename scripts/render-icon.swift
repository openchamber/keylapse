import Cocoa
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

// Renders Resources/AppIcon.png: a blurred square of the given photo inside a rounded
// square, with the flower drawn as a white outline and a centre dot, like the menu bar glyph. Then run scripts/make-iconset.sh.
//
//   swift scripts/render-icon.swift <photo> [cropX cropY cropSize] [--background-only <output.png>] [--pixel]
//   swift scripts/render-icon.swift --glyph <output.png> <pixels>
//   swift scripts/render-icon.swift --pixel-glyph <output.png> <pixels> <grid> [outline cells]
//
// --pixel-glyph writes the pixel-art flower (white on transparent) with whole-pixel cells:
// 84/21 (header) and 34/17 (chooser) for the in-app glyphs, 36/17 and 18/17 for the menu bar template images.
//
// --glyph writes just the white flower glyph (outline plus dot) on a transparent square of
// the given size: the in-app glyph for the settings header and the destination chooser.
//
// --pixel draws the flower as crisp pixel art on a 13 × 13 grid instead of the smooth outline.
//
// With --background-only, only the blurred rounded square is written, to the given path,
// for drawing the flower by hand in another tool.
//
// Crop values are fractions of the photo's width and height (0–1); the default takes
// a square from the middle.

let arguments = CommandLine.arguments

/// White outline-plus-dot flower in the menu bar template's proportions, drawn with
/// morphology so the outline follows the silhouette with no seams.
func drawFlowerGlyph(into context: CGContext, canvas: CGFloat) {
    let unit = canvas / 42  // the silhouette spans 38 units; 2 units of margin each side for the stroke
    let centre = CGPoint(x: canvas / 2, y: canvas / 2)
    let circles: [(offset: CGPoint, radius: CGFloat)] = [
        (CGPoint(x: 0, y: 10), 9), (CGPoint(x: 10, y: 0), 9), (CGPoint(x: 0, y: -10), 9), (CGPoint(x: -10, y: 0), 9), (.zero, 11)
    ]
    let stroke: CGFloat = 4.5 * unit
    let dot: CGFloat = 5.3 * unit
    guard let silhouetteContext = CGContext(data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("No context") }
    silhouetteContext.setFillColor(CGColor(gray: 1, alpha: 1))
    for circle in circles {
        let r = circle.radius * unit
        silhouetteContext.addEllipse(in: CGRect(x: centre.x + circle.offset.x * unit - r, y: centre.y + circle.offset.y * unit - r, width: 2 * r, height: 2 * r))
    }
    silhouetteContext.fillPath()
    guard let silhouetteCG = silhouetteContext.makeImage() else { fatalError("No silhouette") }
    let silhouette = CIImage(cgImage: silhouetteCG)
    let dilate = CIFilter.morphologyMaximum()
    dilate.inputImage = silhouette
    dilate.radius = Float(stroke / 2)
    let erode = CIFilter.morphologyMinimum()
    erode.inputImage = silhouette
    erode.radius = Float(stroke / 2)
    let band = CIFilter.sourceOutCompositing()
    band.inputImage = dilate.outputImage
    band.backgroundImage = erode.outputImage
    guard let outline = band.outputImage,
          let outlineCG = CIContext().createCGImage(outline, from: silhouette.extent) else { fatalError("Outline failed") }
    context.draw(outlineCG, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillEllipse(in: CGRect(x: centre.x - dot, y: centre.y - dot, width: 2 * dot, height: 2 * dot))
}

/// Pixel-art flower: the five-circle silhouette sampled on a square grid, outlined one cell
/// thick, with a pixel-circle dot in the middle. No anti-aliasing, so cells stay crisp.
func drawPixelFlower(into context: CGContext, canvas: CGFloat, grid: Int, cell: CGFloat, outline: Int = 1) {
    let half = CGFloat(grid) / 2
    let unitsPerCell: CGFloat = 42 / CGFloat(grid)
    let circles: [(dx: CGFloat, dy: CGFloat, r: CGFloat)] = [(0, -10, 9), (10, 0, 9), (0, 10, 9), (-10, 0, 9), (0, 0, 11)]
    func inside(_ column: Int, _ row: Int) -> Bool {
        let x = (CGFloat(column) + 0.5 - half) * unitsPerCell
        let y = (CGFloat(row) + 0.5 - half) * unitsPerCell
        return circles.contains { hypot(x - $0.dx, y - $0.dy) <= $0.r }
    }
    func dot(_ column: Int, _ row: Int) -> Bool {
        let x = (CGFloat(column) + 0.5 - half) * unitsPerCell
        let y = (CGFloat(row) + 0.5 - half) * unitsPerCell
        return hypot(x, y) <= 5.3
    }
    let gridSize = cell * CGFloat(grid)
    let originX = ((canvas - gridSize) / 2).rounded()
    let originY = ((canvas - gridSize) / 2).rounded()
    context.setShouldAntialias(false)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    for row in 0..<grid {
        for column in 0..<grid {
            let onOutline = inside(column, row) && (1...outline).contains { d in [(d, 0), (-d, 0), (0, d), (0, -d)].contains { !inside(column + $0.0, row + $0.1) } }
            guard onOutline || dot(column, row) else { continue }
            context.fill(CGRect(x: originX + cell * CGFloat(column), y: originY + gridSize - cell * CGFloat(row + 1), width: cell, height: cell))
        }
    }
    context.setShouldAntialias(true)
}

if let flag = arguments.firstIndex(of: "--pixel-glyph"), arguments.count > flag + 3,
   let size = Int(arguments[flag + 2]), let grid = Int(arguments[flag + 3]) {
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("No context") }
    let outline = arguments.count > flag + 4 ? Int(arguments[flag + 4]) ?? 1 : 1
    drawPixelFlower(into: context, canvas: CGFloat(size), grid: grid, cell: CGFloat(size / grid), outline: outline)
    guard let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fatalError("No image") }
    try png.write(to: URL(fileURLWithPath: arguments[flag + 1]))
    print(arguments[flag + 1])
    exit(0)
}

if let flag = arguments.firstIndex(of: "--glyph"), arguments.count > flag + 2, let size = Int(arguments[flag + 2]) {
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("No context") }
    drawFlowerGlyph(into: context, canvas: CGFloat(size))
    guard let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fatalError("No image") }
    try png.write(to: URL(fileURLWithPath: arguments[flag + 1]))
    print(arguments[flag + 1])
    exit(0)
}

guard arguments.count >= 2, let photo = NSImage(contentsOfFile: arguments[1]),
      let photoCG = photo.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("Usage: swift scripts/render-icon.swift <photo> [cropX cropY cropSize]\n", stderr)
    exit(1)
}
let backgroundOnly = arguments.firstIndex(of: "--background-only").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
let pixelArt = arguments.contains("--pixel")
let fractions = arguments.dropFirst(2).filter { $0 != "--background-only" && $0 != backgroundOnly && $0 != "--pixel" }.compactMap(Double.init)
let cropX = fractions.count > 0 ? fractions[0] : 0.5
let cropY = fractions.count > 1 ? fractions[1] : 0.5
let cropSize = fractions.count > 2 ? fractions[2] : 0.6

let canvas: CGFloat = 1024
let unit = canvas / 64   // the SVG icon grid

// 1. Square crop, then blur. The crop is padded so the blur has no dark edges.
let side = min(CGFloat(photoCG.width), CGFloat(photoCG.height)) * cropSize
let origin = CGPoint(x: CGFloat(photoCG.width) * cropX - side / 2, y: CGFloat(photoCG.height) * (1 - cropY) - side / 2)
let cropRect = CGRect(origin: origin, size: CGSize(width: side, height: side)).integral
var source = CIImage(cgImage: photoCG).cropped(to: cropRect)
source = source.clampedToExtent()
let blur = CIFilter.gaussianBlur()
blur.inputImage = source
blur.radius = Float(side / 12)
guard let blurred = blur.outputImage?.cropped(to: cropRect),
      let blurredCG = CIContext().createCGImage(blurred, from: cropRect) else { fatalError("Blur failed") }

// 2. Compose on a transparent canvas.
guard let context = CGContext(data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("No context") }
let square = CGRect(x: 6 * unit, y: 6 * unit, width: 52 * unit, height: 52 * unit)
context.addPath(CGPath(roundedRect: square, cornerWidth: 12 * unit, cornerHeight: 12 * unit, transform: nil))
context.clip()
context.draw(blurredCG, in: square)
// A touch of darkening so the white outline reads on bright parts of the photo.
context.setFillColor(CGColor(gray: 0, alpha: 0.18))
context.fill(square)

if let backgroundOnly {
    guard let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fatalError("No image") }
    try png.write(to: URL(fileURLWithPath: backgroundOnly))
    print(backgroundOnly)
    exit(0)
}

if pixelArt {
    // 21 cells × 30 px = 630 px, about 75% of the 832 px square: room to breathe without looking small.
    drawPixelFlower(into: context, canvas: canvas, grid: 21, cell: 30)
} else {
// 3. Flower outline plus centre dot, in the menu bar glyph's proportions (stroke 3 px and
//    dot 7 px across a 25 px silhouette). The outline is a band centred on the silhouette
//    edge: dilate the silhouette by half the stroke, erode it by half, keep the difference.
//    Morphology on a 1024 px bitmap gives smooth edges without seams between arcs.
let centre = CGPoint(x: 32 * unit, y: 32 * unit)
let circles: [(offset: CGPoint, radius: CGFloat)] = [
    (CGPoint(x: 0, y: 10), 9), (CGPoint(x: 10, y: 0), 9), (CGPoint(x: 0, y: -10), 9), (CGPoint(x: -10, y: 0), 9), (.zero, 11)
]
let stroke: CGFloat = 4.5 * unit
let dot: CGFloat = 5.3 * unit
guard let silhouetteContext = CGContext(data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("No context") }
silhouetteContext.setFillColor(CGColor(gray: 1, alpha: 1))
for circle in circles {
    let r = circle.radius * unit
    silhouetteContext.addEllipse(in: CGRect(x: centre.x + circle.offset.x * unit - r, y: centre.y + circle.offset.y * unit - r, width: 2 * r, height: 2 * r))
}
silhouetteContext.fillPath()
guard let silhouetteCG = silhouetteContext.makeImage() else { fatalError("No silhouette") }
let silhouette = CIImage(cgImage: silhouetteCG)
let dilate = CIFilter.morphologyMaximum()
dilate.inputImage = silhouette
dilate.radius = Float(stroke / 2)
let erode = CIFilter.morphologyMinimum()
erode.inputImage = silhouette
erode.radius = Float(stroke / 2)
let band = CIFilter.sourceOutCompositing()
band.inputImage = dilate.outputImage
band.backgroundImage = erode.outputImage
guard let outline = band.outputImage,
      let outlineCG = CIContext().createCGImage(outline, from: silhouette.extent) else { fatalError("Outline failed") }
context.draw(outlineCG, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
context.setFillColor(CGColor(gray: 1, alpha: 1))
context.fillEllipse(in: CGRect(x: centre.x - dot, y: centre.y - dot, width: 2 * dot, height: 2 * dot))
}

guard let image = context.makeImage() else { fatalError("No image") }
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent("Resources/AppIcon.png")
let representation = NSBitmapImageRep(cgImage: image)
guard let png = representation.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
try png.write(to: output)
print(output.path)
