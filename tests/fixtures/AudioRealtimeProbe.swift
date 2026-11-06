import Foundation
import SaytileKit

@main struct AudioRealtimeProbe {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4, let seconds = Double(args[2]), seconds > 0 else { fatalError("fixture.aiff seconds isolated-directory") }
        let store = try SaytileStore(directory: URL(fileURLWithPath: args[3]))
        let result = try await AudioDiagnostics.exerciseRealtimeFixture(url: URL(fileURLWithPath: args[1]), seconds: seconds, store: store)
        print(result)
        try await store.close()
    }
}
