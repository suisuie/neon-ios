import UIKit

/// Flat 2D overlay drawn on top of the GL view: crosshair, health/ammo, scoreboard, kill
/// feed, hit markers and the touch-control chrome. Mirrors the Android `HudView` layout so
/// both builds feel the same in the hand.
final class HudView: UIView {

    weak var game: Game?
    weak var world: World?
    var isPaused = false
    /// live left-thumb stick, so the chrome follows the finger
    var stickOrigin: CGPoint?
    var stickVector = CGVector.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let world = world else { return }
        let w = rect.width, h = rect.height
        let player = world.local()

        // ---- damage vignette
        if world.hurtT > 0 {
            let a = CGFloat(min(1, world.hurtT)) * 0.5
            let colors = [UIColor(red: 0.9, green: 0.1, blue: 0.15, alpha: a).cgColor,
                          UIColor(red: 0.9, green: 0.1, blue: 0.15, alpha: 0).cgColor]
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors as CFArray, locations: [0, 1]) {
                ctx.drawRadialGradient(grad, startCenter: CGPoint(x: w / 2, y: h / 2),
                                       startRadius: min(w, h) * 0.32,
                                       endCenter: CGPoint(x: w / 2, y: h / 2),
                                       endRadius: min(w, h) * 0.72, options: [])
            }
        }

        // ---- crosshair
        let aim = CGPoint(x: w / 2, y: h / 2)
        var spread: CGFloat = 16
        if let me = player {
            let wi = max(0, min(World.weapons - 1, me.weapon))
            let base = me.ads ? World.wSpreadAds[wi] : World.wSpreadHip[wi]
            spread = 8 + CGFloat(base) * 460
        }
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.85).cgColor)
        ctx.setLineWidth(2)
        for (dx, dy) in [(spread, 0), (-spread, 0), (0, spread), (0, -spread)] as [(CGFloat, CGFloat)] {
            ctx.move(to: CGPoint(x: aim.x + dx, y: aim.y + dy))
            ctx.addLine(to: CGPoint(x: aim.x + dx * 1.9, y: aim.y + dy * 1.9))
        }
        ctx.strokePath()
        ctx.setFillColor(UIColor(red: 0.3, green: 1, blue: 0.9, alpha: 0.9).cgColor)
        ctx.fillEllipse(in: CGRect(x: aim.x - 1.5, y: aim.y - 1.5, width: 3, height: 3))

        // hit marker
        if world.hitT > 0 {
            let a = CGFloat(min(1, world.hitT / 0.22))
            ctx.setStrokeColor(UIColor(red: 1, green: 0.35, blue: 0.35, alpha: a).cgColor)
            ctx.setLineWidth(3)
            let r: CGFloat = 13
            for (sx, sy) in [(CGFloat(1), CGFloat(1)), (1, -1), (-1, 1), (-1, -1)] {
                ctx.move(to: CGPoint(x: aim.x + sx * r * 0.55, y: aim.y + sy * r * 0.55))
                ctx.addLine(to: CGPoint(x: aim.x + sx * r, y: aim.y + sy * r))
            }
            ctx.strokePath()
        }

        drawControls(ctx, rect: rect, world: world)

        // ---- banner
        if world.bannerT > 0 && !world.banner.isEmpty {
            let a = CGFloat(min(1, world.bannerT / 0.6))
            draw(text: world.banner, at: CGPoint(x: w / 2, y: h * 0.13), size: 20,
                 color: UIColor(white: 1, alpha: a), align: .center)
        }

        // ---- health / ammo bottom-left / bottom-right
        if let me = player {
            let hp = max(0, me.hp)
            let barW = min(240, w * 0.22), barH: CGFloat = 12
            let bx = 28.0, by = h - 64.0
            ctx.setFillColor(UIColor(white: 1, alpha: 0.18).cgColor)
            ctx.fill(CGRect(x: bx, y: by, width: barW, height: barH))
            let frac = CGFloat(min(1, Float(hp) / Float(World.MAX_HP)))
            let col = hp > 55 ? UIColor(red: 0.35, green: 0.95, blue: 0.55, alpha: 0.95)
                : (hp > 25 ? UIColor(red: 1, green: 0.8, blue: 0.25, alpha: 0.95)
                   : UIColor(red: 1, green: 0.32, blue: 0.32, alpha: 0.95))
            ctx.setFillColor(col.cgColor)
            ctx.fill(CGRect(x: bx, y: by, width: barW * frac, height: barH))
            draw(text: "\(hp)", at: CGPoint(x: bx + barW + 12, y: by - 5), size: 22,
                 color: .white, align: .left)

            let wi = max(0, min(World.weapons - 1, me.weapon))
            let name = World.wName[wi]
            let ammo = me.reloadT > 0 ? "换弹…" : "\(me.mag) / \(World.wMag[wi])"
            draw(text: "\(name)  \(ammo)", at: CGPoint(x: w - 28, y: h - 78), size: 22,
                 color: .white, align: .right)
            // weapon slots
            for i in 0..<World.weapons {
                let x = w - 28 - CGFloat(World.weapons - 1 - i) * 74
                let r = CGRect(x: x - 66, y: h - 56, width: 66, height: 30)
                ctx.setFillColor((i == wi ? UIColor(red: 0.25, green: 0.9, blue: 1, alpha: 0.35)
                                  : UIColor(white: 1, alpha: 0.12)).cgColor)
                ctx.fill(r)
                draw(text: World.wName[i], at: CGPoint(x: r.midX, y: r.minY + 6), size: 13,
                     color: UIColor(white: 1, alpha: i == wi ? 1 : 0.6), align: .center)
            }
        }

        // ---- scoreboard (rooms) or wave counter
        if world.duel {
            let mine = world.teamKills(world.local()?.team ?? 0)
            let theirs = world.teamKills((world.local()?.team ?? 0) == 0 ? 1 : 0)
            draw(text: "\(mine) : \(theirs)   目标 \(World.scoreLimit)",
                 at: CGPoint(x: w / 2, y: 20), size: 20, color: .white, align: .center)
        } else if world.ffa {
            let myKills = world.local()?.kills ?? 0
            draw(text: "混战 \(myKills) / \(World.scoreFfa)", at: CGPoint(x: w / 2, y: 20),
                 size: 20, color: .white, align: .center)
        } else {
            draw(text: "WAVE \(world.wave)", at: CGPoint(x: w / 2, y: 20), size: 20,
                 color: UIColor(red: 0.6, green: 0.95, blue: 1, alpha: 0.9), align: .center)
        }

        // ---- network status
        if let net = game?.arena?.netStatus, !net.isEmpty {
            draw(text: net, at: CGPoint(x: w - 20, y: 16), size: 13,
                 color: UIColor(red: 1, green: 0.75, blue: 0.35, alpha: 0.95), align: .right)
        }
        if isPaused {
            ctx.setFillColor(UIColor(white: 0, alpha: 0.55).cgColor)
            ctx.fill(rect)
            draw(text: "暂停", at: CGPoint(x: w / 2, y: h / 2 - 30), size: 40,
                 color: .white, align: .center)
            draw(text: "点右上角继续 · 点这里返回菜单", at: CGPoint(x: w / 2, y: h / 2 + 24), size: 18,
                 color: UIColor(white: 1, alpha: 0.7), align: .center)
        }
    }

    /// On-screen buttons: fire, scope, crouch, lean, reload, jump, pause, weapon strip.
    private func drawControls(_ ctx: CGContext, rect: CGRect, world: World) {
        let b = rect
        let player = world.local()

        // left thumb stick
        if let o = stickOrigin {
            let base = UIBezierPath(ovalIn: CGRect(x: o.x - 62, y: o.y - 62, width: 124, height: 124))
            ctx.setFillColor(UIColor(white: 1, alpha: 0.07).cgColor)
            ctx.addPath(base.cgPath)
            ctx.fillPath()
            ctx.setStrokeColor(UIColor(white: 1, alpha: 0.22).cgColor)
            ctx.setLineWidth(2)
            ctx.addPath(base.cgPath)
            ctx.strokePath()
            let kx = o.x + CGFloat(stickVector.dx) * 46
            let ky = o.y + CGFloat(stickVector.dy) * 46
            ctx.setFillColor(UIColor(red: 0.4, green: 0.95, blue: 1, alpha: 0.45).cgColor)
            ctx.fillEllipse(in: CGRect(x: kx - 26, y: ky - 26, width: 52, height: 52))
        }

        func circle(_ c: CGPoint, _ r: CGFloat, _ fill: UIColor, _ title: String,
                    _ textColor: UIColor = .white) {
            let path = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.setFillColor(fill.cgColor)
            ctx.addPath(path.cgPath)
            ctx.fillPath()
            ctx.setStrokeColor(UIColor(white: 1, alpha: 0.25).cgColor)
            ctx.setLineWidth(1.5)
            ctx.addPath(path.cgPath)
            ctx.strokePath()
            draw(text: title, at: CGPoint(x: c.x, y: c.y - 8), size: min(15, r * 0.5),
                 color: textColor, align: .center, width: r * 2)
        }

        // fire
        let fireOn = player?.fire ?? false
        circle(Controls.fire(b), Controls.fireRadius(),
               UIColor(red: 1, green: 0.28, blue: 0.3, alpha: fireOn ? 0.55 : 0.26), "开火")
        // scope
        let adsOn = player?.ads ?? false
        circle(Controls.ads(b), Controls.adsRadius(),
               UIColor(red: 0.3, green: 0.9, blue: 1, alpha: adsOn ? 0.5 : 0.2), "开镜")
        // crouch
        let crouchOn = player?.crouch ?? false
        circle(Controls.crouch(b), Controls.crouchRadius(),
               UIColor(white: 1, alpha: crouchOn ? 0.4 : 0.15), "蹲")
        // lean
        circle(Controls.leanLeft(b), Controls.leanRadius(), UIColor(white: 1, alpha: 0.14), "左探")
        circle(Controls.leanRight(b), Controls.leanRadius(), UIColor(white: 1, alpha: 0.14), "右探")
        // reload / jump
        let reloading = (player?.reloadT ?? 0) > 0
        circle(Controls.reload(b), Controls.reloadRadius(),
               UIColor(red: 1, green: 0.82, blue: 0.3, alpha: reloading ? 0.45 : 0.2), "换弹")
        circle(Controls.jump(b), Controls.jumpRadius(), UIColor(white: 1, alpha: 0.14), "跳")

        // pause
        let pr = Controls.pauseRect(b)
        ctx.setFillColor(UIColor(white: 1, alpha: 0.16).cgColor)
        ctx.fill(pr)
        draw(text: "II", at: CGPoint(x: pr.minX, y: pr.minY + 14), size: 20,
             color: UIColor(white: 1, alpha: 0.8), align: .center, width: pr.width)
    }

    private func draw(text: String, at p: CGPoint, size: CGFloat, color: UIColor,
                      align: NSTextAlignment, width fixed: CGFloat = 600) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: size, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: style]
        let s = NSAttributedString(string: text, attributes: attrs)
        let width = fixed
        let rect = CGRect(x: p.x - (align == .center ? width / 2 : (align == .right ? width : 0)),
                          y: p.y, width: width, height: size * 2)
        s.draw(in: rect)
    }
}