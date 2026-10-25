import Foundation

extension Item {
    /// Apply only user-editable changes relative to the editor's opening snapshot.
    /// Status, trash, occurrence identity, ordering and other live metadata belong
    /// to the current record, not a potentially stale editor copy.
    public func mergingUserEdits(_ draft: Item, original: Item) throws -> Item {
        guard id == draft.id, id == original.id, kind == draft.kind, kind == original.kind else { throw DataError.invalid("The edited item changed identity.") }
        var updated = self
        if draft.title != original.title { updated.title = draft.title }
        if draft.notes != original.notes { updated.notes = draft.notes }
        if draft.checklist != original.checklist { updated.checklist = draft.checklist }
        updated.tagIDs.formUnion(draft.tagIDs.subtracting(original.tagIDs))
        updated.tagIDs.subtract(original.tagIDs.subtracting(draft.tagIDs))
        if draft.projectID != original.projectID || draft.areaID != original.areaID || draft.headingID != original.headingID {
            updated.projectID = draft.projectID; updated.areaID = draft.areaID; updated.headingID = draft.headingID
        }
        if draft.placement != original.placement || draft.start != original.start || draft.bucket != original.bucket || draft.reminder != original.reminder {
            updated.placement = draft.placement; updated.start = draft.start; updated.bucket = draft.bucket; updated.reminder = draft.reminder
        }
        if draft.deadline != original.deadline { updated.deadline = draft.deadline }
        if draft.recurrence != original.recurrence {
            guard draft.recurrence == nil || status == .open else { throw DataError.invalid("Reopen this item before making it repeat.") }
            updated.recurrence = draft.recurrence
        }
        return updated
    }
}
