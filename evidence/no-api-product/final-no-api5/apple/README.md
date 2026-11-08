# Local Apple speech corpus

All eight synthetic speech files completed on `702a24b9767826275f650c70f7e118365601a2a8`, using the installed Apple local speech framework. They contain 48.7029375 seconds of generated audio. Each produced a local candidate, unified evidence and a dispatchable text revision. The recorded probe hash matched before and after execution. [Run receipt](receipt.json) · [Corpus results](apple-corpus.json)

Normalized CER ranged from 0 to 0.2631579. Four cases missed a critical phrase. The mixed-language case missed `Mac`, the pause case missed `保存原音`, the second synthetic voice missed `充电器`, and the correction case missed `修改开始时间`. Expected and recognized text remains available for each case. [Metric summary](apple-summary.json)

First text appeared after 1.1912–1.2312 seconds, with a median of 1.20885 seconds. Completion followed the end of input by 0.02973–0.09925 seconds, with a median of 0.04666 seconds. These figures describe this synthetic local run. Natural human speech, dual-expert cloud accuracy and any accuracy advantage from fusion await separate evidence. The run used no microphone, cloud request or asset preparation.
