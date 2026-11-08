import Foundation
import Testing
@testable import SaytileKit

@Suite("Diagnostic directory boundaries before Store initialization")
struct DiagnosticDirectoryTests {
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-diagnostic-boundary-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func defaultProductionRootDescendantsAndLexicalAliasesRejectWithoutOpeningIt() throws {
        let production = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Saytile", isDirectory: true)
        // Construct URLs only. Validation rejects these lexically before lstat,
        // realpath, archive reads or directory creation on the user's actual path.
        for candidate in [production, production.appendingPathComponent("Audio/new-diagnostic"),
                          production.appendingPathComponent("unused/../new-diagnostic"),
                          URL(fileURLWithPath: production.path.uppercased())] {
            #expect(throws: DiagnosticDirectory.ValidationError.isolationRequired) {
                try DiagnosticDirectory.validate(directory: candidate)
            }
        }
    }

    @Test func parentAliasesAndMissingDescendantsCannotReachSyntheticProduction() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let production = root.appendingPathComponent("Saytile")
        try FileManager.default.createDirectory(at: production, withIntermediateDirectories: true)
        let marker = production.appendingPathComponent("keep.txt")
        let bytes = Data("synthetic archive must remain unchanged".utf8); try bytes.write(to: marker)
        let direct = root.appendingPathComponent("direct-alias")
        let parent = root.appendingPathComponent("parent-alias")
        try FileManager.default.createSymbolicLink(at: direct, withDestinationURL: production)
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: root)
        for candidate in [direct, direct.appendingPathComponent("not-created/deeper"),
                          parent.appendingPathComponent("Saytile/not-created/deeper")] {
            #expect(throws: DiagnosticDirectory.ValidationError.isolationRequired) {
                try DiagnosticDirectory.validate(directory: candidate, productionDirectory: production)
            }
        }
        #expect(try Data(contentsOf: marker) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: production.path) == ["keep.txt"])
    }

    @Test func newIndependentPathAndStandardParentAliasAreAcceptedWithoutMutation() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let production = root.appendingPathComponent("Saytile")
        let safe = root.appendingPathComponent("safe")
        try FileManager.default.createDirectory(at: safe, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("safe-parent-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: safe)
        let sibling = root.appendingPathComponent("Saytile-tests/new")
        let child = alias.appendingPathComponent("new/deeper")
        try DiagnosticDirectory.validate(directory: sibling, productionDirectory: production)
        try DiagnosticDirectory.validate(directory: child, productionDirectory: production)
        #expect(!FileManager.default.fileExists(atPath: sibling.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: safe.path).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: production.path))
    }

    @Test func danglingProductionAliasAndCyclesFailClosedWithoutCreatingTheirTargets() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let production = root.appendingPathComponent("not-yet-created-production")
        let dangling = root.appendingPathComponent("dangling-parent")
        try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: production)
        let first = root.appendingPathComponent("cycle-first"), second = root.appendingPathComponent("cycle-second")
        try FileManager.default.createSymbolicLink(at: first, withDestinationURL: second)
        try FileManager.default.createSymbolicLink(at: second, withDestinationURL: first)
        for candidate in [dangling, dangling.appendingPathComponent("never-created/deeper"),
                          first, second.appendingPathComponent("never-created/deeper")] {
            #expect(throws: DiagnosticDirectory.ValidationError.isolationRequired) {
                try DiagnosticDirectory.validate(directory: candidate, productionDirectory: production)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: production.path))
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)) == ["dangling-parent", "cycle-first", "cycle-second"])
    }

    @Test func leafAliasesFilesAndInvalidURLsRejectWithPathFreeErrors() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let production = root.appendingPathComponent("production")
        let safe = root.appendingPathComponent("safe")
        try FileManager.default.createDirectory(at: safe, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("owned-leaf-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: safe)
        let file = root.appendingPathComponent("not-a-directory")
        try Data("fixture".utf8).write(to: file)
        for candidate in [alias, file, file.appendingPathComponent("child"), URL(string: "https://example.invalid/data")!] {
            do {
                try DiagnosticDirectory.validate(directory: candidate, productionDirectory: production)
                Issue.record("unsafe diagnostic directory was accepted")
            } catch {
                #expect(error is DiagnosticDirectory.ValidationError)
                #expect(!error.localizedDescription.contains(root.path))
                #expect(!error.localizedDescription.contains(candidate.absoluteString))
            }
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "fixture")
    }
}
