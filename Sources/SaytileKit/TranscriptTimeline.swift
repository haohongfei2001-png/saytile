import Foundation

public struct TimelineEntry: Identifiable, Equatable, Sendable {
    public var id: UUID { recording.id }
    public let recording: Recording
    public let position: Int64
    public let group: Int64
    public let groupStart: Date
    public let groupDay: String
    public let groupUTCOffset: Int
    public let speechEnd: Date
    public let paragraphID: Int64
    public let paragraphStart: Date
    public let paragraphBreakHidden: Bool
    public private(set) var preferredOrigin: RevisionOrigin? = nil
}

public struct TimelineTextSnapshot: Equatable, Sendable {
    public let position: Int64
    public let recordingID: UUID
    public let revisionID: UUID?
    public let text: String

    public init(_ entry: TimelineEntry) {
        self.init(position: entry.position, recordingID: entry.id, revisionID: entry.recording.preferredRevisionID, text: entry.recording.text)
    }
    fileprivate init(position: Int64, recordingID: UUID, revisionID: UUID?, text: String) {
        self.position = position
        self.recordingID = recordingID
        self.revisionID = revisionID
        self.text = text
    }
}

public enum TimelineWindow: Equatable, Sendable {
    case latest, ending(at: Int64), starting(at: Int64)
}

public struct TimelinePage: Equatable, Sendable {
    public static let capacity = 64
    public var entries: [TimelineEntry] = []
    public var hasOlder = false
    public var hasNewer = false
    public init() {}
}

/// One natural paragraph may own many independently saved ASR recordings.
/// The first capture position remains its identity even if that recording is erased.
public struct TimelineParagraph: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let firstRecordingID: UUID
    public let started: Date
    public let group: Int64
    public let groupStart: Date
    public let groupDay: String
    public let groupUTCOffset: Int
    public let firstPosition: Int64
    public let lastPosition: Int64
    public let memberCount: Int
    public let isPinned: Bool
    public let hasAudio: Bool
}

public struct TimelineParagraphPage: Equatable, Sendable {
    public var paragraphs: [TimelineParagraph] = []
    public var hasOlder = false
    public var hasNewer = false
    public init() {}
}

/// The UI owns a small, independent writer so the next AppKit key can use
/// committed row identities. Closing the store revokes it before releasing
/// the process lock, including when a second process opens the same library.
final class PanelEditConnection: @unchecked Sendable {
    private let lock = NSLock()
    private var database: StoreDatabase?
    private var closed = false

    func use<T>(at url: URL, _ body: (StoreDatabase) throws -> T) throws -> T {
        try lock.withLock {
            guard !closed else { throw StoreError.database("资料库已关闭。") }
            if database == nil {
                let writer = try StoreDatabase(url: url)
                try writer.configureForWriting()
                database = writer
            }
            guard let database else { throw StoreError.database("无法打开文字编辑资料库。") }
            return try body(database)
        }
    }

    func close() throws {
        try lock.withLock {
            closed = true
            try database?.close()
            database = nil
        }
    }
}

extension SaytileStore {
    // Positions follow capture order even after the wall clock moves backwards.
    // A group keeps its first utterance's civil date and offset for its lifetime.
    static let timelineSchema = """
    CREATE TABLE IF NOT EXISTS timeline_settings(singleton INTEGER PRIMARY KEY CHECK(singleton=1),idle_seconds INTEGER NOT NULL CHECK(idle_seconds BETWEEN 10 AND 3600));
    INSERT OR IGNORE INTO timeline_settings VALUES(1,60);
    CREATE TABLE IF NOT EXISTS transcript_timeline(
      position INTEGER PRIMARY KEY AUTOINCREMENT, recording_id TEXT UNIQUE REFERENCES recordings(id) ON DELETE SET NULL,
      started REAL NOT NULL, ended REAL, day TEXT NOT NULL, utc_offset INTEGER NOT NULL, group_start INTEGER NOT NULL DEFAULT 0);
    CREATE INDEX IF NOT EXISTS timeline_by_group ON transcript_timeline(group_start,position);
    CREATE TRIGGER IF NOT EXISTS timeline_group AFTER INSERT ON transcript_timeline BEGIN
      UPDATE transcript_timeline SET group_start=COALESCE((
        SELECT CASE WHEN prior.day=NEW.day AND NEW.started>=prior.started
          AND NEW.started-COALESCE(prior.ended,prior.started+r.total_frames/r.sample_rate)<s.idle_seconds
          THEN prior.group_start END
        FROM transcript_timeline prior JOIN recordings r ON r.id=prior.recording_id
        JOIN timeline_settings s ON s.singleton=1
        WHERE prior.position<NEW.position ORDER BY prior.position DESC LIMIT 1),NEW.position)
      WHERE position=NEW.position;
    END;
    -- SQLite rounds fractional dates to milliseconds. Classify the containing
    -- whole second before asking for the local day or UTC offset.
    DROP TRIGGER IF EXISTS timeline_record;
    CREATE TRIGGER IF NOT EXISTS timeline_record_civil_second AFTER INSERT ON recordings BEGIN
      INSERT INTO transcript_timeline(recording_id,started,day,utc_offset)
      VALUES(NEW.id,NEW.created_at,date(floor(NEW.created_at),'unixepoch','localtime'),
        unixepoch(datetime(floor(NEW.created_at),'unixepoch','localtime'))-CAST(floor(NEW.created_at) AS INTEGER));
    END;
    """
    static let timelineBackfill = """
    INSERT INTO transcript_timeline(recording_id,started,day,utc_offset)
    SELECT id,created_at,date(floor(created_at),'unixepoch','localtime'),
      unixepoch(datetime(floor(created_at),'unixepoch','localtime'))-CAST(floor(created_at) AS INTEGER)
    FROM recordings r WHERE NOT EXISTS(SELECT 1 FROM transcript_timeline t WHERE t.recording_id=r.id)
    ORDER BY created_at,rowid;
    """

    /// Additive schema-6 metadata. Old apps can still open the same archive; the
    /// recording, version, audio and existing time-group identities never change.
    static func installParagraphSchema(in db: StoreDatabase) throws {
        try db.script("""
            CREATE TABLE IF NOT EXISTS natural_paragraph_schema(singleton INTEGER PRIMARY KEY CHECK(singleton=1),version INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS timeline_paragraphs(
              position INTEGER PRIMARY KEY REFERENCES transcript_timeline(position) ON DELETE CASCADE,
              paragraph_start INTEGER NOT NULL,break_hidden INTEGER NOT NULL DEFAULT 0 CHECK(break_hidden IN(0,1)));
            CREATE INDEX IF NOT EXISTS paragraph_members ON timeline_paragraphs(paragraph_start,position);
            """)
        let version = try db.rows("SELECT version FROM natural_paragraph_schema WHERE singleton=1").first?["version"]
        guard version == nil || version == "1" || version == "2" else { throw StoreError.database("自然段资料来自更新版本，请升级 Saytile。") }
        if try !db.rows("PRAGMA table_info(timeline_paragraphs)").contains(where: { $0["name"] == "break_hidden" }) {
            try db.execute("ALTER TABLE timeline_paragraphs ADD COLUMN break_hidden INTEGER NOT NULL DEFAULT 0 CHECK(break_hidden IN(0,1))")
        }
        if version == nil {
            // 120 was the previous shipped default. Preserve other explicit
            // intervals of at least a minute, and leave historical group_start alone.
            try db.execute("UPDATE timeline_settings SET idle_seconds=60 WHERE idle_seconds=120 OR idle_seconds<60")
        }
        // Window functions find boundaries from capture times, never ASR arrival.
        // Fill only missing metadata so edits, deletion and restart cannot regroup
        // a previously displayed paragraph. Tombstones retain their positions.
        let needsBackfill = try !db.rows("""
            SELECT 1 FROM transcript_timeline t LEFT JOIN timeline_paragraphs p ON p.position=t.position
            WHERE t.recording_id IS NOT NULL AND p.position IS NULL LIMIT 1
            """).isEmpty
        if needsBackfill {
            try db.script("""
                WITH ordered AS (
                  SELECT t.position,t.started,t.day,t.utc_offset,t.group_start,
                    lag(t.started) OVER w AS prior_start,lag(t.day) OVER w AS prior_day,
                    lag(t.utc_offset) OVER w AS prior_offset,lag(t.group_start) OVER w AS prior_group,
                    lag(COALESCE(t.ended,t.started+r.total_frames/r.sample_rate)) OVER w AS prior_end
                  FROM transcript_timeline t JOIN recordings r ON r.id=t.recording_id
                  WINDOW w AS (ORDER BY t.position)
                ), boundaries AS (
                  SELECT position,CASE WHEN prior_day=day AND prior_offset=utc_offset AND prior_group=group_start
                    AND started>=prior_start AND started-prior_end<15 THEN NULL ELSE position END AS boundary FROM ordered
                ), mapped AS (
                  SELECT position,max(boundary) OVER (ORDER BY position ROWS UNBOUNDED PRECEDING) AS paragraph_start FROM boundaries
                )
                INSERT OR IGNORE INTO timeline_paragraphs(position,paragraph_start) SELECT position,paragraph_start FROM mapped;
                """)
        }
        try db.script("""
            CREATE TRIGGER IF NOT EXISTS timeline_natural_paragraph AFTER INSERT ON transcript_timeline
            WHEN NEW.recording_id IS NOT NULL BEGIN
              INSERT INTO timeline_paragraphs(position,paragraph_start)
              VALUES(NEW.position,COALESCE((
                SELECT CASE WHEN prior.day=NEW.day AND prior.utc_offset=NEW.utc_offset AND NEW.started>=prior.started
                  AND NEW.started-COALESCE(prior.ended,prior.started+r.total_frames/r.sample_rate)<min(15,s.idle_seconds)
                  THEN p.paragraph_start END
                FROM transcript_timeline prior JOIN recordings r ON r.id=prior.recording_id
                JOIN timeline_paragraphs p ON p.position=prior.position JOIN timeline_settings s ON s.singleton=1
                WHERE prior.position<NEW.position ORDER BY prior.position DESC LIMIT 1),NEW.position));
              UPDATE recordings SET pinned=1 WHERE id=NEW.recording_id AND EXISTS(
                SELECT 1 FROM timeline_paragraphs p JOIN transcript_timeline t ON t.position=p.position
                JOIN recordings r ON r.id=t.recording_id
                WHERE p.paragraph_start=(SELECT paragraph_start FROM timeline_paragraphs WHERE position=NEW.position)
                  AND p.position<NEW.position AND r.deleted=0 AND r.pinned=1);
            END;
            INSERT INTO natural_paragraph_schema VALUES(1,2) ON CONFLICT(singleton) DO UPDATE SET version=2;
            """)
    }

    public func setTimelineIdleSeconds(_ seconds: Int) throws {
        guard (60...3600).contains(seconds) else { throw StoreError.database("时间间隔须在 1 分钟至 1 小时之间。") }
        try db.execute("UPDATE timeline_settings SET idle_seconds=? WHERE singleton=1", [.int(Int64(seconds))])
    }
    public func timelinePosition(of id: UUID) throws -> Int64? {
        try db.rows("SELECT position FROM transcript_timeline WHERE recording_id=?", [.text(id.uuidString)]).first?["position"].flatMap(Int64.init)
    }
    public func timelinePage(_ window: TimelineWindow = .latest) throws -> TimelinePage {
        try Self.timelinePage(window, from: db)
    }

    /// Page from the newest captures, even when one session spans several pages. A search result,
    /// bookmark, or page beginning mid-group retains its first utterance's civil time.
    public func archiveEntries(query: String = "", filter: RecordingFilter = .transcribed,
                               limit: Int = 100, editingID: UUID? = nil) throws -> [TimelineEntry] {
        let (predicate, values) = Self.archivePredicate(query: query, filter: filter, editingID: editingID)
        return try db.rows(Self.timelineSelection + " AND " + predicate + " ORDER BY t.position DESC LIMIT ?",
                           values + [.int(Int64(max(1, limit)))]).map(Self.decodeTimelineEntry)
    }

    /// Select paragraphs first, then expose their complete membership. A match in
    /// an old revision, draft, or one starred fragment must not truncate the text.
    public func archiveParagraphPage(_ window: TimelineWindow = .latest, query: String = "",
                                     filter: RecordingFilter = .transcribed, limit: Int = 32,
                                     editingID: Int64? = nil) throws -> TimelineParagraphPage {
        var (match, values) = Self.archivePredicate(query: query, filter: filter)
        if let editingID {
            let (keep, _) = Self.archivePredicate(query: "", filter: filter == .transcribed ? .all : filter)
            match = "((" + match + ") OR (p.paragraph_start=? AND " + keep + "))"
            values.append(.int(editingID))
        }
        let from = " FROM timeline_paragraphs p JOIN transcript_timeline t ON t.position=p.position JOIN recordings r ON r.id=t.recording_id LEFT JOIN revisions v ON v.id=r.preferred_revision WHERE r.deleted=0 AND (" + match + ")"
        let direction: String, predicate: String, windowValues: [StoreDatabase.Value]
        switch window {
        case .latest: direction = "DESC"; predicate = ""; windowValues = []
        case .ending(let key): direction = "DESC"; predicate = " AND p.paragraph_start<=?"; windowValues = [.int(key)]
        case .starting(let key): direction = "ASC"; predicate = " AND p.paragraph_start>=?"; windowValues = [.int(key)]
        }
        let keys = try db.rows("SELECT DISTINCT p.paragraph_start" + from + predicate + " ORDER BY p.paragraph_start " + direction + " LIMIT ?",
                              values + windowValues + [.int(Int64(max(1, min(128, limit))))]).compactMap { $0["paragraph_start"].flatMap(Int64.init) }
        guard !keys.isEmpty else { return TimelineParagraphPage() }
        let marks = Array(repeating: "?", count: keys.count).joined(separator: ",")
        let rows = try db.rows("""
            WITH selected AS (
              SELECT p.paragraph_start,min(t.position) AS first_position,max(t.position) AS last_position,
                     count(*) AS member_count,max(r.pinned) AS pinned,
                     max(CASE WHEN r.audio_state='available' AND r.total_frames>0 THEN 1 ELSE 0 END) AS has_audio
              FROM timeline_paragraphs p JOIN transcript_timeline t ON t.position=p.position
              JOIN recordings r ON r.id=t.recording_id WHERE r.deleted=0 AND p.paragraph_start IN(\(marks))
              GROUP BY p.paragraph_start
            )
            SELECT s.*,COALESCE(a.recording_id,f.recording_id) AS first_id,a.started,a.group_start,g.started AS group_date,g.day,g.utc_offset
            FROM selected s JOIN transcript_timeline f ON f.position=s.first_position
            JOIN transcript_timeline a ON a.position=s.paragraph_start JOIN transcript_timeline g ON g.position=a.group_start
            ORDER BY s.paragraph_start
            """, keys.map { .int($0) })
        var page = TimelineParagraphPage()
        page.paragraphs = try rows.map { row in
            guard let id = row["paragraph_start"].flatMap(Int64.init), let first = row["first_id"].flatMap(UUID.init(uuidString:)),
                  let started = row["started"].flatMap(Double.init), let group = row["group_start"].flatMap(Int64.init),
                  let groupDate = row["group_date"].flatMap(Double.init), let day = row["day"], let offset = row["utc_offset"].flatMap(Int.init),
                  let begin = row["first_position"].flatMap(Int64.init), let end = row["last_position"].flatMap(Int64.init),
                  let count = row["member_count"].flatMap(Int.init) else { throw StoreError.database("无法读取自然段。") }
            return TimelineParagraph(id: id, firstRecordingID: first, started: Date(timeIntervalSince1970: started),
                group: group, groupStart: Date(timeIntervalSince1970: groupDate), groupDay: day, groupUTCOffset: offset,
                firstPosition: begin, lastPosition: end, memberCount: count, isPinned: row["pinned"] == "1", hasAudio: row["has_audio"] == "1")
        }
        if let first = page.paragraphs.first, let last = page.paragraphs.last {
            page.hasOlder = try !db.rows("SELECT 1" + from + " AND p.paragraph_start<? LIMIT 1", values + [.int(first.id)]).isEmpty
            page.hasNewer = try !db.rows("SELECT 1" + from + " AND p.paragraph_start>? LIMIT 1", values + [.int(last.id)]).isEmpty
        }
        return page
    }

    public func paragraphMembers(paragraphID: Int64, _ window: TimelineWindow = .starting(at: 0),
                                 limit: Int = TimelinePage.capacity) throws -> TimelinePage {
        try Self.timelinePage(window, from: db, limit: max(1, min(256, limit)), paragraphID: paragraphID)
    }

    /// IDs alone are cheap even for a long uninterrupted paragraph. The player
    /// keeps audio leases tied to each original recording and releases them on stop.
    public func paragraphRecordingIDs(paragraphID: Int64) throws -> [UUID] {
        try db.rows("""
            SELECT t.recording_id FROM timeline_paragraphs p JOIN transcript_timeline t ON t.position=p.position
            JOIN recordings r ON r.id=t.recording_id WHERE p.paragraph_start=? AND r.deleted=0 ORDER BY t.position
            """, [.int(paragraphID)]).compactMap { $0["recording_id"].flatMap(UUID.init(uuidString:)) }
    }

    /// Existing partial stars mean the paragraph is already starred; one click
    /// clears the entire paragraph, not just its currently loaded member page.
    @discardableResult public func toggleParagraphPinned(paragraphID: Int64) throws -> Bool {
        try db.transaction {
            let members = "SELECT t.recording_id FROM timeline_paragraphs p JOIN transcript_timeline t ON t.position=p.position WHERE p.paragraph_start=?"
            let rows = try db.rows("SELECT max(pinned) AS pinned,count(*) AS n FROM recordings WHERE deleted=0 AND id IN(" + members + ")", [.int(paragraphID)])
            guard let row = rows.first, row["n"] != "0" else { throw StoreError.missingRecording }
            let pinned = row["pinned"] != "1"
            try db.execute("UPDATE recordings SET pinned=? WHERE deleted=0 AND id IN(" + members + ")", [.int(pinned ? 1 : 0), .int(paragraphID)])
            return pinned
        }
    }

    /// Each edited UTF-16 span retains its original recording owner. Validate all
    /// membership and human baseline before writing any revision. An ASR update
    /// cannot veto an explicit edit to the text the person saw; a newer human edit
    /// or wrong paragraph rolls the whole keystroke back without losing versions.
    @MainActor public func editArchiveParagraph(id: Int64, edits: [PanelRowEdit]) throws -> [TimelineEntry] {
        try panelEditor.use(at: directory.appendingPathComponent("Saytile.sqlite")) { writer in
            try writer.transaction {
                guard Set(edits.map(\.id)).count == edits.count else { throw StoreError.invalidBoundary }
                for edit in edits {
                    guard let before = edit.before,
                          let row = try writer.rows(Self.timelineSelection + " AND p.paragraph_start=? AND r.id=?",
                                                    [.int(id), .text(edit.id.uuidString)]).first else { throw StoreError.missingRecording }
                    if row["preferred_origin"] == RevisionOrigin.userEdit.rawValue,
                       !(row["text"] ?? "").utf16.elementsEqual(before.utf16) {
                        throw StoreError.database("这段文字已在另一处修改，请重新选择要编辑的文字。")
                    }
                }
                try Self.writePanelEdits(edits, to: writer, at: .now)
                return try edits.map { edit in
                    guard let row = try writer.rows(Self.timelineSelection + " AND r.id=?", [.text(edit.id.uuidString)]).first else { throw StoreError.missingRecording }
                    return try Self.decodeTimelineEntry(row)
                }.sorted { $0.position < $1.position }
            }
        }
    }

    /// Preserve a failed explicit edit without selecting it over another human
    /// revision. A different pre-existing draft becomes an immutable, unselected
    /// user version before its draft slot is reused; neither text is discarded.
    @MainActor public func preserveArchiveParagraphDraft(id: Int64, edits: [PanelRowEdit], bases: [UUID: UUID]) throws {
        try panelEditor.use(at: directory.appendingPathComponent("Saytile.sqlite")) { writer in
            try writer.transaction {
                guard Set(edits.map(\.id)).count == edits.count else { throw StoreError.invalidBoundary }
                for edit in edits {
                    guard edit.before != nil,
                          try writer.rows(Self.timelineSelection + " AND p.paragraph_start=? AND r.id=?", [.int(id), .text(edit.id.uuidString)]).first != nil
                    else { throw StoreError.missingRecording }
                    if let base = bases[edit.id], let owner = try writer.rows("SELECT recording_id FROM revisions WHERE id=?", [.text(base.uuidString)]).first?["recording_id"],
                       owner != edit.id.uuidString { throw StoreError.missingRevision }
                }
                for edit in edits {
                    let key = StoreDatabase.Value.text(edit.id.uuidString)
                    if let draft = try writer.rows("""
                        SELECT d.text,d.updated_at,b.revision_id FROM editing_drafts d
                        LEFT JOIN archive_draft_bases b USING(recording_id) WHERE d.recording_id=?
                        """, [key]).first, let previous = draft["text"], !previous.utf16.elementsEqual(edit.after.utf16) {
                        let oldBase = draft["revision_id"].map(StoreDatabase.Value.text) ?? .null
                        let retained = try writer.rows("SELECT 1 FROM revisions WHERE recording_id=? AND origin='userEdit' AND text=? AND base_revision IS ? LIMIT 1",
                                                       [key, .text(previous), oldBase])
                        if retained.isEmpty {
                            try writer.execute("INSERT INTO revisions(id,recording_id,text,origin,created_at,base_revision) VALUES(?,?,?,'userEdit',?,?)",
                                               [.text(UUID().uuidString), key, .text(previous), .double(draft["updated_at"].flatMap(Double.init) ?? Date().timeIntervalSince1970), oldBase])
                        }
                    }
                    try Self.persistArchiveDraft(edit.after, id: edit.id, base: bases[edit.id], updateBase: true, in: writer)
                }
            }
        }
    }

    /// A newly arriving transcript may push a focused paragraph just outside the
    /// current page. Read that one owner without widening the page to the whole library.
    public func archiveEntryForEditing(_ id: UUID, filter: RecordingFilter) throws -> TimelineEntry? {
        let (predicate, values) = Self.archivePredicate(query: "", filter: filter, editingID: id)
        return try db.rows(Self.timelineSelection + " AND t.recording_id=? AND " + predicate,
                           [.text(id.uuidString)] + values).first.map(Self.decodeTimelineEntry)
    }

    /// The next NSTextView keystroke needs the committed version synchronously,
    /// including edits to records far outside the board's loaded timeline.
    @MainActor public func editArchiveParagraph(id: UUID, before: String, after: String) throws -> Recording {
        try panelEditor.use(at: directory.appendingPathComponent("Saytile.sqlite")) { writer in
            try writer.transaction {
                _ = try Self.writePanelEdits([PanelRowEdit(id: id, before: before, after: after)], to: writer, at: .now)
                guard let updated = try writer.rows(Self.selection + " WHERE r.id=? AND r.deleted=0", [.text(id.uuidString)]).first else {
                    throw StoreError.missingRecording
                }
                return try Self.decodeRecording(updated)
            }
        }
    }

    /// The scrollable board pages through text. Audio-only recordings remain
    /// available in the archive and the actual capture tail is returned separately.
    public func panelTimeline(_ window: TimelineWindow) throws -> (page: TimelinePage, tail: TimelineEntry?, textTail: TimelineEntry?) {
        try Self.panelTimeline(window, from: db)
    }

    /// NSTextView needs the new row spans before it can accept the next key.
    /// Read the exact committed page and tail in the same bounded transaction.
    @MainActor public func editTimeline(_ edits: [PanelRowEdit], window: TimelineWindow) throws -> (page: TimelinePage, tail: TimelineEntry?, textTail: TimelineEntry?) {
        try panelEditor.use(at: directory.appendingPathComponent("Saytile.sqlite")) { writer in
            try writer.transaction {
                try Self.writePanelEdits(edits, to: writer, at: .now)
                return try Self.panelTimeline(window, from: writer)
            }
        }
    }

    private static func panelTimeline(_ window: TimelineWindow, from db: StoreDatabase) throws -> (page: TimelinePage, tail: TimelineEntry?, textTail: TimelineEntry?) {
        let page = try timelinePage(window, from: db, textOnly: true)
        let tail = try timelinePage(.latest, from: db, limit: 1).entries.last
        // The capture tail may belong to a new group that has not produced text yet.
        // Reuse the displayed page unless the reader is paging through older text.
        let textTail: TimelineEntry?
        if !page.hasNewer && (window == .latest || !page.entries.isEmpty),
           let lastText = page.entries.last(where: { !$0.recording.text.isEmpty }) {
            textTail = lastText
        } else if let tail, !tail.recording.text.isEmpty {
            textTail = tail
        } else {
            textTail = try timelinePage(.latest, from: db, textOnly: true, limit: 1).entries.last
        }
        return (page, tail, textTail)
    }

    private static func timelinePage(_ window: TimelineWindow, from db: StoreDatabase,
                                     textOnly: Bool = false, limit: Int = TimelinePage.capacity,
                                     paragraphID: Int64? = nil) throws -> TimelinePage {
        let direction: String, predicate: String, values: [StoreDatabase.Value]
        switch window {
        case .latest: direction = "DESC"; predicate = ""; values = []
        case .ending(let key): direction = "DESC"; predicate = " AND t.position<=?"; values = [.int(key)]
        case .starting(let key): direction = "ASC"; predicate = " AND t.position>=?"; values = [.int(key)]
        }
        let textPredicate = textOnly ? " AND v.text<>''" : ""
        let paragraphPredicate = paragraphID == nil ? "" : " AND p.paragraph_start=?"
        let paragraphValues: [StoreDatabase.Value] = paragraphID.map { [.int($0)] } ?? []
        let rows = try db.rows(timelineSelection + textPredicate + paragraphPredicate + predicate + " ORDER BY t.position " + direction + " LIMIT ?",
                               paragraphValues + values + [.int(Int64(limit))])
        var page = TimelinePage()
        page.entries = try rows.map(decodeTimelineEntry)
        if direction == "DESC" { page.entries.reverse() }
        if limit == 1 && paragraphID == nil { return page } // Tail lookup does not need navigation flags.
        let versionJoin = textOnly ? " JOIN revisions v ON v.id=r.preferred_revision" : ""
        let neighbors = "SELECT 1 FROM transcript_timeline t CROSS JOIN recordings r ON r.id=t.recording_id JOIN timeline_paragraphs p ON p.position=t.position" +
            versionJoin + " WHERE r.deleted=0" + textPredicate + paragraphPredicate + " AND t.position"
        if let first = page.entries.first, let last = page.entries.last {
            page.hasOlder = try !db.rows(neighbors + "<? ORDER BY t.position DESC LIMIT 1", paragraphValues + [.int(first.position)]).isEmpty
            page.hasNewer = try !db.rows(neighbors + ">? ORDER BY t.position LIMIT 1", paragraphValues + [.int(last.position)]).isEmpty
        }
        return page
    }

    private static let timelineSelection = """
        SELECT r.*,v.text,v.origin AS preferred_origin,t.position,t.group_start,g.started AS group_date,g.day,g.utc_offset,
               p.paragraph_start,a.started AS paragraph_date,ph.break_hidden,
               COALESCE(t.ended,t.started+r.total_frames/r.sample_rate) AS speech_end
        FROM transcript_timeline t CROSS JOIN recordings r ON r.id=t.recording_id
        JOIN transcript_timeline g ON g.position=t.group_start JOIN timeline_paragraphs p ON p.position=t.position
        JOIN transcript_timeline a ON a.position=p.paragraph_start
        JOIN timeline_paragraphs ph ON ph.position=p.paragraph_start LEFT JOIN revisions v ON v.id=r.preferred_revision
        WHERE r.deleted=0
        """

    private static func decodeTimelineEntry(_ row: [String: String]) throws -> TimelineEntry {
        guard let position = row["position"].flatMap(Int64.init), let group = row["group_start"].flatMap(Int64.init),
                  let first = row["group_date"].flatMap(Double.init), let day = row["day"],
                  let offset = row["utc_offset"].flatMap(Int.init), let end = row["speech_end"].flatMap(Double.init),
                  let paragraph = row["paragraph_start"].flatMap(Int64.init), let paragraphDate = row["paragraph_date"].flatMap(Double.init) else {
            throw StoreError.database("无法读取时间轴位置。")
        }
        return TimelineEntry(recording: try Self.decodeRecording(row), position: position, group: group,
                groupStart: Date(timeIntervalSince1970: first), groupDay: day, groupUTCOffset: offset, speechEnd: Date(timeIntervalSince1970: end),
                paragraphID: paragraph, paragraphStart: Date(timeIntervalSince1970: paragraphDate), paragraphBreakHidden: row["break_hidden"] == "1",
                preferredOrigin: row["preferred_origin"].flatMap(RevisionOrigin.init(rawValue:)))
    }

    /// Snapshot the group selected at the click, including segments outside the
    /// current TextKit page. Reading another group never expands this range.
    private nonisolated func timelineGroupRows(group: Int64, through last: Int64, after cleared: Int64 = 0) throws -> [[String: String]] {
        let reader = try StoreDatabase(url: directory.appendingPathComponent("Saytile.sqlite"), readOnly: true)
        return try reader.rows("""
            SELECT t.position,r.id,r.preferred_revision,v.text,v.origin,p.paragraph_start,ph.break_hidden FROM transcript_timeline t CROSS JOIN recordings r ON r.id=t.recording_id
            JOIN timeline_paragraphs p ON p.position=t.position JOIN timeline_paragraphs ph ON ph.position=p.paragraph_start LEFT JOIN revisions v ON v.id=r.preferred_revision
            WHERE t.group_start=? AND t.position<=? AND t.position>? AND r.deleted=0 ORDER BY t.position
            """, [.int(group), .int(last), .int(cleared)])
    }

    public nonisolated func timelineGroupSnapshots(group: Int64, through last: Int64) throws -> [TimelineTextSnapshot] {
        try timelineGroupRows(group: group, through: last).map { row in
            guard let position = row["position"].flatMap(Int64.init), let id = row["id"].flatMap(UUID.init(uuidString:)) else {
                throw StoreError.database("无法读取时间轴位置。")
            }
            return TimelineTextSnapshot(position: position, recordingID: id,
                revisionID: row["preferred_revision"].flatMap(UUID.init(uuidString:)), text: row["text"] ?? "")
        }
    }

    /// Already rendered text wins over a newer revision not yet drawn.
    public nonisolated func timelineCopy(group: Int64, through last: Int64, after cleared: Int64 = 0, displayed: [Int64:String]) throws -> String {
        try Self.formatParagraphText(timelineGroupRows(group: group, through: last, after: cleared), displayed: displayed)
    }

    /// A single SQLite statement supplies a consistent whole-paragraph copy even
    /// when its member text spans more than one UI page. Never changes pasteboard later.
    public nonisolated func paragraphCopy(paragraphID: Int64, displayed: [Int64: String]) throws -> String {
        let reader = try StoreDatabase(url: directory.appendingPathComponent("Saytile.sqlite"), readOnly: true)
        let rows = try reader.rows("""
            SELECT t.position,v.text,v.origin,p.paragraph_start,ph.break_hidden FROM timeline_paragraphs p
            JOIN timeline_paragraphs ph ON ph.position=p.paragraph_start
            JOIN transcript_timeline t ON t.position=p.position JOIN recordings r ON r.id=t.recording_id
            LEFT JOIN revisions v ON v.id=r.preferred_revision
            WHERE p.paragraph_start=? AND r.deleted=0 ORDER BY t.position
            """, [.int(paragraphID)])
        return try Self.formatParagraphText(rows, displayed: displayed)
    }

    private nonisolated static func formatParagraphText(_ rows: [[String: String]], displayed: [Int64: String]) throws -> String {
        var result = "", preceding: String?, previousParagraph: Int64?, pendingBreak = false
        for row in rows {
            guard let paragraph = row["paragraph_start"].flatMap(Int64.init) else { throw StoreError.invalidBoundary }
            let text = row["position"].flatMap(Int64.init).flatMap { displayed[$0] } ?? row["text"] ?? ""
            if let previousParagraph, previousParagraph != paragraph { pendingBreak = row["break_hidden"] != "1" }
            else if row["break_hidden"] == "1" { pendingBreak = false }
            previousParagraph = paragraph
            guard !text.isEmpty else { continue }
            if let preceding {
                if pendingBreak && !(preceding.unicodeScalars.last.map(CharacterSet.newlines.contains) ?? false) && !(text.unicodeScalars.first.map(CharacterSet.newlines.contains) ?? false) { result += "\n" }
                else { result += VoiceTranscriptFlow.separator(between: preceding, and: text) }
            }
            result += text; preceding = text; pendingBreak = false
        }
        return result
    }
}
