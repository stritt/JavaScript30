import SpriteKit
import StepquestKit
import UIKit

/// Code-drawn placeholder art for the trail, rendered once into small textures and shown with
/// nearest-neighbour filtering so it reads as chunky 16-bit-style pixel art.
///
/// Drop-in real art: add images to Assets.xcassets (Sprites folder) with these names and they win
/// over the procedural versions automatically:
///   hero_walk_0, hero_walk_1, hero_idle, monster_<id> (e.g. monster_slime), gate_<zoneId>,
///   tile_<palette>_<kind> (kind: path, grass, cliff).
/// Or ship a `.spriteatlas`; `UIImage(named:)` resolves atlas images too.
@MainActor
final class SpriteFactory {
    /// Design units are rendered 1:1 into textures; `TrailScene` scales the world up by this amount.
    static let pixelScale: CGFloat = 2

    private weak var view: SKView?

    init(view: SKView?) {
        self.view = view
    }

    // MARK: Public

    /// A texture plus the anchor that puts the art's logical origin (feet / tile base) at the node position.
    struct Art {
        var texture: SKTexture
        var anchor: CGPoint

        @MainActor
        func sprite() -> SKSpriteNode {
            let node = SKSpriteNode(texture: texture)
            node.anchorPoint = anchor
            return node
        }
    }

    func heroWalkFrames() -> [Art] {
        [art("hero_walk_0", defaultAnchor: Self.feet) { Self.heroNode(stride: 0) },
         art("hero_walk_1", defaultAnchor: Self.feet) { Self.heroNode(stride: 1) }]
    }

    func heroIdle() -> Art { art("hero_idle", defaultAnchor: Self.feet) { Self.heroNode(stride: -1) } }

    func monster(_ def: MonsterDefinition) -> Art {
        art("monster_\(def.id)", defaultAnchor: Self.feet) { Self.monsterNode(id: def.id) }
    }

    func gateGuardian(zone: ZoneDefinition) -> Art {
        art("gate_\(zone.id)", defaultAnchor: Self.feet) { Self.guardianNode(palette: zone.palette) }
    }

    func tile(_ kind: TileKind, palette: ZonePalette, elevation: Int, variant: Int) -> Art {
        art("tile_\(palette.rawValue)_\(kind.rawValue)", cacheKey: "tile_\(palette.rawValue)_\(kind.rawValue)_\(elevation)_\(variant)",
            defaultAnchor: CGPoint(x: 0.5, y: 0)) {
            Self.tileNode(kind, palette: palette, elevation: elevation, variant: variant)
        }
    }

    func decoration(_ palette: ZonePalette, variant: Int) -> Art {
        art("deco_\(palette.rawValue)_\(variant)", defaultAnchor: Self.feet) { Self.decorationNode(palette, variant: variant) }
    }

    static let feet = CGPoint(x: 0.5, y: 0.05)

    // MARK: Texture pipeline

    private var artCache: [String: Art] = [:]

    private func art(_ assetName: String, cacheKey: String? = nil, defaultAnchor: CGPoint, build: () -> SKNode) -> Art {
        let key = cacheKey ?? assetName
        if let cached = artCache[key] { return cached }
        if let image = UIImage(named: assetName) {
            let texture = SKTexture(image: image)
            texture.filteringMode = .nearest
            let result = Art(texture: texture, anchor: defaultAnchor)
            artCache[key] = result
            return result
        }
        let node = build()
        let anchor = Self.anchor(for: node)
        guard let view, let rendered = view.texture(from: node) else {
            // No view yet: transparent placeholder, not cached so it's rebuilt once a view exists.
            return Art(texture: SKTexture(image: Self.solidImage(color: .clear)), anchor: anchor)
        }
        let result = Art(texture: Self.pixelate(rendered), anchor: anchor)
        artCache[key] = result
        return result
    }

    /// Downsamples a screen-scale render to 1 px per design unit.
    private static func pixelate(_ texture: SKTexture) -> SKTexture {
        let size = texture.size()
        guard size.width >= 1, size.height >= 1 else { return texture }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .medium
            UIImage(cgImage: texture.cgImage()).draw(in: CGRect(origin: .zero, size: size))
        }
        let t = SKTexture(image: image)
        t.filteringMode = .nearest
        return t
    }

    private static func solidImage(color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    /// Anchor that keeps a node's local origin at the same spot once it's a sprite.
    static func anchor(for node: SKNode) -> CGPoint {
        let frame = node.calculateAccumulatedFrame()
        guard frame.width > 0, frame.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: -frame.minX / frame.width, y: -frame.minY / frame.height)
    }

    // MARK: Primitive helpers

    static func shape(_ path: CGPath, fill: UIColor, stroke: UIColor? = nil, line: CGFloat = 1) -> SKShapeNode {
        let n = SKShapeNode(path: path)
        n.fillColor = fill
        n.strokeColor = stroke ?? .clear
        n.lineWidth = stroke == nil ? 0 : line
        n.isAntialiased = false
        return n
    }

    static func rect(_ r: CGRect, fill: UIColor, stroke: UIColor? = UIColor(white: 0.08, alpha: 1), corner: CGFloat = 0) -> SKShapeNode {
        shape(CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner, transform: nil), fill: fill, stroke: stroke)
    }

    static func ellipse(_ r: CGRect, fill: UIColor, stroke: UIColor? = UIColor(white: 0.08, alpha: 1)) -> SKShapeNode {
        shape(CGPath(ellipseIn: r, transform: nil), fill: fill, stroke: stroke)
    }

    static func poly(_ points: [CGPoint], fill: UIColor, stroke: UIColor? = UIColor(white: 0.08, alpha: 1)) -> SKShapeNode {
        let p = CGMutablePath()
        p.addLines(between: points)
        p.closeSubpath()
        return shape(p, fill: fill, stroke: stroke)
    }

    static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static let outline = UIColor(white: 0.08, alpha: 1)

    // MARK: Hero (chibi wanderer)

    /// Origin = feet. ~16 x 24 design units. `stride` -1 idle, 0/1 walk frames.
    static func heroNode(stride: Int) -> SKNode {
        let root = SKNode()
        let skin = color(0xF2C9A0), hair = color(0x6B3E1F), tunic = color(0x2D4F8E), cape = color(0x9A2E22)
        let boots = color(0x3A2614), gold = color(0xD4A82E), steel = color(0xC9CED6)

        root.addChild(ellipse(CGRect(x: -6, y: -2, width: 12, height: 4), fill: UIColor(white: 0, alpha: 0.3), stroke: nil))
        // Cape behind the body.
        root.addChild(poly([CGPoint(x: -5, y: 13), CGPoint(x: 4, y: 13), CGPoint(x: 6, y: 3), CGPoint(x: -7, y: 3)], fill: cape))
        // Legs (alternate on walk frames).
        let lift: (CGFloat, CGFloat) = stride == 0 ? (2, 0) : stride == 1 ? (0, 2) : (0, 0)
        root.addChild(rect(CGRect(x: -4, y: lift.0, width: 3, height: 5), fill: boots))
        root.addChild(rect(CGRect(x: 1, y: lift.1, width: 3, height: 5), fill: boots))
        // Body + belt.
        root.addChild(rect(CGRect(x: -5, y: 4, width: 10, height: 9), fill: tunic, corner: 2))
        root.addChild(rect(CGRect(x: -5, y: 7, width: 10, height: 2), fill: gold, stroke: nil))
        // Sword on the right.
        root.addChild(rect(CGRect(x: 6, y: 6, width: 2, height: 10), fill: steel))
        root.addChild(rect(CGRect(x: 4.5, y: 5, width: 5, height: 2), fill: gold))
        // Big chibi head.
        root.addChild(ellipse(CGRect(x: -7, y: 12, width: 14, height: 13), fill: skin))
        root.addChild(shape({
            let p = CGMutablePath()
            p.addArc(center: CGPoint(x: 0, y: 19), radius: 7.5, startAngle: 0.1, endAngle: .pi - 0.1, clockwise: false)
            p.addLine(to: CGPoint(x: -7, y: 17))
            p.addLine(to: CGPoint(x: 7, y: 17))
            p.closeSubpath()
            return p
        }(), fill: hair, stroke: outline))
        // Eyes.
        root.addChild(rect(CGRect(x: -3.5, y: 15, width: 2, height: 3), fill: outline, stroke: nil))
        root.addChild(rect(CGRect(x: 1.5, y: 15, width: 2, height: 3), fill: outline, stroke: nil))
        return root
    }

    // MARK: Monsters

    private struct MonsterLook {
        enum Shape { case blob, beast, humanoid, tree, worm, orb }
        var shape: Shape
        var body: UInt32
        var accent: UInt32
    }

    private static let looks: [String: MonsterLook] = [
        "slime": .init(shape: .blob, body: 0x6FAF4A, accent: 0x3F6B33),
        "hare": .init(shape: .beast, body: 0xEDE6D6, accent: 0xC9A227),
        "goblin": .init(shape: .humanoid, body: 0x6E9B3A, accent: 0x6B3E1F),
        "wisp": .init(shape: .orb, body: 0xF3D77A, accent: 0xE07A2E),
        "wolf": .init(shape: .beast, body: 0x7A7470, accent: 0x3A3330),
        "treant": .init(shape: .tree, body: 0x6B4A2B, accent: 0x3F6B33),
        "scarab": .init(shape: .blob, body: 0xB58A2E, accent: 0x5C4630),
        "mummy": .init(shape: .humanoid, body: 0xE6DCC2, accent: 0x8A7B5A),
        "sandworm": .init(shape: .worm, body: 0xC9B48A, accent: 0x8E6B3A),
    ]

    /// Origin = feet, faces left (toward the hero).
    static func monsterNode(id: String) -> SKNode {
        let look = looks[id] ?? {
            var h: UInt32 = 2166136261
            for b in id.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
            return MonsterLook(shape: .blob, body: h & 0xFFFFFF, accent: (h >> 4) & 0x7F7F7F)
        }()
        let body = color(look.body), accent = color(look.accent)
        let root = SKNode()
        root.addChild(ellipse(CGRect(x: -7, y: -2, width: 14, height: 4), fill: UIColor(white: 0, alpha: 0.3), stroke: nil))

        func eyes(y: CGFloat, x: CGFloat = -4) {
            root.addChild(rect(CGRect(x: x, y: y, width: 2, height: 2), fill: .white, stroke: nil))
            root.addChild(rect(CGRect(x: x + 4, y: y, width: 2, height: 2), fill: .white, stroke: nil))
            root.addChild(rect(CGRect(x: x, y: y, width: 1, height: 1), fill: outline, stroke: nil))
            root.addChild(rect(CGRect(x: x + 4, y: y, width: 1, height: 1), fill: outline, stroke: nil))
        }

        switch look.shape {
        case .blob:
            root.addChild(shape({
                let p = CGMutablePath()
                p.move(to: CGPoint(x: -8, y: 0))
                p.addQuadCurve(to: CGPoint(x: 0, y: 13), control: CGPoint(x: -9, y: 12))
                p.addQuadCurve(to: CGPoint(x: 8, y: 0), control: CGPoint(x: 9, y: 12))
                p.closeSubpath()
                return p
            }(), fill: body, stroke: outline))
            root.addChild(ellipse(CGRect(x: -5, y: 7, width: 4, height: 3), fill: UIColor(white: 1, alpha: 0.5), stroke: nil))
            root.addChild(rect(CGRect(x: -8, y: 0, width: 16, height: 2), fill: accent, stroke: nil))
            eyes(y: 5)
        case .orb:
            root.addChild(poly([CGPoint(x: -4, y: 10), CGPoint(x: 0, y: 22), CGPoint(x: 4, y: 10)], fill: accent))
            root.addChild(ellipse(CGRect(x: -6, y: 4, width: 12, height: 12), fill: body))
            eyes(y: 9)
        case .beast:
            root.addChild(ellipse(CGRect(x: -8, y: 2, width: 16, height: 9), fill: body))
            root.addChild(ellipse(CGRect(x: -11, y: 6, width: 9, height: 8), fill: body))
            root.addChild(poly([CGPoint(x: -9, y: 13), CGPoint(x: -8, y: 20), CGPoint(x: -6, y: 13)], fill: body))
            root.addChild(poly([CGPoint(x: -6, y: 13), CGPoint(x: -4, y: 19), CGPoint(x: -3, y: 12)], fill: accent))
            root.addChild(rect(CGRect(x: -6, y: 0, width: 3, height: 3), fill: body))
            root.addChild(rect(CGRect(x: 3, y: 0, width: 3, height: 3), fill: body))
            root.addChild(rect(CGRect(x: -9, y: 9, width: 2, height: 2), fill: outline, stroke: nil))
        case .humanoid:
            root.addChild(rect(CGRect(x: -4, y: 0, width: 3, height: 4), fill: accent))
            root.addChild(rect(CGRect(x: 1, y: 0, width: 3, height: 4), fill: accent))
            root.addChild(rect(CGRect(x: -5, y: 4, width: 10, height: 8), fill: body, corner: 2))
            root.addChild(ellipse(CGRect(x: -6, y: 11, width: 12, height: 11), fill: body))
            root.addChild(poly([CGPoint(x: -6, y: 17), CGPoint(x: -10, y: 19), CGPoint(x: -6, y: 15)], fill: body))
            root.addChild(poly([CGPoint(x: 6, y: 17), CGPoint(x: 10, y: 19), CGPoint(x: 6, y: 15)], fill: body))
            root.addChild(rect(CGRect(x: -10, y: 5, width: 3, height: 10), fill: accent))
            eyes(y: 15)
        case .tree:
            root.addChild(rect(CGRect(x: -4, y: 0, width: 8, height: 14), fill: body))
            root.addChild(ellipse(CGRect(x: -10, y: 11, width: 20, height: 14), fill: accent))
            root.addChild(ellipse(CGRect(x: -6, y: 19, width: 12, height: 9), fill: accent))
            eyes(y: 7, x: -3)
        case .worm:
            for (i, r) in [CGFloat(5), 6, 5, 4].enumerated() {
                let y = CGFloat(i) * 5
                let x = CGFloat(i) * -2
                root.addChild(ellipse(CGRect(x: x - r, y: y, width: r * 2, height: r * 1.6), fill: i % 2 == 0 ? body : accent))
            }
            root.addChild(rect(CGRect(x: -10, y: 18, width: 2, height: 2), fill: outline, stroke: nil))
        }
        return root
    }

    /// Bigger, armored guardian with a banner (origin = feet).
    static func guardianNode(palette: ZonePalette) -> SKNode {
        let (armor, cloth): (UInt32, UInt32) = switch palette {
        case .meadow: (0x7A8A5A, 0x3F6B33)
        case .forest: (0x5C4630, 0x2B1D10)
        case .desert: (0xC9A227, 0x6E3A9E)
        case .unknown: (0x6E6253, 0x9A2E22)
        }
        let root = SKNode()
        root.addChild(ellipse(CGRect(x: -12, y: -3, width: 24, height: 6), fill: UIColor(white: 0, alpha: 0.35), stroke: nil))
        // Banner pole + flag.
        root.addChild(rect(CGRect(x: 12, y: 0, width: 2, height: 40), fill: color(0x3A2614)))
        root.addChild(poly([CGPoint(x: 14, y: 39), CGPoint(x: 26, y: 35), CGPoint(x: 14, y: 30)], fill: color(cloth)))
        // Legs, body, pauldrons, helm.
        root.addChild(rect(CGRect(x: -7, y: 0, width: 5, height: 9), fill: color(armor)))
        root.addChild(rect(CGRect(x: 2, y: 0, width: 5, height: 9), fill: color(armor)))
        root.addChild(rect(CGRect(x: -9, y: 8, width: 18, height: 15), fill: color(armor), corner: 3))
        root.addChild(rect(CGRect(x: -9, y: 12, width: 18, height: 4), fill: color(cloth), stroke: nil))
        root.addChild(ellipse(CGRect(x: -14, y: 18, width: 9, height: 7), fill: color(armor)))
        root.addChild(ellipse(CGRect(x: 5, y: 18, width: 9, height: 7), fill: color(armor)))
        root.addChild(rect(CGRect(x: -7, y: 22, width: 14, height: 13), fill: color(armor), corner: 4))
        root.addChild(rect(CGRect(x: -5, y: 27, width: 10, height: 2), fill: color(0xF3D77A), stroke: nil))
        root.addChild(poly([CGPoint(x: -3, y: 35), CGPoint(x: 0, y: 42), CGPoint(x: 3, y: 35)], fill: color(0x9A2E22)))
        // Shield.
        root.addChild(poly([CGPoint(x: -16, y: 20), CGPoint(x: -8, y: 20), CGPoint(x: -8, y: 10), CGPoint(x: -12, y: 6), CGPoint(x: -16, y: 10)],
                           fill: color(cloth)))
        return root
    }

    // MARK: Tiles

    enum TileKind: String { case path, grass, cliff }

    static let tileWidth: CGFloat = 32
    static let tileHeight: CGFloat = 16
    static let elevationStep: CGFloat = 6
    static let baseDepth: CGFloat = 5

    struct TileColors { var top: UInt32; var left: UInt32; var right: UInt32 }

    static func tileColors(_ kind: TileKind, _ palette: ZonePalette) -> TileColors {
        switch (palette, kind) {
        case (.meadow, .path): .init(top: 0xC9A66B, left: 0x8C6B3E, right: 0x6E5230)
        case (.meadow, .grass): .init(top: 0x7DB24A, left: 0x6B4A2B, right: 0x4F361F)
        case (.meadow, .cliff): .init(top: 0x6A9A3E, left: 0x7A7470, right: 0x5A5450)
        case (.forest, .path): .init(top: 0x8C7A5A, left: 0x5C4630, right: 0x463422)
        case (.forest, .grass): .init(top: 0x3F6B33, left: 0x4A3420, right: 0x352416)
        case (.forest, .cliff): .init(top: 0x355A2B, left: 0x5A5450, right: 0x423D3A)
        case (.desert, .path): .init(top: 0xD9B98A, left: 0xA88A5A, right: 0x8C7048)
        case (.desert, .grass): .init(top: 0xE8CF94, left: 0xB89A62, right: 0x9C804E)
        case (.desert, .cliff): .init(top: 0xD6B577, left: 0xA0784A, right: 0x80603A)
        case (.unknown, .path): .init(top: 0xB0A090, left: 0x7A6A5A, right: 0x5A4A3A)
        case (.unknown, _): .init(top: 0x8A9A7A, left: 0x6A5A4A, right: 0x4A3A2A)
        }
    }

    /// Isometric block. Origin = bottom-center of the ground footprint's center line.
    static func tileNode(_ kind: TileKind, palette: ZonePalette, elevation: Int, variant: Int) -> SKNode {
        let w = tileWidth / 2, h = tileHeight / 2
        let top = baseDepth + CGFloat(elevation) * elevationStep
        let c = tileColors(kind, palette)
        let shade: CGFloat = [1.0, 0.94, 1.05][variant % 3]
        let root = SKNode()
        let edge = UIColor(white: 0.05, alpha: 0.6)
        root.addChild(poly([CGPoint(x: -w, y: top), CGPoint(x: 0, y: top - h), CGPoint(x: 0, y: -h), CGPoint(x: -w, y: 0)],
                           fill: color(c.left), stroke: edge))
        root.addChild(poly([CGPoint(x: 0, y: top - h), CGPoint(x: w, y: top), CGPoint(x: w, y: 0), CGPoint(x: 0, y: -h)],
                           fill: color(c.right), stroke: edge))
        root.addChild(poly([CGPoint(x: -w, y: top), CGPoint(x: 0, y: top + h), CGPoint(x: w, y: top), CGPoint(x: 0, y: top - h)],
                           fill: color(c.top).adjusted(brightness: shade), stroke: edge))
        // Strata lines on taller blocks.
        if elevation > 0 {
            for e in 1...elevation {
                let y = baseDepth + CGFloat(e - 1) * elevationStep + 1
                root.addChild(poly([CGPoint(x: -w, y: y), CGPoint(x: 0, y: y - h), CGPoint(x: 0, y: y - h + 1), CGPoint(x: -w, y: y + 1)],
                                   fill: UIColor(white: 0, alpha: 0.18), stroke: nil))
            }
        }
        // Texture specks on the top face.
        let speck = kind == .path ? UIColor(white: 0, alpha: 0.15) : UIColor(white: 1, alpha: 0.18)
        for k in 0..<3 {
            let dx = CGFloat((variant * 7 + k * 5) % 13) - 6
            let dy = CGFloat((variant * 3 + k * 4) % 7) - 3
            root.addChild(rect(CGRect(x: dx, y: top + dy * 0.6, width: 2, height: 1), fill: speck, stroke: nil))
        }
        return root
    }

    static func decorationNode(_ palette: ZonePalette, variant: Int) -> SKNode {
        let root = SKNode()
        switch palette {
        case .meadow:
            if variant % 2 == 0 {
                // Flower clump.
                for (i, hex) in [UInt32(0xE85D75), 0xF3D77A, 0xFFFFFF].enumerated() {
                    root.addChild(rect(CGRect(x: CGFloat(i * 3) - 4, y: CGFloat(i % 2) * 2, width: 2, height: 2), fill: color(hex), stroke: nil))
                }
            } else {
                root.addChild(ellipse(CGRect(x: -5, y: 0, width: 10, height: 7), fill: color(0x4E8A3A)))
            }
        case .forest:
            root.addChild(rect(CGRect(x: -1.5, y: 0, width: 3, height: 8), fill: color(0x5C4630)))
            root.addChild(poly([CGPoint(x: -8, y: 6), CGPoint(x: 0, y: 18), CGPoint(x: 8, y: 6)], fill: color(0x2F5A2A)))
            root.addChild(poly([CGPoint(x: -6, y: 12), CGPoint(x: 0, y: 24), CGPoint(x: 6, y: 12)], fill: color(0x3F6B33)))
        case .desert:
            if variant % 2 == 0 {
                root.addChild(rect(CGRect(x: -2, y: 0, width: 4, height: 14), fill: color(0x5E8C3A), corner: 2))
                root.addChild(rect(CGRect(x: -6, y: 6, width: 4, height: 2), fill: color(0x5E8C3A), stroke: nil))
                root.addChild(rect(CGRect(x: -6, y: 6, width: 2, height: 5), fill: color(0x5E8C3A), stroke: nil))
            } else {
                root.addChild(ellipse(CGRect(x: -5, y: 0, width: 10, height: 6), fill: color(0xA0784A)))
            }
        case .unknown:
            root.addChild(ellipse(CGRect(x: -4, y: 0, width: 8, height: 5), fill: color(0x7A7470)))
        }
        return root
    }
}

extension UIColor {
    func adjusted(brightness factor: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: s, brightness: min(1, b * factor), alpha: a)
    }
}
