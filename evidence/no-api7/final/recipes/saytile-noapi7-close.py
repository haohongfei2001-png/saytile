"""Assemble the no-api.7 engineering manifest from local receipts, derived from no-api.6.

Run from the no-api.7 worktree. Default verification is read-only. --write performs
the same verification and atomically installs the completed manifest. No test,
network request, installation or user-database access is performed here.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

if not __debug__:
    raise SystemExit("Run without Python optimization. Integrity assertions must remain active.")

parser = argparse.ArgumentParser(description=__doc__)
mode = parser.add_mutually_exclusive_group()
mode.add_argument("--check-current", action="store_true", help="check available short receipts only, never close")
mode.add_argument("--write", action="store_true", help="write delivery-manifest.json after every receipt verifies")
args = parser.parse_args()
root = Path.cwd()
out = root / "evidence/no-api7/final"
sha = "4b97bd89b258fea29a0be61d4bd4c23cb5ab428c"
tree = "4aac670d6edfcce0c12ed22fa3cd5c68e66061b9"
successor = "54b4c40fea85069ee77c60fd414bfab8f535c8fb"
successor_tree = "8b5efa4eab48db698f9072d39c65fbcd81d447b5"
version = "1.0.0-rc.2-no-api.7"
references = set()

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def read(rel):
    references.add(rel)
    return json.loads((out / rel).read_bytes())

def verified_hashes(directory, mapping):
    assert mapping, f"Empty hash receipt at {directory}"
    for name, expected in mapping.items():
        assert digest(directory / name) == expected, f"File hash differs: {name}"

def git(*arguments):
    return subprocess.check_output(["git", *arguments], text=True).strip()

assert git("rev-parse", sha + "^{tree}") == tree
before = read("source-before.json")
assert before["head"] == sha and before["tree"] == tree and not before["runtime_diff"]
# Additional docs or evidence commits may already have landed. Compare actual inputs.
verified_hashes(root, before["source_sha256"])
pack = read("package-identity.json")
assert pack["source_revision"] == sha and pack["tree"] == tree and pack["source_dirty"] is False
assert pack["version"] == version and pack["installed_rc1_replaced"] is False and pack["cloud_calls"] == 0
binary = pack["binary_sha256"]
dmg = pack["dmg_sha256"]
paths = read("delivery-paths.json")
assert (paths["source_revision"], paths["runtime_tree"], paths["binary_sha256"], paths["dmg_sha256"]) == (sha, tree, binary, dmg)
assert paths["rc1_replaced"] is False and paths["dmg_bytes"] == pack["dmg_bytes"]
assert paths["github_path"] == "deliverables/no-api.7/Saytile-1.0.0-rc.2-no-api.7-arm64.dmg"
for file in (Path(pack["dmg_path"]), root / paths["github_path"], Path(paths["canonical_dmg"])):
    assert file.stat().st_size == pack["dmg_bytes"] and digest(file) == dmg, f"DMG differs: {file.name}"
assert digest(Path(pack["app_path"]) / "Contents/MacOS/Saytile") == binary
links = read("package-check-linkage.json")
assert (links["source_revision"], links["executable_sha256"], links["dmg_sha256"]) == (sha, binary, dmg)
assert {"apple/signed-app.json","install-upgrade.json","uninstall-reinstall.json","cloud-probe-cli.json",
        "connection-setup-cli.json","app-idle.json","ui/manifest.json","ui-render-only/manifest.json",
        "startup-focus.log","startup-focus-identities.txt"} <= links["checks"].keys()
verified_hashes(out, links["checks"])
references.update(links["checks"])

policy = read("gatekeeper.json")
assert policy["source_revision"] == sha and policy["binary_sha256"] == binary and policy["dmg_sha256"] == dmg
assert policy["system_assessment"]["stdout"] == "assessments enabled" and policy["code_integrity"]["exit"] == 0
assert policy["executable_assessment"]["exit"] == 3 and policy["executable_assessment"]["stderr"].endswith("rejected")

native = read("protocol/run-after.json")
native_before = read("protocol/run-before.json")
assert (native["result"], native["head"], native["tree"], native["head_unchanged"], native["tree_unchanged"]) == ("PASS",sha,tree,True,True)
assert native["source_sha256"] == native_before["source_sha256"] and not native["source_changes_during_run"]
assert all(before["source_sha256"].get(p) == h for p,h in native["source_sha256"].items())
assert (native["native_test_functions"],native["native_suites"],native["native_effective_scenarios"],native["protocol_test_functions"],native["protocol_scenarios"],native["network_cases"]) == (392,48,512,12,52,50)
assert not native["skip_or_not_run_lines"] and not native["protocol_violations"]
verified_hashes(out / "protocol", native["artifacts_sha256"])
wire = read("protocol/wire-audit.json")
assert wire["scope"] == "SIMULATED_PROTOCOL_NOT_LIVE_CLOUD" and len(wire["cases"]) == 50 and not any(v["violations"] for v in wire["cases"].values())

def check_ci(directory, expected_head, expected_tree, conclusions):
    ci = read(directory + "/ci-snapshot.json")
    merge = read(directory + "/ci-merge-identity.json")
    assert ci["head"] == expected_head and ci["tree"] == expected_tree and ci["same_tree"]
    assert merge["sha"] == ci["checkout_merge_sha"] and merge["tree"] == ci["checkout_tree"] == expected_tree
    assert merge["parents"][-1] == expected_head
    assert {r["name"]:r["conclusion"] for r in ci["runs"]} == conclusions
    assert (ci["native_functions"],ci["native_expanded_scenarios"],ci["native_test_skip_or_not_run_lines"]) == (392,512,[])
    assert any(l.startswith("WIRE_AUDIT cases=50 protocol_violations=0") for l in ci["summary_lines"])
    verified_hashes(out / directory, ci["artifacts_sha256"])
    return ci

ci = check_ci("protocol", sha, tree, {"Saytile native":"cancelled","Saytile design contracts":"success"})
steps = {s["name"]:s["conclusion"] for j in ci["jobs"] if j["name"] == "native" for s in j["steps"]}
assert steps["Real localhost provider protocols (no API keys)"] == "success"
assert steps["Run scripts/test-app-model.sh"] == "cancelled" and steps["Run scripts/build-app.sh"] == "skipped"
assert ci["ui_captures"] == ci["ax_press"] == 0
succ = check_ci("protocol/docs-successor-ci",successor,successor_tree,{"Saytile native":"success","Saytile design contracts":"success"})
comp = read("protocol/docs-successor-ci/comparison.json")
assert (comp["frozen_head"],comp["docs_only_successor"],comp["same_full_tree"]) == (sha,successor,False)
assert not comp["changed_engineering_files"] and git("diff","--name-status",sha,successor,"--",*comp["compared_engineering_paths"]) == ""
assert git("diff","--name-status",sha,successor).splitlines() == comp["all_changed_files"] and all(row.startswith("M\tdocs/") for row in comp["all_changed_files"])
assert (succ["ui_captures"],succ["ax_press"],succ["ci_ui_controls"]) == (27,0,"NOT_RUN_RENDER_ONLY")

ui = read("ui/manifest.json")
render = read("ui-render-only/manifest.json")
assert all(m["passed"] and m["source_revision"] == sha and m["binary_sha256"] == binary and not m["source_dirty"] for m in (ui,render))
assert (len(ui["images"]),ui["native_ax_press"],ui["native_menu_select"],ui["control_groups"],ui["outside_foreground_observations"],len(render["images"]),render["native_ax_press"]) == (37,45,10,15,0,27,0)
ui_run = read("ui/execution-receipt.json")
glyph = read("ui/voice-glyph-audit.json")
assert all(r["source_revision"] == sha and r["source_tree"] == tree and r["tracked_inputs_unchanged"] for r in (ui_run,glyph))
assert (ui_run["binary_sha256"],ui_run["dmg_sha256"]) == (binary,dmg)
for folder, prefix in [("ui","controls"),("ui-render-only","render_only")]:
    motion = read(folder + "/voice-glyph-motion/manifest.json")
    assert len(motion["frames"]) == len(glyph[prefix+"_frame_sha256"]) == 71
    verified_hashes(out / folder / "voice-glyph-motion", glyph[prefix+"_frame_sha256"])
    verified_hashes(out / folder, ui_run[prefix+"_png_sha256"])
references.update(["reference-source.json","ui/glass-samples.json","ui/REVIEW.md","INDEPENDENT-REVIEW.md"])

model = read("input/app-model-identity.json")
dom = read("input/browser-identity.json")
inp = read("input/native-receipt.json")
owned = read("owned-range/summary.json")
assert (model["head"],model["tree"],model["checks"],model["exit"],model["unchanged"]) == (sha,tree,104,0,True)
assert (dom["head"],dom["tree"],dom["checks"],dom["unchanged"]) == (sha,tree,20,True)
assert model["log_sha256"] == digest(out / "input/app-model.log") and dom["log_sha256"] == digest(out / "input/input-browser-dom.log")
assert inp["source_revision"] == owned["head"] == sha and inp["source_tree"] == tree and inp["tracked_inputs_unchanged"]
assert (inp["ordinary_native_checks"],inp["owned_range_scenarios"],inp["send_events"],inp["uncertain_replay"],inp["foreground_resolver"],inp["wk_dispatch"]) == (9,9,0,False,"NOT_RUN","unverified")
assert owned["status"] == "PASS" and len(owned["scenarios_passed"]) == 9 and not owned["source_changed_during_run"]

apple = read("apple/apple-summary.json")
rows = read("apple/apple-corpus.json")
fixture = read("apple/fixture-identity.json")
asset = read("apple/asset-preparation.json")
signed = read("apple/signed-app.json")
assert (apple["runtime"],apple["tree"],apple["cases"],apple["completed"],len(rows)) == (sha,tree,8,8,8)
assert all(row["recognitionState"]=="completed" and row["localProviders"]==["apple-speech-analyzer"] and row["dispatchableUTF16Length"]>0 for row in rows)
verified_hashes(out / "apple", apple["results_sha256"])
assert (signed["passed"],signed["runtime"],signed["binary_sha256"]) == (True,sha,binary)
assert fixture["runtime"] == sha and fixture["tree"] == tree and signed["fixture_sha256"] == fixture["generated_synthetic_audio"][signed["synthesized_fixture"]]
attempt = signed["attempts"][-1]
assert attempt["exit"]==0 and attempt["rows"] == [["completed","available",0]] and attempt["latest_text"] and attempt["saved_wavs"]
assert all(n > 44 and re.fullmatch("[0-9a-f]{64}", h) for n,h in attempt["saved_wavs"])
assert asset["after"]["installed"] and asset["preparationCalls"] <= 1

upgrade = read("install-upgrade.json")
reinstall = read("uninstall-reinstall.json")
assert all(r["status"]=="PASS" and r["source_revision"]==sha and r["binary_sha256"]==binary for r in (upgrade,reinstall))
assert (upgrade["dmg_sha256"],upgrade["release_version"],upgrade["count"],len(reinstall["checks"])) == (dmg,version,8,2)
before_preserve = read("preservation-before.json")
assert upgrade["baseline_app_source_revision"] == before_preserve["installed_source"] == "8906a9dc4b2ec186f634bb2c829d8eb0c1700679"
assert upgrade["baseline_binary_sha256"]==before_preserve["installed_binary_sha256"] and upgrade["previous_dmg_sha256"]==before_preserve["rc1_dmg_sha256"]
cloud_cli = read("cloud-probe-cli.json")
setup = read("connection-setup-cli.json")
assert len(cloud_cli["cases"])==17 and all(c["result"].startswith("PASS") for c in cloud_cli["cases"])
assert not (cloud_cli["cloud_calls"] or cloud_cli["microphone_started"] or cloud_cli["private_database_accessed"])
assert (setup["passed"],setup["source_revision"],setup["binary_sha256"]) == (7,sha,binary)
assert not (setup["provider_requests"] or setup["window_opened"] or setup["credential_values_read"])
idle = read("app-idle.json")
assert (idle["source_revision"],idle["binary_sha256"],idle["release_version"],idle["isolated_preferences_confirmed"]) == (sha,binary,version,True)
assert idle["wall_seconds"] >= 300

quality = read("cloud-quality-boundary.json")
assert quality["scope"]=="NOT_MEASURED_WITH_LIVE_PROVIDERS" and quality["source_revision"]==sha
assert quality["real_provider_calls"]==quality["same_human_audio_samples_uploaded"]==0
assert all(quality[k] is None for k in ("best_single_model","absolute_accuracy_gain","relative_error_reduction","extra_confirmation_latency_seconds","winning_conditions"))
assert set(quality["stages"])=={"first_text","corrected_during_speech","dispatchable_stable","final_text"} and all(v is None for stage in quality["stages"].values() for v in stage.values())
short = read("../local/short-source-after.json")
storage = read("../local/storage-processes.json")
scale = read("../local/storage-scale/storage-scale.json")
assert (short["status"],short["source_revision"],short["tree"],short["source_changed"]) == ("PASS",sha,tree,[])
assert len(short["checks"])==8 and all(v is True for v in short["checks"].values())
assert (storage["status"],storage["passed"],storage["source_revision"],storage["source_dirty"]) == ("PASS",12,sha,False)
assert (scale["recordings"],scale["revisions"],scale["partial_writes"],scale["search_matches"]) == (100000,300000,200,100)
pending = ["../local/realtime-assessment.json","../local/post-run-identities.json","source-after.json","preservation-after.json","public-download.json"]
missing = [f for f in pending if not (out / f).is_file()]
if args.check_current:
    print("Verified existing short receipts. No manifest written. Remaining receipt paths:", missing)
    raise SystemExit(0)
if missing:
    raise SystemExit("Open evidence. No manifest written. Missing " + ", ".join(missing))

after = read("source-after.json")
after_preserve = read("preservation-after.json")
assert (after["head"],after["tree"],after["runtime_diff"],after["changed_files"],after["source_sha256"]) == (sha,tree,[],[],before["source_sha256"])
assert all(before_preserve[k] == after_preserve[k] for k in ("installed_source","installed_binary_sha256","rc1_dmg_sha256"))
assert before_preserve["canonical_tracked_diff"] == after_preserve["canonical_tracked_diff"]
canonical = "/Users/hhf/Documents/GitHub/saytile"
canonical_changes = git("-C",canonical,"diff","--name-status",before_preserve["canonical_head"],after_preserve["canonical_head"]).splitlines()
assert all(row.split("\t")[-1].startswith(("docs/","design/")) for row in canonical_changes), "Inspect unexpected external canonical change before closing."
long = read("../local/realtime-assessment.json")
post = read("../local/post-run-identities.json")
assert long["source_revision"]==long["head_after"]==sha and long["status"] == "PASS" and len(long["checks"])==23 and all(v is True for v in long["checks"].values())
assert long["actual_wallclock_seconds"]>=1800 and long["different_sample_frames"]==0 and long["upload_grants"]==0
assert long["reference_frames"]==long["saved_frames"]==28800000 and long["reference_sha256"]==long["concatenated_saved_pcm_sha256"]
assert (post["status"],post["source_revision"],post["tree"],post["owned_probe_exited"],post["assessor_true_checks"]) == ("PASS",sha,tree,True,23)
assert post["probes"] and all(r["unchanged"] for r in post["probes"].values())
pub = read("public-download.json")
assert (pub["source_revision"],pub["bytes"],pub["downloaded_sha256"],pub["matches_mounted_tested_dmg"]) == (sha,pack["dmg_bytes"],dmg,True)
assert re.fullmatch("[0-9a-f]{40}",pub["publication_commit"]) and pub["retrieved_utc"]
assert pub["url"] == "https://raw.githubusercontent.com/haohongfei2001-png/saytile/" + pub["publication_commit"] + "/" + paths["github_path"]

artifact_ci = read("protocol/publication-ci.json")
assert artifact_ci["publication_commit"] == pub["publication_commit"] and artifact_ci["source_revision"] == sha
assert not artifact_ci["changed_engineering_paths"] and len(artifact_ci["runs"]) == 2
assert all(x["sha"] == pub["publication_commit"] and x["conclusion"] == "success" for x in artifact_ci["runs"])

states = {"NO_API_ENGINEERING_READY":True,"LIVE_CONNECTION_PENDING":True,"LIVE_PROTOCOL_VERIFIED":False,
          "LIVE_TRANSCRIPTION_VERIFIED":False,"QUALITY_VERIFIED":False,"PRODUCTION_READY":False}
manifest = {
    "states":states,"role":"Personal no-api.7 macOS engineering candidate with lavender-blue panel. Live cloud acceptance pending.",
    "tested_source":sha,"runtime_tree":tree,"release_version":version,"binary_sha256":binary,
    "dmg_sha256":dmg,"dmg_bytes":pack["dmg_bytes"],"public_download":pub,"delivery_paths":paths,
    "source_inputs_before_and_after":len(before["source_sha256"]),"production_main_or_rc1_replaced":False,
    "canonical_commit_changes_during_verification":canonical_changes,"real_provider_calls":0,"private_audio_uploaded":False,
    "cloud_quality":quality,
    "native":{"functions":392,"suites":48,"expanded_scenarios":512,"protocol_functions":12,"protocol_scenarios":52,"wire_cases":50,"skipped":0,"appmodel_checks":104},
    "ci":{"publication_checkpoint":artifact_ci,"exact_source":{"head":sha,"checkout":ci["checkout_merge_sha"],"checkout_tree":ci["checkout_tree"],"native":"cancelled_during_appmodel","design":"success","swift_functions":392,"wire_cases":50,"ui_captures":0},
          "docs_only_successor":{"head":successor,"full_tree":successor_tree,"checkout":succ["checkout_merge_sha"],"native":"success","design":"success","changed_engineering_files":[],"ui_captures":27,"ci_ax_controls":"NOT_RUN"}},
    "ui":{"real_ax_press":45,"actual_menu_selections":10,"control_images":37,"render_only_images":27,"control_groups":15,"glyph_frames_per_mode":71,"outside_foreground_transitions":0},
    "input":inp,"headless_dom_checks":20,"apple":apple,"signed_packaged_apple":signed,
    "install":{"upgrade_checks":upgrade["count"],"reinstall_checks":len(reinstall["checks"]),"candidate_version":version,"rc1_source":upgrade["baseline_app_source_revision"],"rc1_rollback":"Use the explicit pre-upgrade copy, preserving candidate data."},
    "public_mac_distribution":{"code_integrity":"verified","gatekeeper_assessment":"rejected","notarized":False,"policy_modified":False},"signed_app_idle_seconds":idle["wall_seconds"],
    "long_capture":{k:long[k] for k in ("actual_wallclock_seconds","recordings","closed_wav_chunks_verified","saved_frames","reference_sha256","different_sample_frames","upload_grants","resource_samples","sampled_rss_kib_min","sampled_rss_kib_max","cpu_seconds_per_wallclock_percent")},
    "limitations":[
        "Real-provider authentication, authorized human speech processing, accuracy, strongest-single comparison, fusion gain and extra confirmation latency remain unmeasured.",
        "Apple speech evidence covers eight synthetic Mandarin fixtures and one separate signed-app fixture. Four expected phrases were missing in the corpus.",
        "Physical microphone, arbitrary foreground apps, physical sleep/hot-plug, multiple displays and 24–72-hour energy remain unverified.",
        "Foreground input resolution was not exercised. A background WK setter acknowledged the request without changing the DOM. That dispatch remained unverified and was not replayed.",
        "The original approved PNG bytes were unavailable. Actual package colors and deterministic animation sample frames are documented. User visual acceptance, exact original color matching and live wallpaper appearance remain unverified.",
        "The personal arm64 build carries an ad-hoc signature. Strict code verification passed, but enabled Gatekeeper rejected the exact candidate (spctl exit 3). Ordinary distribution requires authorized Developer ID signing and notarization; no policy was bypassed."
    ],
    "evidence_sha256":{f:digest(out/f) for f in sorted(references)}
}
encoded = json.dumps(manifest,ensure_ascii=False,indent=2) + "\n"
if args.write:
    dest = out / "delivery-manifest.json"
    if dest.exists() and dest.read_text() != encoded:
        raise SystemExit("Different manifest already exists. Inspect it before replacing evidence.")
    if not dest.exists():
        with tempfile.NamedTemporaryFile(mode="w",encoding="utf-8",dir=out,delete=False) as temp:
            temp.write(encoded)
            temp.flush()
            os.fsync(temp.fileno())
            temp_path = Path(temp.name)
        os.replace(temp_path,dest)
    print("Closed local engineering evidence",sha,len(references),len(long["checks"]),long["actual_wallclock_seconds"])
else:
    print("All closure receipts verified. No manifest written. Use --write to save.")
