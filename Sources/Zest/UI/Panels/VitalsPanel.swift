import SwiftUI

// System Vitals. Runs the original fetch.py at its Ubersicht path (single source of
// truth), then recreates the card: battery arc, CPU/RAM, load bars, sensors, peripherals,
// network + Wi-Fi + the conditional VPN block (vendor detection logic untouched, it
// lives entirely inside fetch.py), speedtest, and the Codex usage block.
struct VitalsPanel: View {
    @ObservedObject var runner: WidgetPanelRunner

    var body: some View {
        let d = JDict(runner.json)
        if d.isEmpty || d.obj("battery").isEmpty {
            LoadingCard(text: "Waiting for first data pull...")
        } else {
            content(d)
        }
    }

    private func content(_ d: JDict) -> some View {
        let cpu = d.obj("cpu"), mem = d.obj("memory"), disk = d.obj("disk")
        let batt = d.obj("battery"), bp = d.obj("battery_power"), bh = d.obj("battery_health")
        let thermal = d.obj("thermal"), sensors = d.obj("sensors"), swap = d.obj("swap")
        let net = d.obj("network"), wifi = d.obj("wifi"), vpn = d.obj("vpn"), speed = d.obj("speedtest")
        let brew = d.obj("brew"), boot = d.obj("boot"), codex = d.obj("codex")
        let bluetooth = d.objArr("bluetooth")
        let bPct = batt.d("percent")
        let bColor = Theme.batteryColor(bPct)

        var arcSub = "ON BATTERY"
        if batt.b("charging") { arcSub = "⚡ CHARGING" }
        else if batt.b("ac_power") && bPct >= 99 { arcSub = "⚡ FULL" }
        else if batt.b("ac_power") { arcSub = "⚡ AT LIMIT" }
        else if !batt.s("time_remaining").isEmpty { arcSub = "\(batt.s("time_remaining")) LEFT" }

        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Badge(text: "SYSTEM VITALS", color: Theme.emerald)
                    if brew.i("count") > 0 { Badge(text: "🍺 \(brew.i("count"))", color: Theme.orange) }
                    Spacer()
                    Text("🕒 booted \(boot.s("display"))").font(.system(size: 10)).foregroundColor(Theme.faint)
                }

                if thermal.b("throttled") {
                    Text("🔥 THERMAL THROTTLING · CPU LIMITED TO \(thermal.i("cpu_limit"))%")
                        .font(.system(size: 10)).foregroundColor(Theme.redSoft)
                        .frame(maxWidth: .infinity).padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.red.opacity(0.12)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.red, lineWidth: 1)))
                }

                ArcGauge(pct: bPct, color: bColor, big: "\(Int(bPct))%", small: arcSub)

                HStack {
                    Text("🔋 usage: \(powerText(bp))").font(.system(size: 10, weight: .semibold)).foregroundColor(drainColor(bp))
                    Spacer()
                    if bh.has("cycles") {
                        Text("\(bh.i("cycles")) cyc · \(bh.i("max_capacity"))% · \(bh.s("condition"))")
                            .font(.system(size: 10)).foregroundColor(Theme.faint)
                    }
                }

                HStack(spacing: 8) {
                    Tile(label: "CPU", value: "\(Int(cpu.d("total")))%", color: cpuColor(cpu.d("total")), sub: "\(Int(cpu.d("user")))u · \(Int(cpu.d("system")))s")
                    Tile(label: "RAM", value: "\(String(format: "%.1f", mem.d("used_gb")))GB", color: ramColor(mem), sub: "\(mem.i("percent"))% · L\(mem.i("pressure"))")
                }

                SectionHead(label: "LOAD")
                BarRow(label: "CPU", right: "\(Int(cpu.d("total")))% (\(Int(cpu.d("idle")))% idle)", pct: cpu.d("total"), color: cpuColor(cpu.d("total")))
                BarRow(label: "RAM \(String(format: "%.1f", mem.d("used_gb"))) / \(String(format: "%.1f", mem.d("total_gb"))) GB", right: "\(mem.i("percent"))%", pct: mem.d("percent"), color: ramColor(mem))
                BarRow(label: "Disk \(String(format: "%.1f", disk.d("used_gb"))) / \(String(format: "%.1f", disk.d("total_gb"))) GB", right: "\(disk.i("percent"))%", pct: disk.d("percent"), color: diskColor(disk.d("percent")))
                if swap.d("used_gb") >= 0.5 {
                    BarRow(label: "Swap \(String(format: "%.1f", swap.d("used_gb"))) GB", right: "in use", pct: min(100, swap.d("used_gb") * 10), color: Theme.orange)
                }

                if sensors.has("temps") || sensors.has("fans") {
                    SectionHead(label: "SENSORS")
                    HStack {
                        let temps = sensors.obj("temps")
                        if temps.has("cpu") { Text("🌡️ CPU \(String(format: "%.1f", temps.d("cpu")))°C").font(.system(size: 11)).foregroundColor(Theme.textVitals) }
                        if temps.has("gpu") { Text("GPU \(String(format: "%.1f", temps.d("gpu")))°C").font(.system(size: 11)).foregroundColor(Theme.textVitals) }
                        Spacer()
                        let fans = sensors.objArr("fans")
                        if !fans.isEmpty {
                            Text("🌀 " + fans.map { "\($0.i("rpm"))" }.joined(separator: " / ") + " RPM").font(.system(size: 10)).foregroundColor(Theme.dim)
                        }
                    }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelBG))
                }

                if !bluetooth.isEmpty {
                    SectionHead(label: "PERIPHERALS", right: "\(bluetooth.count) connected")
                    ForEach(Array(bluetooth.enumerated()), id: \.offset) { _, dev in
                        VitalsDeviceRow(dev: dev)
                    }
                }

                SectionHead(label: "NETWORK")
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle().fill(net.s("status") == "UP" ? Theme.green : Theme.red).frame(width: 8, height: 8)
                        Text(net.s("interface")).font(.system(size: 11)).foregroundColor(Theme.textVitals)
                        Text("(\(net.s("iface")))").font(.system(size: 10)).foregroundColor(Theme.faint)
                        Spacer()
                        Text(net.s("ip")).font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.dim)
                    }
                    if !wifi.isEmpty && wifi.has("ssid") {
                        HStack {
                            Text("📶 \(wifi.s("ssid"))").font(.system(size: 10)).foregroundColor(Theme.textVitals)
                            Spacer()
                            Text("\(rssiLabel(wifi["rssi"])) · \(wifi.has("rssi") ? "\(wifi.i("rssi")) dBm" : "--")").font(.system(size: 10)).foregroundColor(rssiColor(wifi["rssi"]))
                        }
                    }
                    HStack {
                        Text("↓ \(rate(net.d("down_kbs")))").font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.teal)
                        Spacer()
                        Text("↑ \(rate(net.d("up_kbs")))").font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.pink)
                    }
                    if !speed.isEmpty {
                        HStack {
                            Text("Speedtest").font(.system(size: 10)).foregroundColor(Theme.faint)
                            Spacer()
                            Text("\(String(format: "%.0f", speed.d("down_mbps")))↓ / \(String(format: "%.0f", speed.d("up_mbps")))↑ Mbps · \(String(format: "%.0f", speed.d("ping_ms")))ms").font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.dim)
                        }
                    }
                    if !vpn.isEmpty {
                        Divider1()
                        HStack {
                            Text("🔒 \(vpn.s("app"))").font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.purple)
                            Spacer()
                            Text("via \(vpn.s("iface"))").font(.system(size: 10)).foregroundColor(Theme.faint)
                        }
                        HStack {
                            Text("\(vpn.s("city").isEmpty ? "" : vpn.s("city") + ", ")\(vpn.s("country"))").font(.system(size: 10)).foregroundColor(Theme.dim)
                            Spacer()
                            Text(vpn.s("ip")).font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.faint)
                        }
                        if !vpn.s("org").isEmpty { Text(vpn.s("org")).font(.system(size: 9)).foregroundColor(Theme.faint).lineLimit(1) }
                    }
                }.padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelBG))

                if !codex.isEmpty && (codex.d("todayTok") > 0 || codex.d("lifeTok") > 0) {
                    SectionHead(label: "CODEX", right: "GPT")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(Fmt.tokens(codex.d("todayTok"))).font(.system(size: 20, weight: .semibold)).foregroundColor(Theme.textVitals)
                            Text("today").font(.system(size: 10)).tracking(1.2).foregroundColor(Theme.dim)
                            Spacer()
                            Text(Fmt.money(codex.d("todayCost"))).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.green)
                        }
                        Divider1()
                        HStack {
                            Text("lifetime \(Fmt.tokens(codex.d("lifeTok")))").font(.system(size: 10)).foregroundColor(Theme.faint)
                            Spacer()
                            Text(Fmt.money(codex.d("lifeCost"))).font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.faint)
                        }
                    }.padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelBG))
                }
            }
        }
        .frame(width: 344)
        .frame(maxHeight: 720)
    }

    private func powerText(_ bp: JDict) -> String {
        switch bp.s("state") {
        case "charging": return "\(String(format: "%.1f", bp.d("watts")))W charging"
        case "discharging": return "\(String(format: "%.1f", bp.d("watts")))W drain"
        case "idle": return "\(String(format: "%.1f", bp.d("watts")))W idle"
        default: return ""
        }
    }
    private func drainColor(_ bp: JDict) -> Color {
        if bp.isEmpty { return Theme.faint }
        if bp.s("state") == "charging" { return Theme.teal }
        if bp.s("state") == "idle" { return Theme.faint }
        let w = bp.d("watts"); if w >= 15 { return Theme.red }; if w >= 8 { return Theme.orange }; return Theme.green
    }
    private func cpuColor(_ p: Double) -> Color { p < 40 ? Theme.green : p < 70 ? Theme.orange : Theme.red }
    private func ramColor(_ m: JDict) -> Color {
        let pr = m.i("pressure"), pct = m.d("percent")
        if pr >= 4 { return Theme.red }; if pr >= 2 || pct >= 80 { return Theme.orange }; return Theme.blue
    }
    private func diskColor(_ p: Double) -> Color { p > 85 ? Theme.red : p > 70 ? Theme.orange : Theme.purple }
    private func rate(_ kbs: Double) -> String {
        if kbs >= 1024 { return String(format: "%.1f MB/s", kbs/1024) }
        if kbs >= 10 { return "\(Int(kbs)) KB/s" }
        if kbs >= 1 { return String(format: "%.1f KB/s", kbs) }
        return "0 KB/s"
    }
    private func rssiLabel(_ v: Any?) -> String {
        guard let r = (v as? Int) ?? (v as? Double).map(Int.init) else { return "--" }
        if r >= -50 { return "Excellent" }; if r >= -60 { return "Good" }; if r >= -70 { return "Fair" }; if r >= -80 { return "Weak" }; return "Poor"
    }
    private func rssiColor(_ v: Any?) -> Color {
        guard let r = (v as? Int) ?? (v as? Double).map(Int.init) else { return Theme.dim }
        if r >= -60 { return Theme.green }; if r >= -75 { return Theme.orange }; return Theme.red
    }
}

struct VitalsDeviceRow: View {
    let dev: JDict
    var body: some View {
        let name = dev.s("name")
        let hasStereo = dev.has("left") || dev.has("right") || dev.has("case")
        return Group {
            if hasStereo {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(icon(name)); Text(name).font(.system(size: 11)).foregroundColor(Theme.textVitals) }
                    HStack(spacing: 8) {
                        ForEach(["left", "right", "case"].filter { dev.has($0) }, id: \.self) { k in
                            let v = dev.d(k)
                            VStack(spacing: 3) {
                                HStack { Text(k == "left" ? "L" : k == "right" ? "R" : "Case").font(.system(size: 10)).foregroundColor(Theme.dim); Spacer(); Text("\(Int(v))%").font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.batteryColor(v)) }
                                MeterBar(pct: v, color: Theme.batteryColor(v), height: 4)
                            }
                        }
                    }
                }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelBG))
            } else {
                let pct = dev.d("battery")
                HStack(spacing: 10) {
                    Text(icon(name))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(name).font(.system(size: 11)).foregroundColor(Theme.textVitals).lineLimit(1)
                        MeterBar(pct: pct, color: Theme.batteryColor(pct), height: 4)
                    }
                    Text(dev.has("battery") ? "\(Int(pct))%" : "--").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.batteryColor(pct)).frame(width: 42, alignment: .trailing)
                }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelBG))
            }
        }
    }
    private func icon(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpod") || n.contains("beats") || n.contains("headphone") || n.contains("headset") { return "🎧" }
        if n.contains("keyboard") || n.contains(" kb") { return "⌨️" }
        if n.contains("trackpad") { return "👆" }
        if n.contains("mouse") || n.contains("mx master") || n.contains("logi") { return "🖱️" }
        if n.contains("iphone") { return "📱" }
        if n.contains("ipad") { return "📲" }
        if n.contains("watch") { return "⌚" }
        return "🔗"
    }
}
