import AppKit
import WebKit

/// The panel's web view. The panel does not activate the app, so it is often not the key window
/// when you click it. The first click then goes to the page, as in a key window, so a single
/// press on the title bar starts a drag and a single click works.
final class PanelWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The panel's native translucent material. ChatGPT's light colors are made for a white page,
/// so in the light theme a lighter material with a white tint keeps its gray text and icons
/// readable over any window behind the panel. The dark theme shows the material alone.
class PanelMaterialView: NSVisualEffectView {
    private let tint = NSView()
    var isLight = false {
        didSet {
            material = isLight ? .popover : .underWindowBackground
            tint.layer?.backgroundColor = isLight ? NSColor.white.withAlphaComponent(0.7).cgColor : nil
        }
    }

    init() {
        super.init(frame: .zero)
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .active
        tint.wantsLayer = true
        tint.frame = bounds
        tint.autoresizingMask = [.width, .height]
        addSubview(tint)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// Covers the page with the panel's material and a spinner while a page loads. It stops when
/// the page is ready, or after 15 seconds. A drag on it moves the panel.
final class LoadingView: PanelMaterialView {
    private let spinner = NSProgressIndicator()
    private var timeout: Task<Void, Never>?

    override init() {
        super.init()
        isHidden = true
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var isLoading: Bool { !isHidden }

    func start() {
        alphaValue = 1
        isHidden = false
        spinner.startAnimation(nil)
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            if !Task.isCancelled { self?.stop() }
        }
    }

    func stop() {
        timeout?.cancel()
        timeout = nil
        guard isLoading else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.alphaValue == 0 else { return }
                self.isHidden = true
                self.spinner.stopAnimation(nil)
            }
        })
    }

    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The panel's material over the page while the panel changes its size. It takes no clicks.
final class ResizeCover: PanelMaterialView {
    override init() {
        super.init()
        alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Reports when the pointer enters or leaves the panel.
final class PointerWatcher: NSObject {
    private let onChange: (Bool) -> Void

    init(onChange: @escaping (Bool) -> Void) { self.onChange = onChange }

    // The names that a tracking area calls on its owner.
    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) { onChange(true) }
    @objc(mouseExited:) func mouseExited(with event: NSEvent) { onChange(false) }
}
