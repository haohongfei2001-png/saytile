"""Executable design model for the two recovered Saytile review changes.

Uses synthetic files and SQLite. This is NOT a macOS audio engine or input
adapter. It never records, contacts a speech service or changes another app.
Shared-file erasure is conservatively deferred, not falsely reported complete.
"""
from __future__ import annotations
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator
import sqlite3
import uuid

SCHEMA = Path(__file__).resolve().parents[1] / 'contracts/schema.sql'

class ContractError(ValueError):
    pass

def now() -> str:
    return datetime.now(timezone.utc).isoformat()

def utf16_length(text: str) -> int:
    return len(text.encode('utf-16-le')) // 2

def utf16_prefix(text: str, end: int) -> str:
    """Reject out-of-bounds offsets and split surrogate pairs (AX uses UTF-16)."""
    raw = text.encode('utf-16-le')
    if not isinstance(end, int) or isinstance(end, bool) or end < 0 or end * 2 > len(raw):
        raise ContractError('invalid UTF-16 boundary')
    try:
        return raw[:end * 2].decode('utf-16-le', errors='strict')
    except UnicodeDecodeError as e:
        raise ContractError('UTF-16 boundary splits a surrogate pair') from e

class Store:
    def __init__(self, path: Path, audio_root: Path, *, recover: bool = True):
        self.audio_root = audio_root.resolve()
        self.audio_root.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path, isolation_level=None, timeout=5)
        self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA foreign_keys=ON')
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('PRAGMA synchronous=FULL')
        version = self.db.execute('PRAGMA user_version').fetchone()[0]
        if version == 0:
            if self.db.execute("SELECT 1 FROM sqlite_master WHERE type='table'").fetchone():
                raise ContractError('Existing unversioned database needs a reviewed migration')
            self.db.executescript(SCHEMA.read_text())
        elif version != 2:
            raise ContractError('Unsupported schema version')
        self.runtime_bindings: set[str] = set()
        if recover:
            self.recover_input()
            # This reference model has one process owner; leases cannot survive
            # that process. Production multi-process leases need owner epochs.
            self.db.execute('DELETE FROM audio_leases')

    def close(self) -> None:
        self.db.close()

    @contextmanager
    def transaction(self) -> Iterator[None]:
        self.db.execute('BEGIN IMMEDIATE')
        try:
            yield
            self.db.execute('COMMIT')
        except BaseException:
            if self.db.in_transaction:
                self.db.execute('ROLLBACK')
            raise

    def audio_path(self, relative: str) -> Path:
        path = (self.audio_root / relative).resolve()
        if not path.is_relative_to(self.audio_root) or path == self.audio_root:
            raise ContractError('Audio path escapes managed store')
        return path

    def request_audio_erasure(self, utterance_id: str, *, reason: str = 'user') -> str:
        if reason not in ('user','retention'):
            raise ContractError('invalid erasure reason')
        with self.transaction():
            u = self.db.execute('SELECT * FROM utterances WHERE id=?',(utterance_id,)).fetchone()
            if not u or u['deleted_at']:
                raise ContractError('record is unavailable')
            existing = self.db.execute('SELECT id FROM audio_erasure_intents WHERE utterance_id=?',(utterance_id,)).fetchone()
            if existing:
                return existing['id']
            if u['core_end_sample'] is None:
                raise ContractError('Seal active utterance and start a new one before erasure')
            if reason == 'retention':
                unfinished = self.db.execute("SELECT 1 FROM recognition_jobs WHERE utterance_id=? AND state IN ('queued','running','retry_wait','paused')",(utterance_id,)).fetchone()
                has_final = self.db.execute("SELECT 1 FROM transcript_revisions WHERE utterance_id=? AND origin='asr_final'",(utterance_id,)).fetchone()
                if u['is_pinned'] or unfinished or not has_final:
                    raise ContractError('protected audio is not eligible for retention cleanup')
            iid = str(uuid.uuid4())
            self.db.execute('INSERT INTO audio_erasure_intents VALUES (?,?,?,?,?,?,NULL)',
                            (iid,utterance_id,u['content_generation'],reason,'pending',now()))
            refs = self.db.execute('SELECT * FROM utterance_audio_refs WHERE utterance_id=?',(utterance_id,)).fetchall()
            spans = {(u['core_start_sample'],u['core_end_sample'])}
            spans.update((r['start_sample'],r['end_sample']) for r in refs)
            for start,end in spans:
                if end > start:
                    self.db.execute('INSERT INTO audio_erasure_ranges VALUES (?,?,?,?)',(iid,u['session_id'],start,end))
            for chunk in {r['chunk_id'] for r in refs}:
                self.db.execute('INSERT INTO audio_erasure_chunks(intent_id,chunk_id) VALUES (?,?)',(iid,chunk))
            self.db.execute("UPDATE utterances SET audio_state='delete_pending', audio_epoch=audio_epoch+1 WHERE id=?",(utterance_id,))
            self.db.execute("UPDATE recognition_jobs SET state='cancelled',active_attempt=NULL WHERE utterance_id=? AND state!='completed'",(utterance_id,))
            # transcript_revisions, preferred_revision_id and content_generation
            # deliberately remain unchanged; no record-deletion tombstone is used.
        return iid

    def cleanup_audio(self, intent_id: str, *, fail_after_unlink: bool = False) -> bool:
        """Single maintenance worker. A crash rolls back metadata, not unlink;
        repeating cleanup is safe. Leases/shared references delay completion.
        No claim of secure SSD/backup erasure is made.
        """
        with self.transaction():
            intent = self.db.execute('SELECT * FROM audio_erasure_intents WHERE id=?',(intent_id,)).fetchone()
            if not intent:
                raise ContractError('unknown erasure intent')
            pending = self.db.execute('SELECT * FROM audio_erasure_chunks WHERE intent_id=?',(intent_id,)).fetchall()
            for item in pending:
                cid = item['chunk_id']
                chunk = self.db.execute('SELECT * FROM audio_chunks WHERE id=?',(cid,)).fetchone()
                if chunk is None:
                    raise ContractError('chunk metadata missing; keep cleanup pending')
                lease = self.db.execute('SELECT 1 FROM audio_leases WHERE chunk_id=?',(cid,)).fetchone()
                shared = self.db.execute("""SELECT 1 FROM utterance_audio_refs r JOIN utterances u ON u.id=r.utterance_id
                    WHERE r.chunk_id=? AND u.audio_state='available' AND u.deleted_at IS NULL""",(cid,)).fetchone()
                if chunk['state']=='writing' or lease or shared:
                    state = 'leased' if lease or chunk['state']=='writing' else 'shared_deferred'
                    self.db.execute('UPDATE audio_erasure_chunks SET state=? WHERE intent_id=? AND chunk_id=?',(state,intent_id,cid))
                    continue
                self.audio_path(chunk['relative_path']).unlink(missing_ok=True)
                if fail_after_unlink:
                    raise OSError('injected crash boundary after unlink, before metadata commit')
                self.db.execute("UPDATE audio_chunks SET state='deleted' WHERE id=?",(cid,))
                self.db.execute('DELETE FROM utterance_audio_refs WHERE chunk_id=?',(cid,))
                self.db.execute("UPDATE audio_erasure_chunks SET state='complete' WHERE chunk_id=?",(cid,))
            # Complete every intent whose shared files have now all been removed.
            for row in self.db.execute("SELECT id,utterance_id FROM audio_erasure_intents WHERE state='pending'").fetchall():
                remains = self.db.execute("SELECT 1 FROM audio_erasure_chunks WHERE intent_id=? AND state!='complete'",(row['id'],)).fetchone()
                if not remains:
                    self.db.execute("UPDATE audio_erasure_intents SET state='complete',completed_at=? WHERE id=?",(now(),row['id']))
                    self.db.execute("UPDATE utterances SET audio_state='deleted' WHERE id=?",(row['utterance_id'],))
            return self.db.execute('SELECT state FROM audio_erasure_intents WHERE id=?',(intent_id,)).fetchone()[0]=='complete'

    def recoverable_audio_ranges(self, generation: int, session: str, start: int, end: int) -> list[tuple[int,int]]:
        """Subtract tombstoned spans before considering orphan sidecars."""
        if start < 0 or end <= start:
            raise ContractError('invalid range')
        current = int(self.db.execute("SELECT value FROM store_meta WHERE key='content_generation'").fetchone()[0])
        if generation != current:
            return []
        if self.db.execute("SELECT 1 FROM deletion_tombstones WHERE source_generation=? AND scope='generation'",(generation,)).fetchone():
            return []
        masks = [(r[0],r[1]) for r in self.db.execute("""SELECT r.start_sample,r.end_sample FROM audio_erasure_ranges r
            JOIN audio_erasure_intents i ON i.id=r.intent_id WHERE i.source_generation=? AND r.session_id=?""",(generation,session))]
        masks += [(r[0],r[1]) for r in self.db.execute("SELECT start_sample,end_sample FROM deletion_tombstones WHERE source_generation=? AND session_id=?",(generation,session))]
        spans = [(start,end)]
        for a,b in sorted(masks):
            kept = []
            for x,y in spans:
                if b <= x or a >= y:
                    kept.append((x,y))
                else:
                    if x<a: kept.append((x,a))
                    if b<y: kept.append((b,y))
            spans = kept
        return spans

    def accept_asr(self, job_id: str, attempt: str, text: str) -> bool:
        """One transaction checks lifetime and writes a new immutable revision."""
        with self.transaction():
            row = self.db.execute('''SELECT j.*,u.audio_state,u.audio_epoch,u.deleted_at,u.preferred_revision_id
                FROM recognition_jobs j JOIN utterances u ON u.id=j.utterance_id WHERE j.id=?''',(job_id,)).fetchone()
            generation = int(self.db.execute("SELECT value FROM store_meta WHERE key='content_generation'").fetchone()[0])
            if not row or row['state']!='running' or row['active_attempt']!=attempt or row['source_generation']!=generation or row['source_audio_epoch']!=row['audio_epoch'] or row['audio_state']!='available' or row['deleted_at']:
                return False
            rid = str(uuid.uuid4())
            self.db.execute('''INSERT INTO transcript_revisions(id,utterance_id,job_id,attempt_id,revision_no,origin,text,created_at)
                VALUES (?,?,?,?,1,'asr_final',?,?)''',(rid,row['utterance_id'],job_id,attempt,text,now()))
            chosen = self.db.execute('SELECT origin FROM transcript_revisions WHERE id=?',(row['preferred_revision_id'],)).fetchone()
            if not chosen or chosen['origin']!='user_edit':
                self.db.execute('UPDATE utterances SET preferred_revision_id=? WHERE id=?',(rid,row['utterance_id']))
            self.db.execute("UPDATE recognition_jobs SET state='completed' WHERE id=?",(job_id,))
            return True

    def bind_target(self, label: str) -> str:
        bid = str(uuid.uuid4())
        with self.transaction():
            self.db.execute('INSERT INTO input_bindings VALUES (?,?,?,?)',(bid,label,'active',now()))
        self.runtime_bindings.add(bid)
        return bid

    def invalidate_binding(self, bid: str) -> None:
        with self.transaction():
            self.db.execute("UPDATE input_bindings SET state='invalidated' WHERE id=?",(bid,))
            self.db.execute("UPDATE insertion_operations SET state='cancelled' WHERE binding_id=? AND state='prepared'",(bid,))
        self.runtime_bindings.discard(bid)

    def reserve_direct(self, bid: str, utterance_id: str, revision_id: str, stable_end: int) -> dict | None:
        """Reserve once before the native side effect. Returning None is no new
        suffix. Changed prefixes pause this binding instead of rewriting a field.
        Caller must also validate the live OS target immediately before delivery.
        """
        if bid not in self.runtime_bindings:
            raise ContractError('binding is expired or belongs to another process')
        conflict = False
        result = None
        with self.transaction():
            binding = self.db.execute('SELECT * FROM input_bindings WHERE id=?',(bid,)).fetchone()
            if not binding or binding['state']!='active':
                raise ContractError('binding needs explicit review/rebind')
            revision = self.db.execute('''SELECT r.*,u.deleted_at FROM transcript_revisions r
                JOIN utterances u ON u.id=r.utterance_id WHERE r.id=? AND r.utterance_id=?''',(revision_id,utterance_id)).fetchone()
            if not revision or revision['deleted_at']:
                raise ContractError('revision is unavailable')
            stable = utf16_prefix(revision['text'],stable_end)
            self.db.execute('INSERT OR IGNORE INTO dispatch_cursors(binding_id,utterance_id) VALUES (?,?)',(bid,utterance_id))
            cursor = self.db.execute('SELECT * FROM dispatch_cursors WHERE binding_id=? AND utterance_id=?',(bid,utterance_id)).fetchone()
            start = cursor['dispatched_utf16_end']
            if stable_end < start or not stable.startswith(cursor['dispatched_prefix']):
                self.db.execute("UPDATE input_bindings SET state='review' WHERE id=?",(bid,))
                conflict = True
            elif stable_end > start:
                suffix = stable[len(cursor['dispatched_prefix']):]
                oid = str(uuid.uuid4())
                self.db.execute('''INSERT INTO insertion_operations(id,utterance_id,revision_id,text_start,text_end,
                    destination_label,state,created_at,dispatched_at,binding_id,operation_kind,text_snapshot)
                    VALUES (?,?,?,?,?,?,'dispatching',?,?,?,'direct',?)''',
                    (oid,utterance_id,revision_id,start,stable_end,binding['destination_label'],now(),now(),bid,suffix))
                self.db.execute('UPDATE dispatch_cursors SET dispatched_utf16_end=?,dispatched_prefix=? WHERE binding_id=? AND utterance_id=?',
                                (stable_end,stable,bid,utterance_id))
                result = {'id':oid,'text':suffix,'start_utf16':start,'end_utf16':stable_end}
        if conflict:
            raise ContractError('stable prefix changed; automatic append paused')
        return result

    def mark_dispatch(self, oid: str, state: str) -> None:
        if state not in ('confirmed','unverified','failed'):
            raise ContractError('invalid outcome')
        with self.transaction():
            changed = self.db.execute("UPDATE insertion_operations SET state=?,completed_at=? WHERE id=? AND state='dispatching'",(state,now(),oid)).rowcount
            if changed != 1:
                raise ContractError('operation already settled or unknown')

    def recover_input(self) -> None:
        with self.transaction():
            self.db.execute("UPDATE insertion_operations SET state='unverified' WHERE state='dispatching'")
            self.db.execute("UPDATE insertion_operations SET state='cancelled' WHERE state='prepared'")
            self.db.execute("UPDATE input_bindings SET state='invalidated' WHERE state!='invalidated'")
        self.runtime_bindings.clear()

    def search(self, query: str) -> list[str]:
        escaped = query.replace('\\','\\\\').replace('%','\\%').replace('_','\\_')
        return [r[0] for r in self.db.execute("""SELECT DISTINCT r.text FROM transcript_revisions r
            JOIN utterances u ON u.id=r.utterance_id WHERE u.deleted_at IS NULL AND r.text LIKE ? ESCAPE '\\'""",('%'+escaped+'%',))]
