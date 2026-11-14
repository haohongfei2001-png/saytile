from pathlib import Path
import json,sys,hashlib
base,new,out=map(Path,sys.argv[1:4])
old=json.loads(base.read_text());cur=json.loads(new.read_text())
assert old['source']=='0dc6ed70e873ec41da3b1dd24f47350a91211a43'
assert cur['source']=='0fbca1d892bbc8aa550c4439b8cfcb045af825ae'
assert cur['passed'] and old['passed']
keys=['source','fixture_sha256','input_duration','elapsed','exit_code','archive_chunks','archived_seconds','completed_rows','total_rows','integrity','foreign_errors','timeline_rows','dispatches','unmatched_chunk_ordinals','readable_pcm_manifest','resources','idle','ui_updates','providers','requested_automatic','observed_automatic']
result={label:{**{k:r[k]for k in keys},'input_clips':len(r['input_clips']),'all_inputs_have_archived_audio':all(c['completed_frames']>0 for c in r['clips'])}for label,r in [('474',old),('476',cur)]}
compared=['fixture_sha256','readable_pcm_manifest','input_duration','input_clips','clips','completed_rows','total_rows','archive_chunks','archived_seconds']
result['same']={k:cur[k]==old[k] for k in compared}
result['baseline_receipt_sha256']=hashlib.sha256(base.read_bytes()).hexdigest()
result['candidate_receipt_sha256']=hashlib.sha256(new.read_bytes()).hexdigest()
result['transcript_comparison']='NOT_RUN: prior successful 474 soak saved PCM integrity and archive totals, no record text. Same-input final-text comparison is reported independently for the 440 files.'
out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(result['same']))
