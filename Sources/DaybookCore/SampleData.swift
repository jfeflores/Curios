import Foundation

extension Database {
    public static func sample(today: Day = Day()) -> Database {
        var db = Database()
        let work = Area("Work", position: 0), personal = Area("Personal", position: 1)
        let focus = Tag("Focus"), errands = Tag("Errands"), home = Tag("Home"), important = Tag("Important")
        db.areas = [work, personal]; db.tags = [focus, errands, home, important]
        var website = Item("Launch the new website", kind: .project, placement: .anytime, position: 10)
        website.areaID = work.id; website.notes = "A thoughtful home for our next chapter.\n\nKeep it simple, useful, and distinctly us."; website.tagIDs = [focus.id]
        website.deadline = today.adding(.day, 10)
        var weekend = Item("A weekend away", kind: .project, placement: .anytime, position: 20)
        weekend.areaID = personal.id; weekend.notes = "A little room to explore. A lot of room to unwind."
        var heading = Item("The essentials", kind: .heading, placement: .anytime, position: 11)
        heading.projectID = website.id
        db.items = [website, weekend, heading]
        func task(_ title: String, placement: Placement = .scheduled, offset: Int = 0, project: UUID? = nil, area: UUID? = nil, tags: Set<UUID> = [], notes: String = "", evening: Bool = false) -> Item {
            var item = Item(title, placement: placement, start: placement == .scheduled ? today.adding(.day, offset) : nil, position: Double(db.items.count + 30))
            item.projectID = project; item.areaID = area; item.tagIDs = tags; item.notes = notes; item.bucket = evening ? .evening : .day
            return item
        }
        var review = task("Make room for the work that matters", area: work.id, tags: [focus.id], notes: "Review the week, choose three priorities, and leave a little breathing room.")
        review.checklist = [ChecklistEntry("Review open projects"), ChecklistEntry("Choose three priorities"), ChecklistEntry("Protect an hour of focus")]
        db.items.append(review)
        var design = task("Sketch the homepage", project: website.id, tags: [focus.id]); design.headingID = heading.id; db.items.append(design)
        var proposal = task("Send the project proposal", area: work.id, tags: [important.id]); proposal.deadline = today; db.items.append(proposal)
        db.items.append(task("Pick up a few things for dinner", tags: [errands.id], notes: "Something fresh. Something seasonal."))
        db.items.append(task("Choose a place to stay", project: weekend.id, evening: true))
        db.items.append(task("Read a chapter, not a notification", tags: [home.id], evening: true))
        db.items.append(task("Review the first design direction", offset: 1, project: website.id))
        db.items.append(task("Book the train tickets", offset: 2, project: weekend.id))
        db.items.append(task("Write the launch announcement", offset: 4, project: website.id))
        db.items.append(task("Find a good trail", placement: .anytime, project: weekend.id))
        db.items.append(task("Learn to make fresh pasta", placement: .someday, tags: [home.id]))
        db.items.append(task("A thought worth coming back to", placement: .inbox, notes: "Capture now. Decide later."))
        var done = task("Start with a clean slate", placement: .anytime); done.status = .completed; done.statusDate = Date(); db.items.append(done)
        for index in db.items.indices { db.items[index].position = Double(index) }
        return db
    }
}
