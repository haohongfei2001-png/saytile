# 服务与证据附录 · 最高质量重裁决

核验日期：2026-11-06。此文件替代旧单引擎供应商附录；旧版可在 `c9eac9b` 查看。当前可执行实现与未验证边界以 [REVISION](REVISION-2026-11-06.md) 为准。

## 1. 角色与当前选择

| 角色 | 模型与接口 | 裁决 |
|---|---|---|
| 中文实时专家 | Qwen `qwen-audio-3.1-asr-flash-message` | 暂定默认；显式启用 intermediate results，关闭润色、翻译、去口癖。中文能力依据与流式协议分开。 |
| 英文实时专家 | AssemblyAI `universal-3-6-pro` / v3 WebSocket / `max_accuracy` | 暂定默认；真实partial、词时间及型号回声验证。不能写成全球英文冠军。 |
| 英文强挑战者 | Meta `muse-voice-transcribe-1.0` / realtime | 当前独立榜表现很强，官方API已开放。作为已支持的可选专家，同输入验收时必须比较；可替换或并行加入。 |
| 混说第三路 | Soniox `stt-rt-v6` | 可选并行，保存原始词时间、语言与confidence；不再拥有唯一发布权。 |
| 文本仲裁 | OpenAI `gpt-6-astra` / Responses | 默认精确融合，允许high/xhigh/max与standard/pro；返回候选引用，不能自由润色。 |
| 原音复听 | Gemini `gemini-3.8-flash` / generateContent音频输入 | 默认启用的复核角色；盲听后生成新的声学候选，仍需本地验证。 |
| 独立文件复核 | ElevenLabs `scribe_v2` | 默认高精度定稿；可换OpenAI `gpt-transcribe`。文件性能不冒充实时性能。 |
| 本机备用 | Apple SpeechAnalyzer | 未完成云授权时保留；失败后原音可恢复。旧实测不重跑。 |

服务Key与处理授权没有完成前，任何推荐模型都不会自动上传。价格不决定上述首选；新增源是否默认长期运行，以同输入的互补错误与最终实际收益决定。

## 2. 证据层级与数值边界

**独立实时证据：** [Pipecat原始仓库](https://github.com/pipecat-ai/stt-benchmark)当前页面使用1,000条smart-turn样本，pooled semantic WER为Meta 0.73%、Assembly 3.6 Pro 0.80%、Soniox **v5** 1.09%、Deepgram Nova-3 1.37%、旧OpenAI GPT-4o Transcribe 2.95%、Scribe v2 Realtime 3.13%。这是该样本集与其语义评分法的结果，不能外推为严格逐字听写、普通话、代码名或混说成绩。语义评分可忽略填充、格式及部分等义差异，而Saytile必须保留用户有意重复。Meta与Assembly的0.07个百分点差异没有在这里给出显著性结论。TTFS是停声至final，不是首字。

**中文厂商研究：** [Qwen3.1技术页](https://qwenaudio.github.io/qwen-audio-3.1-asr/)给出其新模型族、公开数据集与API对照。页面保留历史3.0数据，必须检查表头版本。厂商实施的评测可以支持优先接入，但不证明Message流式、用户口音和中文/英文专家融合后的冠军。AISHELL朗读表现也不等于自然产品术语混说。

**旧商业应用比较：** [Verli分语言比较](https://verli.app/blog/per-language-speech-to-text-accuracy)是较早版本、每语种200条FLEURS的应用测量；不覆盖最新Qwen、SeedASR或自然中英混说。旧文件成绩仅保留为历史线索。

**厂商接口事实：** 官方文档用于确认端点、鉴权、事件、输入格式和可用型号，不能作为独立准确率实验。Soniox v6的新版本事实不能继承v5分数；Scribe file与realtime、Assembly async与streaming也必须分开。

**本项目证据：** 已有Apple/本地Qwen结果和本轮无云fixture各有独立边界，均不构成最新云模型质量排名。

## 3. 主要接口与精确语义

### Qwen Message

[WebSocket文档](https://help.aliyun.com/zh/model-studio/qwen-asr-message-websocket-api)；[Server events](https://help.aliyun.com/en/model-studio/qwen-asr-message-server-events)。使用Workspace所属北京/新加坡端点、Bearer认证、16kHz mono PCM。等待task-started，按sentence_id更新文本，finish-task后继续读至task-finished。启用intermediate_result_enabled；不把中间稿当不可变前缀。final有真实words时保留词边界；缺失或无法逐字对应时降为真实句级边界。不得按字数推算时间。当前模型提示与话题合计400字；超限明确报配置错误。

### AssemblyAI

[完整消息顺序](https://www.assemblyai.com/docs/streaming/message-sequence)；[准确率与延迟模式](https://www.assemblyai.com/docs/streaming/getting-started/optimizing-accuracy-and-latency)。v3端点使用原生Authorization key，显式speech_model、max_accuracy与partial turns。Begin必须返回期望型号与模式，否则拒绝静默降级。保留words[].word_is_final连续真值与真实词时间；格式化不匹配时降级对齐。Terminate排在所有音频后，再排空Termination。计费时长按连接而非只有语音；费用显示为用户费率估算，不假称供应商实际账单。

### Meta Muse

[官方Speech-to-text](https://dev.meta.ai/docs/speech-to-text)；[2026-09-03发布](https://dev.meta.ai/resources/blog/meet-muse-voice-transcribe-streaming-speech-to-text)；[Voice schemas](https://dev.meta.ai/docs/api-reference/voice/schemas)。官方支持25语言及code-switching，含普通话和英文。WS握手首帧使用authorization.accessToken，不能假设HTTP Authorization生效。ENDPOINTING按turnId保存完成事件，partial归最新speechStart；turn编号不当排序含义。只有turn/progress级信息，没有词时戳或confidence，不能冒充精确词证据。此能力限制影响可验证拼词路径，不是否认其独立英文质量证据；授权验收须实测它作为完整候选、主专家或额外源的收益。

### Soniox

[模型目录](https://docs.soniox.com/stt/models)；[WebSocket](https://docs.soniox.com/api-reference/stt/websocket-api)；[鉴权](https://docs.soniox.com/authentication/websocket-authentication)。v6于2026-11-03发布。Bearer Upgrade认证，binary PCM；语言提示zh/en不限制自然切换；final token累积，non-final尾部替换。结束是空**文本**帧，再等待finished。原始confidence不跨模型比较。

### 复核与融合

- [ElevenLabs文件API](https://elevenlabs.io/docs/api-reference/speech-to-text/convert)：`scribe_v2`，xi-api-key，原音文件、真实词时间。Realtime已研究但本轮不开放选择：其manual仍有自动分段，现有未验真的终止处理不能保证长录音完整，不能带着已知截断风险交付。
- [OpenAI转写](https://developers.openai.com/api/docs/guides/speech-to-text)：`gpt-transcribe`文件输入；文件响应stream不等于持续麦克风实时。另有`gpt-live-transcribe`，本轮未实现对应实时协议。
- [OpenAI模型](https://developers.openai.com/api/docs/models)与[推理](https://developers.openai.com/api/docs/guides/reasoning)：Astra承担文本证据推理，不宣称它通过当前Responses听取原音。
- [Gemini音频](https://ai.google.dev/gemini-api/docs/audio?hl=en)：原生音频输入独立接口。原音盲听不直接收到争议文字暗示；返回不确定状态，不能以大模型自信覆盖音频证据。

## 4. 仍需比较的成熟候选

豆包SeedASR2.0优化双向流式与句末非流式复核，使用语音产品专用资源/鉴权，不能把方舟聊天权限当成语音权限。它仍是中文最重要的替代挑战者之一；当前证据没有形成与Qwen Message同条件的独立中文混说结论。详细资源和官方链接见[中文专题](CHINESE-AND-MIXED-2026-11-06.md)。Fun-ASR、FireRed、Deepgram、Speechmatics与Google等也按具体版本和真实流式证据保留，不为了增加API个数全部默认运行。

### 最新其他候选的版本核查

- **Deepgram：** [2026-10-23官方变更](https://developers.deepgram.com/changelog/2026/10/23)将`nova-3&language=multi`更新为55语言，batch/streaming同名接口均支持切换与逐词语言信息；旧10语言型号可用version固定。Flux仍有独立v2流式协议及对话轮次目标。不能把Pipecat的`nova-3-general`旧行解释成新multi已败给首选，也不能凭官方相对WER宣传宣布它胜出。本轮列入成熟混说替代，未默认实现所有供应商。
- **Speechmatics：** [当前型号文档](https://docs.speechmatics.com/speech-to-text/models)将Enhanced、Standard、Melia 1、Oak 1列为batch/realtime可用；Enhanced仍是其最高精度定位，Melia为自动多语言，Oak针对医疗。Melia实时有partial/final和词时间，但客户端需要显式ForceEndOfUtterance，不能复制旧自动端点参数。[普通话英文语言包](https://docs.speechmatics.com/speech-to-text/languages)是另一成熟路径。没有其当前版本与首选在相同普通话混说上的独立证据，所以保留候选，避免拿‘更新’当‘一定更准’。

## 5. 最小实际裁决

复用Mac现有真人片段，保留四阶段文本与时间，定向比较双专家、替换Meta、加Soniox、加文本仲裁、加原音复听。主要看关键语义错误、术语正确率、中英混说错误、反复修正及实际外部输入错误；不要只比较最终一份文本。没有获得授权服务凭据与真实输出前，首选配置是可执行的工程默认，质量排名仍明确未封榜。
