# Architecture

MermaidSwift turns Mermaid source into drawings without a browser, a
JavaScript engine, or a network connection. Every diagram flows through
the same pipeline:

```
source ──▶ Preprocessor ──▶ DiagramRegistry ──▶ <Type>Parser ──▶ <Type>Diagram
                                                                    │
            SVG / CGImage / PNG / SwiftUI ◀── renderers ◀── Scene ◀─┘ scene(in: RenderContext)
```

## Layers

| Layer | Location | Responsibility |
|---|---|---|
| Core | `Sources/Mermaid/Core` | `Scanner` (character cursor with line/column), `SourceLine` (line splitter), `MermaidError` with locations |
| Config | `Sources/Mermaid/Config` | front matter YAML, `%%{init}%%` directives, `ConfigValue`, `Preprocessor` |
| Style | `Sources/Mermaid/Style` | CSS `Color`, `ElementStyle` (`style`/`classDef` declarations), `Theme` with Mermaid's five themes and derivation rules |
| Text | `Sources/Mermaid/Text` | `LabelParser` (HTML-ish and markdown labels → `RichText`), `TextMeasurer` (CoreText or approximate), `TextBlock` (measured, wrapped lines) |
| Scene | `Sources/Mermaid/Scene` | `Point`/`Size`/`Rect`, `Path` (move/line/cubic/close), `Scene` of shapes (flat or linear-gradient fills), text and groups |
| Layout | `Sources/Mermaid/Layout` | `LayeredLayout`: Sugiyama layout with clusters, labels, ports and all four directions |
| Shared | `Sources/Mermaid/Shared` | `NodeShape` catalog and geometry, `ShapeRenderer`, `Connector` (clipped, curved edges with markers and labels), `Marker`, `Curve`, `DiagramCanvas`, chart helpers (d3-compatible ticks and scales, anchored text, nested theme variables) |
| Diagrams | `Sources/Mermaid/Diagrams/<Type>` | one folder per diagram type: model, parser, scene builder |
| Render | `Sources/Mermaid/Render` | `SVGRenderer`, `CoreGraphicsRenderer`, image export, SwiftUI view |
| API | `Sources/Mermaid/API` | `Mermaid.parse/render`, `Diagram` protocol, `RenderContext`, `DiagramRegistry` |

## Principles

- **One scene model.** Diagram types never draw directly. They produce a
  `Scene`; renderers only consume scenes, so every output format stays
  consistent and each drawing primitive is implemented once.
- **Measure with the fonts you draw with.** Layout sizes shapes with the
  `TextMeasurer` in the `RenderContext`; the CoreGraphics renderer uses the
  same `FontResolver`, so labels never overflow their shapes.
- **Diagram space is top-left, y-down**, like SVG. Bitmap export flips
  explicitly (tested pixel by pixel).
- **Errors are located.** Parsers throw `MermaidError` with the line and
  column of the problem. Unknown or malformed input never crashes.
- **Mermaid compatibility first.** Syntax, theme variable names,
  configuration keys and defaults follow mermaid.js. Deliberate leniency
  (accepting input mermaid.js rejects) is documented at the call site.
- **No dependencies.** Foundation, CoreGraphics, CoreText, ImageIO and
  SwiftUI only. The parse → layout → SVG path works without CoreText.

## Adding a diagram type

1. `Diagrams/<Type>/<Type>Diagram.swift`: a `Sendable` model struct with
   `static let type = DiagramType.<case>` and `accessibility`.
2. `Diagrams/<Type>/<Type>Parser.swift`: `static func parse(_ source:
   DiagramSource) throws -> <Type>Diagram`. Use `source.lines` for
   line-oriented grammars or `Scanner(source.text)` for free-form ones.
   `accTitle`/`accDescr` are already extracted into `source.accessibility`.
3. `Diagrams/<Type>/<Type>Diagram+Scene.swift`: conform to `Diagram` and
   build a `Scene`, laying out at the origin and finishing with
   `DiagramCanvas(context:).scene(content:size:)`. Read settings from
   `context.section("<configKey>")` using mermaid.js key names and defaults,
   and colors from `context.theme` (use `theme.color("<variable>", default:)`
   for diagram-specific theme variables).
4. Register the header keywords in `DiagramRegistry.entries`
   (`Sources/Mermaid/API/Mermaid.swift`).
5. Tests in `Tests/MermaidTests/<Type>*Tests.swift` covering the grammar,
   errors, and layout invariants (no overlaps, ordering, sizes).
6. Render real examples with `swift run mermaid-render in.mmd out.png` and
   look at them.
