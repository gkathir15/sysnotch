import SwiftUI

/// Which mark a provider cell draws.
enum ProviderGlyph: String, Codable, Equatable {
    case claude
    case devin
    case openai
    case third
    case cursor
    /// The raw value stays `gemini`: it is the key archived readings were
    /// written under, and renaming it would make every stored reading for this
    /// provider undecodable.
    case antigravity = "gemini"
    /// Gemini's own sparkle, for the provider that meters a raw API key.
    ///
    /// It cannot be called `gemini`: that raw value already names Antigravity's
    /// arch inside every archived snapshot, and swapping its meaning would
    /// redraw old readings as a mark they were never written for. So the
    /// sparkle gets a key of its own instead.
    case geminiSpark = "gemini-spark"
    case glm
    case qwen
    case gemma
    case meta
    case deepseek
    case mistral
    case grok
    case opencode
    case commandcode
    case copilot
    case kimi
    case kilo
    case kiro
    case amp
    case apify
    case minimax
    case ollama
    case ollamaLocal = "ollama-local"
    case lmstudio
    case llamaCpp = "llamacpp"
    /// The QianwenAI platform's own console mark, which is a different emblem
    /// from the local Qwen model brand in `.qwen` — a ring wearing this one is
    /// the platform account, not a model.
    case qoder
    case qianwenAI = "qianwenai"

    // System Activity Monitor glyphs
    case ram = "system-ram"
    case cpu = "system-cpu"
    case gpu = "system-gpu"
    case disk = "system-storage"
    case thermals = "system-thermals"
    case network = "system-network"
    case energy = "system-energy"
    case fan = "system-fan"

    var systemSymbolName: String? {
        switch self {
        case .ram: return "memorychip"
        case .cpu: return "cpu.fill"
        case .gpu: return "display"
        case .disk: return "internaldrive.fill"
        case .thermals: return "thermometer.medium"
        case .network: return "network"
        case .energy: return "bolt.fill"
        case .fan: return "fanblades.fill"
        default: return nil
        }
    }

    /// If an asset with this name is in the bundle it wins over the traced
    /// outline — drop a PDF/SVG export from Figma in and it is picked up.
    var assetName: String { self == .ollamaLocal ? "glyph-ollama" : "glyph-\(rawValue)" }

    /// How much to scale this mark so it reads the same size as the others.
    ///
    /// Every outline is normalised into the same unit box, which makes their
    /// *boxes* identical and their marks anything but: measured on screen at
    /// 16pt, the OpenAI knot covered 32px while the Gemini spark covered 25 —
    /// a fifth smaller — because a spark's points are thin and its corners are
    /// mostly empty. Boxes of equal size are not marks of equal size, and the
    /// eye reads the mark.
    ///
    /// Measured from a render rather than guessed: each value brings that
    /// glyph's ink to the same extent as Claude's.
    var opticalScale: CGFloat {
        switch self {
        case .claude: return 0.97
        case .cursor: return 0.97
        case .openai: return 0.94
        case .antigravity: return 1.0
        case .geminiSpark: return 1.0
        case .glm:    return 0.95
        case .grok:   return 1.0
        case .opencode: return 0.95
        case .commandcode: return 0.96
        case .copilot: return 0.96
        case .kimi:   return 0.95
        case .kilo:   return 0.97
        case .kiro:   return 0.95
        case .amp:    return 1.0
        // The asset's viewBox is cropped to the ink, so the mark fills its box
        // the way Claude's outline does and takes the same scale.
        case .apify:  return 0.97
        case .minimax: return 0.95
        case .ollama: return 0.95
        case .third:  return 1.0
        case .ollamaLocal: return 0.98
        case .lmstudio: return 0.96
        case .llamaCpp: return 1.0
        // The one value here measured off a render of the asset file rather
        // than of the app: this mark's ink fills 0.996 of its box, rasterised
        // with `rsvg-convert -w 512`. Claude's outline fills 0.997 at 0.97, so
        // the same scale brings this ink to the same extent.
        case .qianwenAI, .qoder: return 0.97
        case .devin, .qwen, .gemma, .meta, .deepseek, .mistral,
             .ram, .cpu, .gpu, .disk, .thermals, .network, .energy, .fan: return 1.0
        }
    }

    var outline: [[CGPoint]] {
        if systemSymbolName != nil { return [] }
        switch self {
        case .claude: return GlyphOutline.claude
        case .openai: return GlyphOutline.openai
        case .third:  return GlyphOutline.third
        case .cursor: return GlyphOutline.cursor
        case .antigravity: return GlyphOutline.antigravity
        case .geminiSpark: return GlyphOutline.gemini
        // Fallbacks only: glyph-glm, glyph-opencode, glyph-commandcode and
        // glyph-kimi in the asset catalogue are drawn instead.
        case .glm:    return GlyphOutline.glm
        case .devin, .qwen, .gemma, .meta, .deepseek, .mistral, .lmstudio,
             .qianwenAI, .qoder, .amp, .apify, .llamaCpp: return []
        case .grok:   return GlyphOutline.grok
        case .opencode: return GlyphOutline.opencode
        case .commandcode: return GlyphOutline.commandcode
        case .copilot: return GlyphOutline.copilot
        case .kimi:   return GlyphOutline.kimi
        case .kilo:   return GlyphOutline.kilo
        case .kiro:   return GlyphOutline.kiro
        // A fallback only: glyph-minimax in the asset catalogue is drawn instead.
        case .minimax: return GlyphOutline.minimax
        case .ollama, .ollamaLocal: return GlyphOutline.ollama
        case .ram, .cpu, .gpu, .disk, .thermals, .network, .energy, .fan: return []
        }
    }
}

/// A traced outline scaled into the view's bounds, filled even-odd so the
/// counters inside a knot stay open.
struct GlyphShape: Shape {
    let outline: [[CGPoint]]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for loop in outline {
            guard let first = loop.first else { continue }
            path.move(to: point(first, in: rect))
            for p in loop.dropFirst() { path.addLine(to: point(p, in: rect)) }
            path.closeSubpath()
        }
        return path
    }

    private func point(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }
}

/// A wireframe globe turning on its own axis.
///
/// The old mark was a flat `globe` symbol with a 3D flip on it, which reads as
/// a card being turned edge-on and then vanishing. This draws an orthographic
/// sphere instead: latitude rings stay put while the meridians sweep across the
/// face, so the mark is recognisably a globe at every frame, including the one
/// where it is seen straight on.
private struct SpinningGlobe: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let meridianCount = 12
    private let turnSeconds: Double = 9

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, phase: phase(at: timeline.date))
            }
        }
    }

    private func phase(at date: Date) -> Double {
        guard !reduceMotion else { return 0.7 }
        let turn = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: turnSeconds)
        return turn / turnSeconds * 2 * .pi
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, phase: Double) {
        let radius = min(size.width, size.height) / 2
        guard radius > 0 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let lineWidth = max(0.7, radius * 0.065)
        let sphereRect = CGRect(x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2)
        let sphere = Path(ellipseIn: sphereRect)

        // A soft light from the upper left makes the outline read as a volume
        // rather than as a circle full of grid lines.
        context.fill(sphere, with: .radialGradient(
            Gradient(colors: [Color.primary.opacity(0.24), Color.primary.opacity(0.03)]),
            center: CGPoint(x: center.x - radius * 0.38, y: center.y - radius * 0.38),
            startRadius: 0,
            endRadius: radius * 1.35
        ))
        context.stroke(sphere, with: .color(Color.primary.opacity(0.95)), lineWidth: lineWidth)

        context.drawLayer { layer in
            layer.clip(to: sphere)

            for latitude in stride(from: -60.0, through: 60.0, by: 30.0) {
                let angle = latitude * .pi / 180
                let y = center.y + radius * sin(angle)
                let halfWidth = radius * cos(angle)
                var line = Path()
                line.move(to: CGPoint(x: center.x - halfWidth, y: y))
                line.addLine(to: CGPoint(x: center.x + halfWidth, y: y))
                layer.stroke(line, with: .color(Color.primary.opacity(latitude == 0 ? 0.55 : 0.30)),
                             lineWidth: lineWidth * 0.75)
            }

            for index in 0..<meridianCount {
                let longitude = Double(index) / Double(meridianCount) * 2 * .pi + phase
                let facing = cos(longitude)
                guard facing > 0 else { continue }
                let halfWidth = radius * abs(sin(longitude))
                let opacity = 0.18 + 0.62 * facing
                let meridian: Path
                if halfWidth < 0.5 {
                    var line = Path()
                    line.move(to: CGPoint(x: center.x, y: center.y - radius))
                    line.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                    meridian = line
                } else {
                    meridian = Path(ellipseIn: CGRect(x: center.x - halfWidth,
                                                      y: center.y - radius,
                                                      width: halfWidth * 2,
                                                      height: radius * 2))
                }
                layer.stroke(meridian, with: .color(Color.primary.opacity(opacity)),
                             lineWidth: lineWidth * 0.8)
            }
        }
    }
}

struct ProviderGlyphView: View {
    let glyph: ProviderGlyph
    var customIconFilename: String? = nil
    var size: CGFloat = Design.px(46)
    /// The metric's own reading, 0–1, for the glyphs whose colour carries the
    /// number: the battery bolt and the thermal thermometer. Nil leaves them
    /// in the ordinary foreground colour, as in Settings where no reading is
    /// being drawn beside the mark.
    var level: Double? = nil

    @State private var fanDegrees: Double = 0

    /// Green, yellow or red, whichever the reading means.
    private var levelTint: Color? {
        guard let level, level.isFinite else { return nil }
        let value = min(max(level, 0), 1)
        switch glyph {
        case .energy:
            // A battery is good when it is full, unlike a quota.
            if value >= 0.50 { return Palette.ample }
            if value >= 0.20 { return Palette.watch }
            return Palette.critical
        case .thermals:
            // Thermal pressure is good when it is low: nominal/fair stay green,
            // serious is yellow, critical is red.
            if value < 0.50 { return Palette.ample }
            if value < 0.75 { return Palette.watch }
            return Palette.critical
        default:
            return nil
        }
    }

    var body: some View {
        Group {
            if let customIconFilename,
               let image = CustomIconStore.loadIcon(filename: customIconFilename) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else if glyph == .fan {
                Image(systemName: "fanblades.fill")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .rotationEffect(.degrees(fanDegrees))
                    .onAppear {
                        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                            fanDegrees = 360
                        }
                    }
            } else if glyph == .cpu {
                Image(systemName: "cpu.fill")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else if glyph == .network {
                SpinningGlobe()
            } else if glyph == .thermals {
                Image(systemName: "thermometer.medium")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(levelTint ?? Palette.textPrimary)
            } else if glyph == .energy {
                Image(systemName: "bolt.fill")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(levelTint ?? Palette.textPrimary)
                    .shadow(color: (levelTint ?? .clear).opacity(0.55), radius: size * 0.10)
            } else if let systemSymbol = glyph.systemSymbolName {
                Image(systemName: systemSymbol)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else if let image = NSImage(named: glyph.assetName) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                GlyphShape(outline: glyph.outline)
                    .fill(style: FillStyle(eoFill: true))
            }
        }
        // Scaled inside a frame of the fixed size, so the *layout* stays on a
        // single grid — every row still reserves the same width — while the ink
        // is evened out within it.
        .scaleEffect(glyph.opticalScale)
        .frame(width: size, height: size)
    }
}
