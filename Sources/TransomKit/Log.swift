import os

/// Centralised `os.Logger` instances, one per subsystem area.
///
/// User-facing report output uses `print`. Structured diagnostics — the things
/// you want to pull out of the unified logging system with `log stream
/// --predicate 'subsystem == "one.transom.host"'` — go through these loggers.
public enum Log {
    /// Reverse-DNS subsystem shared by every logger in the host.
    public static let subsystem = "one.transom.host"

    public static let general = Logger(subsystem: subsystem, category: "general")
    public static let doctor = Logger(subsystem: subsystem, category: "doctor")
    public static let capture = Logger(subsystem: subsystem, category: "capture")
    public static let ax = Logger(subsystem: subsystem, category: "accessibility")
    public static let app = Logger(subsystem: subsystem, category: "app")
}
