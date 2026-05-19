import AppKit

/// Inline editor for `dictionary.json`. Two editable columns
/// (spoken phrase → replacement), plus add/remove buttons. Edits commit on
/// end-of-field-editing — every save round-trips through `DictionaryManager`
/// so the regex cache stays in sync without an extra "Save" press.
@MainActor
public final class DictionaryWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {

    private static var sharedController: DictionaryWindowController?

    /// Tag identifier on a row's text field. Tag layout: `row * 2 + column`,
    /// where column 0 is the phrase and column 1 is the replacement.
    private static let phraseColumnID = NSUserInterfaceItemIdentifier("phrase")
    private static let replacementColumnID = NSUserInterfaceItemIdentifier("replacement")

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let addRemoveControl = NSSegmentedControl()
    private let doneButton = NSButton(title: "", target: nil, action: nil)

    /// In-memory working copy. We mutate this on every edit, then persist via
    /// `DictionaryManager.save`. Reloading the window re-reads from disk.
    private var entries: [(key: String, value: String)] = []

    /// Present (or re-focus) the editor.
    public static func present() {
        if let existing = sharedController {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            existing.reloadEntries()
            return
        }
        let controller = DictionaryWindowController()
        sharedController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.dictionaryTitle
        window.minSize = NSSize(width: 460, height: 320)
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
        reloadEntries()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - UI

    private func buildUI() {
        guard let window = window, let content = window.contentView else { return }

        let titleLabel = NSTextField(labelWithString: L10n.dictionaryTitle)
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)

        let introLabel = NSTextField(wrappingLabelWithString: L10n.dictionaryIntro)
        introLabel.font = .systemFont(ofSize: 12)
        introLabel.textColor = .secondaryLabelColor

        configureTable()

        addRemoveControl.segmentCount = 2
        addRemoveControl.setImage(NSImage(systemSymbolName: "plus", accessibilityDescription: L10n.dictionaryAddTooltip), forSegment: 0)
        addRemoveControl.setImage(NSImage(systemSymbolName: "minus", accessibilityDescription: L10n.dictionaryRemoveTooltip), forSegment: 1)
        addRemoveControl.setWidth(32, forSegment: 0)
        addRemoveControl.setWidth(32, forSegment: 1)
        addRemoveControl.trackingMode = .momentary
        addRemoveControl.target = self
        addRemoveControl.action = #selector(addRemoveTapped)
        addRemoveControl.setToolTip(L10n.dictionaryAddTooltip, forSegment: 0)
        addRemoveControl.setToolTip(L10n.dictionaryRemoveTooltip, forSegment: 1)

        doneButton.title = L10n.dictionaryDone
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.target = self
        doneButton.action = #selector(doneTapped)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [addRemoveControl, spacer, doneButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.distribution = .fill

        let stack = NSStackView(views: [titleLabel, introLabel, scrollView, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -20),
            buttonRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -20),
        ])
        // Make the table expand to fill vertical space.
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    private func configureTable() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.style = .inset
        tableView.rowHeight = 26
        tableView.target = self
        tableView.doubleAction = #selector(beginEditingSelectedRow)

        let phraseColumn = NSTableColumn(identifier: Self.phraseColumnID)
        phraseColumn.title = L10n.dictionaryColumnPhrase
        phraseColumn.minWidth = 140
        phraseColumn.width = 220
        tableView.addTableColumn(phraseColumn)

        let replacementColumn = NSTableColumn(identifier: Self.replacementColumnID)
        replacementColumn.title = L10n.dictionaryColumnReplacement
        replacementColumn.minWidth = 140
        replacementColumn.width = 260
        tableView.addTableColumn(replacementColumn)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Data

    /// Reload from disk and refresh the table. Called on first show and when
    /// the window is re-presented while still alive (e.g. user closes & reopens).
    private func reloadEntries() {
        entries = DictionaryManager.shared.snapshot()
        tableView.reloadData()
    }

    /// Write the working copy back to `dictionary.json` and refresh the
    /// in-memory regex cache. Empty keys are dropped by the manager, so the
    /// table can keep a placeholder row in memory without polluting disk.
    private func persist() {
        do {
            try DictionaryManager.shared.save(entries: entries)
        } catch {
            NSLog("[Dict] Save failed: %@", error.localizedDescription)
            let alert = NSAlert()
            alert.messageText = L10n.dictionaryTitle
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - Actions

    @objc private func addRemoveTapped() {
        switch addRemoveControl.selectedSegment {
        case 0: addRow()
        case 1: removeSelectedRows()
        default: break
        }
    }

    private func addRow() {
        entries.append((key: "", value: ""))
        let newRow = entries.count - 1
        tableView.insertRows(at: IndexSet(integer: newRow), withAnimation: .effectFade)
        tableView.scrollRowToVisible(newRow)
        tableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        // Focus the phrase cell so the user can start typing immediately.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.tableView.editColumn(0, row: newRow, with: nil, select: true)
        }
    }

    private func removeSelectedRows() {
        let selected = tableView.selectedRowIndexes
        guard !selected.isEmpty else { return }

        // Commit any pending edit before mutating the model — otherwise
        // controlTextDidEndEditing will fire after the row vanishes and write
        // back to the wrong index.
        window?.makeFirstResponder(tableView)

        for index in selected.reversed() {
            entries.remove(at: index)
        }
        tableView.removeRows(at: selected, withAnimation: .effectFade)
        persist()
    }

    @objc private func beginEditingSelectedRow() {
        let row = tableView.clickedRow
        let column = tableView.clickedColumn
        guard row >= 0, column >= 0 else { return }
        tableView.editColumn(column, row: row, with: nil, select: true)
    }

    @objc private func doneTapped() {
        // Force-commit any in-flight cell edit, then close.
        window?.makeFirstResponder(nil)
        close()
    }

    // MARK: - NSTableViewDataSource

    public func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    // MARK: - NSTableViewDelegate

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let columnID = tableColumn?.identifier, row < entries.count else { return nil }

        let isPhrase = columnID == Self.phraseColumnID
        let cellID = isPhrase ? Self.phraseColumnID : Self.replacementColumnID
        let column = isPhrase ? 0 : 1

        let cell: NSTableCellView
        let textField: EditableRowField
        if let recycled = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView,
           let recycledField = recycled.textField as? EditableRowField {
            cell = recycled
            textField = recycledField
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID
            textField = EditableRowField()
            textField.isEditable = true
            textField.isBordered = false
            textField.drawsBackground = false
            textField.font = isPhrase
                ? .systemFont(ofSize: 13)
                : .monospacedSystemFont(ofSize: 13, weight: .regular)
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.delegate = self
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        textField.row = row
        textField.column = column
        textField.stringValue = isPhrase ? entries[row].key : entries[row].value
        return cell
    }

    // MARK: - NSTextFieldDelegate

    public func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? EditableRowField else { return }
        let row = field.row
        let column = field.column
        guard row >= 0, row < entries.count else { return }

        let newValue = field.stringValue
        let oldEntry = entries[row]
        if column == 0 {
            guard newValue != oldEntry.key else { return }
            entries[row] = (key: newValue, value: oldEntry.value)
        } else {
            guard newValue != oldEntry.value else { return }
            entries[row] = (key: oldEntry.key, value: newValue)
        }
        persist()
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        // Final commit in case the user closes the window mid-edit.
        window?.makeFirstResponder(nil)
        DictionaryWindowController.sharedController = nil
    }
}

/// Text field that remembers which (row, column) it represents so the
/// controller can route end-of-edit notifications back to the right entry.
private final class EditableRowField: NSTextField {
    var row: Int = -1
    var column: Int = -1
}
