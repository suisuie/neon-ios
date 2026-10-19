import Foundation
import OpenGLES
import simd

/// Minimal OpenGL ES 2 renderer: box geometry, one directional light, distance fog.
/// A straight port of the Android `Renderer.java` shaders and palette, with the same
/// palette per map, the same first-person weapon models and the same arena layout.
final class Renderer {

    private static let vs = """
    uniform mat4 uVP;
    uniform mat4 uM;
    attribute vec3 aPos;
    attribute vec3 aNrm;
    attribute vec3 aCol;
    uniform float uTexScale;
    varying vec2 vUV;
    varying vec3 vW;
    varying vec3 vN;
    varying vec3 vC;
    void main(){
      vec4 w = uM * vec4(aPos, 1.0);
      vW = w.xyz;
      vN = mat3(uM) * aNrm;
      vC = aCol;
      vec3 an = abs(aNrm);
      vec2 uv = an.y > 0.5 ? w.xz : (an.x > 0.5 ? vec2(w.z, -w.y) : vec2(w.x, -w.y));
      vUV = uv * uTexScale;
      gl_Position = uVP * w;
    }
    """

    private static let fs = """
    precision mediump float;
    varying vec2 vUV;
    uniform vec3 uEye;
    uniform vec3 uFog;
    uniform float uFogEnd;
    uniform float uEmis;
    uniform float uFlash;
    varying vec3 vW;
    varying vec3 vN;
    varying vec3 vC;
    void main(){
      vec3 n = normalize(vN);
      float d = max(dot(n, normalize(vec3(0.32, 0.86, 0.22))), 0.0);
      float hemi = 0.5 + 0.5 * n.y;
      float light = 0.34 + 0.46 * hemi + 0.55 * d;
      vec3 base = vC;
      float ao = 0.62 + 0.38 * smoothstep(0.0, 0.9, vW.y);
      base *= mix(1.0, ao, 1.0 - abs(n.y));
      vec3 c = base * mix(light, 1.0, uEmis);
      c += vec3(uFlash) * 0.7;
      float dist = length(vW - uEye);
      float f = clamp((dist - 14.0) / max(1.0, uFogEnd - 14.0), 0.0, 1.0);
      c = mix(c, uFog, f);
      gl_FragColor = vec4(c, 1.0);
    }
    """

    private var prog: GLuint = 0
    private var aPos: GLint = 0, aNrm: GLint = 0, aCol: GLint = 0
    private var uVP: GLint = 0, uM: GLint = 0, uEye: GLint = 0
    private var uFog: GLint = 0, uFogEnd: GLint = 0, uEmis: GLint = 0, uFlash: GLint = 0

    private var staticVbo: GLuint = 0
    private var staticVerts = 0
    private var dynVbo: GLuint = 0
    private var lightVbo: GLuint = 0
    private var lightVerts = 0
    private var gunVbo: GLuint = 0
    private var gunVerts = 0
    private var magVbo: GLuint = 0
    private var magVerts = 0
    private var flashVbo: GLuint = 0
    private var flashVerts = 0
    private let magMesh = Mesh()
    private let flashMesh = Mesh()
    /// current head-tilt (lean) roll in degrees, used by the view model
    private var leanNow: Float = 0
    private let muzzleZ: [Float] = [-1.02, -0.80, -1.32]
    private var builtGun = -1

    private var statics = Mesh()
    private var lights = Mesh()
    private var dyn = Mesh()
    private var gun = Mesh()

    private var vp = simd_float4x4(1)
    private var proj = simd_float4x4(1)
    private var view = simd_float4x4(1)
    private var hudVP = simd_float4x4(1)

    private var width: GLsizei = 1, height: GLsizei = 1
    private(set) var fovNow: Float = 74
    private var ads: Float = 0
    private var builtMap = -1
    private let world: World

    init(world: World) {
        self.world = world
    }

    // ------------------------------------------------------------------ setup

    func setup(width: GLsizei, height: GLsizei) {
        self.width = width
        self.height = height
        glViewport(0, 0, width, height)
        if prog == 0 { build() }
        if builtMap != world.mapId { buildArena() }
    }

    func hudProjection() -> simd_float4x4 { hudVP }

    private func build() {
        prog = Renderer.link(Renderer.vs, Renderer.fs)
        aPos = glGetAttribLocation(prog, "aPos")
        aNrm = glGetAttribLocation(prog, "aNrm")
        aCol = glGetAttribLocation(prog, "aCol")
        uVP = glGetUniformLocation(prog, "uVP")
        uM = glGetUniformLocation(prog, "uM")
        uEye = glGetUniformLocation(prog, "uEye")
        uFog = glGetUniformLocation(prog, "uFog")
        uFogEnd = glGetUniformLocation(prog, "uFogEnd")
        uEmis = glGetUniformLocation(prog, "uEmis")
        uFlash = glGetUniformLocation(prog, "uFlash")
        buildGuns()
    }

    private static func link(_ vs: String, _ fs: String) -> GLuint {
        let v = compile(GLenum(GL_VERTEX_SHADER), vs)
        let f = compile(GLenum(GL_FRAGMENT_SHADER), fs)
        let p = glCreateProgram()
        glAttachShader(p, v)
        glAttachShader(p, f)
        glLinkProgram(p)
        var ok: GLint = 0
        glGetProgramiv(p, GLenum(GL_LINK_STATUS), &ok)
        if ok == 0 {
            var log = [GLchar](repeating: 0, count: 1024)
            glGetProgramInfoLog(p, 1024, nil, &log)
            NSLog("shader link failed: %@", String(cString: log))
        }
        glDeleteShader(v)
        glDeleteShader(f)
        return p
    }

    private static func compile(_ type: GLenum, _ src: String) -> GLuint {
        let s = glCreateShader(type)
        src.withCString { c in
            var p: UnsafePointer<GLchar>? = c
            glShaderSource(s, 1, &p, nil)
        }
        glCompileShader(s)
        var ok: GLint = 0
        glGetShaderiv(s, GLenum(GL_COMPILE_STATUS), &ok)
        if ok == 0 {
            var log = [GLchar](repeating: 0, count: 1024)
            glGetShaderInfoLog(s, 1024, nil, &log)
            NSLog("shader compile failed: %@", String(cString: log))
        }
        return s
    }

    private func upload(_ mesh: Mesh, into vbo: inout GLuint, verts: inout Int) {
        let floats = mesh.floats
        if floats.isEmpty { verts = 0; return }
        if vbo == 0 { glGenBuffers(1, &vbo) }
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vbo)
        floats.withUnsafeBufferPointer { b in
            glBufferData(GLenum(GL_ARRAY_BUFFER),
                         b.count * MemoryLayout<Float>.size, b.baseAddress, GLenum(GL_STATIC_DRAW))
        }
        verts = mesh.verts
    }

    // ------------------------------------------------------------------ arena

    private func buildArena() {
        statics.clear()
        lights.clear()
        let C = World.CELL
        let th = World.theme(world.mapId)
        let floor = (th[0], th[1], th[2])
        let wall = (th[3], th[4], th[5])
        let ceil = (th[6], th[7], th[8])
        let trim = (th[9], th[10], th[11])
        let lamp = (th[12], th[13], th[14])
        let crate = (th[18], th[19], th[20])

        for cx in 0..<World.GW {
            for cz in 0..<World.GH {
                let x0 = Float(cx) * C, z0 = Float(cz) * C
                let v = world.solidHeight(cx, cz)
                if v > 0 {
                    // wall or crate: textured sides plus a floor tile underneath
                    let h = v
                    let c = v >= World.WALL_H ? wall : crate
                    statics.box(cx: x0 + C / 2, cz: z0 + C / 2, y0: 0, y1: h,
                                hx: C / 2, hz: C / 2, r: c.0, g: c.1, b: c.2)
                    if v >= World.WALL_H {
                        // neon trim strip along the top of the outer walls
                        if cx == 0 || cz == 0 || cx == World.GW - 1 || cz == World.GH - 1 {
                            statics.box(cx: x0 + C / 2, cz: z0 + C / 2, y0: h, y1: h + 0.12,
                                        hx: C / 2 * 1.02, hz: C / 2 * 1.02,
                                        r: trim.0, g: trim.1, b: trim.2)
                        }
                    }
                } else {
                    statics.flat(x0, z0, x0 + C, z0 + C, y: 0, r: floor.0, g: floor.1, b: floor.2)
                    // ceiling
                    statics.flat(x0, z0, x0 + C, z0 + C, y: World.WALL_H + 0.9,
                                 r: ceil.0, g: ceil.1, b: ceil.2)
                }
            }
        }
        // ceiling lamps over the open cells
        for cx in stride(from: 4, to: World.GW - 2, by: 5) {
            for cz in stride(from: 4, to: World.GH - 2, by: 5) {
                if world.solidHeight(cx, cz) > 0 { continue }
                lights.box(cx: (Float(cx) + 0.5) * C, cz: (Float(cz) + 0.5) * C,
                           y0: World.WALL_H + 0.62, y1: World.WALL_H + 0.72,
                           hx: C * 0.6, hz: 0.5, r: lamp.0, g: lamp.1, b: lamp.2)
            }
        }
        upload(statics, into: &staticVbo, verts: &staticVerts)
        upload(lights, into: &lightVbo, verts: &lightVerts)
        builtMap = world.mapId
    }

    /// Shared view-model bits. The gun itself is rebuilt by `drawViewGun` whenever the
    /// player swaps weapons (three different models, like the Android build).
    private func buildGuns() {
        // shared magazine, slid down during a reload
        magMesh.clear()
        magMesh.box(cx: 0, cz: -0.22, y0: -0.30, y1: -0.02, hx: 0.055, hz: 0.14,
                    r: 0.13, g: 0.14, b: 0.17)
        upload(magMesh, into: &magVbo, verts: &magVerts)
        // muzzle flash: a small star of boxes at the barrel tip
        flashMesh.clear()
        flashMesh.box(cx: 0, cz: 0, y0: -0.05, y1: 0.05, hx: 0.05, hz: 0.05, r: 1.8, g: 1.2, b: 0.5)
        flashMesh.box(cx: 0, cz: 0, y0: -0.02, y1: 0.02, hx: 0.16, hz: 0.02, r: 1.6, g: 1.0, b: 0.35)
        flashMesh.box(cx: 0, cz: 0, y0: -0.02, y1: 0.02, hx: 0.02, hz: 0.16, r: 1.6, g: 1.0, b: 0.35)
        upload(flashMesh, into: &flashVbo, verts: &flashVerts)
    }

    // ------------------------------------------------------------------ frame

    /// Draw one frame. `flash` is the muzzle/impact white-out (0..1).
    func draw(dt: Float, flash: Float) {
        let localPlayer = world.local()
        var camX: Float = 0, camZ: Float = 0
        var camY = World.EYE
        var yaw: Float = 0, pitch: Float = 0, roll: Float = 0
        var weapon = World.wRifle
        var adsTarget = false
        if let me = localPlayer {
            camX = me.x + me.leanX
            camZ = me.z + me.leanZ
            weapon = me.weapon
            roll = World.leanRoll(me.lean)
            camY -= abs(me.lean) * 0.06
            yaw = world.aimYaw(me)
            pitch = me.pitch + me.kick * 0.6
            camY += World.eyeY(me) + World.bobY(me) - World.EYE - (me.alive ? 0 : 0.85)
            let lt = me.landT
            camY -= lt * lt * 0.11
            adsTarget = me.ads && me.alive && me.switchT <= 0
        }
        pitch = max(-1.45, min(1.45, pitch))
        ads += ((adsTarget ? 1 : 0) - ads) * min(1, dt * 16)
        let fov = 74 - World.wZoom[max(0, min(World.weapons - 1, weapon))] * ads
        fovNow = fov
        leanNow = roll

        proj = Renderer.perspective(fov, Float(width) / Float(max(1, height)), 0.05, 110)
        let dx = cos(pitch) * cos(yaw)
        let dy = sin(pitch)
        let dz = cos(pitch) * sin(yaw)
        let up = Renderer.rolledUp(dx: dx, dy: dy, dz: dz, rollDeg: roll)
        view = Renderer.lookAt(eye: SIMD3(camX, camY, camZ),
                               center: SIMD3(camX + dx, camY + dy, camZ + dz), up: up)
        vp = proj * view
        hudVP = vp

        let th = World.theme(world.mapId)
        glClearColor(th[15], th[16], th[17], 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))
        glUseProgram(prog)
        glEnable(GLenum(GL_DEPTH_TEST))
        glEnableVertexAttribArray(GLuint(aPos))
        glEnableVertexAttribArray(GLuint(aNrm))
        glEnableVertexAttribArray(GLuint(aCol))
        var vpCopy = vp
        withUnsafePointer(to: &vpCopy) { p in
            p.withMemoryRebound(to: GLfloat.self, capacity: 16) {
                glUniformMatrix4fv(uVP, 1, GLboolean(GL_FALSE), $0)
            }
        }
        glUniform3f(uEye, camX, camY, camZ)
        glUniform3f(uFog, th[15], th[16], th[17])
        glUniform1f(uFogEnd, 42)
        glUniform1f(uFlash, flash)

        Renderer.identity.withUnsafeBufferPointer {
            glUniformMatrix4fv(uM, 1, GLboolean(GL_FALSE), $0.baseAddress)
        }
        glUniform1f(uEmis, 0)
        drawVbo(staticVbo, staticVerts)

        glUniform1f(uEmis, 1)
        drawVbo(lightVbo, lightVerts)

        buildEntities()
        upload(dyn, into: &dynVbo, verts: &dynVerts)
        glUniform1f(uEmis, 0.18)
        drawVbo(dynVbo, dynVerts)

        drawViewGun(weapon)

        glDisableVertexAttribArray(GLuint(aPos))
        glDisableVertexAttribArray(GLuint(aNrm))
        glDisableVertexAttribArray(GLuint(aCol))
    }

    private var dynVerts = 0

    private static let identity: [GLfloat] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]

    private func drawVbo(_ vbo: GLuint, _ verts: Int) {
        if verts == 0 || vbo == 0 { return }
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vbo)
        let stride = GLsizei(9 * MemoryLayout<Float>.size)
        glVertexAttribPointer(GLuint(aPos), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), stride,
                              UnsafeRawPointer(bitPattern: 0))
        glVertexAttribPointer(GLuint(aNrm), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), stride,
                              UnsafeRawPointer(bitPattern: 3 * MemoryLayout<Float>.size))
        glVertexAttribPointer(GLuint(aCol), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), stride,
                              UnsafeRawPointer(bitPattern: 6 * MemoryLayout<Float>.size))
        glDrawArrays(GLenum(GL_TRIANGLES), 0, GLsizei(verts))
    }

    // ------------------------------------------------------------------ entities

    private func buildEntities() {
        dyn.clear()
        // enemies
        for e in world.enemies where e.hp > 0 {
            var r: Float = 0.15, g: Float = 0.50, b: Float = 0.60
            if e.type == World.botType && (world.duel || world.ffa) {
                (r, g, b) = Renderer.sideColor(e.team)
            } else if e.type == 1 {
                r = 0.68; g = 0.15; b = 0.26
            } else if e.type == 2 {
                r = 0.90; g = 0.56; b = 0.13
            }
            let hit = max(0, e.hitT) * 2.4
            r = min(1, r + hit); g = min(1, g + hit); b = min(1, b + hit)
            let glow = 0.30 + min(1, e.charge * 1.6) * 0.9
            Humanoid.build(dyn, x: e.x, z: e.z, baseY: 0, yaw: e.yaw, scale: World.enemyScale(e),
                           phase: e.walk, gait: e.gait, leanX: 0, leanZ: 0, crouch: 0,
                           r: r, g: g, b: b, glow: glow, charge: e.charge,
                           accent: e.type == 1 ? 1.15 : 0.35,
                           variant: (e.id &* 2654435) >> 7)
        }
        // remote players
        for p in world.players where p.id != world.myId {
            var r: Float = p.alive ? 0.22 : 0.30
            var g: Float = p.alive ? 0.66 : 0.30
            var b: Float = p.alive ? 0.92 : 0.34
            if (world.duel || world.ffa) && p.alive {
                (r, g, b) = Renderer.sideColor(p.team)
            }
            let phit = max(0, p.hitT) * 2.4
            r = min(1, r + phit); g = min(1, g + phit); b = min(1, b + phit)
            let spd = sqrt(p.vx * p.vx + p.vz * p.vz)
            let gait = min(1, spd / 3.4)
            if !p.alive {
                Humanoid.buildFallen(dyn, x: p.x, z: p.z, yaw: p.yaw, scale: 1, t: p.downT,
                                     r: r, g: g, b: b, variant: p.id * 977 + 3)
                continue
            }
            Humanoid.build(dyn, x: p.x, z: p.z, baseY: p.y, yaw: p.yaw, scale: 1,
                           phase: p.bob, gait: gait, leanX: p.leanX, leanZ: p.leanZ,
                           crouch: p.crouchAmt, r: r, g: g, b: b, glow: 0.55, charge: 0,
                           accent: 0.42, variant: p.id * 977 + 3)
        }
        for c in world.corpses {
            var r: Float = 0.4, g: Float = 0.4, b: Float = 0.4
            if c.type == World.botType && (world.duel || world.ffa) {
                (r, g, b) = Renderer.sideColor(c.team)
            } else if c.type == 1 {
                r = 0.68; g = 0.15; b = 0.26
            } else if c.type == 2 {
                r = 0.90; g = 0.56; b = 0.13
            } else {
                r = 0.15; g = 0.50; b = 0.60
            }
            Humanoid.buildFallen(dyn, x: c.x, z: c.z, yaw: c.yaw, scale: c.scale, t: c.t,
                                 r: r, g: g, b: b,
                                 variant: Int(c.x * 131 + c.z * 71))
        }
        // pickups: a floating, spinning crate on a glowing pad
        let tt = world.time
        for i in 0..<world.pkCount {
            let px = world.pkX[i], pz = world.pkZ[i]
            let hp = world.pkType[i] == World.pkHealth
            let pr: Float = hp ? 0.25 : 1.10, pg: Float = hp ? 1.10 : 0.80, pb: Float = hp ? 0.45 : 0.20
            let on: Float = world.pkT[i] > 0 ? 0.25 : 1
            dyn.box(cx: px, cz: pz, y0: 0.01, y1: 0.05, hx: 0.42, hz: 0.42,
                    r: pr * 0.5 * on, g: pg * 0.5 * on, b: pb * 0.5 * on)
            if world.pkT[i] > 0 { continue }
            let y = 0.55 + sin(tt * 2.4 + Float(i)) * 0.08
            let yaw = tt * 1.6 + Float(i)
            dyn.boxYaw(cx: px, cz: pz, y0: y - 0.16, y1: y + 0.16, hx: 0.18, hz: 0.18, yaw: yaw,
                       r: pr * 0.8, g: pg * 0.8, b: pb * 0.8)
            if hp {
                dyn.boxYaw(cx: px, cz: pz, y0: y - 0.04, y1: y + 0.04, hx: 0.20, hz: 0.06, yaw: yaw,
                           r: 1.3, g: 1.3, b: 1.3)
                dyn.boxYaw(cx: px, cz: pz, y0: y - 0.12, y1: y + 0.12, hx: 0.06, hz: 0.20, yaw: yaw,
                           r: 1.3, g: 1.3, b: 1.3)
            } else {
                for k in [-1, 0, 1] {
                    let ox = cos(yaw) * 0.08 * Float(k), oz = sin(yaw) * 0.08 * Float(k)
                    dyn.box(cx: px + ox, cz: pz + oz, y0: y + 0.16, y1: y + 0.30,
                            hx: 0.025, hz: 0.025, r: 1.3, g: 1.0, b: 0.4)
                }
            }
        }
        // sparks / impacts
        for s in world.sparks {
            let alpha = (s.color >> 24) & 0xff
            let k = max(0, s.life / max(0.05, s.maxLife))
            let size = s.size * (0.4 + k) * (alpha < 13 ? 1.6 : 1)
            dyn.box(cx: s.x, cz: s.z, y0: s.y - size, y1: s.y + size, hx: size, hz: size,
                    r: Float((s.color >> 16) & 0xff) / 255 * 1.5,
                    g: Float((s.color >> 8) & 0xff) / 255 * 1.5,
                    b: Float(s.color & 0xff) / 255 * 1.5)
        }
    }

    static func sideColor(_ team: Int) -> (Float, Float, Float) {
        let t = ((team % 5) + 5) % 5
        switch t {
        case 0: return (0.95, 0.28, 0.30)
        case 1: return (0.25, 0.55, 1.00)
        case 2: return (1.00, 0.78, 0.18)
        case 3: return (0.42, 0.95, 0.42)
        default: return (0.85, 0.40, 1.00)
        }
    }

    /// First-person weapon in view space: `uVP` is the bare projection (identity view),
    /// exactly like the Android renderer, and the model matrix carries the pose.
    private func drawViewGun(_ weapon: Int) {
        guard let me = world.local() else { return }
        let wi = max(0, min(World.weapons - 1, weapon))
        if builtGun != wi {
            gun.clear()
            switch wi {
            case World.wSmg: buildSmgMesh(gun)
            case World.wSniper: buildSniperMesh(gun)
            default: buildRifleMesh(gun)
            }
            gunVerts = 0
            upload(gun, into: &gunVbo, verts: &gunVerts)
            builtGun = wi
        }
        let a = ads
        let bob = sin(me.bob) * 0.012
        let bobX = cos(me.bob * 0.5) * 0.006
        let kick = me.kick
        let baseX: Float = wi == World.wSmg ? 0.215 : (wi == World.wSniper ? 0.245 : 0.235)
        let baseY: Float = wi == World.wSmg ? -0.170 : (wi == World.wSniper ? -0.200 : -0.185)
        var hx = (baseX + bobX) * (1 - a)
        var hy = baseY * (1 - a) - 0.235 * a + bob
        var hz: Float = -0.46 - 0.10 * a
        var yawDeg: Float = -5 * (1 - a)
        var pitchDeg: Float = 0
        var rollDeg: Float = 0
        var magOff: Float = 0
        // the rifle rides with the head, so a peek tilts it and drags it a little
        let leanK = max(-1, min(1, leanNow / 11))
        rollDeg += leanNow * 0.62
        hx -= leanK * 0.030

        // weapon swap: the gun is thrown down out of frame and lifted back up
        if me.switchT > 0 {
            let total = max(0.01, World.SWITCH_TIME)
            let t = 1 - max(0, min(1, me.switchT / total))
            let down = 1 - Renderer.smooth(t, 0, 0.46)
            let up = Renderer.smooth(t, 0.42, 1)
            let drop = max(down, 1 - up)
            hy -= 0.62 * drop
            hx += 0.10 * drop
            pitchDeg += 34 * drop
            rollDeg += 12 * drop
            hz += 0.06 * drop
        }

        // reload: cant the gun over, drop the empty mag and slap a fresh one in
        let rt = me.reloadT
        if rt > 0 {
            let total = max(0.01, me.reloadTotal)
            let t = 1 - max(0, min(1, rt / total))
            let tilt = Renderer.smooth(t, 0, 0.24) * (1 - Renderer.smooth(t, 0.82, 1))
            rollDeg = -36 * tilt
            pitchDeg = -11 * tilt
            hy -= 0.06 * tilt
            hx -= 0.02 * tilt * a
            if t < 0.5 { magOff = -0.42 * Renderer.smooth(t, 0.12, 0.46) }
            else { magOff = -0.42 * (1 - Renderer.smooth(t, 0.52, 0.86)) }
        }

        var gunProj = proj
        withUnsafePointer(to: &gunProj) { p in
            p.withMemoryRebound(to: GLfloat.self, capacity: 16) {
                glUniformMatrix4fv(uVP, 1, GLboolean(GL_FALSE), $0)
            }
        }
        glUniform3f(uEye, 0, 0, 0)
        glUniform1f(uFogEnd, 220)
        glUniform1f(uEmis, 0.45)
        glUniform1f(uFlash, 0)

        // model = translate * rotX(kick) * rotZ(roll) * rotX(pitch) * rotY(yaw)
        var model = Renderer.translation(hx, hy, hz + kick * 0.35)
        model = model * Renderer.rotationX(kick * 5)
        model = model * Renderer.rotationZ(rollDeg * .pi / 180)
        model = model * Renderer.rotationX(pitchDeg * .pi / 180)
        model = model * Renderer.rotationY(yawDeg * .pi / 180)
        var m = model
        withUnsafePointer(to: &m) { p in
            p.withMemoryRebound(to: GLfloat.self, capacity: 16) {
                glUniformMatrix4fv(uM, 1, GLboolean(GL_FALSE), $0)
            }
        }
        drawVbo(gunVbo, gunVerts)

        // magazine, slid down the gun-local Y axis while reloading
        if magOff > -0.40 {
            let magM = model * Renderer.translation(0, magOff, 0)
            var mm = magM
            withUnsafePointer(to: &mm) { p in
                p.withMemoryRebound(to: GLfloat.self, capacity: 16) {
                    glUniformMatrix4fv(uM, 1, GLboolean(GL_FALSE), $0)
                }
            }
            drawVbo(magVbo, magVerts)
        }

        // muzzle flash
        if world.muzzleT > 0.05 {
            let f = model * Renderer.translation(0, 0.01, muzzleZ[wi])
            var fm = f
            withUnsafePointer(to: &fm) { p in
                p.withMemoryRebound(to: GLfloat.self, capacity: 16) {
                    glUniformMatrix4fv(uM, 1, GLboolean(GL_FALSE), $0)
                }
            }
            glUniform1f(uEmis, 1)
            drawVbo(flashVbo, flashVerts)
        }
        // restore the world state for the next frame
        var vpCopy = vp
        withUnsafePointer(to: &vpCopy) { p in
            p.withMemoryRebound(to: GLfloat.self, capacity: 16) {
                glUniformMatrix4fv(uVP, 1, GLboolean(GL_FALSE), $0)
            }
        }
        glUniform1f(uFogEnd, 42)
    }

    /// 0 before `from`, 1 after `to`, smooth in between.
    static func smooth(_ t: Float, _ from: Float, _ to: Float) -> Float {
        if to <= from { return t >= to ? 1 : 0 }
        var k = (t - from) / (to - from)
        k = max(0, min(1, k))
        return k * k * (3 - 2 * k)
    }

    private func buildRifleMesh(_ g: Mesh) {
        g.box(cx: 0, cz: -0.30, y0: -0.10, y1: 0.10, hx: 0.075, hz: 0.34, r: 0.16, g: 0.18, b: 0.22)
        g.box(cx: 0, cz: -0.27, y0: 0.10, y1: 0.15, hx: 0.030, hz: 0.30, r: 0.10, g: 0.11, b: 0.14)
        g.box(cx: 0, cz: -0.72, y0: -0.055, y1: 0.055, hx: 0.032, hz: 0.30, r: 0.20, g: 0.22, b: 0.27)
        g.box(cx: 0, cz: -0.86, y0: -0.030, y1: 0.030, hx: 0.020, hz: 0.12, r: 0.12, g: 0.14, b: 0.18)
        g.box(cx: 0, cz: 0.02, y0: -0.32, y1: -0.02, hx: 0.045, hz: 0.10, r: 0.11, g: 0.12, b: 0.15)
        g.box(cx: 0, cz: 0.26, y0: -0.09, y1: 0.07, hx: 0.05, hz: 0.18, r: 0.14, g: 0.15, b: 0.19)
        g.box(cx: 0.062, cz: -0.40, y0: -0.06, y1: 0.04, hx: 0.008, hz: 0.16, r: 0.15, g: 0.9, b: 1.1)
        g.box(cx: -0.062, cz: -0.40, y0: -0.06, y1: 0.04, hx: 0.008, hz: 0.16, r: 0.15, g: 0.9, b: 1.1)
        g.box(cx: 0, cz: -0.44, y0: 0.13, y1: 0.18, hx: 0.012, hz: 0.012, r: 0.9, g: 1.0, b: 1.1)
    }

    private func buildSmgMesh(_ g: Mesh) {
        g.box(cx: 0, cz: -0.26, y0: -0.09, y1: 0.08, hx: 0.070, hz: 0.24, r: 0.17, g: 0.19, b: 0.24)
        g.box(cx: 0, cz: -0.56, y0: -0.05, y1: 0.05, hx: 0.028, hz: 0.16, r: 0.22, g: 0.24, b: 0.30)
        g.box(cx: 0, cz: -0.66, y0: -0.03, y1: 0.03, hx: 0.020, hz: 0.06, r: 0.56, g: 0.58, b: 0.64)
        g.box(cx: 0, cz: -0.30, y0: -0.30, y1: -0.02, hx: 0.026, hz: 0.030, r: 0.10, g: 0.11, b: 0.14)
        g.box(cx: 0, cz: 0.00, y0: -0.30, y1: -0.02, hx: 0.042, hz: 0.09, r: 0.11, g: 0.12, b: 0.15)
        g.box(cx: 0.058, cz: -0.34, y0: -0.05, y1: 0.03, hx: 0.007, hz: 0.13, r: 1.05, g: 0.55, b: 0.16)
        g.box(cx: -0.058, cz: -0.34, y0: -0.05, y1: 0.03, hx: 0.007, hz: 0.13, r: 1.05, g: 0.55, b: 0.16)
        g.box(cx: 0, cz: -0.40, y0: 0.10, y1: 0.15, hx: 0.010, hz: 0.010, r: 1.0, g: 0.8, b: 0.5)
    }

    private func buildSniperMesh(_ g: Mesh) {
        g.box(cx: 0, cz: -0.38, y0: -0.09, y1: 0.09, hx: 0.062, hz: 0.42, r: 0.13, g: 0.15, b: 0.19)
        g.box(cx: 0, cz: -1.00, y0: -0.045, y1: 0.045, hx: 0.026, hz: 0.34, r: 0.18, g: 0.20, b: 0.25)
        g.box(cx: 0, cz: -1.30, y0: -0.032, y1: 0.032, hx: 0.018, hz: 0.08, r: 0.10, g: 0.12, b: 0.16)
        g.box(cx: 0, cz: -1.22, y0: -0.055, y1: 0.055, hx: 0.036, hz: 0.03, r: 0.30, g: 0.32, b: 0.38)
        g.box(cx: 0, cz: -0.34, y0: 0.10, y1: 0.17, hx: 0.036, hz: 0.26, r: 0.09, g: 0.10, b: 0.13)
        g.box(cx: 0, cz: -0.62, y0: 0.085, y1: 0.185, hx: 0.048, hz: 0.04, r: 0.14, g: 0.15, b: 0.19)
        g.box(cx: 0, cz: -0.10, y0: 0.09, y1: 0.18, hx: 0.042, hz: 0.035, r: 0.11, g: 0.12, b: 0.16)
        g.box(cx: 0, cz: 0.06, y0: 0.02, y1: 0.12, hx: 0.05, hz: 0.12, r: 0.12, g: 0.13, b: 0.17)
        g.box(cx: 0, cz: 0.04, y0: -0.30, y1: -0.02, hx: 0.042, hz: 0.09, r: 0.11, g: 0.12, b: 0.15)
        g.box(cx: 0, cz: 0.30, y0: -0.08, y1: 0.08, hx: 0.046, hz: 0.16, r: 0.13, g: 0.14, b: 0.18)
        g.box(cx: 0.05, cz: -0.60, y0: 0.05, y1: 0.10, hx: 0.006, hz: 0.10, r: 0.35, g: 0.95, b: 1.2)
    }

    // ------------------------------------------------------------------ math

    static func perspective(_ fovy: Float, _ aspect: Float, _ near: Float, _ far: Float) -> simd_float4x4 {
        let f = 1 / tan(fovy * .pi / 360)
        let nf = 1 / (near - far)
        return simd_float4x4(columns: (
            SIMD4(f / aspect, 0, 0, 0),
            SIMD4(0, f, 0, 0),
            SIMD4(0, 0, (far + near) * nf, -1),
            SIMD4(0, 0, 2 * far * near * nf, 0)))
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(center - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)
        return simd_float4x4(columns: (
            SIMD4(s.x, u.x, -f.x, 0),
            SIMD4(s.y, u.y, -f.y, 0),
            SIMD4(s.z, u.z, -f.z, 0),
            SIMD4(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)))
    }

    /// Head tilt rolls about the camera's own forward axis (same as Android `Cam.rolledUp`).
    static func rolledUp(dx: Float, dy: Float, dz: Float, rollDeg: Float) -> SIMD3<Float> {
        let r = rollDeg * .pi / 180
        let right = simd_normalize(SIMD3(-dz, 0, dx))
        let up = simd_normalize(simd_cross(right, SIMD3(dx, dy, dz)))
        return simd_normalize(up * cos(r) + right * sin(r))
    }

    static func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0),
                                SIMD4(0, 0, 1, 0), SIMD4(x, y, z, 1)))
    }

    static func rotationX(_ a: Float) -> simd_float4x4 {
        let c = cos(a), s = sin(a)
        return simd_float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, c, s, 0),
                                       SIMD4(0, -s, c, 0), SIMD4(0, 0, 0, 1)))
    }

    static func rotationY(_ a: Float) -> simd_float4x4 {
        let c = cos(a), s = sin(a)
        return simd_float4x4(columns: (SIMD4(c, 0, -s, 0), SIMD4(0, 1, 0, 0),
                                       SIMD4(s, 0, c, 0), SIMD4(0, 0, 0, 1)))
    }

    static func rotationZ(_ a: Float) -> simd_float4x4 {
        let c = cos(a), s = sin(a)
        return simd_float4x4(columns: (SIMD4(c, s, 0, 0), SIMD4(-s, c, 0, 0),
                                       SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)))
    }
}

// ---------------------------------------------------------------------- mesh

/// Interleaved position/normal/colour triangle soup, same layout and face shading as the
/// Android `Mesh`: every oriented box shades its six faces differently, which is what makes
/// the box skeleton read as a solid body instead of a flat silhouette.
final class Mesh {
    private(set) var floats: [Float] = []
    var verts: Int { floats.count / 9 }

    private var ax = SIMD3<Float>(1, 0, 0)
    private var ay = SIMD3<Float>(0, 1, 0)
    private var az = SIMD3<Float>(0, 0, 1)

    func clear() { floats.removeAll(keepingCapacity: true) }

    /// Append another mesh's vertices unchanged.
    func append(floats other: [Float]) { floats.append(contentsOf: other) }

    func vert(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ c: SIMD3<Float>) {
        floats.append(contentsOf: [p.x, p.y, p.z, n.x, n.y, n.z, c.x, c.y, c.z])
    }

    /// Four corners in order (two triangles), counter-clockwise seen from outside.
    func quad(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>,
              _ n: SIMD3<Float>, _ col: SIMD3<Float>) {
        for p in [p0, p1, p2, p0, p2, p3] { vert(p, n, col) }
    }

    /// Axis-aligned box from y0 (bottom) to y1 (top), centred on cx/cz.
    func box(cx: Float, cz: Float, y0: Float, y1: Float, hx: Float, hz: Float,
             r: Float, g: Float, b: Float) {
        let x0 = cx - hx, x1 = cx + hx, z0 = cz - hz, z1 = cz + hz
        let c = SIMD3(r, g, b)
        quad(SIMD3(x1, y0, z0), SIMD3(x1, y0, z1), SIMD3(x1, y1, z1), SIMD3(x1, y1, z0),
             SIMD3(1, 0, 0), c * 0.92)
        quad(SIMD3(x0, y0, z1), SIMD3(x0, y0, z0), SIMD3(x0, y1, z0), SIMD3(x0, y1, z1),
             SIMD3(-1, 0, 0), c * 0.78)
        quad(SIMD3(x0, y0, z1), SIMD3(x1, y0, z1), SIMD3(x1, y1, z1), SIMD3(x0, y1, z1),
             SIMD3(0, 0, 1), c)
        quad(SIMD3(x1, y0, z0), SIMD3(x0, y0, z0), SIMD3(x0, y1, z0), SIMD3(x1, y1, z0),
             SIMD3(0, 0, -1), c * 0.82)
        quad(SIMD3(x0, y1, z0), SIMD3(x1, y1, z0), SIMD3(x1, y1, z1), SIMD3(x0, y1, z1),
             SIMD3(0, 1, 0), c * 1.08)
        quad(SIMD3(x0, y0, z1), SIMD3(x1, y0, z1), SIMD3(x1, y0, z0), SIMD3(x0, y0, z0),
             SIMD3(0, -1, 0), c * 0.6)
    }

    /// Oriented box: centre with half extents along three orthonormal axes.
    /// Limbs are built this way so a box skeleton can be posed instead of stacked blocks.
    func obox(_ c: SIMD3<Float>, hx: Float, hy: Float, hz: Float,
              _ ax0: SIMD3<Float>, _ ay0: SIMD3<Float>, _ az0: SIMD3<Float>,
              r: Float, g: Float, b: Float) {
        ax = ax0; ay = ay0; az = az0
        let col = SIMD3(r, g, b)
        face(c, hx, hy, hz, 0, 1, [-1, -1, -1, 1, 1, 1, 1, -1], col * 0.92)
        face(c, hx, hy, hz, 0, -1, [-1, 1, -1, -1, 1, -1, 1, 1], col * 0.78)
        face(c, hx, hy, hz, 2, 1, [-1, -1, 1, -1, 1, 1, -1, 1], col)
        face(c, hx, hy, hz, 2, -1, [1, -1, -1, -1, -1, 1, 1, 1], col * 0.82)
        face(c, hx, hy, hz, 1, 1, [-1, -1, 1, -1, 1, 1, -1, 1], col * 1.08)
        face(c, hx, hy, hz, 1, -1, [-1, 1, 1, 1, 1, -1, -1, -1], col * 0.6)
    }

    /// One face of an oriented box. `axis` is the face normal axis, `sign` its direction;
    /// `uv` holds the four corners as (u, v) sign pairs of the two other axes.
    private func face(_ c: SIMD3<Float>, _ hx: Float, _ hy: Float, _ hz: Float,
                      _ axis: Int, _ sign: Int, _ uv: [Float], _ col: SIMD3<Float>) {
        let n: SIMD3<Float>
        switch axis {
        case 0: n = ax * Float(sign)
        case 1: n = ay * Float(sign)
        default: n = az * Float(sign)
        }
        let q = [corner(c, hx, hy, hz, axis, sign, uv[0], uv[1]),
                 corner(c, hx, hy, hz, axis, sign, uv[2], uv[3]),
                 corner(c, hx, hy, hz, axis, sign, uv[4], uv[5]),
                 corner(c, hx, hy, hz, axis, sign, uv[6], uv[7])]
        quad(q[0], q[1], q[2], q[3], n, col)
    }

    private func corner(_ c: SIMD3<Float>, _ hx: Float, _ hy: Float, _ hz: Float,
                        _ axis: Int, _ sign: Int, _ u: Float, _ v: Float) -> SIMD3<Float> {
        var s = SIMD3<Float>(0, 0, 0)
        switch axis {
        case 0: s = SIMD3(Float(sign), u, v)
        case 1: s = SIMD3(u, Float(sign), v)
        default: s = SIMD3(u, v, Float(sign))
        }
        return c + ax * (s.x * hx) + ay * (s.y * hy) + az * (s.z * hz)
    }

    /// Box rotated about the vertical axis: forward is (cos yaw, 0, sin yaw).
    func boxYaw(cx: Float, cz: Float, y0: Float, y1: Float, hx: Float, hz: Float, yaw: Float,
                r: Float, g: Float, b: Float) {
        let cy = (y0 + y1) * 0.5, hy = abs(y1 - y0) * 0.5
        let sy = sin(yaw), cyw = cos(yaw)
        obox(SIMD3(cx, cy, cz), hx: hx, hy: hy, hz: hz,
             SIMD3(-sy, 0, cyw), SIMD3(0, 1, 0), SIMD3(cyw, 0, sy), r: r, g: g, b: b)
    }

    /// Box segment between two joints: half thickness `hs` sideways, `hd` deep.
    func seg(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ hs: Float, _ hd: Float,
             _ r: Float, _ g: Float, _ bl: Float) {
        let d = b - a
        let len = simd_length(d)
        if len < 1e-4 { return }
        let dir = d / len
        var ref = SIMD3<Float>(0, 1, 0)
        if abs(dir.y) > 0.9 { ref = SIMD3(1, 0, 0) }
        var side = simd_cross(dir, ref)
        if simd_length(side) < 1e-5 {
            ref = SIMD3(0, 0, 1)
            side = simd_cross(dir, ref)
            if simd_length(side) < 1e-5 { return }
        }
        side = simd_normalize(side)
        let depth = simd_cross(side, dir)
        obox((a + b) * 0.5, hx: hs, hy: len * 0.5, hz: hd,
             side, dir, depth, r: r, g: g, b: bl)
    }

    /// Horizontal quad with both faces so a floor tile is never invisibly back-faced.
    func flat(_ x0: Float, _ z0: Float, _ x1: Float, _ z1: Float, y: Float,
              r: Float, g: Float, b: Float) {
        let c = SIMD3(r, g, b)
        quad(SIMD3(x0, y, z0), SIMD3(x1, y, z0), SIMD3(x1, y, z1), SIMD3(x0, y, z1),
             SIMD3(0, 1, 0), c)
        quad(SIMD3(x0, y, z0), SIMD3(x0, y, z1), SIMD3(x1, y, z1), SIMD3(x1, y, z0),
             SIMD3(0, -1, 0), c * 0.85)
    }
}
