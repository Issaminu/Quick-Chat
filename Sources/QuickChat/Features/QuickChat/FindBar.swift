import AppKit

/// The find bar (⌘F). It searches the text of the page while you type. Return and ⌘G show the
/// next match, ⇧Return and ⇧⌘G show the previous match, and Esc closes the bar.
final class FindBar: NSVisualEffectView, NSSearchFieldDelegate {
    static let height: CGFloat = 36
    var onSearch: ((String) -> Void)?
    /// `true`: the previous match.
    var onStep: ((Bool) -> Void)?
    var onClose: (() -> Void)?

    let field = FindField()
    /// "2 of 5", or "Not found".
    let result = NSTextField(labelWithString: "")
    private var previous: NSButton!
    private var next: NSButton!

    var text: String { field.stringValue }

    init() {
        super.init(frame: .zero)
        material = .menu
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        isHidden = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("Find")

        field.placeholderString = "Find"
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(search)
        result.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        result.textColor = .secondaryLabelColor
        result.alignment = .right
        result.setContentHuggingPriority(.required, for: .horizontal)
        result.setContentCompressionResistancePriority(.required, for: .horizontal)
        previous = Self.button("chevron.up", label: "Previous Match (⇧⌘G)") { [weak self] in self?.onStep?(true) }
        next = Self.button("chevron.down", label: "Next Match (⌘G)") { [weak self] in self?.onStep?(false) }
        let done = Self.button("xmark", label: "Close Find (Esc)") { [weak self] in self?.onClose?() }
        let stack = NSStackView(views: [field, result, previous, next, done])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.setCustomSpacing(8, after: result)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: Self.height),
        ])
        show(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    /// Shows a result of the search: `index` (from 0, or -1) and `count`. Nil: no search.
    func show(_ result: [String: Any]?) {
        let count = result?["count"] as? Int ?? 0
        let index = result?["index"] as? Int ?? -1
        let limited = result?["limited"] as? Bool == true
        if text.trimmingCharacters(in: .whitespaces).isEmpty || result == nil {
            self.result.stringValue = ""
        } else if count == 0 {
            self.result.stringValue = "Not found"
        } else {
            self.result.stringValue = "\(index + 1) of \(count)\(limited ? "+" : "")"
        }
        previous.isEnabled = count > 0
        next.isEnabled = count > 0
    }

    @objc private func search() { onSearch?(text) }

    /// Return: the next match. ⇧Return: the previous match. Esc: close the bar (a search field
    /// would clear its text).
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)):
            onStep?(NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }

    /// One click works also while the panel is not the key window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private static func button(_ symbol: String, label: String, action: @escaping () -> Void) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)!
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))!
        let button = FindButton(image: image, label: label, action: action)
        return button
    }
}

/// The find bar's text field. One click works also while the panel is not the key window.
final class FindField: NSSearchField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A small borderless button of the find bar.
private final class FindButton: NSButton {
    private let onPress: () -> Void

    init(image: NSImage, label: String, action: @escaping () -> Void) {
        onPress = action
        super.init(frame: .zero)
        self.image = image
        imagePosition = .imageOnly
        isBordered = false
        contentTintColor = .secondaryLabelColor
        toolTip = label
        setAccessibilityLabel(label)
        target = self
        self.action = #selector(press)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 24), heightAnchor.constraint(equalToConstant: 24)])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func press() { onPress() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
