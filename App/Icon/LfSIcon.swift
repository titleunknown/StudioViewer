// LfS Viewer app icon: an eye whose iris is a camera aperture, on the viewer's dark charcoal,
// with a green "live" dot. Drawn in code so it can be tweaked and re-rendered:
//     swift App/Icon/LfSIcon.swift      # writes App/Icon/icon-1024.png
// then App/Icon/make-iconset.sh fills the Xcode asset catalog.
// Layout follows Apple's macOS icon grid: an 824 pt rounded square centred on a 1024 canvas.
import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

let canvas: CGFloat = 1024
let bodySize: CGFloat = 824
let amber = Color(hex: 0xE0A63A)  // the viewer's accent (--accent in viewer.html)

/// The almond outline of the eye.
struct Almond: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.5))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY), control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.5))
        p.closeSubpath()
        return p
    }
}

/// Six aperture blades between a hexagonal opening (radius `inner`) and the iris edge (`outer`).
/// Each blade is bounded by one hexagon edge extended to the iris circle, the next edge's
/// extension, and the arc between them, which is how a real iris diaphragm reads.
func drawAperture(_ ctx: inout GraphicsContext, center c: CGPoint, inner: CGFloat, outer: CGFloat) {
    let n = 6
    let turn = -CGFloat.pi / 2 + 0.18  // a slight twist so it doesn't look like a plain hexagon
    let v = (0..<n).map { i -> CGPoint in
        let a = turn + CGFloat(i) * 2 * .pi / CGFloat(n)
        return CGPoint(x: c.x + inner * cos(a), y: c.y + inner * sin(a))
    }
    // Where the line from a through b, extended past b, meets the iris circle.
    func hit(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let d = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let len = hypot(d.x, d.y)
        let u = CGPoint(x: d.x / len, y: d.y / len)
        let f = CGPoint(x: b.x - c.x, y: b.y - c.y)
        let bq = f.x * u.x + f.y * u.y
        let t = -bq + sqrt(bq * bq - (f.x * f.x + f.y * f.y - outer * outer))
        return CGPoint(x: b.x + u.x * t, y: b.y + u.y * t)
    }
    let p = (0..<n).map { i in hit(v[(i + n - 1) % n], v[i]) }  // edge (i-1 -> i) extended past v[i]
    for i in 0..<n {
        let a0 = atan2(p[i].y - c.y, p[i].x - c.x)
        var a1 = atan2(p[(i + 1) % n].y - c.y, p[(i + 1) % n].x - c.x)
        while a1 < a0 { a1 += 2 * .pi }
        var blade = Path()
        blade.move(to: v[i])
        blade.addLine(to: p[i])
        for s in 1...24 {
            let a = a0 + (a1 - a0) * CGFloat(s) / 24
            blade.addLine(to: CGPoint(x: c.x + outer * cos(a), y: c.y + outer * sin(a)))
        }
        blade.closeSubpath()
        // Light falls from the top left: blades facing it are brighter.
        let mid = (a0 + a1) / 2
        let light = 0.5 + 0.5 * cos(mid - (-3 * .pi / 4))
        let top = Color(hex: 0xF6CB6E).opacity(0.75 + 0.25 * light)
        let bottom = Color(hex: 0xA8701C).opacity(0.85 + 0.15 * (1 - light))
        ctx.fill(blade, with: .linearGradient(Gradient(colors: [top, bottom]),
                                              startPoint: v[i], endPoint: p[(i + 1) % n]))
        ctx.stroke(blade, with: .color(Color(hex: 0x3A2508, opacity: 0.55)), lineWidth: 3)
    }
    // The opening: dark, with a glint.
    var hole = Path()
    hole.addLines(v)
    hole.closeSubpath()
    ctx.fill(hole, with: .radialGradient(Gradient(colors: [Color(hex: 0x1C232B), Color(hex: 0x06080A)]),
                                         center: c, startRadius: 0, endRadius: inner))
    let glint = CGRect(x: c.x - inner * 0.62, y: c.y - inner * 0.66, width: inner * 0.42, height: inner * 0.42)
    ctx.fill(Path(ellipseIn: glint), with: .color(.white.opacity(0.9)))
}

/// Four L-shaped framing marks, as in a camera viewfinder.
struct ViewfinderMarks: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let arm: CGFloat = 70
        for (corner, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1.0, 1.0), (CGPoint(x: r.maxX, y: r.minY), -1.0, 1.0),
                                 (CGPoint(x: r.minX, y: r.maxY), 1.0, -1.0), (CGPoint(x: r.maxX, y: r.maxY), -1.0, -1.0)] {
            p.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            p.addLine(to: corner)
            p.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        }
        return p
    }
}

struct Icon: View {
    var body: some View {
        let squircle = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            // Field: the viewer's charcoal, lit from the centre.
            squircle.fill(RadialGradient(colors: [Color(hex: 0x30343C), Color(hex: 0x16181C), Color(hex: 0x0C0D0F)],
                                         center: .init(x: 0.5, y: 0.42), startRadius: 0, endRadius: 520))
            // Brushed-metal bezel, as on PortScope and Mirror.
            squircle.strokeBorder(LinearGradient(colors: [Color(hex: 0xF2F4F6), Color(hex: 0x9EA4AB), Color(hex: 0x5D636A)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 22)
            squircle.inset(by: 22).strokeBorder(Color.black.opacity(0.55), lineWidth: 4)

            // Viewfinder corner marks around the eye.
            ViewfinderMarks()
                .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                .frame(width: 730, height: 540)

            // The eye.
            let eye = CGRect(x: 0, y: 0, width: 700, height: 330)
            ZStack {
                Almond().fill(LinearGradient(colors: [Color(hex: 0xFBFAF7), Color(hex: 0xD9D6CF)], startPoint: .top, endPoint: .bottom))
                Canvas { ctx, size in
                    var c = ctx
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    // The iris's dark rim, then the aperture inside it.
                    c.fill(Path(ellipseIn: CGRect(x: center.x - 192, y: center.y - 192, width: 384, height: 384)),
                           with: .color(Color(hex: 0x2A1A06)))
                    drawAperture(&c, center: center, inner: 70, outer: 179)
                    // A soft shine across the top of the iris.
                    c.fill(Path(ellipseIn: CGRect(x: center.x - 132, y: center.y - 172, width: 264, height: 120)),
                           with: .linearGradient(Gradient(colors: [.white.opacity(0.28), .white.opacity(0)]),
                                                 startPoint: CGPoint(x: center.x, y: center.y - 172),
                                                 endPoint: CGPoint(x: center.x, y: center.y - 52)))
                }
                .clipShape(Almond())
                // Lid shadow so the eye sits in the face, and a crisp outline.
                Almond().stroke(Color.black.opacity(0.35), lineWidth: 26).blur(radius: 10).clipShape(Almond())
                Almond().stroke(Color(hex: 0x0B0C0E), lineWidth: 10)
            }
            .frame(width: eye.width, height: eye.height)
            .shadow(color: amber.opacity(0.35), radius: 40)

            // Live, like a camera's REC light inside the viewfinder.
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x8AF0A8), Color(hex: 0x2FB35A)], center: .init(x: 0.4, y: 0.35),
                                     startRadius: 0, endRadius: 34))
                .frame(width: 54, height: 54)
                .overlay(Circle().stroke(Color(hex: 0x0B0C0E), lineWidth: 6))
                .shadow(color: Color(hex: 0x4CBB6C).opacity(0.8), radius: 18)
                .offset(x: 300, y: -205)
        }
        .frame(width: bodySize, height: bodySize)
        .clipShape(squircle)  // keep the eye's glow inside the icon
        .compositingGroup()
        .shadow(color: .black.opacity(0.35), radius: 14, y: 10)  // Apple's icon template drop shadow
        .frame(width: canvas, height: canvas)
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let image = renderer.cgImage else { fatalError("render failed") }
    let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
                  : (URL(fileURLWithPath: #filePath).deletingLastPathComponent().path + "/icon-1024.png"))
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: out)
    print("Wrote \(out.path) (\(image.width)x\(image.height))")
}
