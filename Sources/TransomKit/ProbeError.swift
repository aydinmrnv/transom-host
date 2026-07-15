/// A plain, human-readable error the probe surfaces verbatim. The whole tool is
/// a diagnostic instrument, so error text is output, not noise to swallow.
public struct ProbeError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}
