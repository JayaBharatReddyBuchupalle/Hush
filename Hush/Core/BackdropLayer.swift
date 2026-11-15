import AppKit
import QuartzCore

// ⚠️ Private-API territory: CABackdropLayer and CAFilter.
// Everything is resolved at runtime and every key is checked before it is written, because an unknown
// key path on these classes raises an Objective-C exception. Re-verify on each macOS release
// (Settings › Debug › Layer tree prints what the running system provides).
//
// Why "Path B" (our own backdrop layer) rather than tuning NSVisualEffectView ("Path A"):
// on macOS 27 with Reduce Transparency on, NSVisualEffectView collapses to a flat fill and exposes
// no backdrop layer at all, while a CABackdropLayer we own still blurs. With it off, both work,
// and owning the layer gives us the whole filter chain (blur, variable blur, saturation).

enum PrivateCA {
    static let backdropClass: CALayer.Type? = NSClassFromString("CABackdropLayer") as? CALayer.Type
    private static let filterClass: AnyClass? = NSClassFromString("CAFilter")

    /// Creates a private CAFilter such as "gaussianBlur" or "colorSaturate"; nil if unavailable.
    static func filter(_ type: String) -> NSObject? {
        guard let cls = filterClass else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        guard (cls as AnyObject).responds(to: selector),
              let made = (cls as AnyObject).perform(selector, with: type) else { return nil }
        return made.takeUnretainedValue() as? NSObject
    }

    static func inputKeys(of filter: NSObject) -> Set<String> {
        guard filter.responds(to: NSSelectorFromString("inputKeys")) else { return [] }
        return Set((filter.value(forKey: "inputKeys") as? [String]) ?? [])
    }

    /// Sets a filter input only if the filter declares it.
    @discardableResult
    static func set(_ filter: NSObject, _ key: String, _ value: Any) -> Bool {
        guard inputKeys(of: filter).contains(key) else { return false }
        filter.setValue(value, forKey: key)
        return true
    }

    /// Sets a layer property only if the layer responds to its setter.
    static func setLayer(_ layer: CALayer, _ key: String, _ value: Any) {
        let setter = "set" + key.prefix(1).uppercased() + key.dropFirst() + ":"
        guard layer.responds(to: NSSelectorFromString(setter)) else { return }
        layer.setValue(value, forKey: key)
    }

    static let isBackdropAvailable: Bool = {
        guard backdropClass != nil, let blur = filter("gaussianBlur") else { return false }
        return inputKeys(of: blur).contains("inputRadius")
    }()

    static let supportsVariableBlur: Bool = {
        guard let f = filter("variableBlur") else { return false }
        let keys = inputKeys(of: f)
        return keys.contains("inputMaskImage") && keys.contains("inputRadius")
    }()

    static let supportsSaturation: Bool = {
        guard let f = filter("colorSaturate") else { return false }
        return inputKeys(of: f).contains("inputAmount")
    }()

    static func makeBackdropLayer() -> CALayer? {
        guard isBackdropAvailable, let cls = backdropClass else { return nil }
        let layer = cls.init()
        setLayer(layer, "windowServerAware", true)   // without it nothing is captured
        layer.name = "hush.backdrop"
        return layer
    }

    /// Rebuilds the backdrop's filter chain. `variableMask` (Ambient) turns the blur into a progressive blur.
    static func configureBackdrop(_ layer: CALayer, radius: CGFloat, saturation: CGFloat,
                                  variableMask: CGImage?, scale: CGFloat) {
        var filters: [NSObject] = []
        if radius > 0.3 {
            if let mask = variableMask, supportsVariableBlur, let vb = filter("variableBlur") {
                set(vb, "inputRadius", radius)
                set(vb, "inputMaskImage", mask)
                set(vb, "inputNormalizeEdges", true)
                filters.append(vb)
            } else if let blur = filter("gaussianBlur") {
                set(blur, "inputRadius", radius)
                set(blur, "inputNormalizeEdges", true)   // avoids dark fringes at screen edges
                filters.append(blur)
            }
        }
        if saturation < 0.999, let sat = filter("colorSaturate") {
            set(sat, "inputAmount", saturation)
            filters.append(sat)
        }
        layer.filters = filters
        setLayer(layer, "scale", scale)
    }

    static func filterSummary(of layer: CALayer) -> String {
        let filters = (layer.filters as? [NSObject] ?? []).map { f -> String in
            let name = (f.value(forKey: "name") as? String) ?? "?"
            var parts: [String] = []
            for key in ["inputRadius", "inputAmount"] where inputKeys(of: f).contains(key) {
                if let v = f.value(forKey: key) { parts.append("\(key)=\(v)") }
            }
            return parts.isEmpty ? name : "\(name)(\(parts.joined(separator: ", ")))"
        }
        return filters.isEmpty ? "[]" : "[" + filters.joined(separator: ", ") + "]"
    }
}

/// Plain-text dump of a layer tree, for Settings › Debug.
func layerTreeDescription(_ layer: CALayer, depth: Int = 0) -> String {
    var line = String(repeating: "  ", count: depth) + NSStringFromClass(type(of: layer))
    if let name = layer.name { line += " \"\(name)\"" }
    line += String(format: " %.0f×%.0f", layer.bounds.width, layer.bounds.height)
    if layer.opacity < 1 { line += String(format: " opacity %.2f", layer.opacity) }
    if layer.isHidden { line += " hidden" }
    if let filters = layer.filters, !filters.isEmpty { line += " filters " + PrivateCA.filterSummary(of: layer) }
    if NSStringFromClass(type(of: layer)) == "CABackdropLayer",
       layer.responds(to: NSSelectorFromString("scale")), let scale = layer.value(forKey: "scale") {
        line += " scale \(scale)"
    }
    if layer.mask != nil { line += " masked" }
    var out = [line]
    for sub in layer.sublayers ?? [] { out.append(layerTreeDescription(sub, depth: depth + 1)) }
    return out.joined(separator: "\n")
}
