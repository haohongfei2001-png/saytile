#!/usr/bin/env python3
"""Exercise the production model-call summary query on isolated SQLite fixtures.

Run with the Mac system Python for the same SQLite library as the native app.
CPU values are limited to fetching thirty result rows, not whole-app or ASR cost.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import statistics
import time


ROOT = Path(__file__).resolve().parents[2]
STORE = (ROOT / "Sources/SaytileKit/Store.swift").read_text()
TIMELINE = (ROOT / "Sources/SaytileKit/TranscriptTimeline.swift").read_text()
INDEX_NAMES = ("model_runs_recent", "usage_run")
LEGACY_QUERY = ("SELECT r.payload AS run_payload,r.state,r.last_error,u.payload AS usage_payload "
                "FROM model_runs r LEFT JOIN model_usage u ON u.run_id=r.id "
                "ORDER BY r.created_at DESC,r.rowid DESC LIMIT ?")


def sql_block(source, name):
    return re.search(rf'static let {name} = """(.*?)"""', source, re.S)[1]


SCHEMA = sql_block(STORE, "schema")
TIMELINE_SCHEMA = sql_block(TIMELINE, "timelineSchema")
BACKFILL = sql_block(TIMELINE, "timelineBackfill")
QUERY = re.search(r'public func modelCallSummaries\(.*?db\.rows\("([^"]+)"', STORE, re.S)[1]
OLD_SCHEMA = "\n".join(line for line in SCHEMA.splitlines()
                       if not any(f"INDEX IF NOT EXISTS {name} " in line for name in INDEX_NAMES))


def fixture(size, usage_rows):
    db = sqlite3.connect(":memory:")
    db.executescript("PRAGMA foreign_keys=ON;\n" + OLD_SCHEMA)
    for number in range(size):
        key = str(number)
        db.execute("INSERT INTO recordings(id,created_at,sample_rate,deleted) VALUES(?,?,16000,?)",
                   (key, number, number % 17 == 0))
        db.execute("INSERT INTO fusion_sessions(id,recording_id,audio_epoch,mode,state,created_at) "
                   "VALUES(?,?,1,'fixture','completed',?)", (key, key, number))
        db.execute("INSERT INTO model_runs(id,recognition_id,recording_id,audio_epoch,configuration_id,"
                   "payload,state,created_at) VALUES(?,?,?,1,'qwen-small',?,'completed',?)",
                   (key, key, key, json.dumps({"run": number}), number // 2))
        if usage_rows:
            # Include no entry, a single entry, and several deliberately out-of-order
            # entries in both old and recent runs. Some payloads are identical.
            values = [] if number % 13 == 0 else ["z", "a", "a", "c"] if number % 7 == 0 else ["y"]
            db.executemany("INSERT INTO model_usage VALUES(?,?,?,?,?)", (
                (f"{number}-{i}", key, key, json.dumps({"run": number, "usage": value}), number + i / 10)
                for i, value in enumerate(values)))
    db.commit()
    assert not db.execute("PRAGMA foreign_key_check").fetchall()
    return db


def plan(db, sql):
    return [r[-1] for r in db.execute("EXPLAIN QUERY PLAN " + sql, (30,))]


def timing(db, sql, repetitions):
    polls = []
    for _ in range(5):
        start = time.process_time_ns()
        for _ in range(repetitions):
            db.execute(sql, (30,)).fetchall()
        polls.append((time.process_time_ns() - start) / repetitions / 1e6)
    return round(statistics.median(polls), 5)


def verify_open():
    # Run the schema SQL blocks from the actual initializer against isolated fixtures,
    # including the pre-v6 backfill and the existing-v6 branch, then reopen again.
    versions = sorted(set(map(int, re.findall(r'version == "(\d+)"', STORE))))
    assert versions and 'if version != "6" { try database.script(Self.timelineBackfill) }' in STORE
    for version in versions:
        db = fixture(8, True)
        db.execute(f"PRAGMA user_version={version}")
        if version == 6:
            db.executescript(TIMELINE_SCHEMA + BACKFILL)
        before = db.execute(LEGACY_QUERY, (500,)).fetchall()
        for _ in range(2):
            old = db.execute("PRAGMA user_version").fetchone()[0]
            db.executescript("BEGIN;\n" + SCHEMA + TIMELINE_SCHEMA + (BACKFILL if old != 6 else "") +
                             "\nPRAGMA user_version=6; COMMIT;")
            assert not db.execute("PRAGMA foreign_key_check").fetchall()
            assert db.execute(QUERY, (500,)).fetchall() == before
            assert all(db.execute("SELECT 1 FROM sqlite_schema WHERE type='index' AND name=?", (n,)).fetchone()
                       for n in INDEX_NAMES)
        db.close()
    return versions


def benchmark(size, include_usage):
    old = fixture(size, include_usage)
    new = sqlite3.connect(":memory:")
    old.backup(new)
    new.execute("PRAGMA foreign_keys=ON")
    pages = new.execute("PRAGMA page_count").fetchone()[0]
    new.executescript(SCHEMA)
    # Verify complete and truncated joins, including one cut mid-run, with ties in run
    # timestamps, missing/multiple usage entries and logically deleted recordings.
    for limit in (1, 2, 3, 7, 9, 30, 500):
        assert old.execute(LEGACY_QUERY, (limit,)).fetchall() == new.execute(QUERY, (limit,)).fetchall(), limit
    bound_plan = plan(new, QUERY)
    assert any("model_runs_recent" in row for row in bound_plan) and any("usage_run" in row for row in bound_plan)
    assert not any("AUTOMATIC" in row for row in bound_plan)
    count = 16 if size >= 10000 else 100
    result = dict(runs=size, mixed_usage=include_usage,
                  hash_first_30=hashlib.sha256(json.dumps(new.execute(QUERY, (30,)).fetchall()).encode()).hexdigest(),
                  old_cpu_ms=timing(old, LEGACY_QUERY, count), new_cpu_ms=timing(new, QUERY, count),
                  added_index_bytes=(new.execute("PRAGMA page_count").fetchone()[0] - pages) *
                                    new.execute("PRAGMA page_size").fetchone()[0],
                  old_plan=plan(old, LEGACY_QUERY), new_plan=bound_plan)
    old.close()
    new.close()
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = dict(sqlite=sqlite3.sqlite_version, schema_sql_sha256=hashlib.sha256(SCHEMA.encode()).hexdigest(),
                  query_sha256=hashlib.sha256(QUERY.encode()).hexdigest(), version_branches_on_open=verify_open(),
                  fixtures=[benchmark(size, usage) for size in (47, 1000, 10000) for usage in (False, True)])
    args.output.write_text(json.dumps(result, indent=2) + "\n")
