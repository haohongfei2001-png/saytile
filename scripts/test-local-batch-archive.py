#!/usr/bin/env python3
"""One real journal replay, three identical database/audio copies and independent native retry actions."""
import argparse, hashlib, json, pathlib, runpy, sqlite3, subprocess, tempfile, wave
P=pathlib.Path
p=argparse.ArgumentParser()
for k in ("app","weights","audio","paired","probe","output"):p.add_argument("--"+k,type=P,required=True)
a=p.parse_args(); samples=json.loads(a.paired.read_text())["samples"];assert len(samples)==10
score=runpy.run_path("research/asr-2026-11-06/scripts/score.py");a.output.mkdir(exist_ok=True,parents=True)
with tempfile.TemporaryDirectory(prefix="saytile-local-batch-") as td:
    root=P(td);seed=root/"record-only";seed.mkdir()
    def invoke(mode,store,output):
        subprocess.run([str(a.probe.resolve()),mode,str(store.resolve()),str(a.weights.resolve()),str(a.app.resolve()),str(output.resolve())],check=True,timeout=400)
    with wave.open(str(seed/"fixture.wav"),"wb") as out:
        out.setparams((1,2,16000,0,"NONE","not compressed"))
        for idx,s in enumerate(samples):
            f=a.audio/(s["id"]+".wav");assert hashlib.sha256(f.read_bytes()).hexdigest()==s["audio_sha256"]
            with wave.open(str(f)) as w:out.writeframes(w.readframes(w.getnframes()))
            if idx+1<len(samples):out.writeframes(bytes(2*32000))
    invoke("record",seed,root/"unused")
    base=sqlite3.connect((seed/"Saytile.sqlite").as_uri()+"?mode=ro",uri=True)
    assert base.execute("select count(*) from model_runs").fetchone()[0]==0
    for m in ["paraformer","sensevoice","qwen-large"]:
        fresh=root/m;fresh.mkdir()
        with sqlite3.connect(fresh/"Saytile.sqlite") as db:base.backup(db)
        subprocess.run(["cp","-cR",seed/"Audio",fresh],check=True)
        output=a.output/(m+".json");invoke(m,fresh,output)
        d=json.loads(output.read_text());rows=d["rows"];ref="".join(s["reference"] for s in samples);hyp="".join(r["text"] for r in rows)
        d.update(status="PASS" if all(r["state"]=="completed" for r in rows) else "FAIL",
            scope="complete corpus via real production recording (record-only) then one native archive action per independent VAD row, including terminal empty rows; no background cloud or real microphone",
            all_rows_attempted=True,ordered_sample_ids=[s["id"] for s in samples],silence_between_s=2,archived_segments=len(rows),nonempty_rows=sum(bool(r["text"]) for r in rows),
            joined_reference=ref,joined_archive=hyp,joined_cer=score["align"](score["tokenize"](ref,"cer"),score["tokenize"](hyp,"cer")))
        output.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")
