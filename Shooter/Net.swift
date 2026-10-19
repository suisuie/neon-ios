import Foundation
import Darwin

/// LAN multiplayer over plain UDP — the iOS side of the Android `Net.java` protocol.
///
/// Discovery: client broadcasts "SIQ", host answers "SIA:room:players:max:wave".
/// Session: client "JOIN:name:token" -> host "WEL:id:map"; then binary INPUT packets up and
/// fragmented SNAPSHOT packets down. Host owns the 20 Hz simulation.
///
/// Hotspot note: several Android/iOS hotspot ROMs drop a client→AP unicast until the peer
/// has spoken once, and iOS additionally never delivers an unbound-port reply. So a JOIN is
/// always sent to the target address *and* to every LAN broadcast address, and the host
/// replies to the source address it actually saw the packet arrive from.
enum Net {

    static let PORT: UInt16 = 45454
    /// room capacity: 2v2 teams or five free-for-all sides
    static let MAX_PLAYERS = 5
    static let FRAG = 1080

    static let pktSnap: UInt8 = 0x53   // 'S'
    static let pktInput: UInt8 = 0x02

    static let softDropMs: Int64 = 3500
    static let hardDropMs: Int64 = 180_000

    static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    // ------------------------------------------------------------------ discovery

    struct HostInfo {
        var ip = ""
        var room = "ROOM"
        var players = 0, max = 0, wave = 0
        var isRoom = false
        var ffa = false
        var teamSize = 1
    }

    static func discover(timeoutMs: Int) -> [HostInfo] {
        var out: [HostInfo] = []
        var seen: [String: HostInfo] = [:]
        guard let s = UDPSocket() else { return out }
        defer { s.close() }
        s.broadcast = true
        let addrs = broadcastAddresses()
        let q = Array("SIQ".utf8)
        let end = nowMs() + Int64(timeoutMs)
        var nextSend: Int64 = 0
        while nowMs() < end {
            let now = nowMs()
            if now >= nextSend {
                for a in addrs { s.send(q, to: a) }
                nextSend = now + 350
            }
            guard let pk = s.recv(max: 512, timeoutMs: 150) else { continue }
            guard let msg = String(bytes: pk.data, encoding: .utf8) else { continue }
            if !msg.hasPrefix("SIA:") { continue }
            let f = msg.components(separatedBy: ":")
            if f.count < 5 { continue }
            var h = HostInfo()
            h.ip = Net.ipString(pk.from)
            h.room = f[1]
            guard let players = Int(f[2]), let maxp = Int(f[3]), let wave = Int(f[4]) else { continue }
            h.players = players
            h.max = maxp
            h.wave = wave
            if f.count >= 6 && f[5].hasPrefix("FFA") {
                h.isRoom = true
                h.ffa = true
                h.max = min(h.max, World.ffaMax)
            } else if f.count >= 6 && f[5].hasPrefix("ROOM") {
                h.isRoom = true
                h.teamSize = f[5].count > 4 ? (Int(f[5].dropFirst(4).trimmingCharacters(in: .whitespaces)) ?? 1) : 1
            }
            if seen[h.ip] == nil {
                seen[h.ip] = h
                out.append(h)
            }
        }
        return out
    }

    // ------------------------------------------------------------------ device network

    struct LocalNet {
        /// "lan" (Wi-Fi or hotspot), "mobile" (data only, no hotspot yet) or "none".
        var kind = "none"
        var ip = "0.0.0.0"
        var iface = ""
        var hotspot = false
        func usable() -> Bool { kind == "lan" && ip != "0.0.0.0" }
    }

    static func isPrivate(_ ip: String) -> Bool {
        if ip.hasPrefix("10.") || ip.hasPrefix("192.168.") || ip.hasPrefix("127.") { return true }
        if ip.hasPrefix("172.") {
            let parts = ip.components(separatedBy: ".")
            if parts.count >= 2, let second = Int(parts[1]) { return second >= 16 && second <= 31 }
        }
        return false
    }

    /// Interfaces a phone creates when it shares its own connection as a hotspot.
    static func looksLikeHotspot(_ name: String) -> Bool {
        if name.hasPrefix("ap") || name.hasPrefix("swlan") || name.hasPrefix("softap") { return true }
        return name.range(of: "^wlan[1-9]", options: .regularExpression) != nil
    }

    static func isMobileIface(_ name: String) -> Bool {
        name.hasPrefix("rmnet") || name.hasPrefix("ccmni") || name.hasPrefix("pdp")
            || name.hasPrefix("v4-rmnet") || name.hasPrefix("pdp_ip")
    }

    /// Every (name, ipv4, broadcast) triple of the live non-loopback interfaces.
    static func interfaces() -> [(name: String, ip: String, broadcast: String?)] {
        var out: [(name: String, ip: String, broadcast: String?)] = []
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return out }
        defer { freeifaddrs(addrs) }
        var cur: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cur {
            defer { cur = p.pointee.ifa_next }
            guard let sa = p.pointee.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            guard let ip = ipString(sa, port: false), !ip.hasPrefix("169.254.") else { continue }
            let flags = Int32(p.pointee.ifa_flags)
            if (flags & IFF_UP) == 0 || (flags & IFF_LOOPBACK) != 0 { continue }
            let name = String(cString: p.pointee.ifa_name)
            var bcast: String?
            if (flags & IFF_BROADCAST) != 0, let b = p.pointee.ifa_dstaddr {
                bcast = ipString(b, port: false)
            }
            out.append((name, ip, bcast))
        }
        return out
    }

    static func localNet() -> LocalNet {
        var out = LocalNet()
        var lanIp: String?, lanIf = ""
        var mobIp: String?, mobIf = ""
        var lanPrivate = false
        for it in interfaces() {
            if isMobileIface(it.name) {
                if mobIp == nil { mobIp = it.ip; mobIf = it.name }
                continue
            }
            let priv = isPrivate(it.ip) && !it.ip.hasPrefix("127.")
            let ap = looksLikeHotspot(it.name)
            // prefer a hotspot AP, then any private LAN, then anything else
            let score = (ap ? 2 : 0) + (priv ? 1 : 0)
            let best = (looksLikeHotspot(lanIf) ? 2 : 0) + (lanPrivate ? 1 : 0)
            if lanIp == nil || score > best {
                lanIp = it.ip
                lanIf = it.name
                lanPrivate = priv
            }
        }
        if let ip = lanIp {
            out.kind = "lan"
            out.ip = ip
            out.iface = lanIf
            // on iOS the hotspot AP interface is bridge100/bridge0; on Android ap*/swlan*
            out.hotspot = looksLikeHotspot(lanIf) || lanIf.hasPrefix("bridge")
                || (mobIp != nil && !lanIf.hasPrefix("en0"))
        } else if let ip = mobIp {
            out.kind = "mobile"
            out.ip = ip
            out.iface = mobIf
        }
        return out
    }

    /// LAN broadcast targets. Every interface's own broadcast address is used, so the JOIN
    /// beacon reaches a host that sits behind a hotspot AP as well as one on a normal Wi-Fi.
    static func broadcastAddresses() -> [sockaddr_in] {
        var out: [sockaddr_in] = []
        var seen = Set<UInt32>()
        for it in interfaces() where !isMobileIface(it.name) {
            var target: String?
            if let b = it.broadcast, b != "0.0.0.0", !b.hasPrefix("169.254.") {
                target = b
            } else {
                // no IFF_BROADCAST (common on iOS): derive the subnet broadcast from a /24
                let parts = it.ip.components(separatedBy: ".")
                if parts.count == 4 { target = "\(parts[0]).\(parts[1]).\(parts[2]).255" }
            }
            guard let t = target, let a = UDPSocket.address(t) else { continue }
            if seen.insert(a.sin_addr.s_addr).inserted { out.append(a) }
        }
        if out.isEmpty, let a = UDPSocket.address("255.255.255.255") {
            out.append(a)
        }
        return out
    }

    static func localIp() -> String { localNet().ip }

    /// Short status line for the menu / host banner.
    static func describe() -> String {
        let n = localNet()
        if n.usable() {
            return (n.hotspot ? "热点模式 " : "局域网 ") + n.ip + "  ·  UDP \(PORT)"
        }
        if n.kind == "mobile" {
            return "当前只有流量 " + n.ip + "  ·  开热点后好友连上即可联机"
        }
        return "未联网  ·  开 Wi-Fi 或热点后可以联机"
    }

    static func ipString(_ sa: UnsafeMutablePointer<sockaddr>, port: Bool) -> String? {
        guard sa.pointee.sa_family == sa_family_t(AF_INET) else { return nil }
        return sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { p -> String? in
            var raw = p.pointee.sin_addr.s_addr
            var bytes = [UInt8](repeating: 0, count: 4)
            withUnsafeBytes(of: &raw) { buf in
                for i in 0..<4 { bytes[i] = buf[i] }
            }
            let host = "\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])"
            if port { return "\(host):\(UInt16(bigEndian: p.pointee.sin_port))" }
            return host
        }
    }

    static func ipString(_ addr: sockaddr_in) -> String {
        let raw = addr.sin_addr.s_addr
        var bytes = [UInt8](repeating: 0, count: 4)
        var v = raw
        withUnsafeBytes(of: &v) { buf in
            for i in 0..<4 { bytes[i] = buf[i] }
        }
        return "\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])"
    }

    // ------------------------------------------------------------------ host

    final class Peer {
        var id = 0
        var name = ""
        var addr: sockaddr_in
        var lastSeen: Int64
        /// stable per-install token so a reconnecting client gets its old slot back
        var token = 0
        var online = true

        init(id: Int, name: String, addr: sockaddr_in, port: UInt16, token: Int, now: Int64) {
            self.id = id
            self.name = name
            var a = addr
            a.sin_port = port.bigEndian
            self.addr = a
            self.token = token
            self.lastSeen = now
        }
    }

    final class Host {
        let game: World
        let room: String
        private var sock: UDPSocket?
        private let lock = NSLock()
        private var running = true
        private var outq: [(data: [UInt8], addr: sockaddr_in)] = []
        private var peers: [String: Peer] = [:]
        private var byToken: [Int: Peer] = [:]
        var lastError: String?

        private var seq = 0
        private var nextBroadcast: Int64 = 0
        private var rxThread: Thread?
        private var txThread: Thread?

        init(game: World, room: String) throws {
            self.game = game
            self.room = room
            guard let s = UDPSocket() else { throw NSError(domain: "net", code: 1) }
            guard s.bind(PORT) else { throw NSError(domain: "net", code: 2) }
            s.broadcast = true
            sock = s
        }

        func start() {
            let rx = Thread { [weak self] in self?.rxLoop() }
            rx.stackSize = 512 * 1024
            rx.start()
            rxThread = rx
            let tx = Thread { [weak self] in self?.txLoop() }
            tx.stackSize = 512 * 1024
            tx.start()
            txThread = tx
        }

        private func txLoop() {
            while running {
                var item: (data: [UInt8], addr: sockaddr_in)?
                lock.lock()
                if !outq.isEmpty { item = outq.removeFirst() }
                lock.unlock()
                guard let it = item, let s = sock else {
                    Thread.sleep(forTimeInterval: 0.004)
                    continue
                }
                s.send(it.data, to: it.addr)
            }
        }

        private func send(_ data: [UInt8], _ addr: sockaddr_in) {
            lock.lock()
            if outq.count > 512 { outq.removeAll() }   // never let a dead peer grow the queue
            outq.append((data, addr))
            lock.unlock()
        }

        func playerCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return peers.count + 1
        }

        func ip() -> String { Net.localIp() }

        private func rxLoop() {
            while running {
                guard let s = sock else { break }
                guard let pk = s.recv(max: 2048, timeoutMs: 300) else { continue }
                handle(pk.data, pk.from)
            }
        }

        static func key(_ a: sockaddr_in) -> String {
            "\(Net.ipString(a)):\(UInt16(bigEndian: a.sin_port))"
        }

        private static func sourceAddr(_ ip: String, _ port: UInt16) -> sockaddr_in? {
            guard var a = UDPSocket.address(ip) else { return nil }
            a.sin_port = port.bigEndian
            return a
        }

        private func handle(_ raw: [UInt8], _ from: sockaddr_in) {
            let len = raw.count
            if len <= 0 { return }
            let key = Host.key(from)
            let srcIp = Net.ipString(from)
            let srcPort = UInt16(bigEndian: from.sin_port)
            let head = raw[0]
            if head == Net.pktInput {
                lock.lock()
                let pr = peers[key]
                lock.unlock()
                guard let pr = pr else { return }
                if len >= 8 {
                    pr.lastSeen = Net.nowMs()
                    var wasOffline = false
                    lock.lock()
                    if !pr.online {
                        pr.online = true
                        wasOffline = true
                    }
                    lock.unlock()
                    if wasOffline {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.game.setOnline(pr.id, true)
                            self.game.addBanner(pr.name + " 已重新连接")
                        }
                    }
                    let ys = Int(raw[4]) | (Int(raw[5]) << 8)
                    let yaw = Float(Int16(truncatingIfNeeded: ys)) / 10000
                    var px: Float = 0, pz: Float = 0, py: Float = 0
                    let hasPos = len >= 16
                    if hasPos {
                        let xs = Int16(bitPattern: UInt16(raw[10]) | (UInt16(raw[11]) << 8))
                        let zs = Int16(bitPattern: UInt16(raw[12]) | (UInt16(raw[13]) << 8))
                        let hs = Int16(bitPattern: UInt16(raw[14]) | (UInt16(raw[15]) << 8))
                        px = Float(xs) / 100
                        pz = Float(zs) / 100
                        py = Float(hs) / 100
                    }
                    let mx = Float(Int8(bitPattern: raw[2])) / 127
                    let my = Float(Int8(bitPattern: raw[3])) / 127
                    let pitch = Float(Int8(bitPattern: raw[6])) / 127 * 1.35
                    let flags = raw[7]
                    let stance = len >= 9 ? raw[8] : 0
                    let wpn = len >= 10 ? Int(raw[9]) : 0xff
                    let lean = (stance & 4) != 0 ? -1 : ((stance & 8) != 0 ? 1 : 0)
                    DispatchQueue.main.async { [weak self] in
                        self?.game.applyRemoteInput(pr.id, mx, my, yaw, pitch,
                                                    (flags & 1) != 0, (flags & 2) != 0,
                                                    (stance & 1) != 0, (stance & 2) != 0,
                                                    lean, wpn < 0xf0 ? wpn : -1,
                                                    px, pz, py, hasPos)
                    }
                }
                return
            }
            guard let msg = String(bytes: raw, encoding: .utf8) else { return }
            if msg == "SIQ" {
                let reply = "SIA:\(room):\(playerCount()):\(Net.MAX_PLAYERS):\(game.wave)"
                    + (game.ffa ? ":FFA" : (game.duel ? ":ROOM\(game.teamSize)" : ""))
                if let a = Host.sourceAddr(srcIp, srcPort) {
                    send(Array(reply.utf8), a)
                }
            } else if msg.hasPrefix("JOIN:") {
                let rest = String(msg.dropFirst(5))
                var token = 0
                var name = rest
                if let bar = rest.lastIndex(of: ":"), bar != rest.startIndex {
                    if let t = Int(rest[rest.index(after: bar)...].trimmingCharacters(in: .whitespaces)) {
                        token = t
                        name = String(rest[rest.startIndex..<bar])
                    }
                }
                name = name.trimmingCharacters(in: .whitespaces)
                if name.count > 12 { name = String(name.prefix(12)) }
                if name.isEmpty { name = "PLAYER" }
                guard let replyAddr = Host.sourceAddr(srcIp, srcPort) else { return }
                if token != 0 {
                    lock.lock()
                    let returning = byToken[token]
                    if let back = returning {
                        let stale = peers[key]
                        if let old = stale, old !== back { peers.removeValue(forKey: key) }
                        for (k, v) in peers where v === back { peers.removeValue(forKey: k) }
                        back.addr = replyAddr
                        back.name = name
                        back.lastSeen = Net.nowMs()
                        back.online = true
                        peers[key] = back
                        byToken[token] = back
                        lock.unlock()
                        send(Array("WEL:\(back.id):\(game.mapId)".utf8), replyAddr)
                        broadcastNames()
                        DispatchQueue.main.async { [weak self] in
                            self?.game.setOnline(back.id, true)
                            self?.game.addBanner(back.name + " 已重新连接")
                        }
                        return
                    }
                    lock.unlock()
                }
                lock.lock()
                if let existing = peers[key] {
                    existing.lastSeen = Net.nowMs()
                    existing.online = true
                    if token != 0 {
                        existing.token = token
                        byToken[token] = existing
                    }
                    let id = existing.id
                    lock.unlock()
                    send(Array("WEL:\(id):\(game.mapId)".utf8), replyAddr)
                    return
                }
                if game.players.count >= Net.MAX_PLAYERS {
                    lock.unlock()
                    send(Array("FULL".utf8), replyAddr)
                    return
                }
                var id = -1
                for i in 1..<Net.MAX_PLAYERS {
                    var used = false
                    for p in peers.values where p.id == i { used = true }
                    if !used { id = i; break }
                }
                if id < 0 {
                    lock.unlock()
                    send(Array("FULL".utf8), replyAddr)
                    return
                }
                let peer = Peer(id: id, name: name, addr: replyAddr,
                                port: srcPort, token: token, now: Net.nowMs())
                peers[key] = peer
                if token != 0 { byToken[token] = peer }
                lock.unlock()
                send(Array("WEL:\(id):\(game.mapId)".utf8), replyAddr)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if self.game.playerById(id) == nil {
                        self.game.addPlayer(id, name)
                        self.game.addBanner(name + " 加入战斗")
                    }
                }
                broadcastNames()
            }
        }

        private func broadcastNames() {
            var sb = "NAMES:0:\(Host.sanitize(game.myName))"
            lock.lock()
            let list = Array(peers.values)
            lock.unlock()
            for p in list {
                sb += "|\(p.id):\(Host.sanitize(p.name))"
            }
            let data = Array(sb.utf8)
            for p in list { send(data, p.addr) }
        }

        private static func sanitize(_ s: String) -> String {
            s.replacingOccurrences(of: "|", with: "_").replacingOccurrences(of: ":", with: "_")
        }

        /// Called from the game thread: drop-timers and pending input are already applied.
        func pump(_ now: Int64, _ dt: Float) {
            let soft = now - Net.softDropMs
            let hard = now - Net.hardDropMs
            lock.lock()
            var gone: [Peer] = []
            var offline: [Peer] = []
            for (k, p) in peers {
                if p.lastSeen < hard {
                    peers.removeValue(forKey: k)
                    if p.token != 0 { byToken.removeValue(forKey: p.token) }
                    gone.append(p)
                } else if p.lastSeen < soft && p.online {
                    p.online = false
                    offline.append(p)
                }
            }
            lock.unlock()
            for p in gone {
                game.removePlayer(p.id)
                game.addBanner(p.name + " 离开战斗")
                broadcastNames()
            }
            for p in offline {
                game.setOnline(p.id, false)
                game.addBanner(p.name + " 掉线，等待重连…")
            }
        }

        /// ~30 Hz snapshot fan-out; called from the game thread.
        func broadcast(_ now: Int64) {
            if now < nextBroadcast { return }
            nextBroadcast = now + 33
            lock.lock()
            let list = Array(peers.values)
            lock.unlock()
            if list.isEmpty { return }
            let snap = game.encodeSnapshot()
            if snap.isEmpty { return }
            let cnt = (snap.count + Net.FRAG - 1) / Net.FRAG
            if cnt > 120 { return }
            let s = UInt8(seq & 0xff)
            seq += 1
            for p in list {
                for i in 0..<cnt {
                    let off = i * Net.FRAG
                    let n = min(Net.FRAG, snap.count - off)
                    var pkt = [UInt8](repeating: 0, count: 4 + n)
                    pkt[0] = Net.pktSnap
                    pkt[1] = s
                    pkt[2] = UInt8(i)
                    pkt[3] = UInt8(cnt)
                    for k in 0..<n { pkt[4 + k] = snap[off + k] }
                    send(pkt, p.addr)
                }
            }
        }

        func stop() {
            running = false
            lock.lock()
            outq.removeAll()
            byToken.removeAll()
            lock.unlock()
            sock?.close()
            sock = nil
            rxThread?.cancel()
            txThread?.cancel()
        }
    }

    // ------------------------------------------------------------------ client

    final class Client {
        private var sock: UDPSocket?
        private var host: sockaddr_in?
        private var hostPort: UInt16 = Net.PORT
        private var running = true
        private(set) var connected = false
        private(set) var error: String?
        private(set) var status = ""
        private(set) var myId = -1
        private(set) var mapId = 0
        private var lastRecv: Int64 = 0
        let token: Int = Client.newToken()
        private var name = "PLAYER"
        private var joinBytes: [UInt8]?
        private var rxThread: Thread?
        private var txThread: Thread?
        private var keeperThread: Thread?
        private let lock = NSLock()
        private var outq: [[UInt8]] = []
        private var pending: [UInt8]?
        private var messages: [String] = []
        private var curSeq: Int = -1
        private var frags: [[UInt8]?]?
        private var got = 0, fragCount = 0
        private var outSeq = 0

        private static func newToken() -> Int {
            if let v = UserDefaults.standard.object(forKey: "ns_token") as? Int, v != 0 { return v }
            var t = Int.random(in: 1...Int(Int32.max))
            if t == 0 { t = 12345 }
            UserDefaults.standard.set(t, forKey: "ns_token")
            return t
        }

        private func joinPacket() -> [UInt8] {
            if joinBytes == nil { joinBytes = Array("JOIN:\(Client.clean(name)):\(token)".utf8) }
            return joinBytes!
        }

        func connect(ip: String, name: String, timeoutMs: Int) throws {
            guard let h = UDPSocket.address(ip.trimmingCharacters(in: .whitespaces)) else {
                throw NSError(domain: "net", code: 3, userInfo: [NSLocalizedDescriptionKey: "主机地址无效"])
            }
            host = h
            hostPort = Net.PORT
            self.name = Client.clean(name)
            joinBytes = nil
            guard let s = UDPSocket() else { throw NSError(domain: "net", code: 1) }
            s.broadcast = true
            sock = s
            let join = joinPacket()
            let end = Net.nowMs() + Int64(timeoutMs)
            var welcomed = false
            // Direct unicast is what normally works, but some hotspot/AP chipsets drop a
            // client->AP unicast until the peer has spoken once. Also beacon the JOIN to the
            // LAN broadcast address so the host picks it up either way: this is what makes
            // "friend joins my hotspot" work on those ROMs.
            var joins: [sockaddr_in] = [h]
            for b in Net.broadcastAddresses() where b.sin_addr.s_addr != h.sin_addr.s_addr {
                joins.append(b)
            }
            while Net.nowMs() < end && !welcomed {
                for a in joins { s.send(join, to: a) }
                let waitUntil = min(end, Net.nowMs() + 400)
                while Net.nowMs() < waitUntil {
                    guard let pk = s.recv(max: 2048, timeoutMs: 150) else { break }
                    guard let msg = String(bytes: pk.data, encoding: .utf8) else { continue }
                    if msg.hasPrefix("WEL:") {
                        let f = msg.components(separatedBy: ":")
                        if f.count >= 3, let id = Int(f[1]), let map = Int(f[2]) {
                            myId = id
                            mapId = map
                            welcomed = true
                            break
                        }
                    } else if msg == "FULL" {
                        throw NSError(domain: "net", code: 4,
                                      userInfo: [NSLocalizedDescriptionKey: "房间已满"])
                    }
                }
            }
            if !welcomed {
                throw NSError(domain: "net", code: 5,
                              userInfo: [NSLocalizedDescriptionKey: "连接超时，请确认主机在同一 Wi-Fi 且已开房"])
            }
            connected = true
            lastRecv = Net.nowMs()
            let rx = Thread { [weak self] in self?.rxLoop() }
            rx.stackSize = 512 * 1024
            rx.start()
            rxThread = rx
            let tx = Thread { [weak self] in self?.txLoop() }
            tx.stackSize = 512 * 1024
            tx.start()
            txThread = tx
            let keeper = Thread { [weak self] in self?.keepAlive() }
            keeper.stackSize = 256 * 1024
            keeper.start()
            keeperThread = keeper
        }

        /// Re-JOIN with the same token until the host answers, so the slot is reclaimed.
        private func keepAlive() {
            while running {
                if !connected {
                    if status.isEmpty { status = "重连中…" }
                    if let s = sock, let h = host {
                        let j = joinPacket()
                        s.send(j, to: h)
                        // beacon as well, so a re-JOIN gets through on hotspot links that
                        // swallow unicast until the host has answered at least once
                        for b in Net.broadcastAddresses() where b.sin_addr.s_addr != h.sin_addr.s_addr {
                            s.send(j, to: b)
                        }
                    }
                    Thread.sleep(forTimeInterval: 0.9)
                } else {
                    Thread.sleep(forTimeInterval: 0.4)
                }
            }
        }

        private func txLoop() {
            while running {
                var b: [UInt8]?
                lock.lock()
                if !outq.isEmpty { b = outq.removeFirst() }
                lock.unlock()
                guard let data = b, let s = sock, let h = host else {
                    Thread.sleep(forTimeInterval: 0.004)
                    continue
                }
                var a = h
                a.sin_port = hostPort.bigEndian
                s.send(data, to: a)
            }
        }

        private static func clean(_ s: String) -> String {
            var r = s.replacingOccurrences(of: ":", with: "_")
                .replacingOccurrences(of: "|", with: "_")
                .trimmingCharacters(in: .whitespaces)
            if r.isEmpty { r = "PLAYER" }
            return r.count > 12 ? String(r.prefix(12)) : r
        }

        private func rxLoop() {
            while running {
                guard let s = sock else { break }
                guard let pk = s.recv(max: 2048, timeoutMs: 250) else {
                    if Net.nowMs() - lastRecv > 2500 && connected {
                        connected = false
                        error = "与主机失去连接"
                        status = "重连中…"
                        lock.lock()
                        frags = nil
                        lock.unlock()
                        curSeq = -1
                        got = 0
                    }
                    continue
                }
                lastRecv = Net.nowMs()
                handle(pk.data)
            }
        }

        private func handle(_ d: [UInt8]) {
            let len = d.count
            if len <= 0 { return }
            if d[0] == Net.pktSnap {
                if len < 5 { return }
                let seq = Int(d[1])
                let idx = Int(d[2])
                let cnt = Int(d[3])
                if cnt <= 0 || cnt > 120 { return }
                if seq != curSeq || frags == nil {
                    curSeq = seq
                    frags = [[UInt8]?](repeating: nil, count: cnt)
                    got = 0
                    fragCount = cnt
                }
                if idx < fragCount && frags?[idx] == nil {
                    frags?[idx] = Array(d[4..<len])
                    got += 1
                }
                if got == fragCount, let fr = frags {
                    var full: [UInt8] = []
                    full.reserveCapacity(fr.reduce(0) { $0 + ($1?.count ?? 0) })
                    for f in fr { if let f = f { full.append(contentsOf: f) } }
                    pending = full
                    frags = nil
                    curSeq = -1
                    got = 0
                }
                return
            }
            guard let msg = String(bytes: d, encoding: .utf8) else { return }
            if msg.hasPrefix("WEL:") {
                let f = msg.components(separatedBy: ":")
                if f.count >= 3, let id = Int(f[1]), let map = Int(f[2]) {
                    let again = connected
                    myId = id
                    mapId = map
                    connected = true
                    lastRecv = Net.nowMs()
                    error = nil
                    status = ""
                    frags = nil
                    curSeq = -1
                    got = 0
                    lock.lock()
                    messages.append("REC:\(id):\(again ? 1 : 0)")
                    lock.unlock()
                }
            } else if msg.hasPrefix("NAMES:") || msg.hasPrefix("SIA:") {
                lock.lock()
                messages.append(msg)
                lock.unlock()
            } else if msg == "FULL" {
                status = "房间已满，等待空位…"
            }
        }

        func pollSnapshot() -> [UInt8]? {
            let p = pending
            pending = nil
            return p
        }

        func pollMessage() -> String? {
            lock.lock()
            defer { lock.unlock() }
            if messages.isEmpty { return nil }
            return messages.removeFirst()
        }

        func sendInput(_ mx: Float, _ my: Float, _ yaw: Float, _ pitch: Float,
                       _ fire: Bool, _ ads: Bool, _ crouch: Bool, _ jump: Bool) {
            sendInput(mx, my, yaw, pitch, fire, ads, crouch, jump, 0, -1, 0, 0, 0, false)
        }

        func sendInput(_ mx: Float, _ my: Float, _ yaw: Float, _ pitch: Float,
                       _ fire: Bool, _ ads: Bool, _ crouch: Bool, _ jump: Bool,
                       _ leanDir: Int, _ weapon: Int) {
            sendInput(mx, my, yaw, pitch, fire, ads, crouch, jump, leanDir, weapon,
                      0, 0, 0, false)
        }

        /// Full input packet. The client also reports where it actually is, because the host
        /// simulates this avatar from the same input: without the position the host's copy
        /// drifts behind the screen the shooter aims on, so his rounds were aimed from a
        /// spot the host did not know about and nothing ever registered.
        func sendInput(_ mx: Float, _ my: Float, _ yaw: Float, _ pitch: Float,
                       _ fire: Bool, _ ads: Bool, _ crouch: Bool, _ jump: Bool,
                       _ leanDir: Int, _ weapon: Int,
                       _ px: Float, _ pz: Float, _ py: Float, _ hasPos: Bool) {
            if !connected || sock == nil { return }   // keepAlive handles the re-JOIN
            var b = [UInt8](repeating: 0, count: hasPos ? 16 : 10)
            b[0] = Net.pktInput
            b[1] = UInt8(truncatingIfNeeded: outSeq)
            outSeq += 1
            b[2] = UInt8(truncatingIfNeeded: Int8(max(-1, min(1, mx)) * 127))
            b[3] = UInt8(truncatingIfNeeded: Int8(max(-1, min(1, my)) * 127))
            var wy = yaw.truncatingRemainder(dividingBy: Float.pi * 2)
            if wy > Float.pi { wy -= Float.pi * 2 }
            if wy < -Float.pi { wy += Float.pi * 2 }
            let ys = Int16(max(-3.2, min(3.2, wy)) * 10000)
            b[4] = UInt8(truncatingIfNeeded: ys)
            b[5] = UInt8(truncatingIfNeeded: ys >> 8)
            b[6] = UInt8(truncatingIfNeeded: Int8(max(-1.35, min(1.35, pitch)) / 1.35 * 127))
            b[7] = UInt8((fire ? 1 : 0) | (ads ? 2 : 0))
            b[8] = UInt8((crouch ? 1 : 0) | (jump ? 2 : 0)
                         | (leanDir < 0 ? 4 : 0) | (leanDir > 0 ? 8 : 0))
            b[9] = (weapon < 0 || weapon > 2) ? 0xff : UInt8(weapon)
            if hasPos {
                // centimetre positions keep the packet tiny but the aim spot exact
                let xs = Int16(jround(max(-200, min(200, px)) * 100))
                let zs = Int16(jround(max(-200, min(200, pz)) * 100))
                let hs = Int16(jround(max(0, min(4, py)) * 100))
                b[10] = UInt8(truncatingIfNeeded: xs)
                b[11] = UInt8(truncatingIfNeeded: xs >> 8)
                b[12] = UInt8(truncatingIfNeeded: zs)
                b[13] = UInt8(truncatingIfNeeded: zs >> 8)
                b[14] = UInt8(truncatingIfNeeded: hs)
                b[15] = UInt8(truncatingIfNeeded: hs >> 8)
            }
            lock.lock()
            if outq.count > 64 { outq.removeAll() }   // keep only recent input
            outq.append(b)
            lock.unlock()
        }

        func close() {
            running = false
            connected = false
            lock.lock()
            outq.removeAll()
            lock.unlock()
            txThread?.cancel()
            keeperThread?.cancel()
            sock?.close()
            sock = nil
            rxThread?.cancel()
        }
    }
}

// ---------------------------------------------------------------------- UDP socket

/// Thin BSD UDP socket wrapper: broadcast, bind, poll-based receive and `sendto`.
final class UDPSocket {
    private var fd: Int32 = -1

    init?() {
        fd = socket(AF_INET, SOCK_DGRAM, 0)
        if fd < 0 { return nil }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
    }

    deinit { close() }

    var broadcast: Bool = false {
        didSet {
            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &one, socklen_t(MemoryLayout<Int32>.size))
        }
    }

    func bind(_ port: UInt16) -> Bool {
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        a.sin_addr = in_addr(s_addr: INADDR_ANY)
        let r = withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return r == 0
    }

    static func address(_ ip: String) -> sockaddr_in? {
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = 0
        if inet_pton(AF_INET, ip, &a.sin_addr) != 1 { return nil }
        return a
    }

    func send(_ data: [UInt8], to addr: sockaddr_in) {
        var a = addr
        _ = data.withUnsafeBufferPointer { buf in
            withUnsafePointer(to: &a) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buf.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    /// Poll for `timeoutMs`, then read one datagram. Returns nil on timeout.
    func recv(max: Int, timeoutMs: Int) -> (data: [UInt8], from: sockaddr_in)? {
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let n = poll(&pfd, 1, Int32(timeoutMs))
        if n <= 0 { return nil }
        var buf = [UInt8](repeating: 0, count: max)
        var from = sockaddr_in()
        var flen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let got = withUnsafeMutablePointer(to: &from) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                buf.withUnsafeMutableBufferPointer { b in
                    recvfrom(fd, b.baseAddress, max, 0, $0, &flen)
                }
            }
        }
        if got <= 0 { return nil }
        return (Array(buf[0..<got]), from)
    }

    func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }
}