-- Always-On Voice: proposed schema, not a production application.
-- All sample ranges are half-open [start, end) within a capture session.
PRAGMA journal_mode=WAL;
PRAGMA synchronous=FULL;
PRAGMA foreign_keys=ON;

CREATE TABLE store_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
INSERT INTO store_meta VALUES ('content_generation', '1');

CREATE TABLE capture_sessions (
  id TEXT PRIMARY KEY,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  device_uid TEXT NOT NULL,
  sample_rate INTEGER NOT NULL CHECK(sample_rate > 0),
  channels INTEGER NOT NULL DEFAULT 1 CHECK(channels = 1),
  encoding TEXT NOT NULL DEFAULT 'pcm_s16le',
  content_generation INTEGER NOT NULL,
  end_reason TEXT
);

CREATE TABLE audio_chunks (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES capture_sessions(id),
  ordinal INTEGER NOT NULL,
  relative_path TEXT NOT NULL UNIQUE,
  first_sample INTEGER NOT NULL CHECK(first_sample >= 0),
  durable_frames INTEGER NOT NULL DEFAULT 0 CHECK(durable_frames >= 0),
  recovered_frames INTEGER NOT NULL DEFAULT 0 CHECK(recovered_frames >= 0),
  final_frames INTEGER,
  state TEXT NOT NULL CHECK(state IN ('writing','sealed','recovered','missing','deleted')),
  integrity_hash TEXT,
  UNIQUE(session_id, ordinal)
);

CREATE TABLE utterances (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES capture_sessions(id),
  group_id TEXT NOT NULL,
  core_start_sample INTEGER NOT NULL,
  core_end_sample INTEGER,
  context_start_sample INTEGER NOT NULL,
  content_generation INTEGER NOT NULL,
  preferred_revision_id TEXT,
  is_pinned INTEGER NOT NULL DEFAULT 0 CHECK(is_pinned IN (0,1)),
  deleted_at TEXT,
  CHECK(context_start_sample <= core_start_sample),
  CHECK(core_end_sample IS NULL OR core_end_sample >= core_start_sample),
  FOREIGN KEY(preferred_revision_id) REFERENCES transcript_revisions(id)
    DEFERRABLE INITIALLY DEFERRED
);

-- A physical chunk contains contiguous frames in exactly one capture session.
-- References are absolute, half-open sample ranges in that same session.
-- Insert/update these only after the referenced range is recoverable; validate
-- the session and chunk bounds in the same application transaction.
CREATE TABLE utterance_audio_refs (
  utterance_id TEXT NOT NULL REFERENCES utterances(id),
  chunk_id TEXT NOT NULL REFERENCES audio_chunks(id),
  role TEXT NOT NULL CHECK(role IN ('core','context')),
  start_sample INTEGER NOT NULL CHECK(start_sample >= 0),
  end_sample INTEGER NOT NULL CHECK(end_sample > start_sample),
  PRIMARY KEY(utterance_id, chunk_id, role, start_sample)
);

-- No foreign keys here: tombstones must survive removal of their source rows.
-- A per-utterance deletion also snapshots its session/range, so recovery can
-- reject an orphan sidecar that knows only generation + session + frame range.
-- For deleting an active utterance, close its deleted range at the capture
-- cursor and begin any subsequent recording as a new utterance.
CREATE TABLE deletion_tombstones (
  id TEXT PRIMARY KEY,
  source_generation INTEGER NOT NULL,
  scope TEXT NOT NULL CHECK(scope IN ('utterance','range','generation')),
  utterance_id TEXT,
  session_id TEXT,
  start_sample INTEGER,
  end_sample INTEGER,
  created_at TEXT NOT NULL,
  physical_cleanup_completed_at TEXT,
  CHECK(
    (scope = 'generation' AND utterance_id IS NULL AND session_id IS NULL
      AND start_sample IS NULL AND end_sample IS NULL)
    OR
    (scope IN ('utterance','range') AND session_id IS NOT NULL
      AND start_sample IS NOT NULL AND end_sample IS NOT NULL
      AND start_sample >= 0 AND end_sample > start_sample
      AND ((scope = 'utterance' AND utterance_id IS NOT NULL)
        OR (scope = 'range' AND utterance_id IS NULL)))
  )
);

-- Commit tombstones + task cancellation before unlinking files. Deleting all
-- advances store_meta.content_generation in that transaction. On recovery,
-- ignore stale generations and subtract tombstoned ranges before importing.
-- Shared chunks require copying surviving PCM ranges to replacement chunks,
-- updating references, then unlinking the old files; deleting one DB reference
-- alone is not physical erasure. Do not clear tombstones before cleanup.

CREATE TABLE recognition_jobs (
  id TEXT PRIMARY KEY,
  utterance_id TEXT NOT NULL REFERENCES utterances(id),
  engine TEXT NOT NULL,
  model_revision TEXT NOT NULL,
  source_generation INTEGER NOT NULL,
  request_revision INTEGER NOT NULL DEFAULT 1,
  lane TEXT NOT NULL DEFAULT 'live' CHECK(lane IN ('live','manual','recovery')),
  active_attempt TEXT,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL CHECK(state IN ('queued','running','completed','retry_wait','paused','cancelled')),
  retry_after TEXT,
  last_error_code TEXT,
  UNIQUE(utterance_id, engine, model_revision, source_generation, request_revision)
);

CREATE TABLE transcript_revisions (
  id TEXT PRIMARY KEY,
  utterance_id TEXT NOT NULL REFERENCES utterances(id),
  job_id TEXT REFERENCES recognition_jobs(id),
  attempt_id TEXT,
  revision_no INTEGER NOT NULL,
  origin TEXT NOT NULL CHECK(origin IN ('asr_partial','asr_final','user_edit','ai_variant')),
  text TEXT NOT NULL,
  audio_start_sample INTEGER,
  audio_end_sample INTEGER,
  stable_until_sample INTEGER,
  base_revision_id TEXT REFERENCES transcript_revisions(id),
  created_at TEXT NOT NULL,
  UNIQUE(utterance_id, job_id, attempt_id, revision_no)
);

CREATE TABLE insertion_operations (
  id TEXT PRIMARY KEY,
  utterance_id TEXT NOT NULL REFERENCES utterances(id),
  revision_id TEXT NOT NULL REFERENCES transcript_revisions(id),
  text_start INTEGER NOT NULL,
  text_end INTEGER NOT NULL,
  destination_app_id TEXT,
  destination_label TEXT,
  state TEXT NOT NULL CHECK(state IN ('prepared','dispatching','confirmed','unverified','failed','cancelled')),
  created_at TEXT NOT NULL,
  dispatched_at TEXT,
  completed_at TEXT,
  -- Retry requires a new explicit operation; dispatching never auto-replays.
  CHECK(text_end >= text_start)
);

CREATE TABLE capture_gaps (
  id INTEGER PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES capture_sessions(id),
  start_sample INTEGER NOT NULL,
  end_sample INTEGER,
  reason TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX utterances_time ON utterances(session_id, core_start_sample);
CREATE INDEX jobs_ready ON recognition_jobs(state, lane, retry_after);
CREATE INDEX chunks_range ON audio_chunks(session_id, first_sample);
CREATE INDEX refs_chunk ON utterance_audio_refs(chunk_id, start_sample, end_sample);
CREATE INDEX tombstones_range ON deletion_tombstones(
  source_generation, session_id, start_sample, end_sample
);

-- insertion_operations.text_start/text_end are UTF-16 offsets into its immutable
-- transcript revision. Validate boundaries before bridging to AX text ranges.
-- Destination labels are diagnostic only; live target bindings expire at exit,
-- mode changes, and rebinding. Prepared operations are not replayed on startup.

-- FTS5 trigram is an optional migration after a runtime capability check.
-- Search strings shorter than 3 Unicode characters use escaped LIKE instead.
-- SQL LIKE/FTS input must be bound; never interpolate user text into SQL.

-- Saytile recovery revision 2 (reconstructed, not the missing Pro originals).
-- Additive design migration; no production database has been modified.
ALTER TABLE utterances ADD COLUMN audio_state TEXT NOT NULL DEFAULT 'available'
  CHECK(audio_state IN ('available','delete_pending','deleted'));
ALTER TABLE utterances ADD COLUMN audio_epoch INTEGER NOT NULL DEFAULT 1;
ALTER TABLE recognition_jobs ADD COLUMN source_audio_epoch INTEGER NOT NULL DEFAULT 1;

-- These intents are separate from record/content-generation tombstones.
-- No FK to utterances: deletion intent must outlive its source row.
CREATE TABLE audio_erasure_intents (
  id TEXT PRIMARY KEY,
  utterance_id TEXT NOT NULL UNIQUE,
  source_generation INTEGER NOT NULL,
  reason TEXT NOT NULL CHECK(reason IN ('user','retention')),
  state TEXT NOT NULL CHECK(state IN ('pending','complete')),
  created_at TEXT NOT NULL,
  completed_at TEXT
);
CREATE TABLE audio_erasure_ranges (
  intent_id TEXT NOT NULL REFERENCES audio_erasure_intents(id),
  session_id TEXT NOT NULL,
  start_sample INTEGER NOT NULL CHECK(start_sample >= 0),
  end_sample INTEGER NOT NULL CHECK(end_sample > start_sample),
  PRIMARY KEY(intent_id,session_id,start_sample,end_sample)
);
CREATE TABLE audio_erasure_chunks (
  intent_id TEXT NOT NULL REFERENCES audio_erasure_intents(id),
  chunk_id TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'pending'
    CHECK(state IN ('pending','shared_deferred','leased','complete')),
  PRIMARY KEY(intent_id,chunk_id)
);
CREATE TABLE audio_leases (
  id TEXT PRIMARY KEY,
  chunk_id TEXT NOT NULL REFERENCES audio_chunks(id),
  owner TEXT NOT NULL
);

-- Persisted audit labels never reconstruct an OS input target after restart.
CREATE TABLE input_bindings (
  id TEXT PRIMARY KEY,
  destination_label TEXT NOT NULL,
  state TEXT NOT NULL CHECK(state IN ('active','review','invalidated')),
  created_at TEXT NOT NULL
);
CREATE TABLE dispatch_cursors (
  binding_id TEXT NOT NULL REFERENCES input_bindings(id),
  utterance_id TEXT NOT NULL REFERENCES utterances(id),
  dispatched_utf16_end INTEGER NOT NULL DEFAULT 0 CHECK(dispatched_utf16_end >= 0),
  dispatched_prefix TEXT NOT NULL DEFAULT '',
  PRIMARY KEY(binding_id,utterance_id)
);
ALTER TABLE insertion_operations ADD COLUMN binding_id TEXT REFERENCES input_bindings(id);
ALTER TABLE insertion_operations ADD COLUMN operation_kind TEXT NOT NULL DEFAULT 'manual'
  CHECK(operation_kind IN ('manual','direct'));
ALTER TABLE insertion_operations ADD COLUMN text_snapshot TEXT;
CREATE UNIQUE INDEX direct_range_unique ON insertion_operations(
  binding_id,utterance_id,text_start,text_end
) WHERE operation_kind='direct';
CREATE TRIGGER direct_dispatch_no_overlap BEFORE INSERT ON insertion_operations
WHEN NEW.operation_kind='direct' AND EXISTS (
  SELECT 1 FROM insertion_operations i
  WHERE i.operation_kind='direct' AND i.binding_id=NEW.binding_id
    AND i.utterance_id=NEW.utterance_id
    AND NEW.text_start < i.text_end AND i.text_start < NEW.text_end
)
BEGIN SELECT RAISE(ABORT,'direct dispatch overlaps prior reservation'); END;
CREATE TRIGGER dispatch_cursor_no_rewind BEFORE UPDATE OF dispatched_utf16_end ON dispatch_cursors
WHEN NEW.dispatched_utf16_end < OLD.dispatched_utf16_end
BEGIN SELECT RAISE(ABORT,'dispatch cursor cannot rewind'); END;
CREATE TRIGGER immutable_referenced_text BEFORE UPDATE OF text ON transcript_revisions
WHEN OLD.origin IN ('asr_final','user_edit','ai_variant') OR EXISTS (
 SELECT 1 FROM insertion_operations WHERE revision_id=OLD.id
)
BEGIN SELECT RAISE(ABORT,'create a new transcript revision instead'); END;
CREATE INDEX erasures_range ON audio_erasure_ranges(session_id,start_sample,end_sample);
PRAGMA user_version=2;
