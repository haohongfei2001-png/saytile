import Foundation
import Testing
@testable import SaytileKit

@Test func experienceKeepsBuild261StorageWithTheProductIdentity() throws {
    let personal = SaytileStorageProfile.personal
    let standard = SaytileStorageProfile.standard
    #expect(personal.archiveDirectory.lastPathComponent == "Saytile Personal")
    #expect(standard.archiveDirectory.lastPathComponent == "Saytile")
    #expect(personal.byokService == "app.saytile.mac.personal.byok.v1")
    #expect(personal.hostedService == "app.saytile.mac.personal.hosted.auth.v1")
    #expect(standard.byokService == "com.saytile.byok.v1")
    #expect(standard.hostedService == "com.saytile.hosted.auth.v1")
    #expect(throws: DiagnosticDirectory.ValidationError.self) {
        try DiagnosticDirectory.validate(directory: personal.archiveDirectory.appending(path: "LocalModels"), productionDirectory: personal.archiveDirectory)
    }
}

@Test func designExperienceOwnsADistinctArchiveAndCredentialNamespace() throws {
    let design = SaytileStorageProfile.designExperience
    for existing in [SaytileStorageProfile.standard, .personal] {
        #expect(design.archiveDirectory != existing.archiveDirectory)
        #expect(design.hostedService != existing.hostedService)
        #expect(design.byokService != existing.byokService)
    }
    #expect(design.archiveDirectory.lastPathComponent == "Saytile Design Experience")
}
