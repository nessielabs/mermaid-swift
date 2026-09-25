import Testing
@testable import Mermaid

@Suite("Preprocessor")
struct PreprocessorTests {
    @Test func extractsFrontMatterTitleAndConfig() throws {
        let source = """
        ---
        title: Checkout flow
        config:
          theme: dark
          themeVariables:
            primaryColor: "#ff0000"
        ---
        flowchart LR
          A --> B
        """
        let prepared = try Preprocessor.prepare(source)
        #expect(prepared.title == "Checkout flow")
        #expect(prepared.config["theme"] == .string("dark"))
        #expect(prepared.config["themeVariables"]?["primaryColor"] == .string("#ff0000"))
        #expect(prepared.header?.text == "flowchart LR")
        #expect(prepared.header?.number == 8)
    }

    @Test func mergesInitDirectivesOverFrontMatter() throws {
        let source = """
        ---
        config:
          theme: dark
          flowchart: { curve: basis }
        ---
        %%{init: {'theme': 'forest', "flowchart": {htmlLabels: false,}}}%%
        graph TD
        """
        let config = try Preprocessor.prepare(source).config
        #expect(config["theme"] == .string("forest"))
        #expect(config["flowchart"]?["curve"] == .string("basis"))
        #expect(config["flowchart"]?["htmlLabels"] == .bool(false))
    }

    @Test func multiLineDirectivesKeepLineNumbers() throws {
        let source = "%%{\n  init: { \"theme\": \"neutral\" }\n}%%\n%% a comment\nsequenceDiagram"
        let prepared = try Preprocessor.prepare(source)
        #expect(prepared.config["theme"] == .string("neutral"))
        #expect(prepared.header == SourceLine(number: 5, text: "sequenceDiagram", indent: 0))
    }

    @Test func unterminatedFrontMatterIsALocatedError() {
        #expect(throws: MermaidError(.configuration, "Front matter is missing its closing '---'",
                                     at: SourceLocation(line: 1, column: 1))) {
            try Preprocessor.prepare("---\ntitle: x\ngraph TD")
        }
    }

    @Test func lenientJSONAcceptsRelaxedSyntax() throws {
        let value = try LenientJSON.parse("{a: 1, 'b': [true, null, \"x\",], c: {d: 2.5},}")
        #expect(value == .object([
            "a": .number(1),
            "b": .array([.bool(true), .null, .string("x")]),
            "c": .object(["d": .number(2.5)]),
        ]))
    }

    @Test func yamlSequencesAndScalars() throws {
        let lines = SourceLine.split("items:\n  - one\n  - 2\nflag: yes\nname: 'quoted # not a comment'")
        let value = try FrontMatterYAML.parse(lines)
        #expect(value["items"] == .array([.string("one"), .number(2)]))
        #expect(value["flag"] == .bool(true))
        #expect(value["name"] == .string("quoted # not a comment"))
    }

    @Test func configNumbersAcceptPixelSuffix() {
        #expect(ConfigValue.string("16px").numberValue == 16)
    }

    @Test func topLevelDisplayModeConfiguresGantt() throws {
        let prepared = try Preprocessor.prepare("---\ndisplayMode: compact\n---\ngantt\n")
        #expect(prepared.config["gantt"]?["displayMode"] == .string("compact"))
        let explicit = try Preprocessor.prepare("---\ndisplayMode: compact\nconfig:\n  gantt:\n    displayMode: standard\n---\ngantt\n")
        #expect(explicit.config["gantt"]?["displayMode"] == .string("standard"))
    }
}
