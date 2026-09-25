# MermaidSwift

Render [Mermaid](https://mermaid.js.org) diagrams natively in Swift — no
WebView, no JavaScript engine, no network. MermaidSwift parses Mermaid
source, lays it out, and draws it with CoreGraphics and CoreText, SVG, or
SwiftUI.

```swift
import Mermaid

let scene = try Mermaid.render("""
flowchart LR
  A[Request] --> B{Cached?}
  B -->|yes| C[Serve]
  B -->|no| D[(Database)] --> C
""")

let svg: String = scene.svg
let png: Data? = scene.pngData(scale: 2)
```

```swift
import SwiftUI
import Mermaid

struct DiagramView: View {
    var body: some View {
        MermaidView("""
        sequenceDiagram
          Alice->>Bob: Hello
          Bob-->>Alice: Hi!
        """)
    }
}
```

## Features

- **Mermaid-compatible syntax** for every diagram type, including front
  matter, `%%{init}%%` directives, `classDef`/`style`, markdown and HTML
  labels, entity codes, and accessibility (`accTitle`/`accDescr`).
- **Mermaid's themes** (`default`, `neutral`, `dark`, `forest`, `base`) with
  the same `themeVariables` names and derivation rules, so existing
  configuration carries over.
- **Native text**: labels are measured and drawn with the same CoreText
  fonts, so text never overflows its shape.
- **Precise errors**: malformed source produces a `MermaidError` with the
  line and column of the problem, never a crash.
- **Outputs**: SVG strings, `CGImage`, PNG data, and a SwiftUI view that
  follows light and dark mode.
- **No dependencies.** The parse → layout → SVG path also builds on Linux.

## Installation

Add the package to `Package.swift`:

```swift
.package(url: "https://github.com/nessielabs/mermaid-swift.git", branch: "main")
```

and depend on the `Mermaid` product. Requires Swift 6 and macOS 13, iOS 16,
tvOS 16, watchOS 9, or visionOS 1.

## Usage

```swift
// Parse once, render many times.
let diagram = try Mermaid.parse(source)
print(diagram.type)                       // .flowchart

// Choose a theme (overrides the diagram's own configuration).
let dark = try diagram.scene(options: RenderOptions(theme: .dark))

// Customize like mermaid.js themeVariables.
let branded = Theme(.base, variables: ["primaryColor": "#BB2528", "lineColor": "#F8B229"])
let scene = try diagram.scene(options: RenderOptions(theme: branded, background: .transparent))

// Draw into any y-down CGContext (UIKit, AppKit flipped views).
CoreGraphicsRenderer.draw(scene, in: context)
```

Errors carry locations:

```swift
do {
    _ = try Mermaid.render("flowchart TD\n  A[unclosed --> B")
} catch let error as MermaidError {
    print(error)   // 2:3: Node label is missing its closing ']'
}
```

## Command line

```sh
swift run mermaid-render diagram.mmd diagram.png --theme dark --scale 2
swift run mermaid-render diagram.mmd diagram.svg
```

## How it works

Source is preprocessed (front matter, directives, comments), dispatched to
a per-type parser, and laid out into a renderer-independent `Scene` of
shapes, text and groups. Graph diagrams use a from-scratch layered
(Sugiyama) layout with nested clusters, label slots, edge ports, and all
four directions. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
