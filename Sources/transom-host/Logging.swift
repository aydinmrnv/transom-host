import os

/// Centralised `os.Logger` instances, one per subsystem area.
///
/// User-facing report output uses `print`. Structured diagnostics — the things
/// you want to pull out of the unified logging system with `log stream
/// --predicate 'subsystem == "one.transom.host"'` — go through these loggers.
enum Log {
    /// Reverse-DNS subsystem shared by every logger in the host.
    static let subsystem = "one.transom.host"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let doctor = Logger(subsystem: subsystem, category: "doctor")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let ax = Logger(subsystem: subsystem, category: "accessibility")
}
