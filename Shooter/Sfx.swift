import Foundation
import AVFoundation

/// Sound ids shared with the simulation (`World` never talks to AVFoundation directly).
enum Sound {
    static let shoot = 0
    static let smg = 1
    static let sniper = 2
    static let hit = 3
    static let headshot = 4
    static let kill = 5
    static let hurt = 6
    static let step = 7
    static let reload = 8
    static let wave = 9
    static let ui = 10
    static let land = 11
    static let empty = 12
    static let bolt = 13
    static let magOut = 14
    static let magIn = 15
    static let ricochet = 16
    static let farRifle = 17
    static let farSmg = 18
    static let farSniper = 19
}

/// The simulation talks to this so it stays engine agnostic.
protocol SfxSink: AnyObject {
    func play(_ id: Int, _ vol: Float, _ pitch: Float)
    func playPan(_ id: Int, _ vol: Float, _ pitch: Float, _ pan: Float)
}

extension SfxSink {
    func play(_ id: Int) { play(id, 1, 1) }
}

/// Tiny synthesised sound bank: noise bursts and sweeps rendered into PCM buffers once,
/// then played through `AVAudioPlayerNode` pools. No asset files to ship.
final class Sfx: SfxSink {

    private let engine = AVAudioEngine()
    private var buffers: [Int: AVAudioPCMBuffer] = [:]
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private let format: AVAudioFormat
    private var ready = false

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
        build()
    }

    func start() {
        guard !ready else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            for _ in 0..<8 {
                let p = AVAudioPlayerNode()
                engine.attach(p)
                engine.connect(p, to: engine.mainMixerNode, format: format)
                players.append(p)
            }
            engine.mainMixerNode.outputVolume = 0.9
            try engine.start()
            ready = true
        } catch {
            ready = false
        }
    }

    func stop() {
        guard ready else { return }
        engine.stop()
        ready = false
    }

    // ------------------------------------------------------------------ synthesis

    private func build() {
        buffers[Sound.shoot] = gun(0.16, 320, 0.9, 0.5)
        buffers[Sound.smg] = gun(0.09, 480, 0.75, 0.45)
        buffers[Sound.sniper] = gun(0.42, 180, 1.0, 0.75)
        buffers[Sound.farRifle] = gun(0.22, 220, 0.45, 0.9)
        buffers[Sound.farSmg] = gun(0.14, 300, 0.4, 0.9)
        buffers[Sound.farSniper] = gun(0.5, 140, 0.5, 0.95)
        buffers[Sound.hit] = blip(0.07, 900, 0.5, .sine)
        buffers[Sound.headshot] = blip(0.12, 1500, 0.6, .sine)
        buffers[Sound.kill] = blip(0.24, 1100, 0.6, .sine)
        buffers[Sound.hurt] = blip(0.2, 180, 0.55, .saw)
        buffers[Sound.step] = noise(0.06, 0.35, 2600)
        buffers[Sound.reload] = noise(0.18, 0.4, 1800)
        buffers[Sound.magOut] = noise(0.1, 0.45, 1500)
        buffers[Sound.magIn] = noise(0.12, 0.5, 1400)
        buffers[Sound.bolt] = noise(0.1, 0.5, 2200)
        buffers[Sound.ricochet] = blip(0.16, 2400, 0.35, .sine)
        buffers[Sound.empty] = blip(0.05, 1400, 0.4, .square)
        buffers[Sound.wave] = blip(0.7, 420, 0.5, .sine)
        buffers[Sound.ui] = blip(0.08, 700, 0.4, .square)
        buffers[Sound.land] = noise(0.14, 0.5, 700)
    }

    private enum Wave { case sine, saw, square }

    private func makeBuffer(_ seconds: Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        return buf
    }

    private func gun(_ seconds: Double, _ freq: Double, _ amp: Double, _ tail: Double) -> AVAudioPCMBuffer {
        let buf = makeBuffer(seconds)
        let data = buf.floatChannelData![0]
        let sr = format.sampleRate
        var phase = 0.0
        var lp = 0.0
        for i in 0..<Int(buf.frameLength) {
            let t = Double(i) / sr
            let env = exp(-t * (1.0 / max(0.01, tail)) * 6.0)
            let n = Double.random(in: -1...1)
            lp += (n - lp) * 0.35
            phase += freq * 2 * .pi / sr
            phase = phase.truncatingRemainder(dividingBy: 2 * .pi)
            let body = (sin(phase) * 0.4 + lp * 0.9) * env * amp
            data[i] = Float(max(-1, min(1, body)))
        }
        return buf
    }

    private func blip(_ seconds: Double, _ freq: Double, _ amp: Double, _ w: Wave) -> AVAudioPCMBuffer {
        let buf = makeBuffer(seconds)
        let data = buf.floatChannelData![0]
        let sr = format.sampleRate
        var phase = 0.0
        for i in 0..<Int(buf.frameLength) {
            let t = Double(i) / sr
            let env = exp(-t * 18.0)
            let f = freq * (1.0 - 0.25 * (t / seconds))
            phase += f * 2 * .pi / sr
            let v: Double
            switch w {
            case .sine: v = sin(phase)
            case .saw: v = ((phase / (2 * .pi)).truncatingRemainder(dividingBy: 1)) * 2 - 1
            case .square: v = sin(phase) > 0 ? 1 : -1
            }
            data[i] = Float(max(-1, min(1, v * env * amp)))
        }
        return buf
    }

    private func noise(_ seconds: Double, _ amp: Double, _ cutoff: Double) -> AVAudioPCMBuffer {
        let buf = makeBuffer(seconds)
        let data = buf.floatChannelData![0]
        var lp = 0.0
        let k = min(1.0, cutoff / (format.sampleRate * 0.5))
        for i in 0..<Int(buf.frameLength) {
            let t = Double(i) / format.sampleRate
            let env = exp(-t * 20.0)
            lp += (Double.random(in: -1...1) - lp) * k
            data[i] = Float(max(-1, min(1, lp * env * amp)))
        }
        return buf
    }

    // ------------------------------------------------------------------ playback

    func play(_ id: Int, _ vol: Float, _ pitch: Float) {
        playPan(id, vol, pitch, 0)
    }

    func playPan(_ id: Int, _ vol: Float, _ pitch: Float, _ pan: Float) {
        guard ready, let buf = buffers[id], !players.isEmpty else { return }
        let p = players[next]
        next = (next + 1) % players.count
        p.volume = max(0, min(1, vol))
        p.pan = max(-1, min(1, pan))
        if p.isPlaying { p.stop() }
        p.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
        p.play()
    }
}