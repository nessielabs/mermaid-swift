import Foundation
import Mermaid

/// mermaid-render <input.mmd> <output.(svg|png)> [--theme name] [--scale n] [--transparent]
let arguments = Array(CommandLine.arguments.dropFirst())
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
guard arguments.count >= 2 else {
    fail("usage: mermaid-render <input.mmd|-> <output.svg|output.png> [--theme default|neutral|dark|forest|base] [--scale 2] [--transparent]")
}
var options = RenderOptions()
var scale = 2.0
var i = 2
while i < arguments.count {
    switch arguments[i] {
    case "--theme":
        i += 1
        guard i < arguments.count, let name = Theme.Name(rawValue: arguments[i]) else { fail("unknown theme") }
        options.theme = Theme(name)
    case "--scale":
        i += 1
        guard i < arguments.count, let value = Double(arguments[i]) else { fail("invalid scale") }
        scale = value
    case "--transparent":
        options.background = .transparent
    default:
        fail("unknown option \(arguments[i])")
    }
    i += 1
}
let input: String
if arguments[0] == "-" {
    input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
} else if let text = try? String(contentsOfFile: arguments[0], encoding: .utf8) {
    input = text
} else {
    fail("cannot read \(arguments[0])")
}
do {
    let scene = try Mermaid.render(input, options: options)
    let url = URL(fileURLWithPath: arguments[1])
    if url.pathExtension.lowercased() == "png" {
        #if canImport(ImageIO)
        guard let data = scene.pngData(scale: scale) else { fail("rendering failed") }
        try data.write(to: url)
        #else
        fail("PNG output requires CoreGraphics; write .svg instead")
        #endif
    } else {
        try scene.svg.write(to: url, atomically: true, encoding: .utf8)
    }
} catch let error as MermaidError {
    fail("error: \(error)")
} catch {
    fail("error: \(error)")
}
