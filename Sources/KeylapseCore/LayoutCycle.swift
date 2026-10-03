import Foundation

public struct LayoutCycle {
    public enum InvalidSelection: Error { case tooFewLayouts, duplicateLayouts }
    public let ids: [String]

    public init(_ ids: [String]) throws {
        guard ids.count >= 2 else { throw InvalidSelection.tooFewLayouts }
        guard Set(ids).count == ids.count else { throw InvalidSelection.duplicateLayouts }
        self.ids = ids
    }

    public func next(after current: String) -> String {
        guard let index = ids.firstIndex(of: current) else { return ids[0] }
        return ids[(index + 1) % ids.count]
    }
}
