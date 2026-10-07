// CoreWorld/WorldInfo.swift: the live game state and its rules live in this target.
import CoreCatalog

public enum WorldInfo {
    /// Saves record this so an older save is never opened by newer rules. Bump it whenever a balance number or rule changes.
    public static let rulesVersion = 11
    public static let catalogSchema = CatalogInfo.schemaVersion
}
