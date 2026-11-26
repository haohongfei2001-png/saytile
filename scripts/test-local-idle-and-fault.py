#!/usr/bin/env python3
"""Isolated native replay: warm reuse, long-idle release/reload, or checksum-failure PCM survival."""
import argparse, hashlib, json, os, pathlib, plistlib, sqlite3, subprocess, tempfile, time, wave
P=pathlib.Path
p=argparse.ArgumentParser()
for n in ("app","weights","audio","output"):p.add_argument("--"+n,type=P,required=True)
p.add_argument("--retry-exe", type=P)
p.add_argument("--model",choices=("sherpa","zipformer","qwen-small"),default="sherpa")
p.add_argument("--scenario", choices=("all", "warm", "release", "corrupt"), default="all",
               help="Run only the required behavior; all also checks corruption and optional retry.")
p.add_argument("--warm-silence-seconds", type=int, default=60,
               help="Thinking pause that must reuse the same worker (default: 60; must be below 180).")
p.add_argument("--release-silence-seconds", type=int, default=195,
               help="Long silence that must release and reload the worker (default: 195; must exceed 180).")
a=p.parse_args()
if not 0 < a.warm_silence_seconds < 180:p.error("--warm-silence-seconds must be between 1 and 179")
if a.release_silence_seconds <= 180:p.error("--release-silence-seconds must exceed the 180-second warm lease")
app=a.app.resolve(); meta=plistlib.loads((app/"Contents/Info.plist").read_bytes());assert not meta["SaytileSourceDirty"]
model=json.loads(P("Sources/SaytileKit/Resources/LocalASR",a.model+".json").read_text()); exe=app/"Contents/MacOS/Saytile"
source=a.audio/"fleurs-zh-13737992583400421680.wav"
assert hashlib.sha256(source.read_bytes()).hexdigest()=="2c130c47ae74549ca6b33e06a547e2165e14f665380d29cefe6667fa5602fe47"
with wave.open(str(source)) as w:
    assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, 16000)
    signal=w.readframes(w.getnframes()); signal_seconds=w.getnframes()/w.getframerate()
out={"source":meta["SaytileSourceRevision"],"model":a.model,"model_revision":model["revision"],"fixture_sha256":hashlib.sha256(source.read_bytes()).hexdigest(),
     "requested_scenario":a.scenario,"warm_retention_seconds":180,"ingress":"wall-clock-paced file replay, not microphone"}
a.output.parent.mkdir(parents=True, exist_ok=True)
def save_receipt():a.output.write_text(json.dumps(out,indent=2)+"\n")
for mode in (("corrupt","warm","release") if a.scenario=="all" else (a.scenario,)):
    with tempfile.TemporaryDirectory(prefix="saytile-local-batch-fault-") as tmp:
        root=P(tmp); directory=root/"LocalModels"/a.model/model["revision"];directory.parent.mkdir(parents=True)
        subprocess.run(["cp","-cR",str(a.weights/a.model/model["revision"]),str(directory)],check=True)
        silence_seconds={"corrupt":0,"warm":a.warm_silence_seconds,"release":a.release_silence_seconds}[mode]
        fixture_seconds=signal_seconds if mode=="corrupt" else 2*signal_seconds+silence_seconds
        timeout_seconds=max(100,fixture_seconds+90)
        behavior={"corrupt":"reject_corrupt_model_and_preserve_original_pcm", "warm":"reuse_same_worker",
                  "release":"release_during_silence_then_reload"}[mode]
        with wave.open(str(root/"fixture.wav"),"wb") as wav:
            wav.setparams((1,2,16000,0,"NONE","not compressed"));wav.writeframes(signal)
            if mode!="corrupt":wav.writeframes(bytes(silence_seconds*16000*2)+signal)
        if mode=="corrupt":
            small=min(model["files"],key=lambda f:f["bytes"]);path=directory/small["path"]
            with path.open("r+b") as f:
                b=f.read(1);f.seek(0);f.write(bytes([b[0]^0x40]))
            assert path.stat().st_size==small["bytes"] and hashlib.sha256(path.read_bytes()).hexdigest()!=small["sha256"]
        start=time.monotonic()
        proc=subprocess.Popen([str(exe),"--data-directory",str(root),"--local-stream-probe",a.model],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        changes=[];pids=[];prior=None
        while proc.poll() is None:
            if time.monotonic()-start>timeout_seconds:
                proc.terminate()
                try:proc.wait(timeout=5)
                except subprocess.TimeoutExpired:proc.kill();proc.wait()
                out[mode]={"status":"FAIL","reason":"timed out","expected_behavior":behavior,
                           "silence_seconds":silence_seconds,"fixture_seconds":fixture_seconds,
                           "timeout_seconds":timeout_seconds,"process_events":changes}
                save_receipt();raise RuntimeError(f"{mode} timed out after {timeout_seconds:.1f}s")
            matches=subprocess.run(["pgrep","-P",str(proc.pid),"-x","SaytileModelWorker" if a.model=="qwen-small" else "SaytileSherpa"],capture_output=True,text=True).stdout.split()
            assert len(matches)<=1
            state=matches[0] if matches else ""
            if state!=prior:
                if state and state not in pids:pids.append(state)
                changes.append(dict(t=round(time.monotonic()-start,2),worker=pids.index(state)+1 if state else None));prior=state
            time.sleep(.4)
        db=sqlite3.connect((root/"Saytile.sqlite").as_uri()+"?mode=ro",uri=True)
        rows=db.execute("select recognition_state,audio_state,total_frames, is_recording from recordings").fetchall()
        # Preserve observed evidence before assertions; an interrupted or failing
        # check must never leave a PASS receipt for this scenario.
        out[mode]={"status":"NOT_PASSED","expected_behavior":behavior,"silence_seconds":silence_seconds,
                   "fixture_seconds":fixture_seconds,"timeout_seconds":timeout_seconds,
                   "records":len(rows),"record_states":rows,"process_events":changes,"probe_exit":proc.returncode}
        save_receipt()
        chunk_frames=0
        for path,frames in db.execute("select path,frames from chunks"):
            with wave.open(str(root/"Audio"/path)) as wav:assert wav.getnframes()==frames and len(wav.readframes(frames))==frames*2
            chunk_frames+=frames
        assert sum(r[2] for r in rows)==chunk_frames>0 and db.execute("pragma integrity_check").fetchone()[0]=="ok"
        providers=[x[0] for x in db.execute("select distinct json_extract(payload,'$.provider') from model_runs")]
        if mode=="corrupt":
            assert not pids and proc.returncode!=0 and len(rows)==1 and rows[0][0]=="failed" and rows[0][1]=="available"
            assert set(providers).issubset({a.model}) and db.execute("select count(*) from dispatches").fetchone()[0]==0
            if a.retry_exe and a.model == "qwen-small":
                original_id = db.execute("select id from recordings").fetchone()[0]
                def hashes():
                    return {f.name: hashlib.sha256(f.read_bytes()).hexdigest() for f in (root/"Audio").rglob("*.wav")}
                before = hashes()
                source_member = a.weights/a.model/model["revision"]/small["path"]
                (directory/small["path"]).write_bytes(source_member.read_bytes())
                subprocess.run([a.retry_exe.resolve(), a.model, root, root/"LocalModels", app, root/"retry.json"], check=True, timeout=max(100,signal_seconds+90))
                restored = db.execute("select id,recognition_state,audio_state from recordings").fetchall()
                assert restored == [(original_id,"completed","available")] and hashes()==before
                assert db.execute("select count(*) from dispatches").fetchone()[0] == 0
                out["retry"] = dict(status="PASS", same_record=True, original_wav_hashes_unchanged=True, external_dispatches=0)
        else:
            assert proc.returncode==0 and len(rows)==2 and all(r[0]=="completed" and r[1]=="available" and r[3]==0 for r in rows)
            sequence=[v["worker"] for v in changes]
            # Initial launch and final app shutdown may fall between polls.
            # Only trim their absent-worker states; a gap during the warm pause
            # remains a failure, and release requires an observed interior gap.
            if sequence and sequence[0] is None:sequence=sequence[1:]
            if sequence and sequence[-1] is None:sequence=sequence[:-1]
            expected=[1] if mode=="warm" else [1,None,2]
            assert sequence==expected and len(pids)==(1 if mode=="warm" else 2), (mode,sequence,changes)
            assert providers==[a.model]
            visible=json.loads((root/"visible.json").read_text())
            events=visible["rawWorkerEvents"]
            out[mode]["worker_events"]=events
            save_receipt()
            assert len([event for event in events if event["kind"]=="ready"])==(1 if mode=="warm" else 2)
            assert len([event for event in events if event["kind"]=="final"])==2
        out[mode].update(status="PASS",recognition=list({r[0] for r in rows}),audio_available=True,
                         raw_pcm_frames=chunk_frames,providers=providers)
        db.close()
        save_receipt()
