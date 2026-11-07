import AppKit

/// The panel's title bar buttons.
/// - Top left: Sidebar, then Expand (Shrink while the panel is large).
/// - Top right: Temporary Chat (empty chat) or New Chat (conversation), then Close at the far right.
/// The view spans the title bar, but only its buttons take clicks; the rest goes to the page.
final class HeaderButtons: NSView {
    var onClose: (() -> Void)?
    var onSidebar: (() -> Void)?
    var onExpand: (() -> Void)?
    var onTemporaryChat: (() -> Void)?
    var onNewChat: (() -> Void)?
    /// The page has a title bar, and nothing (the sidebar, a menu, a dialog) covers its top left.
    var isLeadingAllowed = false { didSet { updateVisibility() } }
    /// The page is a signed-in chat page (it has a composer).
    var isChatPage = false { didSet { updateVisibility() } }
    /// The page has room for the buttons at the top right: it is a chat page, and nothing covers
    /// this corner. Other pages have their own buttons there.
    var isAllowed = false { didSet { updateVisibility() } }
    /// The page has a sidebar button for the panel's Sidebar button to press.
    var hasSidebarToggle = true { didSet { updateVisibility() } }
    /// Where the page's main area starts: the left buttons sit at its left edge, so a sidebar
    /// that the page docks on the left in a wide window does not cover them.
    var leadingInset: CGFloat = 0 {
        didSet { leadingConstraint.constant = CGFloat(QuickChatPageStyle.composerInset) + leadingInset }
    }
    /// The panel is large (maximized, or as wide as the page's wide layout): the button then
    /// shrinks it.
    var isExpanded = false {
        didSet {
            expand.showsOtherImage = isExpanded
            updateExpandLabel()
        }
    }
    /// The keyboard shortcut of Expand and Shrink, for the tooltip.
    var expandShortcut = Shortcut.controlCommandF.displayString { didSet { updateExpandLabel() } }

    private(set) var sidebar: HeaderButton!
    private(set) var temporaryChat: HeaderButton!
    private(set) var newChat: HeaderButton!
    private(set) var expand: HeaderButton!
    private(set) var close: HeaderButton!
    private let leadingButtons = NSStackView()
    private let trailingButtons = NSStackView()
    private var leadingConstraint: NSLayoutConstraint!
    private var location = QuickChatLocation(nil)

    init() {
        super.init(frame: .zero)
        sidebar = HeaderButton(image: Self.sidebarImage, label: "Sidebar (⌘B)") { [weak self] in self?.onSidebar?() }
        temporaryChat = HeaderButton(image: Self.temporaryChatImage, activeImage: Self.temporaryChatOnImage, label: "Temporary Chat") { [weak self] in self?.onTemporaryChat?() }
        newChat = HeaderButton(image: Self.newChatImage, label: "New Chat (⌘N)") { [weak self] in self?.onNewChat?() }
        expand = HeaderButton(image: Self.expandImage, activeImage: Self.symbol("arrow.down.right.and.arrow.up.left"),
                              label: "Expand") { [weak self] in self?.onExpand?() }
        close = HeaderButton(image: Self.closeImage, label: "Close Quick Chat (Esc)") { [weak self] in self?.onClose?() }
        for (stack, buttons) in [(leadingButtons, [sidebar!, expand!]), (trailingButtons, [temporaryChat!, newChat!, close!])] {
            stack.orientation = .horizontal
            stack.spacing = 8
            for button in buttons { stack.addArrangedSubview(button) }
        }
        for view in [leadingButtons, trailingButtons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let inset = CGFloat(QuickChatPageStyle.composerInset)
        leadingConstraint = leadingButtons.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset)
        NSLayoutConstraint.activate([
            leadingConstraint,
            leadingButtons.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            trailingButtons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            trailingButtons.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            heightAnchor.constraint(equalToConstant: CGFloat(QuickChatPageStyle.titleBarButtonSize) + inset * 2),
        ])
        update(for: nil)
        updateExpandLabel()
    }

    private func updateExpandLabel() {
        expand.toolTip = "\(isExpanded ? "Shrink" : "Expand") (\(expandShortcut))"
        expand.setAccessibilityLabel(expand.toolTip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        return view === self || view === leadingButtons || view === trailingButtons ? nil : view
    }

    func update(for url: URL?) {
        location = QuickChatLocation(url)
        temporaryChat.isActive = location.isTemporary
        updateVisibility()
    }

    private func updateVisibility() {
        leadingButtons.isHidden = !location.isChatGPT || !isLeadingAllowed
        sidebar.isHidden = !hasSidebarToggle
        expand.isHidden = !isChatPage
        temporaryChat.isHidden = !isChatPage || location.isConversation
        newChat.isHidden = !isChatPage || !location.isConversation
        trailingButtons.isHidden = !location.isChatGPT || !isAllowed
    }

    private static func symbol(_ name: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        return image.withSymbolConfiguration(.init(pointSize: 15, weight: .regular)) ?? image
    }

    private static func templateImage(_ draw: @escaping () -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            draw()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func stroke(_ path: NSBezierPath) {
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    /// A circle with an "x", drawn at the same size as the other title bar icons (16 points).
    private static let closeImage = templateImage {
        stroke(NSBezierPath(ovalIn: NSRect(x: 2.75, y: 2.75, width: 14.5, height: 14.5)))
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: 7.75, y: 7.75))
        cross.line(to: NSPoint(x: 12.25, y: 12.25))
        cross.move(to: NSPoint(x: 12.25, y: 7.75))
        cross.line(to: NSPoint(x: 7.75, y: 12.25))
        stroke(cross)
    }

    /// A rounded rectangle with a short bar on its left, like the page's sidebar icon.
    private static let sidebarImage = templateImage {
        stroke(NSBezierPath(roundedRect: NSRect(x: 2.75, y: 3.25, width: 14.5, height: 13.5), xRadius: 3.5, yRadius: 3.5))
        let bar = NSBezierPath()
        bar.move(to: NSPoint(x: 7, y: 7))
        bar.line(to: NSPoint(x: 7, y: 13))
        stroke(bar)
    }

    /// A window frame with a small window in its corner, like the companion window's
    /// "open in the main window" icon.
    private static let expandImage = templateImage {
        let frame = NSBezierPath()
        frame.move(to: NSPoint(x: 17, y: 8))
        frame.appendArc(withCenter: NSPoint(x: 13.5, y: 6.5), radius: 3.5, startAngle: 0, endAngle: -90, clockwise: true)
        frame.appendArc(withCenter: NSPoint(x: 6.5, y: 6.5), radius: 3.5, startAngle: -90, endAngle: -180, clockwise: true)
        frame.appendArc(withCenter: NSPoint(x: 6.5, y: 13.5), radius: 3.5, startAngle: 180, endAngle: 90, clockwise: true)
        frame.line(to: NSPoint(x: 8, y: 17))
        stroke(frame)
        let corner = NSBezierPath()
        corner.move(to: NSPoint(x: 6.5, y: 10))
        corner.appendArc(withCenter: NSPoint(x: 8, y: 8), radius: 1.5, startAngle: 180, endAngle: 270)
        corner.line(to: NSPoint(x: 10, y: 6.5))
        stroke(corner)
        stroke(NSBezierPath(roundedRect: NSRect(x: 10, y: 10, width: 7, height: 7), xRadius: 1.75, yRadius: 1.75))
    }

    /// A square, open at the top right, with a pencil, like the companion window's new chat icon.
    private static let newChatImage = templateImage {
        let square = NSBezierPath()
        square.move(to: NSPoint(x: 9.5, y: 3))
        square.appendArc(withCenter: NSPoint(x: 6.5, y: 6.5), radius: 3.5, startAngle: -90, endAngle: -180, clockwise: true)
        square.appendArc(withCenter: NSPoint(x: 6.5, y: 13.5), radius: 3.5, startAngle: 180, endAngle: 90, clockwise: true)
        square.appendArc(withCenter: NSPoint(x: 13.5, y: 13.5), radius: 3.5, startAngle: 90, endAngle: 0, clockwise: true)
        square.line(to: NSPoint(x: 17, y: 10.5))
        stroke(square)
        // The pencil points to the lower left; it is drawn along the x axis, then turned up 45°.
        let pencil = NSBezierPath()
        pencil.move(to: .zero)
        pencil.line(to: NSPoint(x: 2.4, y: -1.6))
        pencil.appendArc(withCenter: NSPoint(x: 9.6, y: 0), radius: 1.6, startAngle: -90, endAngle: 90)
        pencil.line(to: NSPoint(x: 2.4, y: 1.6))
        pencil.close()
        let place = AffineTransform(translationByX: 7, byY: 13)
        var turn = AffineTransform(rotationByDegrees: -45)
        turn.append(place)
        pencil.transform(using: turn)
        stroke(pencil)
    }

    /// A speech bubble with a dashed outline, like ChatGPT's temporary chat icon.
    private static let temporaryChatImage = templateImage {
        let bubble = NSBezierPath()
        bubble.appendArc(withCenter: NSPoint(x: 10.5, y: 9.5), radius: 7, startAngle: 140, endAngle: 470)
        bubble.lineWidth = 1.6
        bubble.lineCapStyle = .round
        bubble.setLineDash([3.1, 2.6], count: 2, phase: 0)
        bubble.stroke()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 5.2, y: 14.1))
        tail.line(to: NSPoint(x: 3.2, y: 17.2))
        tail.line(to: NSPoint(x: 7.2, y: 16.2))
        tail.lineWidth = 1.6
        tail.lineCapStyle = .round
        tail.lineJoinStyle = .round
        tail.stroke()
    }

    /// The same speech bubble, filled: a temporary chat is on.
    private static let temporaryChatOnImage = templateImage {
        NSBezierPath(ovalIn: NSRect(x: 2.7, y: 1.7, width: 15.6, height: 15.6)).fill()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 5.2, y: 13.1))
        tail.line(to: NSPoint(x: 3.2, y: 17.2))
        tail.line(to: NSPoint(x: 8.2, y: 16.2))
        tail.close()
        tail.lineWidth = 1.6
        tail.lineJoinStyle = .round
        tail.fill()
        tail.stroke()
    }
}

/// A borderless icon button like the page's title bar buttons: 36 pt, a light
/// fill on hover. While active (an "on" state, such as a temporary chat), it shows its other
/// image (such as a filled icon) and a brighter tint. `showsOtherImage` switches only the image
/// (such as Expand and Shrink).
final class HeaderButton: NSButton {
    private let onPress: () -> Void
    private let normalImage: NSImage
    private let activeImage: NSImage?
    private var isHovered = false { didSet { if isHovered != oldValue { updateFill() } } }
    var isActive = false { didSet { updateImage(); updateFill() } }
    var showsOtherImage = false { didSet { updateImage() } }

    init(image: NSImage, activeImage: NSImage? = nil, label: String, onPress: @escaping () -> Void) {
        self.onPress = onPress
        normalImage = image
        self.activeImage = activeImage
        super.init(frame: .zero)
        self.image = image
        imagePosition = .imageOnly
        isBordered = false
        contentTintColor = .secondaryLabelColor
        toolTip = label
        setAccessibilityLabel(label)
        target = self
        action = #selector(press)
        wantsLayer = true
        // The corner buttons sit 8 points from the window's 20-point corners. A radius of
        // 20 - 8 = 12 makes their corners concentric with the window's corners. All buttons
        // use this radius, so they look the same.
        layer?.cornerRadius = CGFloat(QuickChatPageStyle.windowCornerRadius - QuickChatPageStyle.composerInset)
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        let size = CGFloat(QuickChatPageStyle.titleBarButtonSize)
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size)])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func press() { onPress() }

    private func updateImage() {
        image = (isActive || showsOtherImage) ? activeImage ?? normalImage : normalImage
    }

    /// One click works also while the panel is not the key window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// AppKit calls this also when the window changes its size. The button can then move away
    /// from the pointer (or under it) without an "exited" or "entered" event, so the hover state
    /// is read again from where the pointer is.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        if let window {
            isHovered = window.isVisible && bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFill()
    }

    private func updateFill() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let alpha: CGFloat = isHovered ? 0.08 : 0
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(alpha).cgColor
            contentTintColor = isActive ? .labelColor : .secondaryLabelColor
        }
    }
}
