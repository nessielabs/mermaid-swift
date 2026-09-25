# Changelog

All notable changes to this project are documented here. The project
follows [Semantic Versioning](https://semver.org).

## 0.1.3

- Edges run straight through their labels when their column crosses the
  label, instead of jogging to the label's center.
- Gaps between ranks grow when edges travel far sideways, so those edges
  are drawn as steep curves rather than near-flat diagonals.

## 0.1.2

- Long edges' bends line up in straight columns, removing wobble.

## 0.1.1

- Long edges no longer zig-zag (and loop) around clusters.
- A literal `\n` in a label breaks the line.

## 0.1.0

- Initial release: native parsing, layout and rendering of every Mermaid
  diagram type, with SVG, CGImage/PNG and SwiftUI output.
