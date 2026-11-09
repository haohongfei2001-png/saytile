import Foundation
@testable import SaytileKit

@main struct HostedGatewayProbe {
    static func main() async throws {
        let dir = URL(fileURLWithPath:CommandLine.arguments[1])
        let origin = URL(string:"http://127.0.0.1:" + CommandLine.arguments[2])!
        let store = try SaytileStore(directory:dir.appending(path:"AudioFixture"))
        let record = try await store.createRecording()
        let pcm = Data(repeating:0x12,count:3200)
        let journal = try PCMJournal(directory:store.audioDirectory,recordingID:record.id)
        try journal.openChunk();try journal.append(pcm);try journal.closeChunk()
        try await store.registerAudioChunk(recordingID:record.id,relativePath:journal.relativePath,frames:journal.frames)
        try await store.finishRecording(id:record.id)
        let ticket = try await store.beginFusionRecognition(recordingID:record.id)
        let factory = RecognitionSessionFactory()
        factory.select(.connected(.init(origin:origin,bearer:"native-fixture",expiry:Date().addingTimeInterval(120))),revoke:false)
        let snap = factory.snapshot
        factory.select(.byok,revoke:false)
        precondition(snap.isHosted && !factory.snapshot.isHosted && snap.configuration.activeModels.count==2)
        let session=factory.make(store:store,ticket:ticket,snapshot:snap)
        session.append(pcm);session.finish();await session.wait()
        let final = try await store.latestFinalRevision(recordingID:record.id)
        let stable = try await store.latestDispatchableRevision(recordingID:record.id)
        guard final?.text == "没有，五毫克，五毫克。", stable?.text == final?.text else {
            let runs=try await store.modelRuns(recordingID:record.id)
            print("Fixture failure",runs,final as Any,stable as Any);throw ProviderFailure.incomplete
        }
        print("PASS native session factory, frozen source, PCM journal, gateway ASR events, GPT evidence, SQLite final and dispatchable text")
    }
}
