# Contributing

## Building and testing

```sh
swift build
swift test
swift run mermaid-render diagram.mmd diagram.png   # or .svg
```

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before changing code.

## Code

- Swift 6 language mode, value types, `Sendable` throughout.
- Match the surrounding style: doc comments on public API and on
  non-obvious decisions, no dead code, no force unwraps on external input.
- Keep public API minimal and deliberate.
- Parsers must never crash on malformed input; throw a located
  `MermaidError` instead.
- Tests use Swift Testing (`import Testing`). Cover the grammar, error
  cases, and geometric invariants of the output (for example: no node
  overlaps, correct ordering, labels inside their shapes).
- Look at rendered output before sending a change that affects drawing.

## Commits

- [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat(sequence): ...`, `fix(layout): ...`, `test(pie): ...`).
- Small, focused commits of roughly 100 changed lines, each building and
  passing tests on its own. Separate features, fixes, tests, and refactors.
- A body that explains what changed and why.
