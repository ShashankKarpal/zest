import AppKit

// Resolves an app's real icon from its display name by matching running applications, so the
// significant-energy list can look like the macOS battery menu.
enum AppIcon {
    static func image(for name: String) -> NSImage? {
        let apps = NSWorkspace.shared.runningApplications
        let target = name.lowercased()
        if let exact = apps.first(where: { ($0.localizedName ?? "").lowercased() == target }) { return exact.icon }
        if let fuzzy = apps.first(where: {
            let n = ($0.localizedName ?? "").lowercased()
            return !n.isEmpty && (n.contains(target) || target.contains(n))
        }) { return fuzzy.icon }
        return nil
    }

    // A category SF Symbol for processes with no running-app icon (daemons, kernel, scripts),
    // so every row has a meaningful glyph instead of a blank box.
    static func fallbackSymbol(for name: String) -> String {
        let n = name.lowercased()
        if n == "zest" { return "battery.100.bolt" }
        if n.contains("windowserver") || n.contains("dock") || n.contains("controlcenter") { return "macwindow" }
        if n == "kernel_task" || n == "launchd" || n.contains("kernel") { return "cpu" }
        if n.contains("python") || n.contains("node") || n.contains("ruby") || n.contains("perl") || n.contains("java") { return "terminal" }
        if n.contains("chrome") || n.contains("safari") || n.contains("firefox") || n.contains("arc") || n.contains("browser") { return "globe" }
        // daemons / agents: lowercase service-like names
        if n.contains("agent") || n.contains("daemon") || n.contains("helper") || n.contains("service") || (n == n.lowercased() && !n.contains(" ") && n.hasSuffix("d")) { return "gearshape" }
        return "app"
    }
}
