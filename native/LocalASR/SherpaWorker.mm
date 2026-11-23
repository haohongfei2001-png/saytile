#import <Foundation/Foundation.h>
#include "sherpa.h"
#include <array>
#include <vector>
#include <string>

static void publish(NSString *kind, NSString *text, uint64_t frames) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"kind":kind, @"text":text, @"frames":@(frames)} options:0 error:nil];
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}
int main(int argc, char **argv) {
    if (argc != 4) return 64;
    std::string root = std::string(argv[2]) + "/";
    std::string enc = root + "encoder.int8.onnx", dec = root + "decoder.int8.onnx", tok = root + "tokens.txt";
    SherpaOnnxOnlineRecognizerConfig config{};
    config.feat_config.sample_rate = 16000;
    config.feat_config.feature_dim = 80;
    std::string ctc = root + "model.int8.onnx";
    if (std::string(argv[1]) == "zipformer") {
        config.model_config.zipformer2_ctc.model = ctc.c_str();
    } else if (std::string(argv[1]) == "sherpa") {
        config.model_config.paraformer.encoder = enc.c_str();
        config.model_config.paraformer.decoder = dec.c_str();
    } else { return 64; }
    config.model_config.tokens = tok.c_str();
    config.model_config.num_threads = 2;
    config.model_config.provider = "cpu";
    config.decoding_method = "greedy_search";
    const auto *model = SherpaOnnxCreateOnlineRecognizer(&config);
    if (!model) return 65;
    const auto *stream = SherpaOnnxCreateOnlineStream(model);
    if (!stream) return 66;
    uint64_t frames = 0;
    std::string last;
    @autoreleasepool { publish(@"ready", @"", 0); }
    uint32_t size;
    while (fread(&size, 1, sizeof(size), stdin) == sizeof(size)) {
        @autoreleasepool {
            if (size > 65536 || size % 2) return 67;
            if (size) {
                std::vector<int16_t> pcm(size / 2);
                if (fread(pcm.data(), 1, size, stdin) != size) return 68;
                std::vector<float> samples(pcm.size());
                for (size_t i = 0; i < pcm.size(); ++i) samples[i] = pcm[i] / 32768.f;
                SherpaOnnxOnlineStreamAcceptWaveform(stream, 16000, samples.data(), (int)samples.size());
                frames += pcm.size();
            } else {
                // Online Paraformer has right context. Flush the last incomplete
                // encoder chunk with silence, excluded from recorded audio time.
                std::array<float, 9600> silence{};
                SherpaOnnxOnlineStreamAcceptWaveform(stream, 16000, silence.data(), silence.size());
                SherpaOnnxOnlineStreamInputFinished(stream);
            }
            while (SherpaOnnxIsOnlineStreamReady(model, stream)) SherpaOnnxDecodeOnlineStream(model, stream);
            const auto *result = SherpaOnnxGetOnlineStreamResult(model, stream);
            if (!result) return 69;
            std::string text = result->text ? result->text : "";
            SherpaOnnxDestroyOnlineRecognizerResult(result);
            if (!size || (!text.empty() && text != last)) {
                publish(size ? @"partial" : @"final", [NSString stringWithUTF8String:text.c_str()], frames);
                last = text;
            }
            if (!size) {
                SherpaOnnxDestroyOnlineStream(stream);
                stream = SherpaOnnxCreateOnlineStream(model);
                if (!stream) return 66;
                frames = 0; last.clear();
            }
        }
    }
    SherpaOnnxDestroyOnlineStream(stream);
    SherpaOnnxDestroyOnlineRecognizer(model);
    return ferror(stdin) ? 70 : 0;
}
