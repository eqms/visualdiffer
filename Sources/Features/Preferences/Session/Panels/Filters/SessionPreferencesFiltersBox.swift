//
//  SessionPreferencesFiltersBox.swift
//  VisualDiffer
//
//  Created by davide ficano on 26/04/25.
//  Copyright (c) 2025 visualdiffer.com
//

class SessionPreferencesFiltersBox: PreferencesBox, NSMenuItemValidation {
    private lazy var searchField: NSSearchField = {
        let view = NSSearchField(frame: .zero)

        view.placeholderString = NSLocalizedString("Filter Rules", comment: "")
        view.translatesAutoresizingMaskIntoConstraints = false
        view.target = self
        view.action = #selector(searchFilters)
        view.sendsWholeSearchString = false
        view.sendsSearchStringImmediately = true

        return view
    }()

    private lazy var actionMenu: NSPopUpButton = {
        let view = NSPopUpButton(frame: .zero, pullsDown: true)

        view.bezelStyle = .shadowlessSquare
        view.setButtonType(.momentaryPushIn)
        view.isBordered = true
        view.alignment = .left

        view.translatesAutoresizingMaskIntoConstraints = false

        view.target = self
        view.menu = createActionPopupMenu()

        return view
    }()

    private lazy var predicateEditorScrollView: NSScrollView = {
        let view = NSScrollView(frame: .zero)

        view.borderType = .bezelBorder
        view.autohidesScrollers = true
        view.hasHorizontalScroller = true
        view.hasVerticalScroller = true
        view.horizontalLineScroll = 19
        view.horizontalPageScroll = 10
        view.verticalLineScroll = 19
        view.verticalPageScroll = 10
        view.usesPredominantAxisScrolling = false
        view.translatesAutoresizingMaskIntoConstraints = false

        view.documentView = predicateEditor

        predicateEditor.translatesAutoresizingMaskIntoConstraints = false
        predicateEditor.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true

        return view
    }()

    private lazy var predicateEditor: FiltersPredicateEditor = {
        let view = FiltersPredicateEditor(frame: .zero)

        if let defaultFilters = SessionDiff.defaultFileFilters() {
            view.objectValue = NSPredicate(format: defaultFilters)
        }
        return view
    }()

    /// Stores the full predicate while search is active so saves always use the complete set
    private var unfilteredPredicate: NSCompoundPredicate?

    private var currentFilters: String? {
        let predicate = unfilteredPredicate ?? (predicateEditor.objectValue as? NSCompoundPredicate)
        return (predicate as NSPredicate?)?.description
    }

    override init(title: String) {
        super.init(title: title)

        setupViews()
    }

    private func setupViews() {
        if let contentView {
            contentView.addSubview(searchField)
            contentView.addSubview(predicateEditorScrollView)
            contentView.addSubview(actionMenu)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(predicateEditorRowsDidChange),
            name: NSRuleEditor.rowsDidChangeNotification,
            object: predicateEditor
        )

        setupConstraints()
    }

    private func createActionPopupMenu() -> NSMenu {
        let popupMenu = NSMenu()

        // the button title image
        popupMenu.addItem(
            withTitle: "",
            action: nil,
            keyEquivalent: ""
        )
        .image = NSImage(named: NSImage.actionTemplateName)
        popupMenu.addItem(
            withTitle: NSLocalizedString("Fill with Defaults", comment: ""),
            action: #selector(fillWithDefaults),
            keyEquivalent: ""
        )
        popupMenu.addItem(
            withTitle: NSLocalizedString("Set Current as Defaults", comment: ""),
            action: #selector(saveDefaults),
            keyEquivalent: ""
        )
        popupMenu.addItem(
            withTitle: NSLocalizedString("Restore Factory Defaults", comment: ""),
            action: #selector(restoreDefaults),
            keyEquivalent: ""
        )
        popupMenu.addItem(NSMenuItem.separator())
        popupMenu.addItem(
            withTitle: NSLocalizedString("Sort Alphabetically", comment: ""),
            action: #selector(sortAlphabetically),
            keyEquivalent: ""
        )
        popupMenu.addItem(NSMenuItem.separator())
        popupMenu.addItem(
            withTitle: NSLocalizedString("Copy to Clipboard", comment: ""),
            action: #selector(copyToClipboard),
            keyEquivalent: ""
        )
        popupMenu.addItem(
            withTitle: NSLocalizedString("Paste from Clipboard", comment: ""),
            action: #selector(pasteFromClipboard),
            keyEquivalent: ""
        )

        for item in popupMenu.items {
            item.target = self
        }

        return popupMenu
    }

    private func setupConstraints() {
        guard let contentView else {
            return
        }
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            searchField.centerYAnchor.constraint(equalTo: actionMenu.centerYAnchor),
            searchField.trailingAnchor.constraint(lessThanOrEqualTo: actionMenu.leadingAnchor, constant: -8),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),

            actionMenu.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            actionMenu.topAnchor.constraint(equalTo: contentView.topAnchor),

            predicateEditorScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            predicateEditorScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            predicateEditorScrollView.topAnchor.constraint(equalTo: actionMenu.bottomAnchor, constant: 10),
            predicateEditorScrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    // MARK: - Action Methods

    @objc
    func copyToClipboard(_: AnyObject) {
        if let filters = currentFilters as? NSString {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([filters])
        }
    }

    @objc
    func pasteFromClipboard(_: AnyObject) {
        let pasteboard = NSPasteboard.general
        let supportedTypes = [NSPasteboard.PasteboardType.string]

        if let bestType = pasteboard.availableType(from: supportedTypes),
           let filters = pasteboard.string(forType: bestType) {
            do {
                predicateEditor.objectValue = try NSPredicate.createSafe(withFormat: filters)
            } catch {
                let alert = NSAlert()

                alert.messageText = NSLocalizedString("The file filter expression contains errors", comment: "")
                alert.alertStyle = .critical
                alert.informativeText = error.localizedDescription

                alert.runModal()
            }
        }
    }

    @objc
    func saveDefaults(_: AnyObject) {
        guard let filters = currentFilters else {
            return
        }

        var overwrite = true
        if CommonPrefs.shared.defaultFileFilters != nil {
            overwrite = NSAlert.showModalConfirm(
                messageText: NSLocalizedString("Replace Custom Defaults", comment: ""),
                informativeText: NSLocalizedString("Do you want to replace the current custom defaults?", comment: "")
            )
        }
        if overwrite {
            CommonPrefs.shared.defaultFileFilters = filters
        }
    }

    @objc
    func restoreDefaults(_: AnyObject) {
        let result = NSAlert.showModalConfirm(
            messageText: NSLocalizedString("Restore Defaults", comment: ""),
            informativeText: NSLocalizedString("The custom-defined defaults will be replaced with the application defaults. Are you sure?", comment: "")
        )
        if result {
            CommonPrefs.shared.defaultFileFilters = nil
        }
    }

    @objc
    func fillWithDefaults(_: AnyObject) {
        resetSearch()
        if let defaultFilters = SessionDiff.defaultFileFilters() {
            predicateEditor.objectValue = NSPredicate(format: defaultFilters)
        }
    }

    @objc
    func sortAlphabetically(_: AnyObject) {
        resetSearch()
        guard let compound = predicateEditor.objectValue as? NSCompoundPredicate else {
            return
        }
        guard let subs = compound.subpredicates as? [NSPredicate] else {
            return
        }
        let sorted = subs.sorted { lhs, rhs in
            sortKey(for: lhs).localizedCaseInsensitiveCompare(sortKey(for: rhs)) == .orderedAscending
        }
        let sortedCompound = NSCompoundPredicate(
            type: compound.compoundPredicateType,
            subpredicates: sorted
        )
        predicateEditor.objectValue = sortedCompound
    }

    @objc
    func searchFilters(_ sender: NSSearchField) {
        let query = sender.stringValue.trimmingCharacters(in: .whitespaces)

        if query.isEmpty {
            resetSearch()
            return
        }

        // Minimum 3 characters required to trigger search
        if query.count < 3 {
            if unfilteredPredicate != nil {
                resetSearch()
            }
            return
        }

        // On first search input, save the full predicate
        if unfilteredPredicate == nil {
            unfilteredPredicate = predicateEditor.objectValue as? NSCompoundPredicate
        }

        guard let fullPredicate = unfilteredPredicate,
              let subs = fullPredicate.subpredicates as? [NSPredicate] else {
            return
        }

        let filtered = subs.filter { sub in
            sortKey(for: sub).localizedCaseInsensitiveContains(query)
        }

        // Always show at least the compound structure even if no matches
        let filteredCompound = NSCompoundPredicate(
            type: fullPredicate.compoundPredicateType,
            subpredicates: filtered
        )
        predicateEditor.objectValue = filteredCompound
    }

    // MARK: - Search Helpers

    private func resetSearch() {
        if let saved = unfilteredPredicate {
            predicateEditor.objectValue = saved
            unfilteredPredicate = nil
        }
        searchField.stringValue = ""
    }

    /// Synchronizes unfilteredPredicate when rows are added or removed while search is active.
    @objc
    private func predicateEditorRowsDidChange(_: Notification) {
        guard let fullPredicate = unfilteredPredicate,
              let fullSubs = fullPredicate.subpredicates as? [NSPredicate],
              let currentCompound = predicateEditor.objectValue as? NSCompoundPredicate,
              let currentSubs = currentCompound.subpredicates as? [NSPredicate] else {
            return
        }

        // Remove from unfilteredPredicate any subpredicates no longer present in the editor
        let currentDescriptions = Set(currentSubs.map(\.description))
        let updatedSubs = fullSubs.filter { currentDescriptions.contains($0.description) }

        if updatedSubs.count != fullSubs.count {
            unfilteredPredicate = NSCompoundPredicate(
                type: fullPredicate.compoundPredicateType,
                subpredicates: updatedSubs
            )
        }
    }

    private func sortKey(for predicate: Any) -> String {
        if let comparison = predicate as? NSComparisonPredicate {
            return comparison.rightExpression.constantValue as? String ?? ""
        }
        return (predicate as? NSPredicate)?.description ?? ""
    }

    // MARK: - NSMenuItemValidation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        var enabled = true
        let action = menuItem.action

        if action == #selector(restoreDefaults) {
            let defaultFilters = CommonPrefs.shared.defaultFileFilters
            menuItem.isHidden = defaultFilters == nil
        } else if action == #selector(saveDefaults) {
            enabled = if let defaultFilters = CommonPrefs.shared.defaultFileFilters,
                         let filters = currentFilters {
                defaultFilters != filters
            } else {
                false
            }
        } else if action == #selector(sortAlphabetically) {
            let compound = unfilteredPredicate ?? (predicateEditor.objectValue as? NSCompoundPredicate)
            enabled = (compound?.subpredicates.count ?? 0) >= 2
        }

        return enabled
    }

    override func reloadData() {
        resetSearch()
        if let str = delegate?.preferenceBox(self, stringForKey: .defaultFileFilters) {
            predicateEditor.objectValue = NSPredicate(format: str)
        } else {
            predicateEditor.objectValue = nil
        }
    }

    func updatePendingData() {
        if let filters = currentFilters {
            delegate?.preferenceBox(self, setString: filters, forKey: .defaultFileFilters)
        }
    }
}
