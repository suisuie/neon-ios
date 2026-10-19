import UIKit

/// On-screen control layout, shared by the input handling (`ArenaView`) and the chrome
/// drawn by the HUD so the buttons are always exactly where the touches are read.
enum Controls {

    static func pauseRect(_ b: CGRect) -> CGRect {
        CGRect(x: b.width - 74, y: 8, width: 66, height: 56)
    }

    static func fire(_ b: CGRect) -> CGPoint { CGPoint(x: b.width - 110, y: b.height - 110) }
    static func fireRadius() -> CGFloat { 74 }

    static func ads(_ b: CGRect) -> CGPoint { CGPoint(x: b.width - 240, y: b.height - 96) }
    static func adsRadius() -> CGFloat { 46 }

    static func crouch(_ b: CGRect) -> CGPoint { CGPoint(x: b.width - 250, y: b.height - 220) }
    static func crouchRadius() -> CGFloat { 42 }

    static func leanLeft(_ b: CGRect) -> CGPoint { CGPoint(x: b.width - 350, y: b.height - 130) }
    static func leanRight(_ b: CGRect) -> CGPoint { CGPoint(x: b.width - 350, y: b.height - 220) }
    static func leanRadius() -> CGFloat { 38 }

    static func reload(_ b: CGRect) -> CGPoint { CGPoint(x: b.width - 150, y: b.height - 260) }
    static func reloadRadius() -> CGFloat { 40 }

    static func jump(_ b: CGRect) -> CGPoint { CGPoint(x: b.width - 430, y: b.height - 230) }
    static func jumpRadius() -> CGFloat { 40 }

    /// Ids used by `ArenaView.holdButtons`.
    enum Id {
        static let pause = 0
        static let fire = 2
        static let ads = 3
        static let crouch = 4
        static let leanLeft = 5
        static let leanRight = 6
        static let reload = 7
        static let jump = 8
        static let weapon = 9
    }

    static func button(at p: CGPoint, in b: CGRect) -> Int? {
        if pauseRect(b).contains(p) { return Id.pause }
        if hypot(p.x - fire(b).x, p.y - fire(b).y) < fireRadius() { return Id.fire }
        if hypot(p.x - ads(b).x, p.y - ads(b).y) < adsRadius() { return Id.ads }
        if hypot(p.x - crouch(b).x, p.y - crouch(b).y) < crouchRadius() { return Id.crouch }
        if hypot(p.x - leanLeft(b).x, p.y - leanLeft(b).y) < leanRadius() { return Id.leanLeft }
        if hypot(p.x - leanRight(b).x, p.y - leanRight(b).y) < leanRadius() { return Id.leanRight }
        if hypot(p.x - reload(b).x, p.y - reload(b).y) < reloadRadius() { return Id.reload }
        if hypot(p.x - jump(b).x, p.y - jump(b).y) < jumpRadius() { return Id.jump }
        // weapon strip under the ammo readout
        if p.y > b.height - 92 && p.x > b.width * 0.55 && p.x < b.width - 16 { return Id.weapon }
        return nil
    }
}