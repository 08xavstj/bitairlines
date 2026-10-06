// CoreCatalog/LandMask.swift: the world as a land/water grid (0.125 degrees per cell), decoded from run-length rows.

public struct LandMask: Sendable {
    public let width: Int
    public let height: Int
    /// For each row, the column where each run ends. Runs alternate water, land, water, ... starting with water.
    private let runEnds: [[UInt16]]

    public init(encoded: String, width: Int, height: Int) {
        var rows: [[UInt16]] = []
        rows.reserveCapacity(height)
        for line in encoded.split(separator: "\n") {
            var ends: [UInt16] = []
            var total = 0
            for token in line.split(separator: " ") {
                total += Int(token, radix: 36) ?? 0
                ends.append(UInt16(clamping: total))
            }
            rows.append(ends)
        }
        self.width = width
        self.height = height
        self.runEnds = rows
    }

    public static let world = LandMask(encoded: LandMaskRows.rows, width: LandMaskRows.width, height: LandMaskRows.height)

    public func isLand(column: Int, row: Int) -> Bool {
        guard row >= 0, row < runEnds.count, column >= 0, column < width else { return false }
        let ends = runEnds[row]
        var low = 0, high = ends.count
        while low < high {
            let mid = (low + high) / 2
            if Int(ends[mid]) > column { high = mid } else { low = mid + 1 }
        }
        return low % 2 == 1
    }

    public func isLand(latitude: Double, longitude: Double) -> Bool {
        let column = Int((longitude + 180.0) / 360.0 * Double(width))
        let row = Int((90.0 - latitude) / 180.0 * Double(height))
        return isLand(column: min(max(column, 0), width - 1), row: min(max(row, 0), height - 1))
    }
}
