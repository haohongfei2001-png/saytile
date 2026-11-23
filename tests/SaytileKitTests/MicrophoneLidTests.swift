import Testing
@testable import SaytileKit

@Suite("Physical microphone disconnect")
struct MicrophoneLidTests {
    @Test func onlyAnAffirmativeLidReadingBlocksTheBuiltInMicrophone() {
        #expect(MicrophoneLid.blocks(builtIn: true) { true })
        #expect(!MicrophoneLid.blocks(builtIn: true) { false })
        #expect(!MicrophoneLid.blocks(builtIn: true) { nil })
    }

    @Test func externalAndFileRoutesDoNotReadTheLid() {
        let blocked = MicrophoneLid.blocks(builtIn: false) {
            Issue.record("An unrelated route must not depend on the notebook lid"); return true
        }
        #expect(!blocked)
    }
}
