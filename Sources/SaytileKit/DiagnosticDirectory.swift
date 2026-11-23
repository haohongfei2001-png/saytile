import Foundation
import Darwin

/// Checks a diagnostic storage boundary before AppModel/Store can migrate or
/// recover anything. Only path metadata is inspected; no directory is created,
/// enumerated or opened as an archive.
public enum DiagnosticDirectory {
    public enum ValidationError: LocalizedError, Sendable {
        case isolationRequired
        public var errorDescription: String? {
            "诊断必须使用生产资料目录之外的独立目录，且不能通过别名访问已有资料。"
        }
    }

    public static func validate(directory: URL, productionDirectory: URL? = nil) throws {
        let production = productionDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Saytile", isDirectory: true)
        guard directory.isFileURL, production.isFileURL,
              directory.query == nil, directory.fragment == nil,
              directory.host == nil || directory.host == "" || directory.host == "localhost" else {
            throw ValidationError.isolationRequired
        }
        let root = directory.standardizedFileURL
        let protected = production.standardizedFileURL
        // Reject the actual default production tree before even inspecting its
        // metadata. Conservative case/Unicode equivalence also covers normal APFS.
        guard !isWithin(root, protected) else { throw ValidationError.isolationRequired }
        let canonicalRoot = try canonicalDirectory(root)
        let canonicalProduction = try canonicalDirectory(protected)
        guard !isWithin(canonicalRoot, canonicalProduction) else { throw ValidationError.isolationRequired }
        do { try StorePath.rejectSymbolicLink(root) }
        catch { throw ValidationError.isolationRequired }
    }

    private static func isWithin(_ candidate: URL, _ root: URL) -> Bool {
        let path = candidate.path.precomposedStringWithCanonicalMapping.lowercased()
        let base = root.path.precomposedStringWithCanonicalMapping.lowercased()
        return path == base || path.hasPrefix(base == "/" ? base : base + "/")
    }

    private static func canonicalDirectory(_ url: URL) throws -> URL {
        var ancestor = url
        var missing: [String] = []
        while true {
            var info = stat()
            if Darwin.lstat(ancestor.path, &info) == 0 {
                guard info.st_mode & S_IFMT == S_IFDIR || info.st_mode & S_IFMT == S_IFLNK,
                      let resolved = Darwin.realpath(ancestor.path, nil) else {
                    throw ValidationError.isolationRequired
                }
                defer { free(resolved) }
                let existing = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
                var resolvedInfo = stat()
                guard Darwin.lstat(existing.path, &resolvedInfo) == 0,
                      resolvedInfo.st_mode & S_IFMT == S_IFDIR else { throw ValidationError.isolationRequired }
                return missing.reversed().reduce(existing) { $0.appendingPathComponent($1, isDirectory: true) }
            }
            guard errno == ENOENT, ancestor.path != "/" else { throw ValidationError.isolationRequired }
            missing.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
    }
}
