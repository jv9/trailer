
import CoreData
#if os(iOS)
	import UIKit
#endif

final class PullRequest: ListableItem {

	@NSManaged var issueCommentLink: String?
	@NSManaged var issueUrl: String?
	@NSManaged var mergeable: Bool
	@NSManaged var reviewCommentLink: String?
	@NSManaged var statusesLink: String?
	@NSManaged var lastStatusNotified: String?

	@NSManaged var statuses: Set<PRStatus>

	class func syncPullRequests(from data: [[AnyHashable : Any]]?, in repo: Repo) {
		items(with: data, type: PullRequest.self, server: repo.apiServer) { item, info, isNewOrUpdated in
			if isNewOrUpdated {

				item.baseSync(from: info, in: repo)

				item.mergeable = info["mergeable"] as? Bool ?? true

				if let linkInfo = info["_links"] as? [AnyHashable : Any] {
					item.issueCommentLink = (linkInfo["comments"] as? [AnyHashable : Any])?["href"] as? String
					item.reviewCommentLink = (linkInfo["review_comments"] as? [AnyHashable : Any])?["href"] as? String
					item.statusesLink = (linkInfo["statuses"] as? [AnyHashable : Any])?["href"] as? String
					item.issueUrl = (linkInfo["issue"] as? [AnyHashable : Any])?["href"] as? String
				}

				API.refreshesSinceLastLabelsCheck[item.objectID] = nil
				API.refreshesSinceLastStatusCheck[item.objectID] = nil
			}
			item.reopened = item.condition == ItemCondition.closed.rawValue
			item.condition = ItemCondition.open.rawValue
		}
	}

	#if os(iOS)
	override var searchKeywords: [String] {
		return ["PR", "Pull Request", "PRs", "Pull Requests"] + super.searchKeywords
	}
	#endif

	class func active(in moc: NSManagedObjectContext, visibleOnly: Bool) -> [PullRequest] {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		if visibleOnly {
			f.predicate = NSPredicate(format: "sectionIndex == %lld || sectionIndex == %lld || sectionIndex == %lld", Section.mine.rawValue, Section.participated.rawValue, Section.all.rawValue)
		} else {
			f.predicate = NSPredicate(format: "condition == %lld", ItemCondition.open.rawValue)
		}
		return try! moc.fetch(f)
	}

	class func allMerged(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil, includeAllGroups: Bool = false) -> [PullRequest] {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		let p = NSPredicate(format: "condition == %lld", ItemCondition.merged.rawValue)
		add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc, includeAllGroups: includeAllGroups)
		return try! moc.fetch(f)
	}

	class func allClosed(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil, includeAllGroups: Bool = false) -> [PullRequest] {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		let p = NSPredicate(format: "condition == %lld", ItemCondition.closed.rawValue)
		add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc, includeAllGroups: includeAllGroups)
		return try! moc.fetch(f)
	}

	class func countOpen(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil) -> Int {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.includesSubentities = false
		let p = NSPredicate(format: "condition == %lld or condition == nil", ItemCondition.open.rawValue)
		add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc)
		return try! moc.count(for: f)
	}

	class func markEverythingRead(in section: Section, in moc: NSManagedObjectContext) {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		if section != .none {
			f.predicate = NSPredicate(format: "sectionIndex == %lld", section.rawValue)
		}
		for pr in try! moc.fetch(f) {
			pr.catchUpWithComments()
		}
	}

	class func badgeCount(in section: Section, in moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.includesSubentities = false
		f.predicate = NSPredicate(format: "sectionIndex == %lld and unreadComments > 0", section.rawValue)
		return badgeCount(from: f, in: moc)
	}

	class func badgeCount(in moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.includesSubentities = false
		f.predicate = NSPredicate(format: "sectionIndex > 0 and unreadComments > 0")
		return badgeCount(from: f, in: moc)
	}

	class func badgeCount(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil) -> Int {
		let f = requestForItems(of: PullRequest.self, withFilter: nil, sectionIndex: -1, criterion: criterion)
		return badgeCount(from: f, in: moc)
	}

	var markUnmergeable: Bool {
		if !mergeable {
			let s = sectionIndex
			if s == ItemCondition.merged.rawValue || s == ItemCondition.closed.rawValue {
				return false
			}
			if s == Section.all.rawValue && Settings.markUnmergeableOnUserSectionsOnly {
				return false
			}
			return true
		}
		return false
	}

	class func reasonForEmpty(with filterValue: String?, criterion: GroupingCriterion? = nil) -> NSAttributedString {
		let openRequestCount = PullRequest.countOpen(in: DataManager.main, criterion: criterion)
		return reasonForEmpty(with: filterValue, criterion: criterion, openItemCount: openRequestCount)
	}

	func subtitle(with font: FONT_CLASS, lightColor: COLOR_CLASS, darkColor: COLOR_CLASS) -> NSMutableAttributedString {
		let _subtitle = NSMutableAttributedString()
		let p = NSMutableParagraphStyle()
		#if os(iOS)
			p.lineHeightMultiple = 1.3
		#endif

		let lightSubtitle = [NSForegroundColorAttributeName: lightColor, NSFontAttributeName: font, NSParagraphStyleAttributeName: p]

		#if os(iOS)
			let separator = NSAttributedString(string:"\n", attributes: lightSubtitle)
		#elseif os(OSX)
			let separator = NSAttributedString(string:"   ", attributes: lightSubtitle)
		#endif

		if Settings.showReposInName {
			if let n = repo.fullName {
				var darkSubtitle = lightSubtitle
				darkSubtitle[NSForegroundColorAttributeName] = darkColor
				_subtitle.append(NSAttributedString(string: n, attributes: darkSubtitle))
				_subtitle.append(separator)
			}
		}

		if let l = userLogin {
			_subtitle.append(NSAttributedString(string: "@\(l)", attributes: lightSubtitle))
			_subtitle.append(separator)
		}

		if Settings.showCreatedInsteadOfUpdated {
			_subtitle.append(NSAttributedString(string: itemDateFormatter.string(from: createdAt!), attributes: lightSubtitle))
		} else {
			_subtitle.append(NSAttributedString(string: itemDateFormatter.string(from: updatedAt!), attributes: lightSubtitle))
		}

		#if os(iOS)
			if !mergeable {
				_subtitle.append(separator)
				var redSubtitle = lightSubtitle
				redSubtitle[NSForegroundColorAttributeName] = UIColor.red
				_subtitle.append(NSAttributedString(string: "Cannot be merged!", attributes: redSubtitle))
			}
		#endif

		return _subtitle
	}

	var accessibleSubtitle: String {
		var components = [String]()

		if Settings.showReposInName {
			components.append("Repository: \(S(repo.fullName))")
		}

		if let l = userLogin { components.append("Author: \(l)") }

		if Settings.showCreatedInsteadOfUpdated {
			components.append("Created \(itemDateFormatter.string(from: createdAt!))")
		} else {
			components.append("Updated \(itemDateFormatter.string(from: updatedAt!))")
		}

		if !mergeable {
			components.append("Cannot be merged!")
		}

		return components.joined(separator: ",")
	}

	func shouldBeCheckedForRedStatuses(in section: Section) -> Bool {
		if Settings.hidePrsThatArentPassing {
			if Settings.hidePrsThatDontPassOnlyInAll {
				return section == .all
			} else {
				return section == .mine || section == .participated || section == .all
			}
		}
		return false
	}

	var displayedStatuses: [PRStatus] {
		let f = NSFetchRequest<PRStatus>(entityName: "PRStatus")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		let mode = Settings.statusFilteringMode
		if mode==StatusFilter.all.rawValue {
			f.predicate = NSPredicate(format: "pullRequest == %@", self)
		} else {
			let terms = Settings.statusFilteringTerms
			if terms.count > 0 {
				var subPredicates = [NSPredicate]()
				for t in terms {
					subPredicates.append(NSPredicate(format: "descriptionText contains[cd] %@", t))
				}
				let orPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: subPredicates)
				let selfPredicate = NSPredicate(format: "pullRequest == %@", self)

				if mode==StatusFilter.include.rawValue {
					f.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [selfPredicate, orPredicate])
				} else {
					let notOrPredicate = NSCompoundPredicate(notPredicateWithSubpredicate: orPredicate)
					f.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [selfPredicate, notOrPredicate])
				}
			} else {
				f.predicate = NSPredicate(format: "pullRequest == %@", self)
			}
		}
		f.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

		var result = [PRStatus]()
		var targetUrls = Set<String>()
		var descriptions = Set<String>()
		for s in try! managedObjectContext?.fetch(f) ?? [] {
			let targetUrl = S(s.targetUrl)
			let desc = S(s.descriptionText)

			if !desc.isEmpty && !descriptions.contains(desc) {
				descriptions.insert(desc)
				if !targetUrls.contains(targetUrl) {
					targetUrls.insert(targetUrl)
					result.append(s)
				}
			}
		}
		return result
	}

	var labelsLink: String? {
		return issueUrl?.appending(pathComponent: "labels")
	}

	var sectionName: String {
		return Section.prMenuTitles[Int(sectionIndex)]
	}
}
