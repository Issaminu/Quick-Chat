import AppKit

/// Throwing the panel, like ChatGPT's own companion window: a fast drag that ends while the pointer
/// still moves sends the panel to the left or right edge of the screen. A slower drag, a short
/// drag, or a drag that stops before the release moves the panel only as far as the pointer.
enum PanelThrow {
    /// The release speed (points per second) and the drag length that start a throw.
    static let minimumSpeed: CGFloat = 500
    static let minimumDistance: CGFloat = 110
    /// The speed comes from the pointer's moves in this time before its last move.
    static let speedWindow: TimeInterval = 0.05
    /// A longer stop before the release gives no throw.
    static let longestStop: TimeInterval = 0.05
    /// The panel stops this far from the edges of the screen's usable area.
    static let margin: CGFloat = 20
    /// The target looks this far ahead along the throw.
    static let lookAhead: CGFloat = 0.5
    /// The spring that moves the panel: critically damped (no bounce), done in about 0.35 seconds.
    static let stiffness: CGFloat = 25

    struct Sample {
        var time: TimeInterval
        var point: NSPoint
    }

    /// The pointer's speed at the release, from its moves in the `speedWindow` before its last
    /// move. The release itself is no move (it comes at the last move's position).
    static func velocity(_ samples: [Sample], releasedAt time: TimeInterval) -> CGVector {
        guard let lastMove = samples.indices.last(where: { $0 > 0 && samples[$0].point != samples[$0 - 1].point }),
              time - samples[lastMove].time <= longestStop else { return .zero }
        let last = samples[lastMove]
        guard let first = samples[...lastMove].first(where: { last.time - $0.time <= speedWindow }),
              last.time - first.time > 0.008 else { return .zero }
        let duration = CGFloat(last.time - first.time)
        return CGVector(dx: (last.point.x - first.point.x) / duration, dy: (last.point.y - first.point.y) / duration)
    }

    /// Where a throw at `velocity` sends a panel with `frame`, or nil when the drag is not a throw.
    /// `dragged` is the distance from the press to the release. `area` is the screen's usable area.
    /// The panel goes to the side where its center would be after `lookAhead`. Vertically it goes
    /// to the point after `lookAhead`, pulled two thirds of the way to the middle of the screen.
    static func target(frame: NSRect, velocity: CGVector, dragged: CGFloat, area visibleFrame: NSRect) -> NSPoint? {
        guard hypot(velocity.dx, velocity.dy) >= minimumSpeed, dragged >= minimumDistance else { return nil }
        let area = visibleFrame.insetBy(dx: margin, dy: margin)
        guard area.width >= frame.width, area.height >= frame.height else { return nil }
        let ahead = frame.midX + velocity.dx * lookAhead
        let x = ahead < area.midX ? area.minX : area.maxX - frame.width
        let middle = area.midY - frame.height / 2
        let y = (2 * middle + frame.minY + velocity.dy * lookAhead) / 3
        return NSPoint(x: x, y: min(max(y, area.minY), area.maxY - frame.height))
    }

    /// The offset from the target at `elapsed` seconds, for a start offset and a start speed on one
    /// axis. The start speed toward the target is limited, so the panel does not pass the target.
    static func offset(from start: CGFloat, speed: CGFloat, elapsed: CGFloat) -> CGFloat {
        let limit = stiffness * abs(start)
        let towardTarget = speed * start < 0
        let speed = towardTarget ? max(-limit, min(limit, speed)) : speed
        return (start + (speed + stiffness * start) * elapsed) * exp(-stiffness * elapsed)
    }
}

extension QuickChatPanel {
    /// Moves the panel with the pointer from the current press until its release, and throws the
    /// panel if the drag ends fast. Returns the release event, or nil when the press has already
    /// ended. The page reports a press a moment after it happens, so the drag starts from the
    /// press itself (its time and position), and it also takes the moves and the release that
    /// wait in the event queue.
    @discardableResult
    func trackDrag() -> NSEvent? {
        stopThrow()
        // The press is still on: the button is down, or its release waits in the queue.
        guard let press = leftPress, NSEvent.pressedMouseButtons & 1 == 1 ||
                nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .eventTracking, dequeue: false) != nil
        else { return nil }
        let start = press.point
        let origin = frame.origin
        var samples = [press]
        while let event = nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture,
                                    inMode: .eventTracking, dequeue: true) {
            // Where the pointer was at the time of the event (the pointer can be further on now).
            let point = Self.screenPoint(of: event) ?? NSEvent.mouseLocation
            samples.append(PanelThrow.Sample(time: event.timestamp, point: point))
            if event.type == .leftMouseUp {
                leftPress = nil
                let velocity = PanelThrow.velocity(samples, releasedAt: event.timestamp)
                let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? self.screen
                if !isMaximized, let area = screen?.visibleFrame,
                   let target = PanelThrow.target(frame: frame, velocity: velocity,
                                                  dragged: hypot(point.x - start.x, point.y - start.y), area: area) {
                    startThrow(to: target, velocity: velocity)
                }
                return event
            }
            setFrameOrigin(belowMenuBar(NSPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y), pointer: point))
        }
        return nil
    }

    /// The event's position in screen coordinates (origin at the bottom left of the main screen).
    static func screenPoint(of event: NSEvent) -> NSPoint? {
        guard let location = event.cgEvent?.location, let height = NSScreen.screens.first?.frame.maxY else { return nil }
        return NSPoint(x: location.x, y: height - location.y)
    }

    /// Like a system window drag: the top edge stays below the menu bar of the pointer's screen.
    private func belowMenuBar(_ origin: NSPoint, pointer: NSPoint) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) else { return origin }
        return NSPoint(x: origin.x, y: min(origin.y, screen.visibleFrame.maxY - frame.height))
    }

    private func startThrow(to target: NSPoint, velocity: CGVector) {
        let link = displayLink(target: self, selector: #selector(throwStep(_:)))
        throwMotion = ThrowMotion(target: target, start: CGVector(dx: frame.minX - target.x, dy: frame.minY - target.y),
                                  velocity: velocity, startTime: CACurrentMediaTime(), link: link)
        link.add(to: .main, forMode: .common)
    }

    /// Stops a throw where the panel is now (a new drag, a size change, or a hide).
    func stopThrow() {
        throwMotion?.link.invalidate()
        throwMotion = nil
    }

    @objc private func throwStep(_ link: CADisplayLink) {
        guard let motion = throwMotion else { return link.invalidate() }
        let elapsed = CGFloat(link.targetTimestamp - motion.startTime)
        let dx = PanelThrow.offset(from: motion.start.dx, speed: motion.velocity.dx, elapsed: elapsed)
        let dy = PanelThrow.offset(from: motion.start.dy, speed: motion.velocity.dy, elapsed: elapsed)
        if elapsed > 1 || (abs(dx) < 0.5 && abs(dy) < 0.5) {
            setFrameOrigin(motion.target)
            stopThrow()
        } else {
            setFrameOrigin(NSPoint(x: motion.target.x + dx, y: motion.target.y + dy))
        }
    }
}

/// A throw in progress: the offset from the target and the speed at the release.
struct ThrowMotion {
    var target: NSPoint
    var start: CGVector
    var velocity: CGVector
    var startTime: CFTimeInterval
    var link: CADisplayLink
}
