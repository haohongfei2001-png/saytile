#!/usr/bin/env python3
"""Summarise a completed, explicitly isolated 102-repeat FLEURS soak. Never opens a normal Saytile archive."""
import argparse, hashlib, json, sqlite3, statistics, tempfile, wave
from pathlib import Path
p=argparse.ArgumentParser()
for k in ["root","samples","output"]:p.add_argument("--"+k,required=True,type=Path)
a=p.parse_args();root=a.root.resolve()
if root.parent!=Path("/tmp").resolve() or not root.name.startswith("saytile-local-final-soak."):
    raise SystemExit("expected disposable soak data directory")
view=json.loads((root/"visible.json").read_text())
with wave.open(str(root/"fixture.wav")) as w: played=w.getnframes()/w.getframerate()
assert played>=1800 and view["endOfFile"]>=1800 and view["providers"]==["sherpa"]
db=sqlite3.connect((root/"Saytile.sqlite").as_uri()+"?mode=ro",uri=True)
check=db.execute("pragma integrity_check").fetchone()[0];fk=db.execute("pragma foreign_key_check").fetchall()
q=lambda sql:db.execute(sql).fetchone()[0]
records=q("select count(*) from recordings")
ready=q("select count(*) from recordings r join revisions v on v.id=r.preferred_revision where r.audio_state='available' and r.recognition_state='completed' and r.is_recording=0 and r.last_error is null and length(v.text)>0")
assert records==ready==102 and check=="ok" and not fk
assert q("select count(*) from transcript_timeline")==records
paths=db.execute("select path,frames from chunks order by path").fetchall()
assert q("select count(*) from dispatches")==0
assert db.execute("select json_extract(payload, '$.provider'), count(*) from model_runs group by 1").fetchall()==[("sherpa",102)]
manifest=hashlib.sha256();samples=0;data_bytes=0
for name,frames in paths:
    f=root/"Audio"/name
    assert (root/"Audio").resolve() in f.resolve().parents and not f.is_symlink()
    with wave.open(str(f)) as w:
        assert w.getnframes()==frames and (w.getsampwidth(),w.getframerate(),w.getnchannels())==(2,16000,1)
        buf=w.readframes(frames);assert len(buf)==frames*2
        manifest.update(hashlib.sha256(buf).digest())
    samples+=frames;data_bytes+=f.stat().st_size
assert len(list((root/"Audio").rglob("*.wav")))==len(paths)
assert samples==q("select sum(total_frames) from recordings")
series={}
for line in a.samples.read_text().splitlines():
    pid,t,rss,cpu=line.split()
    series.setdefault(pid,[]).append([t,int(rss),float(cpu)])
assert len(series)==2
report=dict(status="PASS",source=view["sha"],model="sherpa",input="102 copies of FLEURS zh-4719524538529342597 with 1s silence between runs, at 1x wall clock; synthetic routing, actual licensed speech.",
       fixture_sha256=hashlib.sha256((root/"fixture.wav").read_bytes()).hexdigest(),paced_s=round(view["endOfFile"],3),
       fixture_duration_s=round(played,3),native_text_changes=view["displayedChanges"],expected_utterances=102,utterances_complete=ready,archive_rows=records,
       chunks_independently_read=len(paths),wav_bytes=data_bytes,journal_pcm_s=round(samples/16000,3),
       pcm_hash_manifest_sha256=manifest.hexdigest(),database_integrity=check,foreign_key_errors=len(fk),external_dispatches=0,
       process_sample_interval_s=10,resources={},scope="Single 30 minute soak on the lightweight default fallback. RSS is resident process memory, not total chip memory. No private microphone; overnight, sleep and sustained power per model are not implied.")
for label,v in zip(["app","worker"],series.values()):
    med=lambda r:round(statistics.median(x[1] for x in r)/1024,1)
    report["resources"][label]={"observations":len(v),"first_5min_median_RSS_MiB":med(v[:30]),"last_5min_median_RSS_MiB":med(v[-30:]),"peak_RSS_MiB":round(max(x[1] for x in v)/1024,1),"median_cpu_percent":round(statistics.median(x[2] for x in v),1)}
a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
