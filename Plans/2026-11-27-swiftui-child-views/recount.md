# Recount the SwiftUI declarations

Run from the repository root with the Xcode in `.xcode-version`. The recipe reads the working copies of tracked Swift files. Use a clean checkout of `5b1747d01` to reproduce the baseline, or run it on a later checkout to measure progress. If the checkout predates this plan, point `recipe` at this document in the plan checkout.

```sh
(
set -eu
recipe=Plans/2026-11-27-swiftui-child-views/recount.md
audit_dir=$(mktemp -d)
compiler=$(xcrun --find swiftc)
host_lib=${compiler%/bin/swiftc}/lib/swift/host
awk '/^```swift$/ {inside=1; next} inside && /^```$/ {exit} inside' "$recipe" > "$audit_dir/recount.swift"
"$compiler" -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -I "$host_lib" -L "$host_lib" -Xlinker -rpath -Xlinker "$host_lib" \
  -module-cache-path "$audit_dir/cache" "$audit_dir/recount.swift" -o "$audit_dir/recount"
git ls-files -z -- '*.swift' > "$audit_dir/files"
"$audit_dir/recount" < "$audit_dir/files" > "$audit_dir/rows.tsv"
awk -F '\t' '{n[$1]++} END {
  print "Helpers", n["same-file"]+n["own-file"]+n["preserve"], "preserved", n["preserve"]+0
  print "Candidates", n["same-file"]+n["own-file"], "same-file", n["same-file"]+0, "own-file", n["own-file"]+0
  print "Named bodies to review", n["named-review"]+0
  print "Small named bodies for ownership review", n["small-named-review"]+0
}' "$audit_dir/rows.tsv"
printf 'Rows saved to %s\n' "$audit_dir/rows.tsv"
)
```

Each TSV row gives the disposition, source file, declaration or attribute line, owning type, symbol and measured body lines. The baseline yields 208 helper hits, 14 preserved boundaries, 194 candidates (124 same-file, 70 own-file) and 34 named bodies of 20+ lines in differently named files. Check callers before treating a filename mismatch as a misplaced child.

The 113 rows marked `small-named-review` form a separate ownership review pool. Each body measures 5–19 lines and its declaring type matches the file stem. Trace its entry points and parents to distinguish a single parent’s private child from a screen, shared component or framework-facing entry point. See the [small named views](small-named-views.md).

```swift
import Foundation
import SwiftParser
import SwiftSyntax

final class Recount: SyntaxVisitor {
    let path: String
    let location: SourceLocationConverter
    let nonblank: Set<Int>

    init(path: String, source: String, tree: SourceFileSyntax) {
        self.path = path
        location = SourceLocationConverter(fileName: path, tree: tree)
        nonblank = Set(source.components(separatedBy: "\n").enumerated().compactMap { index, text in
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : index + 1
        })
        super.init(viewMode: .sourceAccurate)
    }

    func owner(of declaration: some SyntaxProtocol) -> (name: String, inherits: [String]) {
        var current = declaration.parent
        while let node = current {
            current = node.parent
            let name: String
            let clause: InheritanceClauseSyntax?
            if let t = node.as(StructDeclSyntax.self) { (name, clause) = (t.name.text, t.inheritanceClause) }
            else if let t = node.as(ClassDeclSyntax.self) { (name, clause) = (t.name.text, t.inheritanceClause) }
            else if let t = node.as(EnumDeclSyntax.self) { (name, clause) = (t.name.text, t.inheritanceClause) }
            else if let t = node.as(ExtensionDeclSyntax.self) {
                (name, clause) = (t.extendedType.trimmedDescription, t.inheritanceClause)
            } else { continue }
            return (name, clause?.inheritedTypes.map { $0.type.trimmedDescription } ?? [])
        }
        return ("", [])
    }

    func inspect(_ node: some SyntaxProtocol, name: String, statements: CodeBlockItemListSyntax) {
        var lines = Set<Int>()
        for token in statements.tokens(viewMode: .sourceAccurate) where !token.text.isEmpty {
            let first = location.location(for: token.positionAfterSkippingLeadingTrivia).line
            let last = location.location(for: token.endPositionBeforeTrailingTrivia).line
            lines.formUnion(first...last)
        }
        let size = lines.intersection(nonblank).count
        guard size >= 5 else { return }
        let type = owner(of: node)
        let role: String
        if name == "body" {
            let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            guard node.is(PatternBindingSyntax.self) else { return }
            if size >= 20 && type.name != stem {
                role = "named-review"
            } else if size < 20 && type.name == stem {
                role = "small-named-review"
            } else { return }
        } else if type.name == "View" || (name == "content" && type.inherits.contains("WhereScreen"))
            || (name == "makeBody" && type.inherits.contains { ["ButtonStyle", "PrimitiveButtonStyle"].contains($0) }) {
            role = "preserve"
        } else {
            role = size < 20 ? "same-file" : "own-file"
        }
        let line = location.location(for: node.positionAfterSkippingLeadingTrivia).line
        print([role, path, String(line), type.name, name, String(size)].joined(separator: "\t"))
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.signature.returnClause?.type.trimmedDescription == "some View", let body = node.body {
            inspect(node, name: node.name.text, statements: body.statements)
        }
        return .visitChildren
    }

    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        guard node.typeAnnotation?.type.trimmedDescription == "some View", let block = node.accessorBlock
        else { return .visitChildren }
        let name = node.pattern.trimmedDescription
        switch block.accessors {
        case .getter(let statements): inspect(node, name: name, statements: statements)
        case .accessors(let getters):
            if let body = getters.first(where: { $0.accessorSpecifier.text == "get" })?.body {
                inspect(node, name: name, statements: body.statements)
            }
        @unknown default: preconditionFailure("Unexpected SwiftSyntax accessor in \(path)")
        }
        return .visitChildren
    }
}

for bytes in FileHandle.standardInput.readDataToEndOfFile().split(separator: 0) {
    let path = String(decoding: bytes, as: UTF8.self)
    let source = try String(contentsOfFile: path, encoding: .utf8)
    let tree = Parser.parse(source: source)
    precondition(!tree.hasError, "Could not parse \(path)")
    Recount(path: path, source: source, tree: tree).walk(tree)
}
```

## Recheck the inline review locations

Start at the opening lines in the [inline index](audit.md#inline-review-locations). For changed files, walk `ClosureExprSyntax` in call arguments and ordinary or labeled trailing closures. Count tokens in the statements, then identify the actual argument role from its label, overload and source. Inspect `if` and `switch` branches, local view bindings, and complete expressions with their modifiers, including expressions with short closures. For a button, trace the initializer, all arguments and trailing closures, and its attached modifiers. Count distinct code lines across that entire expression, even when the action or label fits on one line. Compare against the [whole-button inventory](buttons.md). Resolve nested label and layout hits to the same control. Preserve the parent’s state and any action it supplies. Inspect map and toolbar builders for the visual children they host.
