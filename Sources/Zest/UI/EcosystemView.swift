import SwiftUI

// A curated, private view of the user's Apple devices. You add each device once; Zest shows
// live battery for whichever report it, and a connected or on-Wi-Fi presence for the rest,
// matched by a stable Bluetooth address or a Wi-Fi IP/MAC. No iCloud sign-in, nothing leaves
// the Mac.
struct EcosystemView: View {
    @ObservedObject var state: AppState
    @ObservedObject var config: AppConfig
    @ObservedObject var presence: PresenceService
    @State private var newName = ""
    @State private var newType: EcoDeviceType = .iphone
    @State private var newBT = ""
    @State private var newNet = ""

    init(state: AppState) { self.state = state; self.config = state.config; self.presence = state.presence }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHead(label: "MY ECOSYSTEM")
                Spacer()
                scanMenu
                Button("Add nearby") { addNearby() }.font(.system(size: 11))
            }

            thisMacCard
            ForEach(config.ecosystem) { dev in ecoCard(dev) }

            Divider1()
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Device name (for example, Shanky iPhone)", text: $newName).textFieldStyle(.roundedBorder).font(.system(size: 12))
                    Picker("", selection: $newType) { ForEach(EcoDeviceType.allCases, id: \.self) { Text($0.label).tag($0) } }.frame(width: 110)
                    Button("Add") { addManual() }.font(.system(size: 11))
                }
                HStack(spacing: 8) {
                    TextField("Bluetooth address (optional)", text: $newBT).textFieldStyle(.roundedBorder).font(.system(size: 11))
                    TextField("Wi-Fi IP or MAC (optional)", text: $newNet).textFieldStyle(.roundedBorder).font(.system(size: 11))
                }
            }

            Text("An iPhone or iPad does not report its battery percent to the Mac over Bluetooth or Continuity (only over a USB cable), so Zest instead shows it as connected via its Bluetooth address, or on Wi-Fi via its IP or MAC, and remembers it. AirPods and Magic accessories do report battery. Use Scan Bluetooth to add a paired device with its address filled in. An EID or serial cannot be detected locally, so it is not used.")
                .font(.system(size: 9)).foregroundColor(Theme.ghost).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scanMenu: some View {
        Menu("Scan Bluetooth") {
            if presence.btDevices.isEmpty { Text("No paired devices found") }
            ForEach(presence.btDevices) { d in
                Button("\(d.connected ? "● " : "○ ")\(d.name)") { addFromBT(d) }
            }
        }.font(.system(size: 11)).frame(width: 140)
    }

    private var thisMacCard: some View {
        let s = state.battery.snapshot
        let state2 = s.isCharging ? "charging" : (s.isACPower ? "on adapter" : "on battery")
        return HStack(spacing: 12) {
            Text("💻").font(.system(size: 20))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(macName).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                    Text("This Mac").font(.system(size: 9)).foregroundColor(Theme.faint)
                    Spacer()
                    Text(state2).font(.system(size: 10)).foregroundColor(s.isACPower ? Theme.teal : Theme.faint)
                }
                MeterBar(pct: Double(s.percent), color: Theme.batteryColor(Double(s.percent)), height: 5)
                if let c = s.maxCapacityPercent, let cy = s.cycleCount {
                    Text("\(c)% capacity · \(cy) cycles").font(.system(size: 9)).foregroundColor(Theme.faint)
                }
            }
            Text("\(s.percent)%").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.batteryColor(Double(s.percent))).frame(width: 46, alignment: .trailing)
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.tileBG).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.green.opacity(0.25), lineWidth: 1)))
    }

    private func ecoCard(_ dev: EcoDevice) -> some View {
        let st = status(for: dev)
        return HStack(spacing: 12) {
            Text(dev.type.icon).font(.system(size: 20))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(dev.name).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                    Text(dev.type.label).font(.system(size: 9)).foregroundColor(Theme.faint)
                    Spacer()
                    Text(st.label).font(.system(size: 9)).foregroundColor(st.present ? Theme.teal : Theme.faint)
                }
                MeterBar(pct: Double(st.level ?? 0), color: st.level != nil ? Theme.batteryColor(Double(st.level!)) : (st.present ? Theme.teal.opacity(0.5) : Theme.faint), height: 5)
                if !dev.btAddress.isEmpty || !dev.netID.isEmpty {
                    Text([dev.btAddress.isEmpty ? nil : "BT \(dev.btAddress)", dev.netID.isEmpty ? nil : "net \(dev.netID)"].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 8)).foregroundColor(Theme.ghost)
                }
            }
            if let lvl = st.level { Text("\(lvl)%").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.batteryColor(Double(lvl))).frame(width: 46, alignment: .trailing) }
            else { Text(st.present ? "•" : "--").font(.system(size: 15, weight: .semibold)).foregroundColor(st.present ? Theme.teal : Theme.faint).frame(width: 46, alignment: .trailing) }
            Button(action: { config.ecosystem.removeAll { $0.id == dev.id }; config.save() }) {
                Image(systemName: "xmark.circle.fill").foregroundColor(Theme.faint)
            }.buttonStyle(.plain)
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.tileBG))
    }

    private var macName: String { Host.current().localizedName ?? "This Mac" }

    private struct Status { var level: Int?; var label: String; var present: Bool }

    private func status(for dev: EcoDevice) -> Status {
        // 1. Real battery, if any source reports it.
        if let (lvl, src) = liveBattery(for: dev) { return Status(level: lvl, label: "via \(src)", present: true) }
        // 2. Connected by Bluetooth address.
        if !dev.btAddress.isEmpty && presence.connectedAddresses.contains(dev.btAddress.lowercased()) {
            return Status(level: nil, label: "connected via Bluetooth", present: true)
        }
        // 3. On the local network by IP or MAC.
        if !dev.netID.isEmpty && presence.lanContains(dev.netID) {
            return Status(level: nil, label: "on Wi-Fi", present: true)
        }
        // 4. Name matches a currently connected Bluetooth device.
        if presence.btDevices.contains(where: { $0.connected && matches($0.name, dev.effectiveHint) }) {
            return Status(level: nil, label: "connected via Bluetooth", present: true)
        }
        return Status(level: nil, label: "not connected", present: false)
    }

    private func matches(_ a: String, _ b: String) -> Bool {
        let x = a.lowercased(), y = b.lowercased()
        return x.contains(y) || y.contains(x)
    }

    private func liveBattery(for dev: EcoDevice) -> (level: Int, source: String)? {
        let hint = dev.effectiveHint
        if let d = state.iosDevices.devices.first(where: { matches($0.name, hint) }), let lvl = d.level { return (lvl, "USB") }
        if let d = state.devices.devices.first(where: { matches($0.name, hint) }) { return (d.sortLevel, "Bluetooth") }
        return nil
    }

    private func typeForMinor(_ minor: String) -> EcoDeviceType {
        let m = minor.lowercased()
        if m.contains("phone") { return .iphone }
        if m.contains("pad") { return .ipad }
        if m.contains("watch") { return .watch }
        if m.contains("headphone") || m.contains("headset") || m.contains("airpod") { return .airpods }
        return .other
    }
    private func typeForName(_ name: String) -> EcoDeviceType {
        let n = name.lowercased()
        if n.contains("iphone") { return .iphone }
        if n.contains("ipad") { return .ipad }
        if n.contains("watch") { return .watch }
        if n.contains("airpod") || n.contains("beats") || n.contains("headphone") { return .airpods }
        if n.contains("mac") { return .mac }
        return .other
    }

    private func addManual() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        config.ecosystem.append(EcoDevice(name: n, type: newType,
                                          btAddress: newBT.trimmingCharacters(in: .whitespaces),
                                          netID: newNet.trimmingCharacters(in: .whitespaces)))
        newName = ""; newBT = ""; newNet = ""; config.save()
    }

    private func addFromBT(_ d: PresenceService.BTDevice) {
        if config.ecosystem.contains(where: { $0.btAddress.lowercased() == d.address.lowercased() }) { return }
        config.ecosystem.append(EcoDevice(name: d.name, type: typeForMinor(d.minorType), btAddress: d.address))
        config.save()
    }

    private func addNearby() {
        var addrs = Set(config.ecosystem.map { $0.btAddress.lowercased() }.filter { !$0.isEmpty })
        var names = Set(config.ecosystem.map { $0.name.lowercased() })
        // Bluetooth devices with addresses.
        for d in presence.btDevices where d.connected {
            if !addrs.contains(d.address.lowercased()) && !names.contains(d.name.lowercased()) {
                addrs.insert(d.address.lowercased()); names.insert(d.name.lowercased())
                config.ecosystem.append(EcoDevice(name: d.name, type: typeForMinor(d.minorType), btAddress: d.address))
            }
        }
        // USB iOS devices.
        for d in state.iosDevices.devices where !names.contains(d.name.lowercased()) {
            names.insert(d.name.lowercased())
            config.ecosystem.append(EcoDevice(name: d.name, type: typeForName(d.name)))
        }
        config.save()
    }
}
