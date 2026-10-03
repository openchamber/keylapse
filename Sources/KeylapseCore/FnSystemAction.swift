/// New macOS versions can retain an obsolete AppleFnUsage alongside AppleFnUsageType.
public enum FnSystemAction: Equatable {
    case ready, conflict, unknown

    public static func resolve(type: Int?, legacy: Int?) -> Self {
        guard let value = type ?? legacy, value >= 0 else { return .unknown }
        return value == 0 ? .ready : .conflict
    }
}
