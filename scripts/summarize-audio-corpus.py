#!/usr/bin/env python3
"""Report raw CER separately from punctuation/width/numeric presentation normalization.
This never changes production transcripts. Numeric normalization is applied equally to references/results.
"""
import json, re, sys, unicodedata
from pathlib import Path
DIGITS = dict(zip('零〇一二两三四五六七八九', [0,0,1,2,2,3,4,5,6,7,8,9]))
UNITS = {'十':10,'百':100,'千':1000,'万':10000}
PATTERN = r'[零〇一二两三四五六七八九十百千万]+'
def number(text):
    total=section=current=0
    for char in text:
        if char in DIGITS: current=DIGITS[char]
        elif UNITS[char] == 10000: total += (section+current)*10000; section=current=0
        else: section += (current or 1)*UNITS[char]; current=0
    return str(total+section+current)
def canonical(text):
    text=unicodedata.normalize('NFKC',text).lower()
    text=re.sub(r'百分之('+PATTERN+r'|\d+)',lambda m:number(m[1])+'%' if not m[1].isdigit() else m[1]+'%',text)
    text=re.sub(PATTERN,lambda m:number(m[0]),text)
    text=re.sub(r'(\d+)点半',r'\1:30',text)
    text=re.sub(r'(\d+)点(?!\d)',r'\1:00',text)
    return ''.join(c for c in text if not c.isspace() and not unicodedata.category(c).startswith(('P','S')))
def edits(a,b):
    row=list(range(len(b)+1))
    for i,c in enumerate(a):
        new=[i+1]
        for j,d in enumerate(b): new.append(min(new[-1]+1,row[j+1]+1,row[j]+(c!=d)))
        row=new
    return row[-1]
def score(cases,key):
    out=[]; raw_errors=raw_chars=norm_errors=norm_chars=0
    for item in cases:
        a,b=item['expected'],item[key]; aa,bb=canonical(a),canonical(b)
        r,n=edits(a,b),edits(aa,bb);raw_errors+=r;raw_chars+=len(a);norm_errors+=n;norm_chars+=len(aa)
        out.append({'id':item['id'],'raw_cer':r/max(1,len(a)),'presentation_normalized_cer':n/max(1,len(aa)),'normalized_reference':aa,'normalized_hypothesis':bb})
    return {'raw_cer':raw_errors/max(1,raw_chars),'presentation_normalized_cer':norm_errors/max(1,norm_chars),'cases':out}
base=Path(sys.argv[1] if len(sys.argv)>1 else 'evidence/rc')
live=json.loads((base/'audio-corpus.json').read_text()); alternative=json.loads((base/'audio-dictation-comparison.json').read_text())
summary={'scope':'Eight authored synthetic TTS samples, two installed voices; not human Mandarin acceptance','engineering_target':'Presentation-normalized aggregate CER approximately <= 0.10; negation semantics checked separately. This is an engineering target, not user acceptance.',
'normalization':'NFKC/case/whitespace/punctuation/symbol stripping, standard Chinese integers and hour/half-hour presentation; applied only to metrics on both sides; raw CER retained',
'latency_definition':'SpeechTranscriber input is paced at source buffer duration using real wall-clock sleeps. firstText measured from session creation; finalizationAfterInput measures after all fixture buffers were fed, not last spoken phoneme or VAD stop latency. Dictation comparison is batch-file quality only; latency is not comparable.',
'speech_transcriber':score(live,'recognized'),'dictation_transcriber':score(alternative,'text'),
'negation_cases':[{k:x[k] for k in ('id','expected','recognized','missingCriticalPhrases')} for x in live if x['id'] in ('negation','correction')],
'first_text_seconds_range':[min(x['firstTextSeconds'] for x in live),max(x['firstTextSeconds'] for x in live)],
'finalization_after_input_seconds_range':[min(x['finalizationAfterInputSeconds'] for x in live),max(x['finalizationAfterInputSeconds'] for x in live)],
'limitations':['Mixed English/Chinese TTS pronunciation has not been independently human-audited','Homophones and some content words remain imperfect in both engines','No personal vocabulary, transcript-specific replacement, cloud upload, or paid API used']}
(base/'audio-corpus-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:summary[k] for k in ['first_text_seconds_range','finalization_after_input_seconds_range']},ensure_ascii=False))
for name in ['speech_transcriber','dictation_transcriber']: print(name,summary[name]['raw_cer'],summary[name]['presentation_normalized_cer'])
