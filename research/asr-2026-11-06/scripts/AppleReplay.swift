// Isolated public-file replay. Does not open a microphone, App store, or input target.
import Foundation
import CryptoKit
@preconcurrency import Speech
@preconcurrency import AVFoundation
struct ReplayItem: Decodable { let id: String; let audio: String; let language: String; let audio_sha256: String }
struct ReplayEvent: Codable, Sendable { let at: Double; let start: Double; let end: Double; let text: String; let isFinal: Bool }
struct ReplayOutput: Codable, Sendable {
    var id: String; var engine: String; var locale: String; var text: String; var stable_text: String
    var audio_sha256: String; var events: [ReplayEvent]; var error: String?
    var elapsed_seconds: Double; var first_readable_seconds: Double?; var stable_after_input_seconds: Double?
    var input_finished_seconds: Double?; var latency_class: String; var completely_final: Bool
}
@main struct AppleReplay {
    static func recognize(item: ReplayItem, audioRoot: URL, localeID: String, paced: Bool) async throws -> ReplayOutput {
        let url=audioRoot.appendingPathComponent(item.audio)
        let digest=SHA256.hash(data: try Data(contentsOf:url)).map { String(format:"%02x",$0) }.joined()
        guard digest == item.audio_sha256 else { throw NSError(domain:"ReplayHash",code:1) }
        guard let locale=await SpeechTranscriber.supportedLocale(equivalentTo:Locale(identifier:localeID)) else { throw NSError(domain:"ReplayLocale",code:1) }
        let transcriber=SpeechTranscriber(locale:locale,preset:.progressiveTranscription)
        let detector=SpeechDetector()
        let modules:[any SpeechModule]=[transcriber,detector]
        let analyzer=SpeechAnalyzer(modules:modules)
        let started=ProcessInfo.processInfo.systemUptime
        let consume=Task { () throws -> (String,String,[ReplayEvent],Bool) in
            var acc=SpeechResultAccumulator();var events:[ReplayEvent]=[]
            for try await result in transcriber.results {
                let a=result.range.start.seconds,b=CMTimeRangeGetEnd(result.range).seconds,t=String(result.text.characters)
                _=acc.apply(start:a,end:b,text:t,isFinal:result.isFinal,finalizedThrough:result.resultsFinalizationTime.seconds)
                events.append(.init(at:ProcessInfo.processInfo.systemUptime-started,start:a,end:b,text:t,isFinal:result.isFinal))
            }
            return (acc.snapshot.fullText,acc.snapshot.stableText,events,acc.snapshot.isCompletelyFinal)
        }
        var eof:Double?=nil
        do {
            let file=try AVAudioFile(forReading:url)
            if !paced {
                try await analyzer.start(inputAudioFile:file,finishAfterFile:true)
            } else {
                guard let format=await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:modules),let converter=AVAudioConverter(from:file.processingFormat,to:format) else {throw NSError(domain:"ReplayFormat",code:1)}
                let (inputs,continuation)=AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy:.bufferingOldest(300))
                try await analyzer.prepareToAnalyze(in:format)
                try await analyzer.start(inputSequence:inputs)
                let clock=ContinuousClock();let began=clock.now;var frames:Int64=0
                while file.framePosition<file.length {
                    let input=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:1600)!
                    try file.read(into:input)
                    let output=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(ceil(Double(input.frameLength)*format.sampleRate/file.processingFormat.sampleRate)+64))!
                    var supplied=false;var error:NSError?
                    let status=converter.convert(to:output,error:&error) { _,state in
                        if supplied {state.pointee = .noDataNow;return nil}
                        supplied=true;state.pointee = .haveData;return input
                    }
                    if status == .error {throw error ?? NSError(domain:"ReplayConversion",code:1)}
                    // Deliver only after this source frame interval has elapsed.
                    frames+=Int64(input.frameLength)
                    try await clock.sleep(until:began.advanced(by:.seconds(Double(frames)/file.processingFormat.sampleRate)))
                    if output.frameLength>0, case .dropped=continuation.yield(AnalyzerInput(buffer:output)) {throw NSError(domain:"ReplayOverflow",code:1)}
                }
                while true {
                    let output=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:4096)!;var error:NSError?
                    let status=converter.convert(to:output,error:&error) { _,state in state.pointee = .endOfStream;return nil }
                    if status == .error {throw error ?? NSError(domain:"ReplayTail",code:1)}
                    if output.frameLength>0, case .dropped=continuation.yield(AnalyzerInput(buffer:output)) {throw NSError(domain:"ReplayOverflow",code:2)}
                    if output.frameLength==0 || status == .endOfStream {break}
                }
                eof=ProcessInfo.processInfo.systemUptime-started;continuation.finish()
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            }
            let (text,stable,events,complete)=try await consume.value
            let ended=ProcessInfo.processInfo.systemUptime-started
            return .init(id:item.id,engine:"apple-speechtranscriber",locale:localeID,text:text,stable_text:stable,audio_sha256:digest,events:events,error:nil,elapsed_seconds:ended,first_readable_seconds:paced ? events.first(where:{!$0.text.isEmpty})?.at : nil,stable_after_input_seconds:eof.map{max(0,ended-$0)},input_finished_seconds:eof,latency_class:paced ? "paced_public_file_first_sample_and_EOF" : "offline_file_processing_not_realtime",completely_final:complete)
        } catch {
            await analyzer.cancelAndFinishNow();consume.cancel();throw error
        }
    }
    static func main() async throws {
        let args=CommandLine.arguments
        guard args.count==6 else {fatalError("manifest audio-root output-jsonl fixed-zh|oracle-language batch|paced")}
        let items=try JSONDecoder().decode([ReplayItem].self,from:Data(contentsOf:URL(fileURLWithPath:args[1])))
        let mode=args[4],paced=args[5]=="paced",out=URL(fileURLWithPath:args[3])
        var done=Set<String>()
        if let content=try? String(contentsOf:out,encoding:.utf8) {
            for line in content.split(separator:"\n") {if let obj=try? JSONDecoder().decode(ReplayOutput.self,from:Data(line.utf8)) {done.insert(obj.id)}}
        } else {FileManager.default.createFile(atPath:out.path,contents:nil)}
        let locales=mode=="oracle-language" ? ["zh-CN","en-US"] : ["zh-CN"]
        for id in locales {
            guard let locale=await SpeechTranscriber.supportedLocale(equivalentTo:Locale(identifier:id)) else {continue}
            let prep=SpeechTranscriber(locale:locale,preset:.progressiveTranscription)
            _=try await AssetInventory.reserve(locale:locale)
            if let install=try await AssetInventory.assetInstallationRequest(supporting:[prep]) {try await install.downloadAndInstall()}
        }
        let handle=try FileHandle(forWritingTo:out);try handle.seekToEnd();defer{try? handle.close()}
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        for (i,item) in items.enumerated() where !done.contains(item.id) {
            let localeID=mode=="oracle-language" && item.language=="en" ? "en-US" : "zh-CN"
            let start=ProcessInfo.processInfo.systemUptime;let result:ReplayOutput
            do {result=try await recognize(item:item,audioRoot:URL(fileURLWithPath:args[2]),localeID:localeID,paced:paced)}
            catch {result = .init(id:item.id,engine:"apple-speechtranscriber",locale:localeID,text:"",stable_text:"",audio_sha256:item.audio_sha256,events:[],error:String(describing:error),elapsed_seconds:ProcessInfo.processInfo.systemUptime-start,first_readable_seconds:nil,stable_after_input_seconds:nil,input_finished_seconds:nil,latency_class:paced ? "paced_public_file_first_sample_and_EOF" : "offline_file_processing_not_realtime",completely_final:false)}
            try handle.write(contentsOf:encoder.encode(result));try handle.write(contentsOf:Data([10]));try handle.synchronize()
            FileHandle.standardError.write(Data("\(i+1)/\(items.count) \(item.id) \(String(format:"%.2f",result.elapsed_seconds))s error=\(result.error ?? "none")\n".utf8))
        }
    }
}
