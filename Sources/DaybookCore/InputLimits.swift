/// Resource bounds for schema-v1 data. These are safety ceilings, not UI capacity
/// or responsiveness promises. Text limits count UTF-8 bytes (not graphemes).
public enum InputLimits {
    public static let maximumItems = 100_000
    public static let maximumTags = 10_000
    public static let maximumAreas = 10_000
    public static let titleUTF8Bytes = 16_384
    public static let notesUTF8Bytes = 1_048_576
    public static let checklistEntriesPerItem = 1_000
    public static let tagAssignmentsPerRecord = 1_000
    public static let totalChecklistEntries = 200_000
    public static let totalTagAssignments = 1_000_000
    public static let totalTextUTF8Bytes = 67_108_864
    public static let tagHierarchyDepth = 128
    public static let relationshipDepth = 128
    public static let calendarIdentifiers = 1_000
    public static let calendarIdentifierUTF8Bytes = 1_024
    /// Aggregate occurrence attempts and copied rows per refresh. A large project
    /// can use one refresh by itself; its atomic copy is capped by maximumItems.
    public static let recurrenceWorkBudget = 1_000
    public static let recurrenceChecklistBudget = 10_000
    public static let recurrenceTextUTF8Bytes = 4 * 1024 * 1024
}
