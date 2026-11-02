import AppKit
import WebKit

class SvgRenderer: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var onFinish: (() -> Void)?

    override init() {
        let config = WKWebViewConfiguration()
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024), configuration: config)
        self.webView.setValue(false, forKey: "drawsBackground")
        super.init()
        self.webView.navigationDelegate = self
    }

    func render(svgPath: String, outputPath: String, completion: @escaping (Bool) -> Void) {
        guard let svgData = try? Data(contentsOf: URL(fileURLWithPath: svgPath)),
              var svgString = String(data: svgData, encoding: .utf8) else {
            completion(false)
            return
        }

        svgString = svgString.replacingOccurrences(of: "<svg width=\"96\" height=\"96\"", with: "<svg viewBox=\"0 0 96 96\" width=\"100%\" height=\"100%\"")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body { width: 1024px; height: 1024px; background: transparent; overflow: hidden; }
        svg { width: 1024px; height: 1024px; display: block; }
        </style>
        </head>
        <body>
        \(svgString)
        </body>
        </html>
        """

        self.onFinish = { [weak self] in
            guard let self = self else { return }
            let snapConfig = WKSnapshotConfiguration()
            snapConfig.rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
            self.webView.takeSnapshot(with: snapConfig) { image, error in
                guard let img = image,
                      let tiff = img.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    completion(false)
                    return
                }
                do {
                    try png.write(to: URL(fileURLWithPath: outputPath))
                    completion(true)
                } catch {
                    completion(false)
                }
            }
        }

        self.webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.onFinish?()
        }
    }
}

let svgPath = "/Applications/Antigravity IDE.app/Contents/Resources/app/out/media/antigravity-gradient-logo.svg"
let projectDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
let outPath = URL(fileURLWithPath: projectDir).appendingPathComponent("Resources/AntigravityGradientLogo.png").path

let renderer = SvgRenderer()
var finished = false
var success = false

renderer.render(svgPath: svgPath, outputPath: outPath) { res in
    success = res
    finished = true
}

while !finished {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
}

if success {
    print("✔ Extracted official Antigravity Gradient Logo to: \(outPath)")
} else {
    print("❌ Failed to extract logo")
    exit(1)
}
