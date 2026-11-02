import Cocoa
import CoreGraphics

func createAntigravityOrbit3DIcon(size: CGFloat) -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to create bitmap context")
    }

    let nsCtx = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    guard let ctx = nsCtx?.cgContext else {
        fatalError("Failed to get cgContext")
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // MARK: - 0. Clear Transparent Canvas (Nền hoàn toàn trong suốt)
    ctx.clear(rect)

    let center = CGPoint(x: size * 0.5, y: size * 0.5)

    // Geometry parameters for 3D Intersecting Orbit
    let ringRadiusX = size * 0.44
    let ringRadiusY = size * 0.165
    let tilt1: CGFloat = -CGFloat.pi * 0.14  // -25 deg tilt
    let tilt2: CGFloat = CGFloat.pi * 0.14   // +25 deg tilt

    // Helper: draw an arc segment of an inclined ellipse
    func drawOrbitArc(tiltAngle: CGFloat, startAngle: CGFloat, endAngle: CGFloat, glowColor: NSColor, strokeWidth: CGFloat, alpha: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: tiltAngle)

        // Scale transform to form ellipse from circular arc
        ctx.scaleBy(x: 1.0, y: ringRadiusY / ringRadiusX)

        let arcPath = CGMutablePath()
        arcPath.addArc(center: .zero, radius: ringRadiusX, startAngle: startAngle, endAngle: endAngle, clockwise: false)

        // Outer soft glow
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: size * 0.022, color: glowColor.cgColor)
        ctx.addPath(arcPath)
        ctx.setStrokeColor(glowColor.withAlphaComponent(alpha * 0.75).cgColor)
        ctx.setLineWidth(strokeWidth * 1.8)
        ctx.setLineCap(.round)
        ctx.strokePath()
        ctx.restoreGState()

        // Core crisp path
        ctx.addPath(arcPath)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(alpha * 0.95).cgColor)
        ctx.setLineWidth(strokeWidth)
        ctx.setLineCap(.round)
        ctx.strokePath()

        ctx.restoreGState()
    }

    // Helper: draw a satellite node
    func drawSatellite(tiltAngle: CGFloat, t: CGFloat, baseColor: NSColor, glowColor: NSColor, radius: CGFloat) {
        let unrotatedX = ringRadiusX * cos(t)
        let unrotatedY = ringRadiusY * sin(t)
        let cosA = cos(tiltAngle)
        let sinA = sin(tiltAngle)
        let satX = center.x + (unrotatedX * cosA - unrotatedY * sinA)
        let satY = center.y + (unrotatedX * sinA + unrotatedY * cosA)
        let satCenter = CGPoint(x: satX, y: satY)

        // Outer Bloom Glow
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: radius * 2.4, color: glowColor.cgColor)
        ctx.addArc(center: satCenter, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        ctx.setFillColor(glowColor.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Satellite Body
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: radius * 1.1, color: baseColor.cgColor)
        ctx.addArc(center: satCenter, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        ctx.setFillColor(baseColor.cgColor)
        ctx.fillPath()

        // Glowing Pure White Center
        ctx.addArc(center: satCenter, radius: radius * 0.48, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()

        // White Halo Edge
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
        ctx.setLineWidth(radius * 0.20)
        ctx.addArc(center: satCenter, radius: radius + radius * 0.35, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - LAYER 1: Orbit BACKGROUND (Nét phía sau lưng con thoi Antigravity)
    // Primary Orbit 1 (Cyan) - Background Arc: from 0.85*pi to 1.85*pi (nửa trên/xa)
    drawOrbitArc(
        tiltAngle: tilt1,
        startAngle: CGFloat.pi * 0.82,
        endAngle: CGFloat.pi * 1.82,
        glowColor: NSColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 0.85),
        strokeWidth: size * 0.006,
        alpha: 0.70
    )

    // Crossing Orbit 2 (Mint/Purple) - Background Arc: from 0.18*pi to 1.18*pi
    drawOrbitArc(
        tiltAngle: tilt2,
        startAngle: CGFloat.pi * 0.18,
        endAngle: CGFloat.pi * 1.18,
        glowColor: NSColor(red: 0.0, green: 0.95, blue: 0.65, alpha: 0.8),
        strokeWidth: size * 0.0055,
        alpha: 0.65
    )

    // Satellite 3 (Electric Violet) - Background node (nằm ở phía sau lưng)
    drawSatellite(
        tiltAngle: tilt2,
        t: CGFloat.pi * 0.80,
        baseColor: NSColor(red: 0.88, green: 0.42, blue: 1.0, alpha: 1.0),
        glowColor: NSColor(red: 0.75, green: 0.25, blue: 1.0, alpha: 0.9),
        radius: size * 0.034
    )

    // MARK: - LAYER 2: Official Antigravity Gradient Logo Core (Con thoi Gradient Google chính thức)
    let candidates = [
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/AntigravityGradientLogo.png").path,
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("AntigravityGradientLogo.png").path,
        "/Applications/Antigravity IDE.app/Contents/Resources/app/out/media/antigravity-gradient-logo.svg"
    ]
    let gradientLogoPath = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? candidates[0]
    guard let gradientLogo = NSImage(contentsOfFile: gradientLogoPath) else {
        fatalError("Cannot load AntigravityGradientLogo.png at \(gradientLogoPath)")
    }

    // Large Size: 84% of canvas (to lớn, nổi bật)
    let logoSize: CGFloat = size * 0.84
    let logoRect = CGRect(
        x: center.x - logoSize * 0.5,
        y: center.y - logoSize * 0.5,
        width: logoSize,
        height: logoSize
    )

    // Soft drop shadow to separate Antigravity logo from the background orbit lines
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.015),
        blur: size * 0.035,
        color: NSColor.black.withAlphaComponent(0.40).cgColor
    )
    nsCtx?.imageInterpolation = .high
    gradientLogo.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    ctx.restoreGState()

    // MARK: - LAYER 3: Orbit FOREGROUND (Nét phía trước vắt ngang qua mặt con thoi)
    // Primary Orbit 1 (Cyan) - Foreground Arc: from -0.18*pi to 0.82*pi (nửa dưới/gần)
    // This arc visibly loops OVER the front of the Antigravity shuttle!
    drawOrbitArc(
        tiltAngle: tilt1,
        startAngle: -CGFloat.pi * 0.18,
        endAngle: CGFloat.pi * 0.82,
        glowColor: NSColor(red: 0.0, green: 0.90, blue: 1.0, alpha: 1.0),
        strokeWidth: size * 0.009,
        alpha: 0.95
    )

    // Luminous Energy Motion Sweep across the foreground section of Orbit 1
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: tilt1)
    ctx.scaleBy(x: 1.0, y: ringRadiusY / ringRadiusX)

    let sweepPath = CGMutablePath()
    sweepPath.addArc(center: .zero, radius: ringRadiusX, startAngle: 0.05, endAngle: 0.70, clockwise: false)

    ctx.setShadow(offset: .zero, blur: size * 0.035, color: NSColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 1.0).cgColor)
    ctx.addPath(sweepPath)
    ctx.setStrokeColor(NSColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 1.0).cgColor)
    ctx.setLineWidth(size * 0.016)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Crossing Orbit 2 (Neon Mint) - Foreground Arc: from 1.18*pi to 2.18*pi
    // This arc loops OVER the front of the Antigravity shuttle in opposite direction!
    drawOrbitArc(
        tiltAngle: tilt2,
        startAngle: CGFloat.pi * 1.18,
        endAngle: CGFloat.pi * 2.18,
        glowColor: NSColor(red: 0.0, green: 1.0, blue: 0.65, alpha: 0.95),
        strokeWidth: size * 0.008,
        alpha: 0.90
    )

    // Satellite 1: Active Node (Cyan) - FOREGROUND (Vắt nổi ở mặt trước bên phải con thoi)
    drawSatellite(
        tiltAngle: tilt1,
        t: 0.42,
        baseColor: NSColor(red: 0.0, green: 0.98, blue: 1.0, alpha: 1.0),
        glowColor: NSColor(red: 0.0, green: 0.90, blue: 1.0, alpha: 1.0),
        radius: size * 0.046
    )

    // Satellite 2: Standby Node (Neon Mint) - FOREGROUND (Vắt nổi ở mặt trước bên trái con thoi)
    drawSatellite(
        tiltAngle: tilt2,
        t: CGFloat.pi * 1.62,
        baseColor: NSColor(red: 0.0, green: 1.0, blue: 0.68, alpha: 1.0),
        glowColor: NSColor(red: 0.0, green: 0.95, blue: 0.58, alpha: 1.0),
        radius: size * 0.040
    )

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

let iconSize: CGFloat = 1024
let bitmapRep = createAntigravityOrbit3DIcon(size: iconSize)

guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to render icon to PNG")
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon1024.png"
try! pngData.write(to: URL(fileURLWithPath: outputPath))
print("Successfully generated Official Gradient Antigravity with 3D Fore/Background Orbit Icon: \(outputPath)")
