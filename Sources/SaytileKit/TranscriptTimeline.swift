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
    CREATE TRIGGER IF NOT EXISTS timeline_record AFTER INSERT ON recordings BEGIN
      INSERT INTO transcript_timeline(recording_id,started,day,utc_offset)
      VALUES(NEW.id,NEW.created_at,date(NEW.created_at,'unixepoch','localtime'),
        unixepoch(datetime(NEW.created_at,'unixepoch','localtime'))-unixepoch(NEW.created_at,'unixepoch'));
    END;
    """
    static let timelineBackfill = """
    INSERT INTO transcript_timeline(recording_id,started,day,utc_offset)
    SELECT id,created_at,date(created_at,'unixepoch','localtime'),
      unixepoch(datetime(created_at,'unixepoch','localtime'))-unixepoch(created_at,'unixepoch')
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
        let direction: String, predicate: String, values: [StoreDatabase.Value]
        switch window {
        case .latest: direction = "DESC"; predicate = ""; values = []
        case .ending(let key): direction = "DESC"; predicate = " AND t.position<=?"; values = [.int(key)]
        case .starting(let key): direction = "ASC"; predicate = " AND t.position>=?"; values = [.int(key)]
        }
        let sql = """
        SELECT r.*,v.text,t.position,t.group_start,g.started AS group_date,g.day,g.utc_offset,
               COALESCE(t.ended,t.started+r.total_frames/r.sample_rate) AS speech_end
        FROM transcript_timeline t CROSS JOIN recordings r ON r.id=t.recording_id
        JOIN transcript_timeline g ON g.position=t.group_start LEFT JOIN revisions v ON v.id=r.preferred_revision
        WHERE r.deleted=0
        """
        let rows = try db.rows(sql + predicate + " ORDER BY t.position " + direction + " LIMIT ?", values + [.int(Int64(TimelinePage.capacity))])
        var page = TimelinePage()
        for row in rows {
            guard let position = row["position"].flatMap(Int64.init), let group = row["group_start"].flatMap(Int64.init),
                  let first = row["group_date"].flatMap(Double.init), let day = row["day"],
                  let offset = row["utc_offset"].flatMap(Int.init), let end = row["speech_end"].flatMap(Double.init) else {
                throw StoreError.database("无法读取时间轴位置。")
            }
            page.entries.append(TimelineEntry(recording: try Self.decodeRecording(row), position: position, group: group,
                groupStart: Date(timeIntervalSince1970: first), groupDay: day, groupUTCOffset: offset, speechEnd: Date(timeIntervalSince1970: end)))
        }
        if direction == "DESC" { page.entries.reverse() }
        let neighbors = "SELECT 1 FROM transcript_timeline t CROSS JOIN recordings r ON r.id=t.recording_id WHERE r.deleted=0 AND t.position"
        if let first = page.entries.first, let last = page.entries.last {
            page.hasOlder = try !db.rows(neighbors + "<? ORDER BY t.position DESC LIMIT 1", [.int(first.position)]).isEmpty
            page.hasNewer = try !db.rows(neighbors + ">? ORDER BY t.position LIMIT 1", [.int(last.position)]).isEmpty
        }
        return page
    }

    /// A click reads one SQLite snapshot. Already rendered revisions win over a newer
    /// database revision not yet drawn. Loading earlier pages never grows this query.
    public nonisolated func timelineCopy(group: Int64, through last: Int64, displayed: [Int64:String]) throws -> String {
        let reader = try StoreDatabase(url: directory.appendingPathComponent("Saytile.sqlite"), readOnly: true)
        let rows = try reader.rows("""
            SELECT t.position,v.text FROM transcript_timeline t CROSS JOIN recordings r ON r.id=t.recording_id
            LEFT JOIN revisions v ON v.id=r.preferred_revision
            WHERE t.group_start=? AND t.position<=? AND r.deleted=0 ORDER BY t.position
            """, [.int(group), .int(last)])
        return rows.compactMap { row in
            let text = row["position"].flatMap(Int64.init).flatMap { displayed[$0] } ?? row["text"] ?? ""
            return text.isEmpty ? nil : text
        }.joined(separator: "\n")
    }
}
