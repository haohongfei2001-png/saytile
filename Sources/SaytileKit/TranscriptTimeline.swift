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
    INSERT OR IGNORE INTO timeline_settings VALUES(1,120);
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

    public func setTimelineIdleSeconds(_ seconds: Int) throws {
        guard (10...3600).contains(seconds) else { throw StoreError.database("时间间隔须在 10 秒至 1 小时之间。") }
        try db.execute("UPDATE timeline_settings SET idle_seconds=? WHERE singleton=1", [.int(Int64(seconds))])
    }
    public func timelinePosition(of id: UUID) throws -> Int64? {
        try db.rows("SELECT position FROM transcript_timeline WHERE recording_id=?", [.text(id.uuidString)]).first?["position"].flatMap(Int64.init)
    }
    public func timelinePage(_ window: TimelineWindow = .latest) throws -> TimelinePage {
        try Self.timelinePage(window, from: db)
    }

    /// The scrollable board pages through text. Audio-only recordings remain
    /// available in the archive and the actual capture tail is returned separately.
    public func panelTimeline(_ window: TimelineWindow) throws -> (page: TimelinePage, tail: TimelineEntry?) {
        try Self.panelTimeline(window, from: db)
    }

    /// NSTextView needs the new row spans before it can accept the next key.
    /// Read the exact committed page and tail in the same bounded transaction.
    @MainActor public func editTimeline(_ edits: [PanelRowEdit], window: TimelineWindow) throws -> (page: TimelinePage, tail: TimelineEntry?) {
        try panelEditor.use(at: directory.appendingPathComponent("Saytile.sqlite")) { writer in
            try writer.transaction {
                try Self.writePanelEdits(edits, to: writer, at: .now)
                return try Self.panelTimeline(window, from: writer)
            }
        }
    }

    private static func panelTimeline(_ window: TimelineWindow, from db: StoreDatabase) throws -> (page: TimelinePage, tail: TimelineEntry?) {
        let page = try timelinePage(window, from: db, textOnly: true)
        let tail = try timelinePage(.latest, from: db, limit: 1).entries.last
        return (page, tail)
    }

    private static func timelinePage(_ window: TimelineWindow, from db: StoreDatabase,
                                     textOnly: Bool = false, limit: Int = TimelinePage.capacity) throws -> TimelinePage {
        let direction: String, predicate: String, values: [StoreDatabase.Value]
        switch window {
        case .latest: direction = "DESC"; predicate = ""; values = []
        case .ending(let key): direction = "DESC"; predicate = " AND t.position<=?"; values = [.int(key)]
        case .starting(let key): direction = "ASC"; predicate = " AND t.position>=?"; values = [.int(key)]
        }
        let textPredicate = textOnly ? " AND v.text<>''" : ""
        let sql = """
        SELECT r.*,v.text,v.origin AS preferred_origin,t.position,t.group_start,g.started AS group_date,g.day,g.utc_offset,
               COALESCE(t.ended,t.started+r.total_frames/r.sample_rate) AS speech_end
        FROM transcript_timeline t CROSS JOIN recordings r ON r.id=t.recording_id
        JOIN transcript_timeline g ON g.position=t.group_start LEFT JOIN revisions v ON v.id=r.preferred_revision
        WHERE r.deleted=0\(textPredicate)
        """
        let rows = try db.rows(sql + predicate + " ORDER BY t.position " + direction + " LIMIT ?", values + [.int(Int64(limit))])
        var page = TimelinePage()
        for row in rows {
            guard let position = row["position"].flatMap(Int64.init), let group = row["group_start"].flatMap(Int64.init),
                  let first = row["group_date"].flatMap(Double.init), let day = row["day"],
                  let offset = row["utc_offset"].flatMap(Int.init), let end = row["speech_end"].flatMap(Double.init) else {
                throw StoreError.database("无法读取时间轴位置。")
            }
            page.entries.append(TimelineEntry(recording: try Self.decodeRecording(row), position: position, group: group,
                groupStart: Date(timeIntervalSince1970: first), groupDay: day, groupUTCOffset: offset, speechEnd: Date(timeIntervalSince1970: end),
                preferredOrigin: row["preferred_origin"].flatMap(RevisionOrigin.init(rawValue:))))
        }
        if direction == "DESC" { page.entries.reverse() }
        if limit == 1 { return page } // Tail lookup doesn't need navigation flags.
        let versionJoin = textOnly ? " JOIN revisions v ON v.id=r.preferred_revision" : ""
        let neighbors = "SELECT 1 FROM transcript_timeline t CROSS JOIN recordings r ON r.id=t.recording_id" +
            versionJoin + " WHERE r.deleted=0" + textPredicate + " AND t.position"
        if let first = page.entries.first, let last = page.entries.last {
            page.hasOlder = try !db.rows(neighbors + "<? ORDER BY t.position DESC LIMIT 1", [.int(first.position)]).isEmpty
            page.hasNewer = try !db.rows(neighbors + ">? ORDER BY t.position LIMIT 1", [.int(last.position)]).isEmpty
        }
        return page
    }

    /// Snapshot the group selected at the click, including segments outside the
    /// current TextKit page. Reading another group never expands this range.
    private nonisolated func timelineGroupRows(group: Int64, through last: Int64, after cleared: Int64 = 0) throws -> [[String: String]] {
        let reader = try StoreDatabase(url: directory.appendingPathComponent("Saytile.sqlite"), readOnly: true)
        return try reader.rows("""
            SELECT t.position,r.id,r.preferred_revision,v.text FROM transcript_timeline t CROSS JOIN recordings r ON r.id=t.recording_id
            LEFT JOIN revisions v ON v.id=r.preferred_revision
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
        let fragments: [String] = try timelineGroupRows(group: group, through: last, after: cleared).compactMap { row in
            let text = row["position"].flatMap(Int64.init).flatMap { displayed[$0] } ?? row["text"] ?? ""
            return text.isEmpty ? nil : text
        }
        return VoiceTranscriptFlow.join(fragments)
    }
}
