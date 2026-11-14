// Screen checks of a chat page with Quick Chat's page style. Used by the daily page check
// (scripts/check-page-hooks.swift) and by the page style check (scripts/check-page-style.swift).
//
// The hook checks find a missing attribute. They do not find a new element that ChatGPT adds,
// such as a button in the title bar or a dark band behind the composer. These checks look at
// the pixels instead: some areas of the panel must show only the panel's material, so the page
// must draw nothing there. When the page draws in such an area, the check names the elements
// that draw there and saves an image of the area with the drawn pixels in red.
import AppKit
import WebKit

@MainActor
enum PageVisualCheck {
    struct Area {
        let id: String
        let name: String
        /// In CSS pixels.
        let rect: CGRect
    }

    struct Finding {
        let area: Area
        let drawnPixels: Int
        let share: Double
        /// One line for each element that draws in the area.
        let painters: [String]
        /// The file name of the marked image, in the output folder.
        let image: String?
    }

    /// A pixel counts as drawn when it is more than 10 % opaque.
    nonisolated static let alphaLimit: UInt8 = 26
    /// An area fails when more pixels than this (in CSS pixels) are drawn. The smallest icon has
    /// about 60.
    static let pixelLimit = 40
    /// Pixels at the edges of an area do not count: borders and anti-aliasing.
    static let edge: CGFloat = 3

    /// The page must be transparent where it draws nothing, as in the panel.
    static func prepare(_ web: WKWebView) {
        web.setValue(false, forKey: "drawsBackground")
        web.underPageBackgroundColor = .clear
    }

    /// The areas of the rendered chat page that must be empty, as JSON: the title bar, the
    /// areas below and beside the composer, and the area above the composer in an empty chat.
    /// None when the page has no chat composer.
    static let areasScript = #"""
        const rendered = selector => [...document.querySelectorAll(selector)].find(e => e.getClientRects().length > 0) ?? null;
        const body = rendered("form[data-chatgpt-composer] [data-composer-body]");
        if (!body || !document.querySelector('[data-app-shell-active-page="true"] form[data-chatgpt-composer]')) return "[]";
        const b = body.getBoundingClientRect();
        const left = Math.max(0, Math.round(rendered("main[data-app-shell-main-surface]")?.getBoundingClientRect().left ?? 0));
        const header = rendered("header[data-app-shell-titlebar]")?.getBoundingClientRect();
        const bar = Math.round(Math.min(Math.max(header?.bottom ?? 52, 0), 64) || 52);
        const width = innerWidth, height = innerHeight;
        const areas = [
            { id: "title-bar", name: "the title bar", x: left, y: 0, w: width - left, h: bar },
            { id: "below-composer", name: "below the composer", x: left, y: b.bottom, w: width - left, h: height - b.bottom },
            { id: "left-of-composer", name: "left of the composer", x: left, y: b.top, w: b.left - left, h: b.height },
            { id: "right-of-composer", name: "right of the composer", x: b.right, y: b.top, w: width - b.right, h: b.height },
        ];
        if (rendered("[data-home-feed-composer]") || rendered('form[data-chatgpt-composer][data-composer-placement="home"]')) {
            areas.push({ id: "above-composer", name: "above the composer in the empty chat", x: left, y: bar, w: width - left, h: b.top - bar });
        }
        return JSON.stringify(areas.filter(a => a.w >= 8 && a.h >= 8));
        """#

    /// The elements that can draw in a rectangle (x, y, w, h in CSS pixels), as JSON:
    /// `{ line, x, y, w, h, pseudo }`. `line` names the element by its tag, attributes and
    /// classes, never by its text. `pseudo`: only its ::before or ::after draws.
    static let paintersScript = #"""
        const rect = { left: x, top: y, right: x + w, bottom: y + h };
        const alpha = color => { const c = document.createElement("canvas").getContext("2d"); c.fillStyle = color; c.fillRect(0, 0, 1, 1); return c.getImageData(0, 0, 1, 1).data[3]; };
        const meets = r => r.width > 0 && r.height > 0 && r.right > rect.left && r.left < rect.right && r.bottom > rect.top && r.top < rect.bottom;
        const shows = e => e.checkVisibility({ opacityProperty: true, visibilityProperty: true });
        const describe = e => {
            const attributes = e.getAttributeNames()
                .filter(n => n.startsWith("data-") || ["id", "role", "aria-label", "aria-hidden", "aria-controls"].includes(n))
                .map(n => { const v = e.getAttribute(n); return v === "" || v === "true" ? `[${n}]` : `[${n}="${v.slice(0, 40)}"]`; });
            const classes = [...e.classList].slice(0, 4).map(c => "." + c).join("");
            return e.localName + attributes.join("") + classes;
        };
        const short = value => value.length > 90 ? value.slice(0, 90) + "…" : value;
        const paints = (style, prefix) => {
            const found = [];
            if (alpha(style.backgroundColor) > 0) found.push(`${prefix}fill ${style.backgroundColor}`);
            if (style.backgroundImage !== "none") found.push(`${prefix}image ${short(style.backgroundImage)}`);
            if (style.boxShadow !== "none") found.push(`${prefix}shadow`);
            if (["Top", "Right", "Bottom", "Left"].some(s => parseFloat(style["border" + s + "Width"]) > 0 && alpha(style["border" + s + "Color"]) > 0)) found.push(`${prefix}border`);
            return found;
        };
        const lines = [];
        for (const e of document.querySelectorAll("body *")) {
            if (lines.length >= 40) break;
            if (e.closest("svg") && e.localName !== "svg") continue;
            if (!shows(e)) continue;
            const r = e.getBoundingClientRect();
            const style = getComputedStyle(e);
            const found = meets(r) ? paints(style, "") : [];
            if (meets(r) && [...e.childNodes].some(n => n.nodeType === Node.TEXT_NODE && n.data.trim())) found.push("text");
            if (meets(r) && /^(svg|img|canvas|video|iframe|picture)$/.test(e.localName)) found.push(e.localName);
            const own = found.length;
            // ::before and ::after can reach outside their element, so they count when the element
            // is near the rectangle.
            const near = r.right > rect.left - 200 && r.left < rect.right + 200 && r.bottom > rect.top - 200 && r.top < rect.bottom + 200;
            for (const pseudo of ["::before", "::after"]) {
                const p = getComputedStyle(e, pseudo);
                if (!near || p.content === "none" || p.display === "none" || p.visibility === "hidden" || p.opacity === "0") continue;
                found.push(...paints(p, pseudo + " "));
            }
            if (!found.length) continue;
            let parent = e.parentElement;
            while (parent && parent !== document.body && !parent.getAttributeNames().some(n => n.startsWith("data-"))) parent = parent.parentElement;
            const inside = parent && parent !== document.body ? ` inside ${describe(parent).split(".")[0]}` : "";
            lines.push({
                line: `\`${describe(e)}\`${inside} at ${[r.left, r.top].map(Math.round).join(",")} ${Math.round(r.width)}×${Math.round(r.height)}: ${found.join("; ")}`,
                x: r.left, y: r.top, w: r.width, h: r.height, pseudo: own === 0,
            });
        }
        return JSON.stringify(lines);
        """#

    struct Result {
        var findings: [Finding] = []
        /// A dialog of the page was open (see `dialogScript`).
        var note: String?
    }

    /// A dialog of the page (for example ChatGPT's one-time Temporary Chat dialog) covers the
    /// panel. It is the page's own content, not a fault of the style, so the check closes it with
    /// Esc first. 0: no dialog, 1: closed, 2: still open.
    static let dialogScript = #"""
        const open = () => [...document.querySelectorAll('[role="dialog"], [role="alertdialog"], [aria-modal="true"]')]
            .filter(e => e.getClientRects().length > 0 && e.checkVisibility({ opacityProperty: true, visibilityProperty: true }));
        if (!open().length) return 0;
        for (const dialog of open()) {
            dialog.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", code: "Escape", keyCode: 27, bubbles: true, cancelable: true }));
        }
        await new Promise(resolve => setTimeout(resolve, 800));
        return open().length ? 2 : 1;
        """#

    /// Runs the screen checks on the page that `web` shows. Saves a marked image of each failed
    /// area as `<prefix>-<area>.png` in `folder`.
    static func check(_ web: WKWebView, prefix: String, folder: URL?) async -> Result {
        var result = Result()
        switch try? await web.callAsyncJavaScript(dialogScript, arguments: [:], in: nil, contentWorld: .page) as? Int {
        case 1: result.note = "A dialog of the page was open. The check closed it with Esc."
        case 2:
            result.note = "A dialog of the page stayed open after Esc, so the screen checks did not run."
            return result
        default: break
        }
        guard let json = try? await web.callAsyncJavaScript(areasScript, arguments: [:], in: nil, contentWorld: .page) as? String,
              let list = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]], !list.isEmpty,
              let image = try? await web.takeSnapshot(configuration: nil),
              let pixels = Pixels(image) else { return result }
        let areas = list.compactMap { item -> Area? in
            guard let id = item["id"] as? String, let name = item["name"] as? String,
                  let x = item["x"] as? Double, let y = item["y"] as? Double,
                  let w = item["w"] as? Double, let h = item["h"] as? Double else { return nil }
            return Area(id: id, name: name, rect: CGRect(x: x, y: y, width: w, height: h))
        }
        for area in areas {
            let inner = area.rect.insetBy(dx: edge, dy: edge)
            guard inner.width > 0, inner.height > 0 else { continue }
            let drawn = pixels.drawn(in: inner)
            let limit = Int(Double(pixelLimit) * pixels.scale * pixels.scale)
            guard drawn > limit else { continue }
            let total = Double(inner.width * inner.height) * pixels.scale * pixels.scale
            let raw = try? await web.callAsyncJavaScript(paintersScript, arguments: [
                "x": inner.minX, "y": inner.minY, "w": inner.width, "h": inner.height,
            ], in: nil, contentWorld: .page) as? String
            // The elements that draw most in the area come first. An element counts only the drawn
            // pixels in its own box, so an element that the page hides (for example a message
            // under the mask) drops out. ::before and ::after can be outside the box, so for them
            // the whole area counts.
            let candidates = (raw.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [[String: Any]]) ?? []
            let painters = candidates.compactMap { item -> (String, Int)? in
                guard let line = item["line"] as? String else { return nil }
                if item["pseudo"] as? Bool == true { return (line, drawn) }
                let box = CGRect(x: item["x"] as? Double ?? 0, y: item["y"] as? Double ?? 0,
                                 width: item["w"] as? Double ?? 0, height: item["h"] as? Double ?? 0).intersection(inner)
                let count = box.isNull ? 0 : pixels.drawn(in: box)
                return count > 0 ? (line, count) : nil
            }.enumerated().sorted { ($0.element.1, -$0.offset) > ($1.element.1, -$1.offset) }.prefix(12).map(\.element.0)
            var file: String?
            if let folder, let png = pixels.markedImage(of: area.rect) {
                file = "\(prefix)-\(area.id).png"
                try? png.write(to: folder.appendingPathComponent(file!))
            }
            result.findings.append(Finding(area: area, drawnPixels: drawn, share: Double(drawn) / total, painters: Array(painters), image: file))
        }
        return result
    }

    /// The page as it shows in the panel: on a gray like the panel's material.
    static func panelImage(_ web: WKWebView) async -> Data? {
        guard let image = try? await web.takeSnapshot(configuration: nil), let pixels = Pixels(image) else { return nil }
        return pixels.markedImage(of: CGRect(origin: .zero, size: image.size), marks: false)
    }

    /// The snapshot's pixels as 8-bit RGBA (premultiplied), first row at the top.
    @MainActor struct Pixels {
        let width: Int, height: Int, scale: Double
        let data: [UInt8]

        init?(_ image: NSImage) {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), image.size.width > 0 else { return nil }
            let width = cg.width, height = cg.height
            self.width = width
            self.height = height
            scale = Double(cg.width) / image.size.width
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = buffer.withUnsafeMutableBytes { bytes -> Bool in
                guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            data = buffer
        }

        private func box(_ rect: CGRect) -> (Int, Int, Int, Int) {
            let x0 = max(0, Int((rect.minX * scale).rounded())), x1 = min(width, Int((rect.maxX * scale).rounded()))
            let y0 = max(0, Int((rect.minY * scale).rounded())), y1 = min(height, Int((rect.maxY * scale).rounded()))
            return (x0, x1, y0, y1)
        }

        func drawn(in rect: CGRect) -> Int {
            let (x0, x1, y0, y1) = box(rect)
            var count = 0
            for y in stride(from: y0, to: y1, by: 1) {
                for x in stride(from: x0, to: x1, by: 1) where data[(y * width + x) * 4 + 3] > PageVisualCheck.alphaLimit { count += 1 }
            }
            return count
        }

        /// A PNG of `rect` on the panel's gray. With `marks`, a second copy below it shows the
        /// drawn pixels in red.
        func markedImage(of rect: CGRect, marks: Bool = true) -> Data? {
            let (x0, x1, y0, y1) = box(rect)
            let w = x1 - x0, h = y1 - y0
            guard w > 0, h > 0 else { return nil }
            let gap = marks ? max(4, Int(4 * scale)) : 0
            let outHeight = marks ? h * 2 + gap : h
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: outHeight, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: w * 4, bitsPerPixel: 32), let out = rep.bitmapData else { return nil }
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let gray: Double = dark ? 0x3a : 0xe8
            for y in 0..<outHeight {
                for x in 0..<w {
                    let o = (y * w + x) * 4
                    var rgb = (gray, gray, gray)
                    if y < h {
                        let i = ((y0 + y) * width + x0 + x) * 4
                        let a = Double(data[i + 3]) / 255
                        rgb = (Double(data[i]) + gray * (1 - a), Double(data[i + 1]) + gray * (1 - a), Double(data[i + 2]) + gray * (1 - a))
                    } else if y >= h + gap {
                        let i = ((y0 + y - h - gap) * width + x0 + x) * 4
                        rgb = data[i + 3] > PageVisualCheck.alphaLimit ? (255, 40, 40) : (20, 20, 20)
                    } else {
                        rgb = (128, 128, 128)
                    }
                    out[o] = UInt8(min(255, rgb.0)); out[o + 1] = UInt8(min(255, rgb.1)); out[o + 2] = UInt8(min(255, rgb.2)); out[o + 3] = 255
                }
            }
            return rep.representation(using: .png, properties: [:])
        }
    }
}
