import Foundation

/// 3D arena simulation: grid map, box/circle collision, hit-scan shooting, chasing bots,
/// waves and the LAN snapshot format. Ported one-to-one from the Android `World.java` —
/// the grid, the physics and the wire format must stay byte identical so an iPhone and an
/// Android phone can play in the same match (the map and the pickups are never sent, they
/// are regenerated from the same seeded `java.util.Random`).
final class World {

    static let GW = 34, GH = 34
    static let CELL: Float = 2.4
    static let WALL_H: Float = 3.4
    static let CRATE_H: Float = 1.15
    static let EYE: Float = 1.62
    static let CROUCH_EYE: Float = 1.13
    static let JUMP_V: Float = 4.35
    static let GRAVITY: Float = 13.5
    static let scoreLimit = 10
    static let MAX_HP = 100
    static let scoreFfa = 20
    static let ffaMax = 5
    static let RADIUS: Float = 0.42

    static let MAG = 32
    static let FIRE_INTERVAL: Float = 0.108
    static let RELOAD_TIME: Float = 1.45

    // ---------------------------------------------------------------- weapons
    static let wRifle = 0, wSmg = 1, wSniper = 2, weapons = 3
    static let wName = ["步枪", "冲锋枪", "狙击枪"]
    static let wMag = [32, 40, 5]
    static let wInterval: [Float] = [0.108, 0.070, 1.05]
    static let wReload: [Float] = [1.45, 1.70, 2.40]
    static let wBody = [25, 17, 84]
    static let wHead = [46, 29, 150]
    static let wAuto = [true, true, false]
    static let wKick: [Float] = [0.011, 0.0085, 0.062]
    static let SWITCH_TIME: Float = 0.46
    static let SNIPER_HIP_DMG: Float = 0.62
    static let wZoom: [Float] = [15, 12, 40]
    static let wSpreadHip: [Float] = [0.021, 0.030, 0.115]
    static let wSpreadCrouch: [Float] = [0.011, 0.016, 0.085]
    static let wSpreadAds: [Float] = [0.004, 0.0055, 0.0016]
    static let LEAN: Float = 0.42

    static let hrHead = 0, hrChest = 1, hrHip = 2, hrArm = 3, hrLeg = 4
    static let hrMult: [Float] = [1, 1, 0.85, 0.55, 0.62]

    static let solo = 0, host = 1, client = 2
    static let MAPS = 4

    static let mapName = ["霓虹训练场", "沙漠仓库", "寒冰基地", "熔炉工厂"]

    static let HIST = 16
    static let LAG_STEPS = 6
    static let POSBUF = 8
    static let INTERP_MS: Int64 = 80

    static let botType = 3

    static let pkHealth = 0, pkAmmo = 1
    static let PICKUPS = 8

    // ---------------------------------------------------------------- state

    var grid = [UInt8](repeating: 0, count: GW * GH)
    let mapId: Int
    let mode: Int
    var players: [Player] = []
    var enemies: [Enemy] = []
    var sparks: [Spark] = []
    var corpses: [Corpse] = []

    var wave = 0
    var waveTimer: Float = 3.5
    var time: Float = 0
    var myId = 0
    var myName = "玩家"
    var hitT: Float = 0, hurtT: Float = 0, muzzleT: Float = 0, bannerT: Float = 0, killT: Float = 0
    var banner = ""
    var nextEnemyId = 1
    var totalKills = 0
    var duel = false
    var teamSize = 1
    var ffa = false
    var ffaBots = true
    var botRespawnT: Float = 0
    var botTeamT = [Float](repeating: 0, count: ffaMax)
    var winTeam = -1
    var roundT: Float = 0
    weak var sfx: SfxSink?
    var sniperHold = true
    var leanLook = true

    var pkX = [Float](repeating: 0, count: PICKUPS)
    var pkZ = [Float](repeating: 0, count: PICKUPS)
    var pkType = [Int](repeating: 0, count: PICKUPS)
    var pkT = [Float](repeating: 0, count: PICKUPS)
    var pkCount = 0

    private var rnd = JavaRandom(Int64(Date().timeIntervalSince1970 * 1000) &+ Int64.random(in: 0...1_000_000))
    private var spawnRnd = JavaRandom(Int64(Date().timeIntervalSince1970 * 1000) &+ Int64.random(in: 0...1_000_000))
    private var flowCache: [Int: [Int16]] = [:]

    // ---------------------------------------------------------------- entities

    final class Player {
        var id = 0
        var name = "玩家"
        var x: Float = 0, z: Float = 0, vx: Float = 0, vz: Float = 0
        var yaw: Float = 0, pitch: Float = 0
        var mx: Float = 0, my: Float = 0
        var fire = false, ads = false, wantReload = false
        var y: Float = 0, vy: Float = 0
        var crouch = false, wantJump = false, jumpNet = false
        var crouchAmt: Float = 0
        var switchT: Float = 0
        var holdScope = false
        var firePulse: Float = 0
        var pulseUnscope = false
        var hp = 100, mag = World.MAG, kills = 0
        var weapon = World.wRifle
        var mags = [World.wMag[0], World.wMag[1], World.wMag[2]]
        var reloadTotal: Float = World.RELOAD_TIME
        var leanDir = 0
        var lean: Float = 0, leanX: Float = 0, leanZ: Float = 0
        var firePrev = false
        var alive = true
        var deadT: Float = 0, fireCd: Float = 0, reloadT: Float = 0, invuln: Float = 0
        var bob: Float = 0, kick: Float = 0
        var online = true
        var deaths = 0
        var team = 0
        var netKnown = false
        var netX: Float = 0, netZ: Float = 0, netYaw: Float = 0, netPitch: Float = 0
        var posDriven = false
        var histX = [Float](repeating: 0, count: World.HIST)
        var histZ = [Float](repeating: 0, count: World.HIST)
        var histY = [Float](repeating: 0, count: World.HIST)
        var histHead = 0, histFill = 0
        var bufX = [Float](repeating: 0, count: World.POSBUF)
        var bufZ = [Float](repeating: 0, count: World.POSBUF)
        var bufYaw = [Float](repeating: 0, count: World.POSBUF)
        var bufT = [Int64](repeating: 0, count: World.POSBUF)
        var bufHead = 0, bufFill = 0
        var shots = 0, netShots = -1
        var landT: Float = 0
        var stepAcc: Float = 0
        var boltT: Float = 0
        var reloadStage = 0
        var lastX: Float = 0, lastZ: Float = 0
        var lastShot: Float = -10
        var downT: Float = 0
        var hitT: Float = 0
        var hpKnown = false
    }

    final class Corpse {
        var x: Float = 0, z: Float = 0, yaw: Float = 0, t: Float = 0, scale: Float = 1
        var type = 0, team = 0
    }

    final class Enemy {
        var id = 0
        var type = 0
        var x: Float = 0, z: Float = 0, yaw: Float = 0
        var hp = 100, maxHp = 100
        var charge: Float = 0, cool: Float = 0, anim: Float = 0, hitT: Float = 0
        var netX: Float = 0, netZ: Float = 0
        var walk: Float = 0, gait: Float = 0
        var team = -1
        var bufX = [Float](repeating: 0, count: World.POSBUF)
        var bufZ = [Float](repeating: 0, count: World.POSBUF)
        var bufT = [Int64](repeating: 0, count: World.POSBUF)
        var bufHead = 0, bufFill = 0
        var seeT: Float = 0
        var react: Float = 0.35, skill: Float = 0.6
        var memX: Float = 0, memZ: Float = 0, memT: Float = 0
        var strafeDir = 1
        var strafeT: Float = 0
        var burst = 0
        var probeX: Float = 0, probeZ: Float = 0, probeT: Float = 0, unstuckT: Float = 0
        var unstuckDir = 0
        var shots = 0, netShots = -1
        var stepAcc: Float = 0, lastX: Float = 0, lastZ: Float = 0
        var hpKnown = false
        var netYawKnown = false
        var netYaw: Float = 0
        var windT: Float = 0
    }

    final class Spark {
        var x: Float = 0, y: Float = 0, z: Float = 0, life: Float = 0, size: Float = 0
        var color: Int = 0
        var vx: Float = 0, vy: Float = 0, vz: Float = 0, maxLife: Float = 0.35
        var grav = false
    }

    // ---------------------------------------------------------------- palette

    /// Per-map palette as rgb triples: floor, wall, ceiling, neon trim, ceiling lamp,
    /// fog/sky, crate. Shared by the renderer so every map has its own mood.
    static func theme(_ mapId: Int) -> [Float] {
        switch ((mapId % MAPS) + MAPS) % MAPS {
        case 1: return [
            0.30, 0.24, 0.16, 0.36, 0.28, 0.19, 0.12, 0.10, 0.08,
            1.10, 0.70, 0.25, 1.40, 1.20, 0.85, 0.20, 0.16, 0.12,
            0.42, 0.30, 0.16]
        case 2: return [
            0.20, 0.26, 0.31, 0.30, 0.38, 0.46, 0.10, 0.13, 0.17,
            0.45, 0.95, 1.20, 1.10, 1.25, 1.40, 0.16, 0.21, 0.27,
            0.26, 0.34, 0.40]
        case 3: return [
            0.16, 0.14, 0.13, 0.27, 0.20, 0.17, 0.08, 0.06, 0.06,
            1.30, 0.38, 0.12, 1.40, 0.95, 0.60, 0.10, 0.06, 0.05,
            0.30, 0.24, 0.14]
        default: return [
            0.11, 0.14, 0.20, 0.17, 0.21, 0.31, 0.05, 0.065, 0.10,
            0.15, 0.85, 1.00, 1.35, 1.28, 1.00, 0.035, 0.05, 0.09,
            0.33, 0.23, 0.13]
        }
    }

    init(mode: Int, mapId: Int) {
        self.mode = mode
        self.mapId = mapId
        genMap()
        placePickups()
        addBanner("地图 · " + World.mapName[((mapId % World.MAPS) + World.MAPS) % World.MAPS]
            + " · 绿箱回血 黄箱补弹")
    }

    // ---------------------------------------------------------------- map

    private func genMap() {
        var r = JavaRandom(Int64(mapId) * 7919 + 17)
        for x in 0..<World.GW {
            for z in 0..<World.GH {
                let border = x == 0 || z == 0 || x == World.GW - 1 || z == World.GH - 1
                grid[x + z * World.GW] = border ? 1 : 0
            }
        }
        var cx = 3
        while cx <= World.GW - 5 {
            var cz = 3
            while cz <= World.GH - 5 {
                let roll = r.nextInt(100)
                if roll < 34 {
                    for dx in 0..<2 {
                        for dz in 0..<2 { grid[(cx + dx) + (cz + dz) * World.GW] = 1 }
                    }
                } else if roll < 66 {
                    grid[cx + cz * World.GW] = 2
                    grid[(cx + 1) + cz * World.GW] = 2
                } else if roll < 78 {
                    for dx in 0..<3 { grid[(cx + dx) + cz * World.GW] = 1 }
                }
                cz += 4
            }
            cx += 4
        }
        for _ in 0..<46 {
            let px = 2 + r.nextInt(World.GW - 4), pz = 2 + r.nextInt(World.GH - 4)
            if grid[px + pz * World.GW] == 0 && r.nextInt(100) < 55 {
                grid[px + pz * World.GW] = 2
            }
        }
        carveLandmarks()
        for i in 0..<4 {
            let sx = Int(World.spawnX(i) / World.CELL), sz = Int(World.spawnZ(i) / World.CELL)
            for dx in -2...2 {
                for dz in -2...2 {
                    let ix = sx + dx, iz = sz + dz
                    if ix > 0 && iz > 0 && ix < World.GW - 1 && iz < World.GH - 1 {
                        grid[ix + iz * World.GW] = 0
                    }
                }
            }
        }
    }

    private func put(_ x: Int, _ z: Int, _ v: Int) {
        if x > 0 && z > 0 && x < World.GW - 1 && z < World.GH - 1 {
            grid[x + z * World.GW] = UInt8(v)
        }
    }

    /// Each map gets its own centrepiece so the four arenas play differently.
    private func carveLandmarks() {
        let m = ((mapId % World.MAPS) + World.MAPS) % World.MAPS
        let c = World.GW / 2
        if m == 0 {
            for x in (c - 4)...(c + 3) { for z in (c - 4)...(c + 3) { put(x, z, 0) } }
            put(c - 2, c - 2, 2); put(c + 1, c - 2, 2); put(c - 2, c + 1, 2); put(c + 1, c + 1, 2)
        } else if m == 1 {
            var z = 6
            while z < World.GH - 6 {
                for x in 5..<(World.GW - 5) { put(x, z, (x % 7 == 3) ? 0 : 2) }
                z += 6
            }
        } else if m == 2 {
            for i in -5...5 {
                let door = abs(i) <= 1
                if !door {
                    put(c + i, c - 5, 1); put(c + i, c + 5, 1)
                    put(c - 5, c + i, 1); put(c + 5, c + i, 1)
                }
            }
            for x in (c - 4)...(c + 4) { for z in (c - 4)...(c + 4) { put(x, z, 0) } }
            put(c, c, 1); put(c - 1, c, 1); put(c, c - 1, 1); put(c - 1, c - 1, 1)
        } else {
            var i = 4
            while i < World.GW - 4 {
                let gate = (i % 8 == 2) || abs(i - c) <= 1
                put(i, c, gate ? 0 : 1)
                put(c, i, gate ? 0 : 1)
                i += 1
            }
        }
    }

    // ---------------------------------------------------------------- pickups

    /// Deterministic pickup spots so host and client agree without sending positions.
    private func placePickups() {
        var r = JavaRandom(Int64(mapId) * 31337 + 5)
        pkCount = 0
        var tries = 0
        while pkCount < World.PICKUPS && tries < 400 {
            tries += 1
            let px = 3 + r.nextInt(World.GW - 6), pz = 3 + r.nextInt(World.GH - 6)
            if grid[px + pz * World.GW] != 0 { continue }
            let x = (Float(px) + 0.5) * World.CELL, z = (Float(pz) + 0.5) * World.CELL
            var close = false
            for i in 0..<pkCount {
                let dx = pkX[i] - x, dz = pkZ[i] - z
                if dx * dx + dz * dz < 8 * 8 { close = true }
            }
            if !close {
                for i in 0..<4 {
                    let dx = World.spawnX(i) - x, dz = World.spawnZ(i) - z
                    if dx * dx + dz * dz < 6 * 6 { close = true }
                }
            }
            if close { continue }
            pkX[pkCount] = x
            pkZ[pkCount] = z
            pkType[pkCount] = pkCount % 2 == 0 ? World.pkHealth : World.pkAmmo
            pkCount += 1
        }
    }

    private func stepPickups(_ dt: Float) {
        for i in 0..<pkCount {
            if pkT[i] > 0 {
                pkT[i] = max(0, pkT[i] - dt)
                continue
            }
            for p in players {
                if !p.alive || !p.online { continue }
                let dx = p.x - pkX[i], dz = p.z - pkZ[i]
                if dx * dx + dz * dz > 0.9 * 0.9 { continue }
                if pkType[i] == World.pkHealth && p.hp >= 100 { continue }
                grantPickup(p, pkType[i])
                pkT[i] = pkType[i] == World.pkHealth ? 18 : 14
                break
            }
        }
    }

    private func grantPickup(_ p: Player, _ type: Int) {
        if type == World.pkHealth {
            p.hp = min(100, p.hp + 50)
        } else {
            World.refillAmmo(p)
        }
        if p.id == myId {
            addBanner(type == World.pkHealth ? "+50 生命" : "弹药补满")
            sfx?.play(Sound.reload, 0.8, 1.3)
        }
    }

    static func refillAmmo(_ p: Player) {
        for w in 0..<weapons { p.mags[w] = wMag[w] }
        p.mag = wMag[p.weapon]
        p.reloadT = 0
    }

    private func clientPickupSeen(_ i: Int, _ nowTaken: Bool) {
        if !nowTaken || pkT[i] > 0 || pkType[i] != World.pkAmmo { return }
        guard let me = local(), me.alive else { return }
        let dx = me.x - pkX[i], dz = me.z - pkZ[i]
        if dx * dx + dz * dz < 1.3 * 1.3 {
            World.refillAmmo(me)
            addBanner("弹药补满")
            sfx?.play(Sound.reload, 0.8, 1.3)
        }
    }

    func solidHeight(_ cx: Int, _ cz: Int) -> Float {
        if cx < 0 || cz < 0 || cx >= World.GW || cz >= World.GH { return World.WALL_H }
        let v = grid[cx + cz * World.GW]
        if v == 1 { return World.WALL_H }
        if v == 2 { return World.CRATE_H }
        return 0
    }

    static func spawnX(_ i: Int) -> Float {
        return (i == 1 || i == 2) ? (Float(GW) - 3.5) * CELL : 2.5 * CELL
    }

    static func spawnZ(_ i: Int) -> Float {
        return (i >= 2) ? (Float(GH) - 3.5) * CELL : 2.5 * CELL
    }

    // ---------------------------------------------------------------- players

    func playerById(_ id: Int) -> Player? {
        for p in players where p.id == id { return p }
        return nil
    }

    func local() -> Player? {
        if let p = playerById(myId) { return p }
        return players.first
    }

    @discardableResult
    func addPlayer(_ id: Int, _ name: String) -> Player {
        if let p = playerById(id) { return p }
        let p = Player()
        p.id = id
        p.name = name
        p.x = World.spawnX(id % 4)
        p.z = World.spawnZ(id % 4)
        p.yaw = atan2(-p.z + Float(World.GH) * World.CELL / 2, -p.x + Float(World.GW) * World.CELL / 2)
        players.append(p)
        if duel { placeInRoom(p) }
        else if ffa { placeInFfa(p) }
        return p
    }

    func removePlayer(_ id: Int) {
        for i in stride(from: players.count - 1, through: 0, by: -1) where players[i].id == id {
            players.remove(at: i)
        }
    }

    /// A networked player dropped or came back. The slot (id, team, score) is kept either way.
    func setOnline(_ id: Int, _ on: Bool) {
        guard let p = playerById(id) else { return }
        p.online = on
        p.mx = 0
        p.my = 0
        p.fire = false
        p.wantJump = false
        if on {
            p.netKnown = false
            if !p.alive {
                p.alive = true
                p.hp = 100
                p.deadT = 0
                if duel || ffa { respawnAt(p, p.team) }
            }
        }
    }

    func remapLocal(_ newId: Int) {
        if let old = playerById(myId), newId != myId {
            if let clash = playerById(newId) {
                players.removeAll { $0 === clash }
            }
            old.id = newId
        }
        myId = newId
    }

    func reset() {
        players.removeAll()
        enemies.removeAll()
        sparks.removeAll()
        wave = 0
        waveTimer = 2.5
        totalKills = 0
        duel = false
        ffa = false
        winTeam = -1
        botRespawnT = 0
        for i in 0..<botTeamT.count { botTeamT[i] = 0 }
        addPlayer(myId, myName)
    }

    // ---------------------------------------------------------------- rooms

    /// Open the room: bots only fill the empty slots, humans always get priority.
    func enterRoom(_ perSide: Int) {
        duel = true
        ffa = false
        teamSize = max(1, min(2, perSide))
        winTeam = -1
        roundT = 0
        enemies.removeAll()
        botTeamT[0] = 0; botTeamT[1] = 0
        botRespawnT = 1.2
        var used = [0, 0]
        for p in players {
            p.kills = 0
            p.deaths = 0
            p.hp = 100
            p.alive = true
            p.deadT = 0
            p.team = used[0] <= used[1] ? 0 : 1
            used[p.team] += 1
            respawnAt(p, p.team)
        }
        addBanner((teamSize == 1 ? "1v1 单挑房" : "2v2 团队房") + " · 先到 \(World.scoreLimit) 杀获胜")
        sfx?.play(Sound.wave)
    }

    func room() -> Bool { duel || ffa }

    func enterFfa() { enterFfa(ffaBots) }

    func enterFfa(_ bots: Bool) {
        duel = false
        ffa = true
        ffaBots = bots
        teamSize = 1
        winTeam = -1
        roundT = 0
        enemies.removeAll()
        for i in 0..<botTeamT.count { botTeamT[i] = 0 }
        botRespawnT = 1.2
        var used = [Bool](repeating: false, count: World.ffaMax)
        for p in players {
            p.kills = 0
            p.deaths = 0
            p.hp = 100
            p.alive = true
            p.deadT = 0
            p.team = freeSlot(&used, p)
            respawnAt(p, p.team)
        }
        addBanner("混战房 · 各自一队 · " + (bots ? "人机补位 · " : "纯真人 · ")
            + "先到 \(World.scoreFfa) 分获胜")
        sfx?.play(Sound.wave)
    }

    private func freeSlot(_ used: inout [Bool], _ skip: Player?) -> Int {
        for i in 0..<World.ffaMax where !used[i] {
            used[i] = true
            return i
        }
        return players.count % World.ffaMax
    }

    private func placeInFfa(_ p: Player) {
        var used = [Bool](repeating: false, count: World.ffaMax)
        p.team = freeSlot(&used, p)
        p.kills = 0
        p.deaths = 0
        p.hp = 100
        p.alive = true
        respawnAt(p, p.team)
    }

    private func placeInRoom(_ p: Player) {
        var used = [0, 0]
        for q in players where q !== p {
            if q.team == 0 { used[0] += 1 } else if q.team == 1 { used[1] += 1 }
        }
        p.team = used[0] <= used[1] ? 0 : 1
        p.kills = 0
        p.deaths = 0
        p.hp = 100
        p.alive = true
        respawnAt(p, p.team)
    }

    private func respawnAt(_ p: Player, _ team: Int) {
        var mask = 0xf
        if duel { mask = team == 0 ? 0x3 : 0xc }
        let corner = pickCorner(mask)
        spawnSpot(p, corner)
        p.y = 0
        p.vy = 0
        p.crouch = false
        p.crouchAmt = 0
        p.yaw = atan2(-p.z + Float(World.GH) * World.CELL / 2, -p.x + Float(World.GW) * World.CELL / 2)
        p.netX = p.x
        p.netZ = p.z
        p.netYaw = p.yaw
    }

    private func pickCorner(_ mask: Int) -> Int {
        var c: [Int] = []
        for i in 0..<4 where (mask & (1 << i)) != 0 { c.append(i) }
        if c.isEmpty { return spawnRnd.nextInt(4) }
        return c[spawnRnd.nextInt(c.count)]
    }

    private func spawnSpot(_ p: Player, _ corner: Int) {
        let cx = Int(jround(World.spawnX(corner) / World.CELL))
        let cz = Int(jround(World.spawnZ(corner) / World.CELL))
        for _ in 0..<24 {
            let ix = cx + spawnRnd.nextInt(5) - 2
            let iz = cz + spawnRnd.nextInt(5) - 2
            if ix <= 0 || iz <= 0 || ix >= World.GW - 1 || iz >= World.GH - 1 { continue }
            if grid[ix + iz * World.GW] != 0 { continue }
            let x = (Float(ix) + 0.5) * World.CELL, z = (Float(iz) + 0.5) * World.CELL
            var crowded = false
            for q in players where q !== p && q.alive {
                let dx = q.x - x, dz = q.z - z
                if dx * dx + dz * dz < 2.2 * 2.2 { crowded = true; break }
            }
            if crowded { continue }
            p.x = x
            p.z = z
            return
        }
        p.x = World.spawnX(corner)
        p.z = World.spawnZ(corner)
    }

    func teamKills(_ team: Int) -> Int {
        var n = 0
        for p in players where p.team == team { n += p.kills }
        return n
    }

    func humansOn(_ team: Int) -> Int {
        var n = 0
        for p in players where p.team == team { n += 1 }
        return n
    }

    func botsOn(_ team: Int) -> Int {
        var n = 0
        for e in enemies where e.type == World.botType && e.hp > 0 && e.team == team { n += 1 }
        return n
    }

    // ---------------------------------------------------------------- input

    func applyInput(_ id: Int, _ mx: Float, _ my: Float, _ yaw: Float, _ pitch: Float,
                    _ fire: Bool, _ ads: Bool, _ crouch: Bool, _ jump: Bool) {
        guard let p = playerById(id) else { return }
        p.mx = mx
        p.my = my
        p.yaw = yaw
        p.pitch = pitch
        p.fire = fire
        p.ads = ads
        p.crouch = crouch
        if jump { p.wantJump = true }
    }

    func applyInput(_ id: Int, _ mx: Float, _ my: Float, _ yaw: Float, _ pitch: Float,
                    _ fire: Bool, _ ads: Bool, _ crouch: Bool, _ jump: Bool,
                    _ leanDir: Int, _ weaponReq: Int) {
        guard let p = playerById(id) else { return }
        applyInput(id, mx, my, yaw, pitch, fire, ads, crouch, jump)
        p.leanDir = leanDir
        if weaponReq >= 0 && weaponReq < World.weapons && weaponReq != p.weapon {
            World.selectWeapon(p, weaponReq)
        }
    }

    /// Remote input that also carries the sender's own position; the host adopts it so the
    /// rounds it traces start from the very spot the shooter aimed from.
    func applyRemoteInput(_ id: Int, _ mx: Float, _ my: Float, _ yaw: Float, _ pitch: Float,
                          _ fire: Bool, _ ads: Bool, _ crouch: Bool, _ jump: Bool,
                          _ leanDir: Int, _ weaponReq: Int,
                          _ px: Float, _ pz: Float, _ py: Float, _ hasPos: Bool) {
        guard let p = playerById(id) else { return }
        applyInput(id, mx, my, yaw, pitch, fire, ads, crouch, jump)
        p.leanDir = leanDir
        if weaponReq >= 0 && weaponReq < World.weapons && weaponReq != p.weapon {
            World.selectWeapon(p, weaponReq)
        }
        if !hasPos {
            p.posDriven = false
            return
        }
        if px < -1 || pz < -1 || px > Float(World.GW) * World.CELL + 1 || pz > Float(World.GH) * World.CELL + 1 {
            return
        }
        let cx = Int(floor(px / World.CELL)), cz = Int(floor(pz / World.CELL))
        let wasFree = solidHeight(Int(floor(p.x / World.CELL)), Int(floor(p.z / World.CELL))) <= 1.6
        if solidHeight(cx, cz) > 1.6 && wasFree { return }
        let dx = px - p.x, dz = pz - p.z
        if p.posDriven && dx * dx + dz * dz > 36 && p.alive && p.deadT <= 0 { return }
        p.x = px
        p.z = pz
        if py >= 0 && py < 3 { p.y = py }
        p.vx = 0
        p.vz = 0
        p.posDriven = true
    }

    // ---------------------------------------------------------------- update

    func update(_ rawDt: Float) {
        let dt = min(0.05, max(0, rawDt))
        time += dt
        decayFx(dt)
        sampleHistory()

        if mode == World.client {
            if let me = local() { stepPlayer(me, dt, true) }
            lerpRemote(dt)
            return
        }

        for p in players { stepPlayer(p, dt, p.id == myId) }
        stepEnemies(dt)
        stepPickups(dt)
        if duel { stepDuel(dt) }
        else if ffa { stepFfa(dt) }
        else { stepWaves(dt) }
    }

    private func sampleHistory() {
        for p in players {
            p.histX[p.histHead] = p.x
            p.histZ[p.histHead] = p.z
            p.histY[p.histHead] = p.y
            p.histHead = (p.histHead + 1) % World.HIST
            if p.histFill < World.HIST { p.histFill += 1 }
        }
    }

    private static func poseAt(_ xs: [Float], _ zs: [Float], _ yaws: [Float]?, _ ts: [Int64],
                               _ head: Int, _ fill: Int, _ out: inout [Float]) -> Bool {
        if fill < 2 { return false }
        let target = Net.nowMs() - INTERP_MS
        let newest = ((head - 1) % POSBUF + POSBUF) % POSBUF
        if target >= ts[newest] {
            out[0] = xs[newest]
            out[1] = zs[newest]
            if let ya = yaws { out[2] = ya[newest] }
            return true
        }
        if fill >= 2 {
            for i in stride(from: fill - 2, through: 0, by: -1) {
                let a = ((head - fill + i) % POSBUF + POSBUF) % POSBUF
                let b = (a + 1) % POSBUF
                if ts[a] > target { continue }
                let span = ts[b] - ts[a]
                let t: Float = span <= 0 ? 1 : Float(target - ts[a]) / Float(span)
                out[0] = xs[a] + (xs[b] - xs[a]) * t
                out[1] = zs[a] + (zs[b] - zs[a]) * t
                if let ya = yaws {
                    var dy = ya[b] - ya[a]
                    while dy > Float.pi { dy -= Float.pi * 2 }
                    while dy < -Float.pi { dy += Float.pi * 2 }
                    out[2] = ya[a] + dy * t
                }
                return true
            }
        }
        let oldest = ((head - fill) % POSBUF + POSBUF) % POSBUF
        out[0] = xs[oldest]
        out[1] = zs[oldest]
        if let ya = yaws { out[2] = ya[oldest] }
        return true
    }

    private func histAt(_ arr: [Float], _ p: Player, _ steps: Int) -> Float {
        let n = min(steps, max(0, p.histFill - 1))
        let i = ((p.histHead - 1 - n) % World.HIST + World.HIST) % World.HIST
        return arr[i]
    }

    private func decayFx(_ dt: Float) {
        hitT = max(0, hitT - dt)
        hurtT = max(0, hurtT - dt * 1.4)
        muzzleT = max(0, muzzleT - dt)
        bannerT = max(0, bannerT - dt)
        killT = max(0, killT - dt)
        for i in stride(from: corpses.count - 1, through: 0, by: -1) {
            corpses[i].t += dt
            if corpses[i].t > 5 { corpses.remove(at: i) }
        }
        for p in players {
            p.downT = p.alive ? 0 : p.downT + dt
            p.hitT = max(0, p.hitT - dt)
        }
        for i in stride(from: sparks.count - 1, through: 0, by: -1) {
            let s = sparks[i]
            s.life -= dt
            if s.life <= 0 { sparks.remove(at: i); continue }
            if s.vx != 0 || s.vy != 0 || s.vz != 0 {
                if s.grav { s.vy -= 9.8 * dt }
                s.x += s.vx * dt
                s.y += s.vy * dt
                s.z += s.vz * dt
                if s.y < 0.01 && s.vy < 0 {
                    s.y = 0.01
                    s.vy = -s.vy * 0.3
                    s.vx *= 0.5
                    s.vz *= 0.5
                }
                let drag = exp(-dt * 1.5)
                s.vx *= drag
                s.vz *= drag
            }
        }
    }

    private func stepPlayer(_ p: Player, _ dt: Float, _ local: Bool) {
        if !p.online && p.id != myId {
            p.mx = 0
            p.my = 0
            p.fire = false
            p.kick *= exp(-dt * 9)
            return
        }
        if !p.alive {
            p.deadT -= dt
            if p.deadT <= 0 && mode != World.client { respawn(p) }
            return
        }
        p.invuln = max(0, p.invuln - dt)
        p.kick *= exp(-dt * 9)

        let crouchTarget: Float = p.crouch ? 1 : 0
        p.crouchAmt += (crouchTarget - p.crouchAmt) * min(1, dt * 8.5)
        if p.crouchAmt < 0.002 { p.crouchAmt = 0 }
        if p.crouchAmt > 0.998 { p.crouchAmt = 1 }
        if p.switchT > 0 { p.switchT = max(0, p.switchT - dt) }
        if p.firePulse > 0 {
            p.firePulse -= dt
            p.fire = p.firePulse > 0
            if p.firePulse <= 0 && p.pulseUnscope {
                p.ads = false
                p.pulseUnscope = false
            }
        }

        let wi = max(0, min(World.weapons - 1, p.weapon))
        if p.reloadT > 0 {
            p.reloadT -= dt
            let tr = 1 - p.reloadT / max(0.01, p.reloadTotal)
            if local {
                if p.reloadStage == 0 && tr > 0.14 { p.reloadStage = 1; sfx?.play(Sound.magOut) }
                if p.reloadStage == 1 && tr > 0.58 { p.reloadStage = 2; sfx?.play(Sound.magIn) }
                if p.reloadStage == 2 && tr > 0.84 { p.reloadStage = 3; sfx?.play(Sound.bolt, 0.7, 1.1) }
            }
            if p.reloadT <= 0 {
                p.mag = World.wMag[wi]
                p.mags[wi] = p.mag
            }
        }
        if p.boltT > 0 {
            p.boltT -= dt
            if p.boltT <= 0 && local && p.weapon == World.wSniper { sfx?.play(Sound.bolt) }
        }
        if p.fireCd > 0 { p.fireCd -= dt }

        if p.wantReload {
            p.wantReload = false
            if p.reloadT <= 0 && p.mag < World.wMag[wi] {
                p.reloadTotal = World.wReload[wi]
                p.reloadT = p.reloadTotal
                p.reloadStage = 0
            }
        }

        let leanTarget = Float(p.leanDir) * World.LEAN
        let leanPrev = p.lean
        p.lean += (leanTarget - p.lean) * min(1, dt * 11)
        var ly = World.worldLeanX(p, p.lean), lx = World.worldLeanZ(p, p.lean)
        if abs(p.lean) > 0.001 && blocked(p.x + World.worldLeanX(p, p.lean) * 1.4,
                                          p.z + World.worldLeanZ(p, p.lean) * 1.4) {
            p.lean = leanPrev
            ly = World.worldLeanX(p, p.lean)
            lx = World.worldLeanZ(p, p.lean)
        }
        p.leanX = ly
        p.leanZ = lx

        let standSpeed: Float = p.ads ? 3.15 : 5.55
        let lowSpeed: Float = p.ads ? 2.35 : 3.05
        var speed = standSpeed + (lowSpeed - standSpeed) * p.crouchAmt
        speed *= 1 - 0.55 * min(1, abs(p.lean) / World.LEAN)
        if p.weapon == World.wSniper { speed *= 0.92 }
        speed *= 1 - 0.35 * p.landT
        var fwd = p.my, str = p.mx
        let len = sqrt(fwd * fwd + str * str)
        if len > 1 {
            fwd /= len
            str /= len
        }
        let cy = cos(p.yaw), sy = sin(p.yaw)
        let wx = cy * fwd - sy * str
        let wz = sy * fwd + cy * str
        if p.posDriven && !local {
            let sp = sqrt(p.mx * p.mx + p.my * p.my) * speed
            p.bob += dt * sp * 1.9
        } else {
            let air = p.y > 0.001
            let tx = wx * speed, tz = wz * speed
            let braking = fwd * fwd + str * str < 0.01
            let rate: Float = air ? 1.6 : (braking ? 18 : 11)
            let k = min(1, dt * rate)
            p.vx += (tx - p.vx) * k
            p.vz += (tz - p.vz) * k
            if !air && braking && p.vx * p.vx + p.vz * p.vz < 0.04 { p.vx = 0; p.vz = 0 }
            moveX(p, p.vx * dt)
            moveZ(p, p.vz * dt)
            let sp = sqrt(p.vx * p.vx + p.vz * p.vz)
            if !air { p.bob += dt * sp * 1.9 }
        }
        p.landT = max(0, p.landT - dt * 3.2)
        footsteps(p, local)

        if p.wantJump {
            p.wantJump = false
            if p.y <= 0.001 {
                p.vy = World.JUMP_V
                p.crouch = false
                if local { sfx?.play(Sound.ui, 0.5, 0.75) }
            }
        }
        if p.y > 0 || p.vy != 0 {
            p.vy -= World.GRAVITY * dt
            p.y += p.vy * dt
            if p.y <= 0 {
                let impact = min(1, -p.vy / World.JUMP_V)
                p.y = 0
                p.vy = 0
                p.landT = max(p.landT, impact)
                p.vx *= 0.8
                p.vz *= 0.8
                if local { sfx?.play(Sound.land, 0.4 + 0.6 * impact, 1) }
            }
        }

        if p.fire && p.mag <= 0 && p.reloadT <= 0 { p.wantReload = true }
        if World.wAuto[wi] {
            if p.fire { _ = shoot(p, local) }
            p.firePrev = p.fire
        } else {
            if p.fire && !p.firePrev && shoot(p, local) { p.firePrev = true }
            if !p.fire { p.firePrev = false }
        }
    }

    private func footsteps(_ p: Player, _ local: Bool) {
        if sfx == nil || p.y > 0.001 {
            p.lastX = p.x
            p.lastZ = p.z
            return
        }
        let dx = p.x - p.lastX, dz = p.z - p.lastZ
        p.lastX = p.x
        p.lastZ = p.z
        let d = sqrt(dx * dx + dz * dz)
        if d > 1.5 { return }
        p.stepAcc += d
        if p.stepAcc < 2.1 { return }
        p.stepAcc = 0
        let quiet: Float = (p.crouchAmt > 0.5 || p.ads) ? 0.35 : 1
        if local {
            sfx?.play(Sound.step, 0.55 * quiet, 0.9 + rnd.nextFloat() * 0.2)
        } else {
            spatial(Sound.step, p.x, p.z, 0.9 * quiet, 1, 18)
        }
    }

    /// Positional one-shot: volume falls off with distance, walls muffle it and the stereo
    /// pan follows where the source is relative to the local view.
    func spatial(_ slot: Int, _ x: Float, _ z: Float, _ vol: Float, _ pitch: Float, _ range: Float) {
        guard let me = local(), sfx != nil else { return }
        let dx = x - me.x, dz = z - me.z
        let d = sqrt(dx * dx + dz * dz)
        if d > range { return }
        var att = 1 / (1 + d * d / 36)
        if !losClear(me.x, me.z, x, z) { att *= 0.55 }
        let yaw = me.yaw
        let pan = d < 0.01 ? 0 : (dx * -sin(yaw) + dz * cos(yaw)) / d
        sfx?.playPan(slot, vol * att, pitch, pan * 0.85)
    }

    static func leanRoll(_ lean: Float) -> Float { (lean / LEAN) * 11 }

    static func worldLeanX(_ p: Player, _ lean: Float) -> Float { -sin(p.yaw) * lean }
    static func worldLeanZ(_ p: Player, _ lean: Float) -> Float { cos(p.yaw) * lean }

    func leanYawOffset(_ p: Player) -> Float { 0 }
    func aimYaw(_ p: Player) -> Float { p.yaw }

    private func respawn(_ p: Player) {
        p.alive = true
        p.hp = 100
        p.mag = World.wMag[max(0, min(World.weapons - 1, p.weapon))]
        p.mags[p.weapon] = p.mag
        p.reloadT = 0
        p.leanDir = 0
        p.lean = 0
        p.crouch = false
        p.crouchAmt = 0
        p.switchT = 0
        p.holdScope = false
        p.firePulse = 0
        p.pulseUnscope = false
        p.invuln = 1.4
        if duel || ffa {
            respawnAt(p, p.team)
            p.vx = 0; p.vz = 0
            if p.id == myId { p.pitch = 0 }
        } else {
            spawnSpot(p, pickCorner(0xf))
            p.vx = 0; p.vz = 0
            p.y = 0; p.vy = 0
            p.crouch = false
            p.crouchAmt = 0
        }
        if duel { p.deadT = 2.6 }
        if p.id == myId {
            addBanner("重生 · 无敌 1.4 秒")
            p.yaw = atan2(-p.z + Float(World.GH) * World.CELL / 2, -p.x + Float(World.GW) * World.CELL / 2)
            p.pitch = 0
        }
    }

    private func blocked(_ x: Float, _ z: Float) -> Bool {
        let x0 = Int(floor((x - World.RADIUS) / World.CELL)), x1 = Int(floor((x + World.RADIUS) / World.CELL))
        let z0 = Int(floor((z - World.RADIUS) / World.CELL)), z1 = Int(floor((z + World.RADIUS) / World.CELL))
        for cx in x0...max(x0, x1) {
            for cz in z0...max(z0, z1) {
                if solidHeight(cx, cz) <= 0 { continue }
                let minX = Float(cx) * World.CELL, maxX = minX + World.CELL
                let minZ = Float(cz) * World.CELL, maxZ = minZ + World.CELL
                let nx = max(minX, min(x, maxX))
                let nz = max(minZ, min(z, maxZ))
                let dx = x - nx, dz = z - nz
                if dx * dx + dz * dz < World.RADIUS * World.RADIUS { return true }
            }
        }
        return false
    }

    private func moveX(_ p: Player, _ d: Float) {
        if d == 0 { return }
        if !blocked(p.x + d, p.z) { p.x += d } else { p.vx = 0 }
    }

    private func moveZ(_ p: Player, _ d: Float) {
        if d == 0 { return }
        if !blocked(p.x, p.z + d) { p.z += d } else { p.vz = 0 }
    }

    private func enemyBlocked(_ x: Float, _ z: Float, _ r: Float) -> Bool {
        let x0 = Int(floor((x - r) / World.CELL)), x1 = Int(floor((x + r) / World.CELL))
        let z0 = Int(floor((z - r) / World.CELL)), z1 = Int(floor((z + r) / World.CELL))
        for cx in x0...max(x0, x1) {
            for cz in z0...max(z0, z1) {
                if solidHeight(cx, cz) > 0.9 {
                    let minX = Float(cx) * World.CELL, maxX = minX + World.CELL
                    let minZ = Float(cz) * World.CELL, maxZ = minZ + World.CELL
                    let nx = max(minX, min(x, maxX))
                    let nz = max(minZ, min(z, maxZ))
                    let dx = x - nx, dz = z - nz
                    if dx * dx + dz * dz < r * r { return true }
                }
            }
        }
        return false
    }

    // ---------------------------------------------------------------- shooting

    func addBanner(_ s: String) {
        banner = s
        bannerT = 2.2
    }

    private func hitSound(_ head: Bool, _ kill: Bool) {
        if kill { sfx?.play(Sound.kill) }
        else if head { sfx?.play(Sound.headshot) }
        else { sfx?.play(Sound.hit) }
    }

    private func impactDebris(_ x: Float, _ y: Float, _ z: Float, _ mat: Int) {
        _ = addSpark(x, y, z, 0xffffe9a8, 0.07)
        let col = mat == 1 ? 0xff8a6a44 : (mat == 2 ? 0xff7d776c : 0xff9a9a96)
        for _ in 0..<5 {
            let s = addSpark(x, y, z, col, 0.018 + rnd.nextFloat() * 0.02)
            s.vx = (rnd.nextFloat() - 0.5) * 3
            s.vz = (rnd.nextFloat() - 0.5) * 3
            s.vy = 0.8 + rnd.nextFloat() * 2.2
            s.grav = true
            s.life = 0.5 + rnd.nextFloat() * 0.5
            s.maxLife = s.life
        }
        let d = addSpark(x, y, z, (col & 0x00ffffff) | 0x66000000, 0.09)
        d.vy = 0.25
        d.life = 0.9
        d.maxLife = 0.9
    }

    private func bloodPuff(_ x: Float, _ y: Float, _ z: Float, _ dx: Float, _ dz: Float) {
        for _ in 0..<4 {
            let s = addSpark(x, y, z, 0xff9a1a1a, 0.02 + rnd.nextFloat() * 0.02)
            s.vx = dx * 1.6 + (rnd.nextFloat() - 0.5) * 1.2
            s.vz = dz * 1.6 + (rnd.nextFloat() - 0.5) * 1.2
            s.vy = rnd.nextFloat() * 1.2
            s.grav = true
            s.life = 0.45
            s.maxLife = 0.45
        }
    }

    @discardableResult
    private func addSpark(_ x: Float, _ y: Float, _ z: Float, _ color: Int, _ size: Float) -> Spark {
        if sparks.count > 160 { sparks.removeFirst() }
        let s = Spark()
        s.x = x
        s.y = y
        s.z = z
        s.life = 0.35
        s.size = size
        s.color = color
        sparks.append(s)
        return s
    }

    static func cycleWeapon(_ p: Player?, _ dir: Int) {
        guard let p = p else { return }
        selectWeapon(p, (p.weapon + (dir < 0 ? weapons - 1 : 1)) % weapons)
    }

    static func selectWeapon(_ p: Player?, _ w: Int) {
        guard let p = p, w >= 0, w < weapons else { return }
        if p.weapon == w && p.switchT <= 0 { return }
        p.mags[p.weapon] = p.mag
        p.weapon = w
        p.mag = p.mags[w]
        p.reloadT = 0
        p.reloadTotal = wReload[w]
        p.switchT = SWITCH_TIME
        p.firePulse = 0
        p.pulseUnscope = false
        p.holdScope = false
    }

    @discardableResult
    private func shoot(_ p: Player, _ local: Bool) -> Bool {
        let wi = p.weapon
        if p.reloadT > 0 || p.fireCd > 0 || p.switchT > 0 { return false }
        if p.mag <= 0 {
            p.wantReload = true
            if local && !p.firePrev { sfx?.play(Sound.empty) }
            return false
        }
        p.mag -= 1
        p.mags[wi] = p.mag
        p.fireCd = World.wInterval[wi]
        let lowSpread = World.wSpreadHip[wi]
            + (World.wSpreadCrouch[wi] - World.wSpreadHip[wi]) * p.crouchAmt
        var spread = p.ads ? World.wSpreadAds[wi] : lowSpread
        if p.ads && p.crouchAmt > 0.5 { spread *= 0.72 }
        if wi == World.wSniper && !p.ads { spread *= 1.35 }
        let yaw = aimYaw(p) + (rnd.nextFloat() - 0.5) * spread * 2
        let pitch = p.pitch + p.kick * 0.55 + (rnd.nextFloat() - 0.5) * spread * 2
        let dx = cos(pitch) * cos(yaw)
        let dy = sin(pitch)
        let dz = cos(pitch) * sin(yaw)
        p.kick += p.ads ? World.wKick[wi] * 0.42 : World.wKick[wi]
        p.kick = min(0.09, p.kick)
        p.shots = (p.shots + 1) & 0xff
        p.lastShot = time
        if wi == World.wSniper { p.boltT = 0.42 }
        if local {
            muzzleT = 1
            sfx?.play(World.nearShot(wi), 1, 1)
        } else {
            remoteShot(wi, p.x, p.z)
        }
        trace(p, p.x + p.leanX, World.eyeY(p) + World.bobY(p), p.z + p.leanZ, dx, dy, dz)
        return true
    }

    static func nearShot(_ wi: Int) -> Int {
        wi == wSniper ? Sound.sniper : (wi == wSmg ? Sound.smg : Sound.shoot)
    }

    static func farShot(_ wi: Int) -> Int {
        wi == wSniper ? Sound.farSniper : (wi == wSmg ? Sound.farSmg : Sound.farRifle)
    }

    func remoteShot(_ wi: Int, _ x: Float, _ z: Float) {
        guard let me = local(), sfx != nil else { return }
        let dx = x - me.x, dz = z - me.z
        let d = sqrt(dx * dx + dz * dz)
        if d < 14 { spatial(World.nearShot(wi), x, z, 0.95, 1, 60) }
        else { spatial(World.farShot(wi), x, z, 2.2, 1, 80) }
    }

    static func bobY(_ p: Player) -> Float { sin(p.bob) * 0.035 }
    static func eyeY(_ p: Player) -> Float { EYE + (CROUCH_EYE - EYE) * p.crouchAmt + p.y }
    static func bodyTop(_ p: Player) -> Float { 1.80 - 0.34 * p.crouchAmt }

    private func trace(_ p: Player, _ ex: Float, _ ey: Float, _ ez: Float,
                       _ dx: Float, _ dy: Float, _ dz: Float) {
        let server = mode != World.client
        let lagShot = mode == World.host && p.id != myId
        let wi = max(0, min(World.weapons - 1, p.weapon))
        let bodyDmg = World.wBody[wi], headDmg = World.wHead[wi]
        let coarseShot = wi == World.wSniper && !p.ads
        let step: Float = 0.05
        let maxT: Float = 46
        var t: Float = 0.6
        while t < maxT {
            let x = ex + dx * t, y = ey + dy * t, z = ez + dz * t
            let cx = Int(floor(x / World.CELL)), cz = Int(floor(z / World.CELL))
            let h = solidHeight(cx, cz)
            if (y <= h && h > 0) || y <= 0 {
                impactDebris(x, max(0.02, y), z, h >= World.WALL_H ? 0 : (h > 0 ? 1 : 2))
                if p.id != myId && rnd.nextInt(3) == 0 { spatial(Sound.ricochet, x, z, 0.8, 1, 9) }
                return
            }
            if duel || ffa {
                for q in players {
                    if q === p || !q.alive { continue }
                    if !ffa && q.team == p.team { continue }
                    let cands = lagShot ? 2 : 1
                    for c in 0..<cands {
                        let qx = c == 0 ? q.x : histAt(q.histX, q, World.LAG_STEPS)
                        let qz = c == 0 ? q.z : histAt(q.histZ, q, World.LAG_STEPS)
                        let qy = c == 0 ? q.y : histAt(q.histY, q, World.LAG_STEPS)
                        let ddx = x - qx, ddz = z - qz
                        if ddx * ddx + ddz * ddz > 0.8 * 0.8 { continue }
                        var reg = World.bodyRegion(ddx, ddz, y - qy, q.yaw, q.crouchAmt, 1,
                                                   q.leanX, q.leanZ)
                        if reg >= 0 {
                            var head = reg == World.hrHead
                            var dmg = head ? headDmg : max(1, Int(jround(Float(bodyDmg) * World.hrMult[reg])))
                            if coarseShot {
                                reg = World.hrChest
                                head = false
                                dmg = max(1, Int(jround(Float(bodyDmg) * World.SNIPER_HIP_DMG)))
                            }
                            addSpark(x, y, z, World.sparkColor(reg), head ? 0.16 : 0.11)
                            bloodPuff(x, y, z, dx, dz)
                            let wasAlive = q.alive
                            q.hitT = 0.2
                            if server { damagePlayer(q, dmg, p) }
                            if p.id == myId {
                                hitT = 0.22
                                hitSound(head, server && wasAlive && !q.alive)
                            }
                            return
                        }
                    }
                }
            }
            for e in enemies {
                if e.hp <= 0 { continue }
                if (duel || ffa) && e.team >= 0 && e.team == p.team { continue }
                let es = World.enemyScale(e)
                let ddx = x - e.x, ddz = z - e.z
                if ddx * ddx + ddz * ddz > 0.8 * es * 0.8 * es { continue }
                let reg = World.bodyRegion(ddx, ddz, y, e.yaw, 0, es, 0, 0)
                if reg >= 0 {
                    var head = reg == World.hrHead
                    if coarseShot { head = false }
                    addSpark(x, y, z, World.sparkColor(reg), head ? 0.16 : 0.11)
                    bloodPuff(x, y, z, dx, dz)
                    e.hitT = max(e.hitT, 0.18)
                    e.memX = p.x
                    e.memZ = p.z
                    e.memT = 4
                    if p.id == myId && !server { hitSound(head, false) }
                    if server {
                        e.hp -= coarseShot ? max(1, Int(jround(Float(bodyDmg) * World.SNIPER_HIP_DMG * 0.96)))
                            : (head ? Int(Float(headDmg) * 0.95)
                               : max(1, Int(jround(Float(bodyDmg) * 0.96 * World.hrMult[reg]))))
                        e.hitT = 0.2
                        if e.hp <= 0 {
                            e.hp = 0
                            p.kills += 1
                            totalKills += 1
                            killT = 0.6
                            if duel || ffa { scoreKill(p) }
                            if p.id == myId { hitSound(head, true) }
                        } else if p.id == myId {
                            hitSound(head, false)
                        }
                    }
                    if p.id == myId { hitT = 0.22 }
                    return
                }
            }
            t += step
        }
    }

    static func enemyScale(_ e: Enemy) -> Float {
        e.type == 2 ? 1.65 : (e.type == 1 ? 0.92 : 1)
    }

    /// Precise hit test against the box skeleton. Returns a hr* region or -1.
    static func bodyRegion(_ dxIn: Float, _ dzIn: Float, _ y: Float, _ yaw: Float, _ crouchAmt: Float,
                           _ scale: Float, _ leanX: Float, _ leanZ: Float) -> Int {
        let cf = 1 - 0.26 * max(0, min(1, crouchAmt))
        let s = scale
        let pad: Float = 0.035
        var dx = dxIn, dz = dzIn
        let fx = cos(yaw), fz = sin(yaw)
        let rx = -fz, rz = fx
        if y < 0 || y > 1.76 * cf * s { return -1 }
        if y > 0.92 * cf * s {
            dx -= leanX * 0.75
            dz -= leanZ * 0.75
        }
        let lat = dx * rx + dz * rz, fwd = dx * fx + dz * fz
        let al = abs(lat)
        if y >= 1.43 * cf * s {
            return (al < 0.11 * s + pad && abs(fwd) < 0.115 * s + pad) ? hrHead : -1
        }
        if y >= 1.04 * cf * s {
            if al < 0.19 * s + pad && fwd > -0.19 * s - pad && fwd < 0.15 * s + pad { return hrChest }
            if al < 0.26 * s + pad && fwd > -0.08 * s && fwd < 0.50 * s + pad
                && y < 1.42 * cf * s { return hrArm }
            return -1
        }
        if y >= 0.82 * cf * s {
            return (al < 0.16 * s + pad && abs(fwd) < 0.15 * s + pad) ? hrHip : -1
        }
        let leg = abs(al - 0.105 * s)
        return (leg < 0.09 * s + pad && abs(fwd) < 0.30 * s) ? hrLeg : -1
    }

    static func hitRegion(_ crouchAmt: Float, _ lat: Float, _ y: Float) -> Int {
        let cf = 1 - 0.26 * max(0, min(1, crouchAmt))
        if y >= 1.44 * cf { return hrHead }
        if abs(lat) > 0.175 && y > 0.88 * cf && y < 1.38 * cf { return hrArm }
        if y >= 1.04 * cf { return hrChest }
        if y >= 0.84 * cf { return hrHip }
        return hrLeg
    }

    static func sparkColor(_ region: Int) -> Int {
        switch region {
        case hrHead: return 0xffffe066
        case hrArm, hrLeg: return 0xffffa24d
        case hrHip: return 0xffff7f6b
        default: return 0xffff5577
        }
    }

    // ---------------------------------------------------------------- enemies

    private func nearestPlayer(_ x: Float, _ z: Float) -> Player? {
        nearestPlayer(x, z, -2)
    }

    private func nearestPlayer(_ x: Float, _ z: Float, _ hostileToTeam: Int) -> Player? {
        var best: Player?
        var bd = Float.greatestFiniteMagnitude
        for p in players {
            if !p.alive || !p.online { continue }
            if hostileToTeam >= 0 && p.team == hostileToTeam { continue }
            let dx = p.x - x, dz = p.z - z
            let d = dx * dx + dz * dz
            if d < bd {
                bd = d
                best = p
            }
        }
        return best
    }

    func losClear(_ ax: Float, _ az: Float, _ bx: Float, _ bz: Float) -> Bool {
        var dx = bx - ax, dz = bz - az
        let len = sqrt(dx * dx + dz * dz)
        if len < 0.001 { return true }
        dx /= len
        dz /= len
        var t: Float = 0.35
        while t < len - 0.3 {
            let cx = Int(floor((ax + dx * t) / World.CELL))
            let cz = Int(floor((az + dz * t) / World.CELL))
            if solidHeight(cx, cz) >= World.CRATE_H { return false }
            t += 0.35
        }
        return true
    }

    private func stepEnemies(_ dt: Float) {
        for i in stride(from: enemies.count - 1, through: 0, by: -1) {
            let e = enemies[i]
            if e.hp <= 0 {
                addCorpse(e)
                enemies.remove(at: i)
                if room() && e.type == World.botType {
                    botTeamT[max(0, min(botTeamT.count - 1, e.team))] = 2.4
                }
                continue
            }
            let px = e.x, pz = e.z
            stepEnemy(e, dt)
            let mvx = e.x - px, mvz = e.z - pz
            let spd = dt > 0 ? sqrt(mvx * mvx + mvz * mvz) / dt : 0
            e.gait += (min(1, spd / 2.4) - e.gait) * min(1, dt * 9)
            e.walk += spd * dt * 2.15
        }
    }

    private func stepEnemy(_ e: Enemy, _ dt: Float) {
        e.anim += dt
        e.hitT = max(0, e.hitT - dt)
        if e.cool > 0 { e.cool -= dt }
        if e.memT > 0 { e.memT -= dt }
        if e.strafeT > 0 { e.strafeT -= dt }
        if e.unstuckT > 0 { e.unstuckT -= dt }
        let rusher = e.type == 1
        if !rusher && e.charge > 0 { e.charge = max(0, e.charge - dt) }
        let speed: Float = rusher ? 3.9 : (e.type == 2 ? 2.1 : (e.type == World.botType ? 3.4 : 2.8))

        guard let tp = nearestPlayer(e.x, e.z, e.team) else {
            e.seeT = 0
            if e.team >= 0 {
                let idx = ffa ? e.team % 4 : (e.team == 0 ? 2 : 0)
                goTo(e, World.spawnX(idx), World.spawnZ(idx), speed * 0.8, dt, true)
            }
            return
        }
        let dx = tp.x - e.x, dz = tp.z - e.z
        let dist = sqrt(dx * dx + dz * dz)
        let toT = atan2(dz, dx)
        let los = losClear(e.x, e.z, tp.x, tp.z)
        let off = abs(World.angDiff(toT, e.yaw))
        let inCone = off < 1.15 || dist < 3.5 || e.memT > 3.6
        let range: Float = e.type == World.botType ? 36 : 28
        let sees = los && inCone && dist < range
        if sees {
            e.seeT += dt
            e.memX = tp.x
            e.memZ = tp.z
            e.memT = 5
        } else {
            e.seeT = max(0, e.seeT - dt * 2)
            let shotHeard = time - tp.lastShot < 0.3 && dist < 30
            let feet = World.playerSpeed(tp) > 3.8 && tp.crouchAmt < 0.5 && dist < 10
            if shotHeard || feet {
                e.memX = tp.x
                e.memZ = tp.z
                e.memT = max(e.memT, 3.5)
            }
        }

        if rusher {
            if e.windT > 0 {
                e.windT -= dt
                e.charge = e.windT
                if e.windT <= 0 {
                    e.charge = 0
                    if dist < 2.3 && tp.alive {
                        damagePlayer(tp, 15, nil)
                        addSpark(tp.x, 1.1, tp.z, 0xffff5566, 0.09)
                    }
                    e.cool = 0.9 + rnd.nextFloat() * 0.5
                }
                e.yaw = World.turnTo(e.yaw, toT, dt * 6)
                return
            }
            if dist < 1.7 && e.cool <= 0 {
                e.windT = 0.32
                return
            }
            goTo(e, tp.x, tp.z, speed, dt, true)
            return
        }

        let lowHp = e.type == World.botType && e.hp < Float(e.maxHp) * 0.35
        let med = lowHp ? nearestPickup(e.x, e.z, World.pkHealth) : -1
        if sees {
            e.yaw = World.turnTo(e.yaw, toT, dt * (3.5 + 3 * e.skill))
            let nx = dx / max(0.001, dist), nz = dz / max(0.001, dist)
            let keep: Float = e.type == 2 ? 6 : (e.type == World.botType ? 9 : 8)
            let radial: Float = dist > keep + 3 ? 0.9 : (dist < keep - 3 ? -0.7 : 0)
            if e.strafeT <= 0 {
                e.strafeDir = rnd.nextInt(3) - 1
                if e.strafeDir == 0 && e.type == World.botType { e.strafeDir = rnd.nextBoolean() ? 1 : -1 }
                e.strafeT = 0.5 + rnd.nextFloat() * 1.2
            }
            let sk: Float = e.type == World.botType ? 0.9 : 0.45
            let mx = nx * radial - nz * Float(e.strafeDir) * sk
            let mz = nz * radial + nx * Float(e.strafeDir) * sk
            if med >= 0 {
                goTo(e, pkX[med], pkZ[med], speed, dt, false)
            } else if !botMove(e, mx, mz, speed * 0.75, dt) {
                e.strafeDir = -e.strafeDir
            }
            let fireRange: Float = e.type == 2 ? 26 : (e.type == World.botType ? 30 : 22)
            if e.seeT >= e.react && e.cool <= 0 && dist < fireRange
                && abs(World.angDiff(toT, e.yaw)) < 0.22 && tp.alive {
                if e.burst <= 0 { e.burst = burstLen(e) }
                botShot(e, tp, dist)
                e.burst -= 1
                e.cool = e.burst > 0 ? burstGap(e) : burstPause(e)
            }
            return
        }
        e.burst = 0
        if med >= 0 {
            goTo(e, pkX[med], pkZ[med], speed, dt, true)
        } else if e.memT > 0 {
            let mdx = e.memX - e.x, mdz = e.memZ - e.z
            if mdx * mdx + mdz * mdz < 1.4 * 1.4 {
                e.yaw += dt * 1.8 * Float(e.strafeDir == 0 ? 1 : e.strafeDir)
            } else {
                goTo(e, e.memX, e.memZ, speed, dt, true)
            }
        } else {
            goTo(e, tp.x, tp.z, speed * 0.85, dt, true)
        }
    }

    static func angDiff(_ a: Float, _ b: Float) -> Float {
        var d = a - b
        while d > Float.pi { d -= Float.pi * 2 }
        while d < -Float.pi { d += Float.pi * 2 }
        return d
    }

    static func turnTo(_ cur: Float, _ target: Float, _ maxStep: Float) -> Float {
        let d = angDiff(target, cur)
        if abs(d) <= maxStep { return target }
        return cur + (d < 0 ? -maxStep : maxStep)
    }

    static func playerSpeed(_ p: Player) -> Float { sqrt(p.vx * p.vx + p.vz * p.vz) }

    private func nearestPickup(_ x: Float, _ z: Float, _ type: Int) -> Int {
        var best = -1
        var bd: Float = 22 * 22
        for i in 0..<pkCount {
            if pkType[i] != type || pkT[i] > 0 { continue }
            let dx = pkX[i] - x, dz = pkZ[i] - z
            let d = dx * dx + dz * dz
            if d < bd {
                bd = d
                best = i
            }
        }
        return best
    }

    private func burstLen(_ e: Enemy) -> Int {
        if e.type == 2 { return 4 + rnd.nextInt(3) }
        if e.type == World.botType { return 3 + rnd.nextInt(4) }
        return 2 + rnd.nextInt(2)
    }

    private func burstGap(_ e: Enemy) -> Float { e.type == 2 ? 0.16 : 0.12 }

    private func burstPause(_ e: Enemy) -> Float {
        let base: Float = e.type == 2 ? 0.9 : (e.type == World.botType ? 0.55 : 1.1)
        return base + rnd.nextFloat() * 0.6
    }

    private func botShot(_ e: Enemy, _ tp: Player, _ dist: Float) {
        e.shots = (e.shots + 1) & 0xff
        e.charge = 0.08
        remoteShot(e.type == 2 ? World.wSniper : World.wRifle, e.x, e.z)
        var p: Float = 0.30 + 0.45 * e.skill
        p *= 1 / (1 + dist * dist / 260)
        p *= 0.55 + 0.45 * min(1, e.seeT / 1.4)
        let lateral = abs(tp.vx * -sin(e.yaw) + tp.vz * cos(e.yaw))
        p *= 1 / (1 + lateral * 0.22)
        if tp.crouchAmt > 0.5 { p *= 0.78 }
        if abs(tp.lean) > World.LEAN * 0.5 { p *= 0.7 }
        if tp.y > 0.2 { p *= 0.7 }
        if rnd.nextFloat() < p {
            var dmg = e.type == 2 ? 20 : (e.type == World.botType ? 11 : 9)
            let head = rnd.nextFloat() < 0.08 + 0.1 * e.skill
            if head { dmg *= 2 }
            damagePlayer(tp, dmg, nil)
            addSpark(tp.x, head ? 1.6 : 1.1, tp.z, 0xffff5566, 0.08)
        } else {
            let side = (rnd.nextFloat() - 0.5) * 1.6
            let mx = tp.x - sin(e.yaw) * side, mz = tp.z + cos(e.yaw) * side
            impactDebris(mx, rnd.nextFloat() * 0.3, mz, 2)
            if tp.id == myId && rnd.nextInt(2) == 0 {
                sfx?.playPan(Sound.ricochet, 0.5, 1.1, side > 0 ? 0.6 : -0.6)
            }
        }
    }

    @discardableResult
    private func botMove(_ e: Enemy, _ mxIn: Float, _ mzIn: Float, _ speed: Float, _ dt: Float) -> Bool {
        var mx = mxIn, mz = mzIn
        var len = sqrt(mx * mx + mz * mz)
        if len < 0.01 { return true }
        if len > 1 {
            mx /= len
            mz /= len
            len = 1
        }
        for o in enemies where o !== e && o.hp > 0 {
            let ox = e.x - o.x, oz = e.z - o.z
            let d2 = ox * ox + oz * oz
            if d2 < 1.0 && d2 > 1e-4 {
                let d = sqrt(d2)
                mx += ox / d * (1 - d) * 0.8
                mz += oz / d * (1 - d) * 0.8
            }
        }
        let sx = mx * speed * dt, sz = mz * speed * dt
        var moved = false
        if !enemyBlocked(e.x + sx, e.z, 0.42) {
            e.x += sx
            moved = true
        }
        if !enemyBlocked(e.x, e.z + sz, 0.42) {
            e.z += sz
            moved = true
        }
        return moved
    }

    private func goTo(_ e: Enemy, _ tx: Float, _ tz: Float, _ speed: Float, _ dt: Float, _ face: Bool) {
        let dx = tx - e.x, dz = tz - e.z
        let d = sqrt(dx * dx + dz * dz)
        if d < 0.3 { return }
        var mx = dx / d, mz = dz / d
        if !pathClear(e.x, e.z, tx, tz) {
            let f = flowField(Int(floor(tx / World.CELL)), Int(floor(tz / World.CELL)))
            let cx = Int(floor(e.x / World.CELL)), cz = Int(floor(e.z / World.CELL))
            var best = -1, bd = Int.max
            for oz in -1...1 {
                for ox in -1...1 {
                    if ox == 0 && oz == 0 { continue }
                    let nx = cx + ox, nz = cz + oz
                    if nx < 0 || nz < 0 || nx >= World.GW || nz >= World.GH { continue }
                    if ox != 0 && oz != 0 && (solidHeight(cx + ox, cz) > 0 || solidHeight(cx, cz + oz) > 0) {
                        continue
                    }
                    let v = Int(f[nx + nz * World.GW])
                    if v >= 0 && v < bd {
                        bd = v
                        best = nx + nz * World.GW
                    }
                }
            }
            if best >= 0 {
                let wx = (Float(best % World.GW) + 0.5) * World.CELL - e.x
                let wz = (Float(best / World.GW) + 0.5) * World.CELL - e.z
                let wl = sqrt(wx * wx + wz * wz)
                if wl > 0.01 {
                    mx = wx / wl
                    mz = wz / wl
                }
            }
        }
        e.probeT += dt
        if e.probeT > 1 {
            let px = e.x - e.probeX, pz = e.z - e.probeZ
            if px * px + pz * pz < 0.25 {
                e.unstuckT = 0.6
                e.unstuckDir = rnd.nextBoolean() ? 1 : -1
            }
            e.probeX = e.x
            e.probeZ = e.z
            e.probeT = 0
        }
        if e.unstuckT > 0 {
            let ux = -mz * Float(e.unstuckDir), uz = mx * Float(e.unstuckDir)
            mx = mx * 0.3 + ux
            mz = mz * 0.3 + uz
        }
        botMove(e, mx, mz, speed, dt)
        if face { e.yaw = World.turnTo(e.yaw, atan2(mz, mx), dt * 5) }
    }

    private func pathClear(_ ax: Float, _ az: Float, _ bx: Float, _ bz: Float) -> Bool {
        var dx = bx - ax, dz = bz - az
        let len = sqrt(dx * dx + dz * dz)
        if len < 0.01 { return true }
        dx /= len
        dz /= len
        var t: Float = 0.3
        while t < len {
            if enemyBlocked(ax + dx * t, az + dz * t, 0.45) { return false }
            t += 0.3
        }
        return true
    }

    /// BFS steps from every open cell to (gx, gz); -1 = unreachable. Cached.
    func flowField(_ gxIn: Int, _ gzIn: Int) -> [Int16] {
        let gx = max(0, min(World.GW - 1, gxIn))
        let gz = max(0, min(World.GH - 1, gzIn))
        let key = gx + gz * World.GW
        if let f = flowCache[key] { return f }
        if flowCache.count > 96 { flowCache.removeAll() }
        var f = [Int16](repeating: -1, count: World.GW * World.GH)
        var q = [Int](repeating: 0, count: World.GW * World.GH)
        var h = 0, t = 0
        f[key] = 0
        q[t] = key
        t += 1
        while h < t {
            let c = q[h]
            h += 1
            let cx = c % World.GW, cz = c / World.GW
            for k in 0..<4 {
                let nx = cx + (k == 0 ? 1 : k == 1 ? -1 : 0)
                let nz = cz + (k == 2 ? 1 : k == 3 ? -1 : 0)
                if nx < 0 || nz < 0 || nx >= World.GW || nz >= World.GH { continue }
                let n = nx + nz * World.GW
                if f[n] >= 0 || grid[n] != 0 { continue }
                f[n] = f[c] + 1
                q[t] = n
                t += 1
            }
        }
        flowCache[key] = f
        return f
    }

    private func damagePlayer(_ tp: Player?, _ dmg: Int, _ attacker: Player?) {
        guard let tp = tp, tp.alive, tp.invuln <= 0, tp.online else { return }
        tp.hp -= dmg
        if tp.id == myId {
            hurtT = 1
            sfx?.play(Sound.hurt)
        }
        if tp.hp > 0 { return }
        tp.hp = 0
        tp.alive = false
        tp.deadT = room() ? 2.2 : 3.5
        tp.deaths += 1
        let botKiller = attacker == nil
        let who = botKiller ? "人机" : (attacker!.id == myId ? "你" : attacker!.name)
        addBanner((tp.id == myId ? "你被\(who)击倒" : "\(tp.name) 被\(who)击倒")
            + " · " + (room() ? "2" : "3") + " 秒后重生")
        if let attacker = attacker, attacker !== tp {
            attacker.kills += 1
            totalKills += 1
            killT = 0.6
            if duel || ffa { scoreKill(attacker) }
        }
    }

    // ---------------------------------------------------------------- room upkeep

    private func stepDuel(_ dt: Float) {
        if roundT > 0 {
            roundT -= dt
            return
        }
        var humans = [0, 0], bots = [0, 0]
        for p in players {
            if p.team == 0 { humans[0] += 1 }
            else if p.team == 1 { humans[1] += 1 }
            else {
                p.team = humans[0] <= humans[1] ? 0 : 1
                humans[p.team] += 1
            }
        }
        for e in enemies where e.type == World.botType && e.hp > 0 {
            if e.team == 0 { bots[0] += 1 } else if e.team == 1 { bots[1] += 1 }
        }
        for t in 0..<2 {
            let want = max(0, teamSize - humans[t])
            if bots[t] > want {
                var drop = bots[t] - want
                for i in stride(from: enemies.count - 1, through: 0, by: -1) where drop > 0 {
                    if enemies[i].type == World.botType && enemies[i].team == t {
                        enemies.remove(at: i)
                        drop -= 1
                    }
                }
                continue
            }
            if bots[t] < want {
                botTeamT[t] -= dt
                if botTeamT[t] <= 0 {
                    botTeamT[t] = 1.6
                    spawnDuelBot(t)
                }
            }
        }
    }

    private func stepFfa(_ dt: Float) {
        if roundT > 0 {
            roundT -= dt
            return
        }
        var used = [Bool](repeating: false, count: World.ffaMax)
        for p in players {
            if p.team < 0 || p.team >= World.ffaMax || used[p.team] {
                p.team = freeSlot(&used, p)
            } else {
                used[p.team] = true
            }
        }
        if !ffaBots {
            for i in stride(from: enemies.count - 1, through: 0, by: -1) where enemies[i].type == World.botType {
                enemies.remove(at: i)
            }
            for i in 0..<botTeamT.count { botTeamT[i] = 0 }
            return
        }
        let humans = players.count
        var bots = 0
        var botSlots = [Bool](repeating: false, count: World.ffaMax)
        for e in enemies where e.type == World.botType && e.hp > 0 {
            if e.team >= 0 && e.team < World.ffaMax && !botSlots[e.team] {
                botSlots[e.team] = true
                bots += 1
            }
        }
        var want = max(0, min(World.ffaMax - humans, max(0, 3 - humans - bots)))
        for t in 0..<World.ffaMax {
            if want <= 0 { break }
            if used[t] || botSlots[t] { continue }
            botTeamT[t] -= dt
            if botTeamT[t] <= 0 {
                botTeamT[t] = 1.6
                spawnDuelBot(t)
                want -= 1
            }
        }
        for t in 0..<World.ffaMax {
            var n = 0
            for i in stride(from: enemies.count - 1, through: 0, by: -1) {
                let e = enemies[i]
                if e.type != World.botType || e.hp <= 0 || e.team != t { continue }
                n += 1
                if n > 1 { enemies.remove(at: i) }
            }
        }
    }

    private func spawnDuelBot(_ team: Int) {
        let mine = local()
        var x: Float = 0, z: Float = 0
        let base = ffa ? team % 4 : (team == 0 ? 0 : 2)
        for tries in 0..<140 {
            var cx = 0, cz = 0
            if tries < 90 {
                cx = 2 + rnd.nextInt(World.GW - 4)
                cz = 2 + rnd.nextInt(World.GH - 4)
            } else {
                let idx = ffa ? base : (base + rnd.nextInt(2)) % 4
                cx = Int(World.spawnX(idx) / World.CELL) + rnd.nextInt(3) - 1
                cz = Int(World.spawnZ(idx) / World.CELL) + rnd.nextInt(3) - 1
            }
            if cx < 1 || cz < 1 || cx >= World.GW - 1 || cz >= World.GH - 1 { continue }
            if solidHeight(cx, cz) > 0 { continue }
            let px = (Float(cx) + 0.5) * World.CELL, pz = (Float(cz) + 0.5) * World.CELL
            if ffa {
                var near = false
                for q in players where q.alive {
                    let dx = q.x - px, dz = q.z - pz
                    if dx * dx + dz * dz < 7 * 7 { near = true }
                }
                if near { continue }
            } else if let me = mine, me.team == team {
                let dx = me.x - px, dz = me.z - pz
                if dx * dx + dz * dz < 7 * 7 { continue }
            }
            x = px
            z = pz
            break
        }
        if x == 0 && z == 0 {
            let idx = ffa ? base : (base + rnd.nextInt(2)) % 4
            x = World.spawnX(idx)
            z = World.spawnZ(idx)
        }
        let e = Enemy()
        e.id = nextEnemyId
        nextEnemyId += 1
        e.type = World.botType
        e.team = team
        e.x = x
        e.z = z
        e.netX = x
        e.netZ = z
        e.hp = 120
        e.maxHp = 120
        e.cool = 1.1
        e.skill = 0.45 + rnd.nextFloat() * 0.4
        e.react = 0.22 + rnd.nextFloat() * 0.3
        e.yaw = atan2(Float(World.GH) * World.CELL / 2 - z, Float(World.GW) * World.CELL / 2 - x)
        enemies.append(e)
        if ffa {
            addBanner("人机补位 · \(team + 1) 号位")
        } else if let me = mine, me.team != team {
            addBanner("人机补位 · " + (team == 0 ? "红队" : "蓝队"))
        }
    }

    private func scoreKill(_ p: Player) {
        if ffa { scoreFfa(p) } else { scoreDuel(p) }
    }

    private func scoreFfa(_ p: Player) {
        var best: Player?
        for q in players where best == nil || q.kills > best!.kills { best = q }
        guard let winner = best, winner.kills >= World.scoreFfa else {
            if p.id == myId { addBanner("击杀 \(p.kills) / \(World.scoreFfa) 分") }
            return
        }
        winTeam = winner.team
        let iWon = winner.id == myId
        addBanner((iWon ? "你赢下这局 · " : (winner.name + " 获胜 · ")) + "\(winner.kills) 分")
        for q in players {
            q.kills = 0
            q.deaths = 0
            q.hp = 100
            q.alive = true
            q.deadT = 0
            respawnAt(q, q.team)
        }
        for i in stride(from: enemies.count - 1, through: 0, by: -1) where enemies[i].type == World.botType {
            enemies.remove(at: i)
        }
        for i in 0..<botTeamT.count { botTeamT[i] = 1.6 }
        roundT = 2.6
        sfx?.play(Sound.wave)
    }

    private func scoreDuel(_ p: Player) {
        let mine = teamKills(0), theirs = teamKills(1)
        guard mine >= World.scoreLimit || theirs >= World.scoreLimit else {
            if p.id == myId { addBanner("击杀 \(mine) : \(theirs)  目标 \(World.scoreLimit)") }
            return
        }
        winTeam = mine > theirs ? 0 : 1
        var weWon = false
        for q in players where q.id == myId && q.team == winTeam { weWon = true }
        addBanner((weWon ? "你所在的队伍获胜 · " : (winTeam == 0 ? "红队" : "蓝队") + "获胜 · ")
            + "\(teamKills(winTeam)) 杀")
        for q in players {
            q.kills = 0
            q.deaths = 0
            q.hp = 100
            q.alive = true
            q.deadT = 0
            respawnAt(q, q.team)
        }
        for i in stride(from: enemies.count - 1, through: 0, by: -1) where enemies[i].type == World.botType {
            enemies.remove(at: i)
        }
        botTeamT[0] = 1.6; botTeamT[1] = 1.6
        roundT = 2.6
        sfx?.play(Sound.wave)
    }

    // ---------------------------------------------------------------- waves

    private func stepWaves(_ dt: Float) {
        if !enemies.isEmpty { return }
        waveTimer -= dt
        if waveTimer > 0 { return }
        spawnWave()
    }

    func spawnWave() {
        wave += 1
        waveTimer = 8 + Float(wave) * 0.5
        var count = min(26, 3 + wave * 2)
        if players.count > 1 { count += (players.count - 1) * 2 }
        for _ in 0..<count { spawnEnemy(0) }
        if wave % 5 == 0 {
            spawnEnemy(2)
            addBanner("WAVE \(wave) · BOSS 出现")
        } else {
            addBanner("WAVE \(wave)")
        }
        sfx?.play(Sound.wave)
    }

    private func spawnEnemy(_ type: Int) {
        var x: Float = 0, z: Float = 0
        for _ in 0..<90 {
            let cx = 2 + rnd.nextInt(World.GW - 4), cz = 2 + rnd.nextInt(World.GH - 4)
            if solidHeight(cx, cz) > 0 { continue }
            let px = (Float(cx) + 0.5) * World.CELL, pz = (Float(cz) + 0.5) * World.CELL
            if let near = nearestPlayer(px, pz) {
                let dx = near.x - px, dz = near.z - pz
                if dx * dx + dz * dz < 11 * 11 { continue }
            }
            x = px
            z = pz
            break
        }
        if x == 0 { return }
        let e = Enemy()
        e.id = nextEnemyId
        nextEnemyId += 1
        e.type = type
        e.x = x
        e.z = z
        e.netX = x
        e.netZ = z
        let rusher = type == 0 && rnd.nextInt(100) < 32
        if type == 0 { e.type = rusher ? 1 : 0 }
        if e.type == 2 {
            e.hp = 780 + wave * 70
            e.maxHp = e.hp
        } else {
            e.hp = Int(58 + Float(wave) * 17 + Float(rusher ? -8 : 0))
            e.maxHp = e.hp
        }
        e.cool = 0.6 + rnd.nextFloat() * 0.8
        e.skill = min(0.85, 0.25 + Float(wave) * 0.05 + rnd.nextFloat() * 0.15)
        e.react = max(0.2, 0.6 - Float(wave) * 0.03 + rnd.nextFloat() * 0.2)
        e.yaw = rnd.nextFloat() * 6.283
        enemies.append(e)
    }

    private func addCorpse(_ e: Enemy) {
        if corpses.count > 12 { corpses.removeFirst() }
        let c = Corpse()
        c.x = e.x
        c.z = e.z
        c.yaw = e.yaw
        c.type = e.type
        c.team = e.team
        c.scale = World.enemyScale(e)
        corpses.append(c)
    }

    // ---------------------------------------------------------------- client mirror

    private var poseTmp = [Float](repeating: 0, count: 3)

    private func lerpRemote(_ dt: Float) {
        let k = min(1, dt * 30)
        for p in players {
            if p.id == myId { continue }
            if !p.netKnown { continue }
            var tx = p.netX, tz = p.netZ, tyaw = p.netYaw
            if World.poseAt(p.bufX, p.bufZ, p.bufYaw, p.bufT, p.bufHead, p.bufFill, &poseTmp) {
                tx = poseTmp[0]
                tz = poseTmp[1]
                tyaw = poseTmp[2]
            }
            p.x += (tx - p.x) * k
            p.z += (tz - p.z) * k
            var dy = tyaw - p.yaw
            while dy > Float.pi { dy -= Float.pi * 2 }
            while dy < -Float.pi { dy += Float.pi * 2 }
            p.yaw += dy * k
            p.pitch += (p.netPitch - p.pitch) * k
            p.crouchAmt += ((p.crouch ? 1 : 0) - p.crouchAmt) * k
        }
        for e in enemies {
            var tx = e.netX, tz = e.netZ
            if World.poseAt(e.bufX, e.bufZ, nil, e.bufT, e.bufHead, e.bufFill, &poseTmp) {
                tx = poseTmp[0]
                tz = poseTmp[1]
            }
            let mvx = (tx - e.x) * k, mvz = (tz - e.z) * k
            e.x += mvx
            e.z += mvz
            e.anim += dt
            e.hitT = max(0, e.hitT - dt)
            if e.netYawKnown { e.yaw = World.turnTo(e.yaw, e.netYaw, dt * 10) }
            else if mvx * mvx + mvz * mvz > 1e-6 { e.yaw = atan2(mvz, mvx) }
            let spd = dt > 0 ? sqrt(mvx * mvx + mvz * mvz) / dt : 0
            e.gait += (min(1, spd / 2.4) - e.gait) * min(1, dt * 9)
            e.walk += spd * dt * 2.15
            if e.charge > 0 && e.type != 1 { e.charge = max(0, e.charge - dt) }
        }
    }

    // ---------------------------------------------------------------- snapshot

    /// Snapshot wire format — every field order, width and endianness matches the Android
    /// build exactly (big endian, like `java.io.DataOutputStream`).
    func encodeSnapshot() -> [UInt8] {
        var w = ByteWriter(capacity: 768)
        w.byte(0x57)
        w.byte(UInt8(truncatingIfNeeded: wave))
        w.float(waveTimer)
        w.bool(duel)
        w.byte(UInt8(truncatingIfNeeded: teamSize))
        w.bool(ffa)
        w.byte(UInt8(truncatingIfNeeded: players.count))
        for p in players {
            w.byte(UInt8(truncatingIfNeeded: p.id))
            w.float(p.x)
            w.float(p.z)
            w.float(p.yaw)
            w.float(p.pitch)
            w.short(p.hp)
            w.bool(p.alive)
            w.short(p.kills)
            w.float(p.y)
            w.bool(p.crouch)
            w.short(p.deaths)
            w.byte(UInt8(truncatingIfNeeded: p.team))
            w.bool(p.online)
            w.byte(UInt8(truncatingIfNeeded: p.weapon))
            w.byte(UInt8(truncatingIfNeeded: max(-127, min(127, p.leanDir * 100))))
        }
        var n = 0
        for e in enemies where e.hp > 0 { n += 1 }
        w.byte(UInt8(min(127, n)))
        for e in enemies where e.hp > 0 {
            w.short(e.id)
            w.byte(UInt8(truncatingIfNeeded: e.type))
            w.float(e.x)
            w.float(e.z)
            w.short(e.hp)
            w.byte(UInt8(min(255, Int(e.charge * 60))))
            w.byte(e.team < 0 ? 0xff : UInt8(truncatingIfNeeded: e.team))
        }
        var mask = 0
        for i in 0..<pkCount where pkT[i] > 0 { mask |= 1 << i }
        w.byte(UInt8(truncatingIfNeeded: mask))
        // v2 extension: shot counters (remote gun audio) and enemy facing
        w.byte(0x32)
        w.byte(UInt8(truncatingIfNeeded: players.count))
        for p in players {
            w.byte(UInt8(truncatingIfNeeded: p.id))
            w.byte(UInt8(truncatingIfNeeded: p.shots))
            w.byte(UInt8(truncatingIfNeeded: p.weapon))
        }
        w.byte(UInt8(min(127, n)))
        var written = 0
        for e in enemies {
            if e.hp <= 0 || written >= 127 { continue }
            written += 1
            w.short(e.id)
            w.short(Int(World.angDiff(e.yaw, 0) * 10000))
            w.byte(UInt8(truncatingIfNeeded: e.shots))
        }
        return w.bytes
    }

    private func readExtension(_ r: inout ByteReader) {
        let pc = Int(r.byte())
        for _ in 0..<pc {
            let id = Int(r.byte())
            let shots = Int(r.byte())
            let weapon = Int(r.byte())
            guard let p = playerById(id), id != myId else { continue }
            if p.netShots >= 0 && shots != p.netShots && p.alive {
                let fired = (shots - p.netShots) & 0xff
                if fired < 8 {
                    remoteShot(min(World.weapons - 1, weapon), p.x, p.z)
                    if p.id != myId { p.kick = 0.02 }
                }
            }
            p.netShots = shots
        }
        let ec = Int(r.byte())
        for _ in 0..<ec {
            let id = Int(Int16(bitPattern: r.short()))
            let yaw = Float(Int16(bitPattern: r.short())) / 10000
            let shots = Int(r.byte())
            for e in enemies where e.id == id {
                e.netYaw = yaw
                if !e.netYawKnown { e.yaw = yaw }
                e.netYawKnown = true
                if e.netShots >= 0 && shots != e.netShots {
                    remoteShot(e.type == 2 ? World.wSniper : World.wRifle, e.x, e.z)
                    e.charge = 0.08
                }
                e.netShots = shots
                break
            }
        }
    }

    func applySnapshot(_ data: [UInt8]?) {
        guard let data = data, data.count >= 8 else { return }
        var r = ByteReader(data)
        guard r.byte() == 0x57 else { return }
        let w = Int(r.byte())
        if w != wave {
            wave = w
            addBanner("WAVE \(w)")
        }
        waveTimer = r.float()
        let duelFlag = r.bool()
        let ts = Int(r.byte())
        let ffaFlag = r.bool()
        if duelFlag {
            ffa = false
            if !duel || teamSize != ts {
                duel = true
                teamSize = max(1, min(2, ts == 0 ? 1 : ts))
                winTeam = -1
                roundT = 0
                enemies.removeAll()
                addBanner((teamSize == 1 ? "1v1 单挑房" : "2v2 团队房") + " · 先到 \(World.scoreLimit) 杀获胜")
            }
        } else if ffaFlag {
            duel = false
            teamSize = 1
            if !ffa {
                ffa = true
                winTeam = -1
                roundT = 0
                enemies.removeAll()
                addBanner("混战房 · 各自一队 · 先到 \(World.scoreFfa) 分获胜")
            }
        } else {
            duel = false
            ffa = false
        }
        let pc = Int(r.byte())
        var seen = [Bool](repeating: false, count: 16)
        for _ in 0..<pc {
            let id = Int(r.byte())
            let x = r.float(), z = r.float(), yaw = r.float(), pitch = r.float()
            let hp = Int(Int16(bitPattern: r.short()))
            let alive = r.bool()
            let kills = Int(UInt16(bitPattern: r.short()))
            let py = r.float()
            let crouch = r.bool()
            let deaths = Int(UInt16(bitPattern: r.short()))
            let team = Int(r.byte())
            let online = r.bool()
            let weapon = Int(r.byte())
            let leanDir = Int(Int8(bitPattern: r.byte()))
            let fresh = playerById(id) == nil
            let p = addPlayer(id, "玩家\(id)")
            if fresh { p.team = team }
            if id != myId { p.online = online }
            if id != myId {
                if weapon < World.weapons { p.weapon = weapon }
                p.leanDir = leanDir < -30 ? -1 : (leanDir > 30 ? 1 : 0)
            }
            if p.id == myId {
                let wasDead = !p.alive
                let prevHp = p.hp
                p.hp = hp
                p.alive = alive
                p.kills = kills
                p.deaths = deaths
                if alive && prevHp > hp && p.hp > 0 {
                    hurtT = 1
                    p.hitT = 0.2
                    sfx?.play(Sound.hurt)
                }
                if !alive {
                    p.deadT = 0.1
                    if !wasDead {
                        hurtT = 1
                        addBanner("你被击倒 · " + (room() ? "2" : "3") + " 秒后重生")
                    }
                }
                let ddx = x - p.x, ddz = z - p.z
                if p.alive && (wasDead || ddx * ddx + ddz * ddz > 9) {
                    p.x = x
                    p.z = z
                    p.y = py
                    p.yaw = yaw
                    p.pitch = pitch
                    p.vx = 0; p.vz = 0
                    p.lean = 0
                    p.leanX = 0; p.leanZ = 0
                    p.netKnown = true
                }
            } else {
                p.y = py
                p.crouch = crouch
                p.deaths = deaths
                p.netX = x
                p.netZ = z
                p.netYaw = yaw
                p.netPitch = pitch
                if p.hpKnown && alive && hp < p.hp { p.hitT = 0.2 }
                p.hpKnown = true
                p.bufX[p.bufHead] = x
                p.bufZ[p.bufHead] = z
                p.bufYaw[p.bufHead] = yaw
                p.bufT[p.bufHead] = Net.nowMs()
                p.bufHead = (p.bufHead + 1) % World.POSBUF
                if p.bufFill < World.POSBUF { p.bufFill += 1 }
                p.hp = hp
                p.alive = alive
                p.kills = kills
                if !p.netKnown {
                    p.x = x
                    p.z = z
                    p.yaw = yaw
                    p.netKnown = true
                }
            }
            if id >= 0 && id < 16 { seen[id] = true }
        }
        let ec = Int(r.byte())
        var eSeen = [Bool](repeating: false, count: 512)
        for _ in 0..<ec {
            let id = Int(Int16(bitPattern: r.short()))
            let type = Int(r.byte())
            let x = r.float(), z = r.float()
            let hp = Int(Int16(bitPattern: r.short()))
            let charge = Int(r.byte())
            let eteam = Int(r.byte())
            var existing = enemies.first { $0.id == id }
            if existing == nil {
                let n = Enemy()
                n.id = id
                n.x = x
                n.z = z
                enemies.append(n)
                existing = n
            }
            guard let e = existing else { continue }
            e.type = type
            e.team = eteam == 0xff ? -1 : eteam
            e.netX = x
            e.netZ = z
            e.bufX[e.bufHead] = x
            e.bufZ[e.bufHead] = z
            e.bufT[e.bufHead] = Net.nowMs()
            e.bufHead = (e.bufHead + 1) % World.POSBUF
            if e.bufFill < World.POSBUF { e.bufFill += 1 }
            if e.hpKnown && hp < e.hp { e.hitT = 0.2 }
            e.hp = hp
            if e.maxHp < hp { e.maxHp = hp }
            e.hpKnown = true
            e.charge = Float(charge) / 60
            if id >= 0 && id < 512 { eSeen[id] = true }
        }
        for i in stride(from: enemies.count - 1, through: 0, by: -1) {
            let e = enemies[i]
            if e.id >= 0 && e.id < 512 && !eSeen[e.id] {
                if e.hp < e.maxHp || e.hitT > 0 { addCorpse(e) }
                enemies.remove(at: i)
            }
        }
        for i in stride(from: players.count - 1, through: 0, by: -1) {
            let p = players[i]
            if p.id != myId && (p.id < 0 || p.id >= 16 || !seen[p.id]) { players.remove(at: i) }
        }
        if r.remaining > 0 {
            let mask = Int(r.byte())
            for i in 0..<pkCount {
                let taken = (mask & (1 << i)) != 0
                clientPickupSeen(i, taken)
                pkT[i] = taken ? 1 : 0
            }
        }
        if r.remaining > 0 && r.byte() == 0x32 { readExtension(&r) }
    }
}

// ---------------------------------------------------------------------- byte helpers

/// Big-endian writer matching `java.io.DataOutputStream`.
struct ByteWriter {
    private(set) var bytes: [UInt8] = []

    init(capacity: Int) { bytes.reserveCapacity(capacity) }

    mutating func byte(_ v: UInt8) { bytes.append(v) }

    mutating func bool(_ v: Bool) { bytes.append(v ? 1 : 0) }

    mutating func short(_ v: Int) {
        let u = UInt16(truncatingIfNeeded: v)
        bytes.append(UInt8(u >> 8))
        bytes.append(UInt8(u & 0xff))
    }

    mutating func float(_ v: Float) {
        let u = v.bitPattern
        bytes.append(UInt8((u >> 24) & 0xff))
        bytes.append(UInt8((u >> 16) & 0xff))
        bytes.append(UInt8((u >> 8) & 0xff))
        bytes.append(UInt8(u & 0xff))
    }
}

/// Big-endian reader with the same semantics as `java.io.DataInputStream`.
struct ByteReader {
    let data: [UInt8]
    var pos = 0

    init(_ d: [UInt8]) { data = d }

    var remaining: Int { data.count - pos }

    mutating func byte() -> UInt8 {
        guard pos < data.count else { return 0 }
        let v = data[pos]
        pos += 1
        return v
    }

    mutating func bool() -> Bool { byte() != 0 }

    mutating func short() -> UInt16 {
        let a = UInt16(byte()), b = UInt16(byte())
        return (a << 8) | b
    }

    mutating func float() -> Float {
        let a = UInt32(byte()), b = UInt32(byte()), c = UInt32(byte()), d = UInt32(byte())
        return Float(bitPattern: (a << 24) | (b << 16) | (c << 8) | d)
    }
}