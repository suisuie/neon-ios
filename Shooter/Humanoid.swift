import Foundation
import simd

/// Articulated soldier shared by the wave enemies and remote players — the iOS port of
/// `Humanoid.java`. Built from posed boxes with real proportions and kit: face with nose,
/// brow and ears, headgear, plate carrier with pouches, belt and holster, knee pads,
/// two-part boots, gloves and a rifle. Joint heights match `World.bodyRegion`.
enum Humanoid {

    private static let skin: [[Float]] = [
        [0.80, 0.60, 0.47], [0.63, 0.45, 0.33], [0.44, 0.30, 0.21], [0.87, 0.70, 0.57]]

    /// Body frame shared by the helpers below. `bx` centres a box `f` metres forward and
    /// `rt` right of the body's foot position.
    private struct F {
        let m: Mesh
        let x: Float, z: Float
        let fx: Float, fz: Float
        let rx: Float, rz: Float
        let yaw: Float, s: Float

        func bx(_ f: Float, _ rt: Float, _ y0: Float, _ y1: Float, _ hw: Float, _ hd: Float,
                _ c: [Float], _ k: Float) {
            m.boxYaw(cx: x + (fx * f + rx * rt) * s, cz: z + (fz * f + rz * rt) * s,
                     y0: y0, y1: y1, hx: hw * s, hz: hd * s, yaw: yaw,
                     r: c[0] * k, g: c[1] * k, b: c[2] * k)
        }
    }

    static func build(_ dyn: Mesh, x: Float, z: Float, baseY: Float, yaw: Float, scale: Float,
                      phase: Float, gait: Float, leanX: Float, leanZ: Float, crouch: Float,
                      r: Float, g: Float, b: Float, glow: Float, charge: Float, accent: Float,
                      variant: Int) {
        let v = variant & 0xffff
        let cf = 1 - 0.26 * max(0, min(1, crouch))
        let s = scale
        let fx = cos(yaw), fz = sin(yaw)
        let rx = -fz, rz = fx
        let sw = sin(phase) * gait
        let sw2 = sin(phase + 1.9) * gait

        let team: [Float] = [r, g, b]
        var cloth = mix([0.30, 0.31, 0.24], team, 0.22)
        if (v >> 4) % 3 == 1 { cloth = mix([0.36, 0.32, 0.24], team, 0.2) }      // khaki
        if (v >> 4) % 3 == 2 { cloth = mix([0.22, 0.24, 0.27], team, 0.2) }      // urban grey
        let pants = scaleArr(cloth, 0.82)
        let vest = mix([0.16, 0.17, 0.16], team, 0.72)
        let webbing = scaleArr(vest, 0.7)
        let black: [Float] = [0.07, 0.075, 0.08]
        let metal: [Float] = [0.15, 0.16, 0.18]
        let boot: [Float] = [0.13, 0.11, 0.09]
        let sk = skin[v % skin.count]
        let glove: [Float] = (v % 2 == 0) ? black : [0.32, 0.27, 0.20]

        let hipY = baseY + 0.92 * cf * s
        let waistY = baseY + 1.06 * cf * s
        let chestY = baseY + 1.34 * cf * s
        let shoulderY = baseY + 1.37 * cf * s
        let neckY = baseY + 1.43 * cf * s
        let headY0 = baseY + 1.46 * cf * s
        let headY1 = baseY + 1.69 * cf * s
        let ux = leanX * 0.75, uz = leanZ * 0.75

        // ---- legs
        for side in [-1, 1] {
            let sf = Float(side)
            let footFwd = sw * 0.26 * sf * s
            let lift = max(0, sw * sf) * 0.07 * s
            let hx = x + rx * 0.10 * sf * s, hz = z + rz * 0.10 * sf * s
            let ax2 = hx + fx * footFwd, az2 = hz + fz * footFwd
            let ankleY = baseY + 0.10 * s + lift
            let kneeY = (hipY + ankleY) * 0.5 + 0.02 * s
            let kneeFwd = 0.05 * s + 0.10 * s * gait + 0.12 * s * crouch
            let kx = (hx + ax2) * 0.5 + fx * kneeFwd, kz = (hz + az2) * 0.5 + fz * kneeFwd
            dyn.seg(SIMD3(hx, hipY, hz), SIMD3(kx, kneeY, kz), 0.088 * s, 0.095 * s,
                    pants[0], pants[1], pants[2])
            dyn.seg(SIMD3(kx, kneeY, kz), SIMD3(ax2, ankleY, az2), 0.064 * s, 0.072 * s,
                    pants[0] * 0.95, pants[1] * 0.95, pants[2] * 0.95)
            let mx = (hx + kx) * 0.5 + rx * 0.085 * sf * s, mz = (hz + kz) * 0.5 + rz * 0.085 * sf * s
            dyn.boxYaw(cx: mx, cz: mz, y0: (hipY + kneeY) * 0.5 - 0.07 * s,
                       y1: (hipY + kneeY) * 0.5 + 0.04 * s, hx: 0.02 * s, hz: 0.06 * s, yaw: yaw,
                       r: pants[0] * 0.85, g: pants[1] * 0.85, b: pants[2] * 0.85)
            dyn.boxYaw(cx: kx + fx * 0.04 * s, cz: kz + fz * 0.04 * s,
                       y0: kneeY - 0.055 * s, y1: kneeY + 0.05 * s,
                       hx: 0.07 * s, hz: 0.045 * s, yaw: yaw,
                       r: black[0] * 1.4, g: black[1] * 1.4, b: black[2] * 1.4)
            dyn.boxYaw(cx: ax2, cz: az2, y0: baseY + lift + 0.03 * s, y1: ankleY + 0.05 * s,
                       hx: 0.068 * s, hz: 0.075 * s, yaw: yaw, r: boot[0], g: boot[1], b: boot[2])
            dyn.boxYaw(cx: ax2 + fx * 0.05 * s, cz: az2 + fz * 0.05 * s,
                       y0: baseY + lift, y1: baseY + lift + 0.06 * s,
                       hx: 0.07 * s, hz: 0.13 * s, yaw: yaw,
                       r: boot[0] * 0.7, g: boot[1] * 0.7, b: boot[2] * 0.7)
        }

        // ---- hips, belt, holster
        var o = F(m: dyn, x: x, z: z, fx: fx, fz: fz, rx: rx, rz: rz, yaw: yaw, s: s)
        o.bx(0, 0, hipY - 0.13 * s, hipY + 0.04 * s, 0.15, 0.10, pants, 1)
        o.bx(0, 0, hipY - 0.02 * s, hipY + 0.035 * s, 0.158, 0.108, webbing, 1)
        o.bx(0.11, 0, hipY - 0.015 * s, hipY + 0.03 * s, 0.03, 0.005, metal, 1.6)
        o.bx(0, 0.17, hipY - 0.16 * s, hipY + 0.01 * s, 0.03, 0.06, black, 1.2)

        // ---- torso (follows the lean)
        o = F(m: dyn, x: x + ux, z: z + uz, fx: fx, fz: fz, rx: rx, rz: rz, yaw: yaw, s: s)
        o.bx(0, 0, hipY + 0.02 * s, waistY + 0.04 * s, 0.145, 0.095, cloth, 0.95)
        o.bx(0, 0, waistY, chestY, 0.18, 0.11, cloth, 1)
        o.bx(0.02, 0, waistY + 0.02 * s, chestY - 0.01 * s, 0.165, 0.125, vest, 1)
        o.bx(0.13, 0, waistY + 0.05 * s, chestY - 0.03 * s, 0.13, 0.012, vest, 1.12)
        for k in [-1, 0, 1] {
            o.bx(0.15, Float(k) * 0.075, waistY + 0.03 * s, waistY + 0.15 * s, 0.03, 0.022, webbing, 1.15)
        }
        o.bx(0.15, 0, waistY + 0.17 * s, waistY + 0.24 * s, 0.08, 0.016, webbing, 1.05)
        o.bx(0.17, -0.09, chestY - 0.07 * s, chestY - 0.035 * s, 0.03, 0.004,
             [glow * 0.4 + r * 0.5, glow * 0.8 + g * 0.5, glow * 0.7 + b * 0.5], 1)
        o.bx(0, 0.1, chestY - 0.02 * s, shoulderY + 0.02 * s, 0.035, 0.12, vest, 0.9)
        o.bx(0, -0.1, chestY - 0.02 * s, shoulderY + 0.02 * s, 0.035, 0.12, vest, 0.9)
        let pack = (v >> 2) % 3
        if pack == 0 {
            o.bx(-0.17, 0, waistY - 0.02 * s, chestY - 0.02 * s, 0.13, 0.06, webbing, 0.95)
            o.bx(-0.235, 0, waistY + 0.05 * s, waistY + 0.2 * s, 0.09, 0.012, webbing, 0.8)
        } else if pack == 1 {
            o.bx(-0.15, 0, waistY + 0.06 * s, chestY - 0.04 * s, 0.10, 0.035, webbing, 0.9)
            o.bx(-0.15, -0.1, chestY - 0.06 * s, chestY + 0.06 * s, 0.03, 0.03, black, 1.2)
            o.bx(-0.15, -0.1, chestY + 0.06 * s, chestY + 0.32 * s, 0.005, 0.005, black, 1)
        }

        // ---- shoulders and arms holding the rifle
        let weaponY = baseY + 1.18 * cf * s
        let handF: [Float] = [0.28, 0.47]
        for side in [-1, 1] {
            let sf = Float(side)
            let sx2 = o.x + rx * 0.19 * sf * s, sz2 = o.z + rz * 0.19 * sf * s
            dyn.boxYaw(cx: sx2, cz: sz2, y0: shoulderY - 0.08 * s, y1: shoulderY + 0.03 * s,
                       hx: 0.06 * s, hz: 0.07 * s, yaw: yaw,
                       r: cloth[0] * 1.05, g: cloth[1] * 1.05, b: cloth[2] * 1.05)
            let fwd = handF[side > 0 ? 0 : 1]
            let handX = o.x + fx * fwd * s + rx * (side > 0 ? 0.05 : -0.02) * s + sw2 * 0.02 * s
            let handZ = o.z + fz * fwd * s + rz * (side > 0 ? 0.05 : -0.02) * s
            let handY = weaponY + (side > 0 ? -0.04 : -0.01) * s
            let ex2 = (sx2 + handX) * 0.5 + rx * 0.07 * sf * s - fx * 0.05 * s
            let ez2 = (sz2 + handZ) * 0.5 + rz * 0.07 * sf * s - fz * 0.05 * s
            let ey2 = (shoulderY + handY) * 0.5 - 0.07 * s
            dyn.seg(SIMD3(sx2, shoulderY - 0.02 * s, sz2), SIMD3(ex2, ey2, ez2),
                    0.056 * s, 0.06 * s, cloth[0], cloth[1], cloth[2])
            let fore: [Float] = v % 4 == 2 ? sk : cloth
            dyn.seg(SIMD3(ex2, ey2, ez2), SIMD3(handX, handY, handZ), 0.046 * s, 0.05 * s,
                    fore[0] * 0.97, fore[1] * 0.97, fore[2] * 0.97)
            dyn.boxYaw(cx: handX, cz: handZ, y0: handY - 0.035 * s, y1: handY + 0.035 * s,
                       hx: 0.04 * s, hz: 0.05 * s, yaw: yaw, r: glove[0], g: glove[1], b: glove[2])
        }

        // ---- neck, head, face
        o.bx(0, 0, neckY - 0.04 * s, headY0 + 0.03 * s, 0.05, 0.05, sk, 0.92)
        o.bx(0, 0, neckY - 0.02 * s, neckY + 0.02 * s, 0.075, 0.075, cloth, 0.9)
        let hy0 = headY0, hy1 = headY1 - 0.035 * s
        o.bx(0.005, 0, hy0, hy1, 0.082, 0.095, sk, 1)
        o.bx(0.03, 0, hy0 - 0.005 * s, hy0 + 0.05 * s, 0.07, 0.075, sk, 0.95)
        o.bx(0.105, 0, hy0 + 0.075 * s, hy0 + 0.115 * s, 0.014, 0.012, sk, 1.02)
        o.bx(0.096, 0, hy0 + 0.125 * s, hy0 + 0.142 * s, 0.07, 0.008, sk, 0.8)
        for side in [-1, 1] {
            let sf = Float(side)
            o.bx(0.094, 0.035 * sf, hy0 + 0.105 * s, hy0 + 0.125 * s, 0.017, 0.004, [0.06, 0.05, 0.05], 1)
            o.bx(-0.005, 0.088 * sf, hy0 + 0.07 * s, hy0 + 0.12 * s, 0.01, 0.025, sk, 0.9)
        }
        o.bx(0.096, 0, hy0 + 0.035 * s, hy0 + 0.045 * s, 0.03, 0.006, [0.35, 0.18, 0.16], 1)
        if v % 5 == 1 || v % 5 == 3 {
            o.bx(0.06, 0, hy0 - 0.01 * s, hy0 + 0.06 * s, 0.075, 0.05, [0.16, 0.11, 0.08], 1)
        }
        let hat = (v >> 1) % 4
        let cover = mix(cloth, team, 0.5)
        if hat == 0 || hat == 3 {
            o.bx(0, 0, hy1 - 0.065 * s, headY1 + 0.04 * s, 0.1, 0.112, cover, 1)
            o.bx(-0.01, 0, hy1 - 0.085 * s, hy1 - 0.055 * s, 0.104, 0.11, cover, 0.85)
            o.bx(0.012, 0, headY1 + 0.04 * s, headY1 + 0.06 * s, 0.08, 0.09, cover, 1.05)
            o.bx(0.11, 0, hy1 - 0.04 * s, hy1, 0.025, 0.01, metal, 1.4)
            if hat == 3 {
                o.bx(0.1, 0, hy1 - 0.03 * s, hy1 + 0.015 * s, 0.075, 0.014, black, 1)
                o.bx(0.113, 0, hy1 - 0.022 * s, hy1 + 0.008 * s, 0.06, 0.003,
                     [0.3 * accent + glow * 0.4, 0.7 * accent + glow * 0.2, accent], 1)
            }
        } else if hat == 1 {
            o.bx(0, 0, hy1 - 0.02 * s, headY1 + 0.01 * s, 0.088, 0.1, cover, 1)
            o.bx(0.13, 0, hy1 - 0.02 * s, hy1 - 0.005 * s, 0.075, 0.05, cover, 0.9)
            for side in [-1, 1] {
                o.bx(-0.005, 0.095 * Float(side), hy0 + 0.06 * s, hy0 + 0.13 * s, 0.016, 0.04, black, 1.3)
            }
        } else {
            o.bx(-0.005, 0, hy1 - 0.035 * s, headY1 + 0.015 * s, 0.088, 0.1, scaleArr(cover, 0.75), 1)
            o.bx(0.098, 0, hy0 + 0.1 * s, hy0 + 0.13 * s, 0.075, 0.008, black, 1)
        }

        // ---- rifle: stock, receiver, optic, mag, handguard, barrel
        o = F(m: dyn, x: x + ux, z: z + uz, fx: fx, fz: fz, rx: rx, rz: rz, yaw: yaw, s: s)
        let wy = weaponY
        o.bx(0.06, 0.08, wy - 0.05 * s, wy + 0.02 * s, 0.022, 0.08, black, 1.1)
        o.bx(0.26, 0.06, wy - 0.035 * s, wy + 0.035 * s, 0.024, 0.13, metal, 1)
        o.bx(0.25, 0.06, wy + 0.035 * s, wy + 0.08 * s, 0.018, 0.045, black, 1)
        o.bx(0.22, 0.06, wy + 0.042 * s, wy + 0.072 * s, 0.006, 0.08,
             [0.25 * accent + glow * 0.3, 0.45 * accent, 0.6 * accent], 0.6)
        o.bx(0.29, 0.06, wy - 0.14 * s, wy - 0.03 * s, 0.018, 0.03, black, 1.2)
        o.bx(0.215, 0.06, wy - 0.11 * s, wy - 0.03 * s, 0.016, 0.02, black, 1)
        o.bx(0.47, 0.06, wy - 0.03 * s, wy + 0.03 * s, 0.026, 0.09, metal, 0.9)
        o.bx(0.62, 0.06, wy - 0.012 * s, wy + 0.012 * s, 0.011, 0.07, black, 1)
        if charge > 0 {
            let mx = o.x + (fx * 0.72 + rx * 0.06) * s, mz = o.z + (fz * 0.72 + rz * 0.06) * s
            let sz = 0.06 + 0.22 * min(1, charge)
            dyn.box(cx: mx, cz: mz, y0: wy - sz, y1: wy + sz, hx: sz * 0.8, hz: sz * 0.8,
                    r: 1.6, g: 1.05, b: 0.45)
        }
    }

    /// A body that went down: built standing, then every vertex rotated about the feet so
    /// it topples backwards, lies still and finally sinks into the floor.
    static func buildFallen(_ dyn: Mesh, x: Float, z: Float, yaw: Float, scale: Float, t: Float,
                            r: Float, g: Float, b: Float, variant: Int) {
        if t > 5 { return }
        let body = Mesh()
        let k = min(1, t / 0.45)
        let knees = min(1, t / 0.25)
        build(body, x: x, z: z, baseY: 0, yaw: yaw, scale: scale, phase: 0, gait: 0,
              leanX: 0, leanZ: 0, crouch: knees * 0.8,
              r: r * 0.8, g: g * 0.8, b: b * 0.8, glow: 0, charge: 0, accent: 0, variant: variant)
        var ang = k * k * 1.5
        if k >= 1 { ang = 1.5708 - sin(min(1, (t - 0.45) / 0.25) * .pi) * 0.12 }
        let sink = t > 3.8 ? (t - 3.8) * 0.25 : 0
        let ca = cos(ang), sa = sin(ang)
        let fx = cos(yaw), fz = sin(yaw)
        var a = body.floats
        let n = body.verts
        for i in 0..<n {
            let o = i * 9
            let px = a[o] - x, pz = a[o + 2] - z, py = a[o + 1]
            let f = px * fx + pz * fz
            let lat = -px * fz + pz * fx
            let nf = f * ca - py * sa
            let ny = max(0.015, f * sa + py * ca) - sink
            a[o] = x + nf * fx - lat * fz
            a[o + 1] = ny
            a[o + 2] = z + nf * fz + lat * fx
            let nnx = a[o + 3], nny = a[o + 4], nnz = a[o + 5]
            let nff = nnx * fx + nnz * fz, nlat = -nnx * fz + nnz * fx
            let rf = nff * ca - nny * sa, ry = nff * sa + nny * ca
            a[o + 3] = rf * fx - nlat * fz
            a[o + 4] = ry
            a[o + 5] = rf * fz + nlat * fx
        }
        dyn.append(floats: a)
    }

    private static func mix(_ a: [Float], _ b: [Float], _ t: Float) -> [Float] {
        [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
    }

    private static func scaleArr(_ a: [Float], _ k: Float) -> [Float] {
        [a[0] * k, a[1] * k, a[2] * k]
    }
}