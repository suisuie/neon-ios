import UIKit
import OpenGLES
import QuartzCore

/// Hosts the GL surface, the HUD overlay and the fixed-timestep game loop — the iOS
/// counterpart of the Android `ArenaView`. Also owns the on-screen touch controls
/// (left thumb stick, look drag, fire/reload/jump/crouch/lean/scope buttons).
final class ArenaView: UIView {

    let world: World
    let renderer: Renderer
    private let glView: GLKViewCompat
    private let hud: HudView
    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var host: Net.Host?
    private var client: Net.Client?
    private var netNext: Int64 = 0
    private var netFireSent = false
    private var netWasUp = true
    private var netDropAt: Int64 = 0
    private(set) var paused = false
    var netStatus: String?
    var onExit: (() -> Void)?
    weak var game: Game?

    private var moveTouch: UITouch?
    private var moveOrigin: CGPoint = .zero
    private var moveVector = CGVector.zero
    private var lookTouch: UITouch?
    private var lookLast: CGPoint = .zero
    private var holdButtons: Set<Int> = []

    init(frame: CGRect, game: Game, world: World) {
        self.world = world
        self.game = game
        self.renderer = Renderer(world: world)
        glView = GLKViewCompat(frame: frame)
        hud = HudView(frame: frame)
        super.init(frame: frame)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        glView.attach(renderer)
        addSubview(glView)
        hud.game = game
        hud.world = world
        addSubview(hud)
        hud.frame = bounds
        glView.frame = bounds
        world.sfx = game.sfx
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        glView.frame = bounds
        hud.frame = bounds
    }

    // ------------------------------------------------------------------ lifecycle

    func start() {
        paused = false
        hud.isPaused = false
        lastTime = 0
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        host?.stop()
        host = nil
        client?.close()
        client = nil
    }

    func attachHost(_ h: Net.Host) {
        host = h
        h.start()
    }

    func attachClient(_ c: Net.Client) {
        client = c
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        var dt: Float = 0.016
        if lastTime > 0 { dt = Float(min(0.05, now - lastTime)) }
        lastTime = now
        guard !paused else {
            glView.drawOnce(dt: dt, flash: 0)
            return
        }
        let ms = Net.nowMs()
        applyInputs()
        host?.pump(ms, dt)
        world.update(dt)
        netStep(ms)
        glView.drawOnce(dt: dt, flash: world.muzzleT * 0.6 + world.hitT * 0.25)
        hud.setNeedsDisplay()
    }

    // ------------------------------------------------------------------ network

    private func netStep(_ now: Int64) {
        host?.broadcast(now)
        guard let client = client else { return }
        if let snap = client.pollSnapshot() { world.applySnapshot(snap) }
        while let msg = client.pollMessage() {
            if msg.hasPrefix("REC:") {
                let f = msg.components(separatedBy: ":")
                guard f.count >= 2, let id = Int(f[1]) else { continue }
                let again = f.count > 2 && f[2] == "1"
                if id != world.myId {
                    world.remapLocal(id)
                    world.addPlayer(id, world.myName)
                }
                if again {
                    world.setOnline(id, true)
                    world.addBanner("已重新连接")
                    game?.sfx.play(Sound.ui)
                }
                continue
            }
            if msg.hasPrefix("NAMES:") {
                let body = String(msg.dropFirst(6))
                for part in body.components(separatedBy: "|") {
                    guard let c = part.firstIndex(of: ":") else { continue }
                    guard let id = Int(part[part.startIndex..<c]) else { continue }
                    let name = String(part[part.index(after: c)...])
                    if let p = world.playerById(id) { p.name = name }
                    else { world.addPlayer(id, name) }
                }
            }
        }
        // 60 Hz input keeps the host's copy of this avatar tight against the screen,
        // and a trigger change is sent the moment it happens instead of on the tick
        if let me = world.local(), now >= netNext || me.fire != netFireSent {
            netNext = now + 16
            netFireSent = me.fire
            client.sendInput(me.mx, me.my, me.yaw, me.pitch, me.fire, me.ads,
                             me.crouch, me.wantJump, me.leanDir, me.weapon,
                             me.x, me.z, me.y, true)
            me.wantJump = false
        }
        // auto reconnect: keep playing, show a single banner per drop, retry in the background
        if !client.connected {
            if netWasUp {
                netWasUp = false
                netDropAt = now
                world.addBanner("网络中断，正在自动重连…")
            } else if world.bannerT <= 0 && now - netDropAt > 4000 {
                world.addBanner(client.status.isEmpty ? "重连中…" : client.status)
                netDropAt = now
            }
            netStatus = client.status.isEmpty ? "重连中…" : client.status
        } else {
            if !netWasUp {
                netWasUp = true
                game?.sfx.play(Sound.ui)
            }
            netStatus = nil
        }
    }

    // ------------------------------------------------------------------ input

    private func applyInputs() {
        guard let me = world.local() else { return }
        if !me.alive {
            me.mx = 0
            me.my = 0
            me.fire = false
            return
        }
        me.mx = Float(moveVector.dx)
        me.my = Float(-moveVector.dy)
        me.fire = holdButtons.contains(Controls.Id.fire)
        me.crouch = holdButtons.contains(Controls.Id.crouch)
        me.leanDir = holdButtons.contains(Controls.Id.leanLeft) ? -1
            : (holdButtons.contains(Controls.Id.leanRight) ? 1 : 0)
        me.ads = holdButtons.contains(Controls.Id.ads)
        if holdButtons.contains(Controls.Id.reload) {
            holdButtons.remove(Controls.Id.reload)
            me.wantReload = true
        }
        if holdButtons.contains(Controls.Id.jump) {
            holdButtons.remove(Controls.Id.jump)
            me.wantJump = true
        }
        if holdButtons.contains(Controls.Id.weapon) {
            holdButtons.remove(Controls.Id.weapon)
            World.cycleWeapon(me, 1)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            if paused {
                if Controls.pauseRect(bounds).contains(p) {
                    paused = false
                    hud.isPaused = false
                } else {
                    onExit?()
                }
                continue
            }
            if p.x < bounds.width * 0.42 && moveTouch == nil {
                moveTouch = t
                moveOrigin = p
                moveVector = .zero
                hud.stickOrigin = p
                hud.stickVector = .zero
                continue
            }
            if p.x > bounds.width * 0.55 && lookTouch == nil && p.y < bounds.height - 150 {
                lookTouch = t
                lookLast = p
                continue
            }
            // buttons
            if let b = Controls.button(at: p, in: bounds) {
                if b == Controls.Id.pause {
                    paused = true
                    hud.isPaused = true
                    moveVector = .zero
                    hud.stickOrigin = nil
                    holdButtons.removeAll()
                    if let me = world.local() {
                        me.mx = 0
                        me.my = 0
                        me.fire = false
                    }
                    continue
                }
                holdButtons.insert(b)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            if t == moveTouch {
                let dx = (p.x - moveOrigin.x) / 70
                let dy = (p.y - moveOrigin.y) / 70
                moveVector = CGVector(dx: max(-1, min(1, dx)), dy: max(-1, min(1, dy)))
                hud.stickVector = moveVector
            } else if t == lookTouch {
                let dx = Float(p.x - lookLast.x), dy = Float(p.y - lookLast.y)
                lookLast = p
                guard let me = world.local() else { continue }
                let sens: Float = me.ads ? 0.0016 : 0.0032
                me.yaw += dx * sens
                me.pitch = max(-1.35, min(1.35, me.pitch + dy * sens * 1.1))
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    private func endTouches(_ touches: Set<UITouch>) {
        for t in touches {
            if t == moveTouch {
                moveTouch = nil
                moveVector = .zero
                hud.stickOrigin = nil
                hud.stickVector = .zero
                continue
            }
            if t == lookTouch {
                lookTouch = nil
                continue
            }
            if let b = Controls.button(at: t.location(in: self), in: bounds) {
                holdButtons.remove(b)
            }
        }
        if moveTouch == nil {
            if let me = world.local() {
                me.mx = 0
                me.my = 0
            }
        }
    }

}

/// Thin wrapper that owns a `CAEAGLLayer` and an ES2 context. `GLKView` would need
/// GLKit; this keeps the render path identical to the Android `GLSurfaceView`.
final class GLKViewCompat: UIView {

    private var context: EAGLContext?
    private var framebuffer: GLuint = 0
    private var colorRenderbuffer: GLuint = 0
    private var depthRenderbuffer: GLuint = 0
    private var renderer: Renderer?
    private var bufW: GLsizei = 1
    private var bufH: GLsizei = 1

    override class var layerClass: AnyClass { CAEAGLLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        isUserInteractionEnabled = false
        contentScaleFactor = UIScreen.main.scale
        if let layer = layer as? CAEAGLLayer {
            layer.isOpaque = true
            layer.drawableProperties = [
                kEAGLDrawablePropertyRetainedBacking: false,
                kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8]
        }
        context = EAGLContext(api: .openGLES2)
        EAGLContext.setCurrent(context)
        setupBuffers()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        EAGLContext.setCurrent(context)
        if colorRenderbuffer != 0 { glDeleteRenderbuffers(1, &colorRenderbuffer) }
        if depthRenderbuffer != 0 { glDeleteRenderbuffers(1, &depthRenderbuffer) }
        if framebuffer != 0 { glDeleteFramebuffers(1, &framebuffer) }
    }

    private func setupBuffers() {
        guard let layer = layer as? CAEAGLLayer else { return }
        glGenFramebuffers(1, &framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        glGenRenderbuffers(1, &colorRenderbuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderbuffer)
        _ = context?.renderbufferStorage(Int(GL_RENDERBUFFER), from: layer)
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                                  GLenum(GL_RENDERBUFFER), colorRenderbuffer)
        var w: GLint = 0, h: GLint = 0
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_WIDTH), &w)
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_HEIGHT), &h)
        bufW = GLsizei(max(1, w))
        bufH = GLsizei(max(1, h))
        glGenRenderbuffers(1, &depthRenderbuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), depthRenderbuffer)
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_DEPTH_COMPONENT16),
                              GLsizei(w), GLsizei(h))
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_DEPTH_ATTACHMENT),
                                  GLenum(GL_RENDERBUFFER), depthRenderbuffer)
        if glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) != GLenum(GL_FRAMEBUFFER_COMPLETE) {
            NSLog("incomplete framebuffer")
        }
    }

    /// Hand over the renderer and give it the live drawable size.
    func attach(_ r: Renderer) {
        renderer = r
        EAGLContext.setCurrent(context)
        rebuildIfNeeded()
        r.setup(width: bufW, height: bufH)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        (layer as? CAEAGLLayer)?.contentsScale = contentScaleFactor
        EAGLContext.setCurrent(context)
        if rebuildIfNeeded() {
            renderer?.setup(width: bufW, height: bufH)
        }
    }

    /// Recreate the render buffers when the drawable size changed (rotation, split view).
    /// @return true when the size changed.
    @discardableResult
    private func rebuildIfNeeded() -> Bool {
        let want = GLsizei(max(1, bounds.width * contentScaleFactor))
        let wantH = GLsizei(max(1, bounds.height * contentScaleFactor))
        if want == bufW && wantH == bufH && framebuffer != 0 { return false }
        if colorRenderbuffer != 0 { glDeleteRenderbuffers(1, &colorRenderbuffer) }
        if depthRenderbuffer != 0 { glDeleteRenderbuffers(1, &depthRenderbuffer) }
        if framebuffer != 0 { glDeleteFramebuffers(1, &framebuffer) }
        setupBuffers()
        return true
    }

    func drawOnce(dt: Float, flash: Float) {
        EAGLContext.setCurrent(context)
        renderer?.draw(dt: dt, flash: flash)
        _ = context?.presentRenderbuffer(Int(GL_RENDERBUFFER))
    }
}