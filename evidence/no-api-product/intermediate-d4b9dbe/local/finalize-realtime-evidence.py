#!/usr/bin/env python3
"""Assess completed owned synthetic run without reading any user data."""
import hashlib,json,pathlib,re,sqlite3,wave
OUT=pathlib.Path(__file__).resolve().parent
before=json.loads((OUT/'source-before.json').read_text())
fixture=json.loads((OUT/'input-fixture.json').read_text())
after=json.loads((OUT/'source-after.json').read_text())
log=(OUT/'realtime-run.log').read_text()
row=re.search(r'^realtime_seconds=(.+)$',log,re.M)
assert row,'Completed production probe summary is required'
values=dict(x.split('=',1) for x in ('realtime_seconds='+row[1]).split())
wall=re.search(r'^\s*([\d.]+) real\s+([\d.]+) user\s+([\d.]+) sys$',log,re.M)
assert wall,'Actual /usr/bin/time result is required'
root=pathlib.Path(after['data_directory'])
assert str(root).startswith('/tmp/saytile-rc-realtime-data.')
checks={
 'process_exit_zero':after['runner_exit']==0,
 'actual_wallclock_1800_seconds':float(wall[1])>=1800,
 'requested_1800_seconds':float(values['realtime_seconds'])==1800,
 'all_input_frames_produced':int(values['produced_frames'])==1800*fixture['sample_rate_hz'],
 'synthetic_input_unchanged':hashlib.sha256(pathlib.Path(fixture['path']).read_bytes()).hexdigest()==fixture['sha256']==before['input_sha256'],
 'repository_input_byte_identical':hashlib.sha256((OUT/'realtime-synthetic-source.aiff').read_bytes()).hexdigest()==fixture['sha256'],
 'no_capture_error':'CAPTURE_FAILURE ' not in log,
 'no_dropped_input_frames':int(values['dropped_frames'])==0,
 'saved_records_exist':int(values['records'])>0,
 'all_audio_available':values['all_available']=='true',
 'all_recordings_finished':values['all_finished']=='true',
 'source_unchanged':not after['source_changed'],
 'probe_binary_unchanged':hashlib.sha256(pathlib.Path(after['probe']['binary']).read_bytes()).hexdigest()==after['probe']['binary_sha256'],
}
with sqlite3.connect('file:'+str(root/'Saytile.sqlite')+'?mode=ro',uri=True) as db:
 checks['sqlite_integrity']=db.execute('pragma quick_check').fetchone()[0]=='ok'
 checks['schema5']=db.execute('pragma user_version').fetchone()[0]==5
 grants=db.execute('select count(*) from recording_cloud_authorizations').fetchone()[0]
 checks['no_implicit_upload_grants']=grants==0
 chunks=db.execute('select path,frames from chunks order by ordinal').fetchall()
 recordings=db.execute('select count(*),coalesce(sum(total_frames),0),coalesce(sum(is_recording),0) from recordings').fetchone()
file_frames=0;valid=0
for path,frames in chunks:
 audio=root/'Audio'/path
 assert audio.resolve().is_relative_to((root/'Audio').resolve()) and not audio.is_symlink()
 with wave.open(str(audio),'rb') as f:
  assert f.getnchannels()==1 and f.getsampwidth()==2 and f.getframerate()==16000 and f.getnframes()==frames
  # Verify payload bytes also exist rather than trusting only a WAV header.
  payload=f.readframes(frames);assert len(payload)==frames*2
 file_frames+=frames;valid+=1
checks['every_closed_wav_header_and_payload_matches_journal']=valid==len(chunks) and valid>0
checks['recording_totals_match_chunk_frames']=recordings[1]==file_frames and recordings[2]==0
resources=[json.loads(x) for x in (OUT/'realtime-resources.jsonl').read_text().splitlines()]
observed=[r['ps'].split(maxsplit=4) for r in resources if r.get('ps')]
result={'status':'PASS' if all(checks.values()) else 'FAIL','scope':'1800s wall-clock synthetic production capture; ASR/microphone/speaker/cloud disabled; not 24h or human speech acceptance','source_revision':before['expected_source_revision'],'head_after':after['head_after'],'checks':checks,'probe_summary':values,'actual_wallclock_seconds':float(wall[1]),'process_user_cpu_seconds':float(wall[2]),'process_system_cpu_seconds':float(wall[3]),'cpu_seconds_per_wallclock_percent':(float(wall[2])+float(wall[3]))/float(wall[1])*100,'owned_directory':str(root),'closed_wav_chunks_verified':valid,'recordings':recordings[0],'saved_frames':file_frames,'upload_grants':grants,'resource_samples':len(observed),'sampled_rss_kib_min':min(int(r[2]) for r in observed),'sampled_rss_kib_max':max(int(r[2]) for r in observed),'sampled_ps_cpu_percent_min':min(float(r[3]) for r in observed),'sampled_ps_cpu_percent_max':max(float(r[3]) for r in observed)}
(OUT/'realtime-assessment.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
raise SystemExit(0 if result['status']=='PASS' else 1)
