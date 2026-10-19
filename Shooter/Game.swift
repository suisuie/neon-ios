import UIKit

/// App-wide state: the saved callsign, the audio bank, the current match and the menu.
final class Game {
    static let shared = Game()

    let sfx = Sfx()
    var name: String {
        get {
            if let s = UserDefaults.standard.string(forKey: "ns_name"), !s.isEmpty { return s }
            let n = "玩家\(Int.random(in: 100...999))"
            UserDefaults.standard.set(n, forKey: "ns_name")
            return n
        }
        set { UserDefaults.standard.set(newValue, forKey: "ns_name") }
    }

    weak var window: UIWindow?
    weak var arena: ArenaView?
    private(set) var world: World?

    func startSolo() {
        sfx.start()
        let w = World(mode: World.solo, mapId: Int.random(in: 0..<World.MAPS))
        w.myId = 0
        w.myName = name
        w.addPlayer(0, name)
        w.waveTimer = 2.5
        w.addBanner("WAVE 1 来袭")
        launch(w, host: nil, client: nil)
    }

    /// `mode` is "waves", "ffa", "1v1" or "2v2" — same rooms the Android menu opens.
    func startHost(mode: String) {
        sfx.start()
        let w = World(mode: World.host, mapId: Int.random(in: 0..<World.MAPS))
        w.myId = 0
        w.myName = name
        w.addPlayer(0, name)
        var room = name + "的房间"
        switch mode {
        case "ffa":
            w.enterFfa(true)
            room = name + " 的混战房"
            w.addBanner(roomBanner("混战房") + " · 最多 \(World.ffaMax) 人 · 人机补位")
        case "1v1":
            w.enterRoom(1)
            room = name + " 的1v1房"
            w.addBanner(roomBanner("房间") + " · 等人加入，人机先补位")
        case "2v2":
            w.enterRoom(2)
            room = name + " 的2v2房"
            w.addBanner(roomBanner("房间") + " · 等人加入，人机先补位")
        default:
            w.waveTimer = 3.5
            w.addBanner(roomBanner("房间已开启"))
        }
        do {
            let h = try Net.Host(game: w, room: room)
            launch(w, host: h, client: nil)
        } catch {
            showAlert("开房失败", error.localizedDescription + "\n请检查是否有其他应用占用 UDP \(Net.PORT)")
        }
    }

    /// One-line room banner that also explains the hotspot / mobile-data case.
    private func roomBanner(_ prefix: String) -> String {
        let n = Net.localNet()
        if n.usable() {
            return prefix + " " + n.ip + ":" + "\(Net.PORT)"
                + (n.hotspot ? " · 好友连你的热点" : " · 好友连同一个 Wi-Fi")
        }
        if n.kind == "mobile" {
            return "只有流量 · 打开手机热点，好友连上后按 \(n.ip) 手动连接"
        }
        return "没检测到网络 · 开 Wi-Fi 或手机热点后好友才能加入"
    }

    func startClient(ip: String) {
        sfx.start()
        let c = Net.Client()
        // connecting blocks for up to a few seconds (it retries the JOIN), so never on main
        showConnecting("正在连接 \(ip)…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var failure: String?
            do {
                try c.connect(ip: ip, name: self?.name ?? "PLAYER", timeoutMs: 6000)
            } catch {
                failure = error.localizedDescription
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.hideConnecting()
                if let f = failure {
                    c.close()
                    self.showAlert("联机失败", f)
                    return
                }
                self.enterClient(c, ip: ip)
            }
        }
    }

    private func enterClient(_ c: Net.Client, ip: String) {
        let w = World(mode: World.client, mapId: c.mapId)
        w.myId = c.myId
        w.myName = name
        w.addPlayer(c.myId, name)
        w.addBanner("已加入房间 · " + ip)
        launch(w, host: nil, client: c)
    }

    private var connecting: UIAlertController?

    private func showConnecting(_ message: String) {
        guard let window = window, connecting == nil else { return }
        let ac = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        window.rootViewController?.present(ac, animated: true)
        connecting = ac
    }

    private func hideConnecting() {
        connecting?.dismiss(animated: true)
        connecting = nil
    }

    private func launch(_ w: World, host: Net.Host?, client: Net.Client?) {
        world = w
        guard let window = window else { return }
        let arena = ArenaView(frame: window.bounds, game: self, world: w)
        arena.onExit = { [weak self] in self?.exitToMenu() }
        if let h = host { arena.attachHost(h) }
        if let c = client { arena.attachClient(c) }
        self.arena = arena
        UIView.transition(with: window, duration: 0.25, options: .transitionCrossDissolve) {
            window.rootViewController = ArenaController(arena: arena)
        }
        arena.start()
    }

    func exitToMenu() {
        arena?.stop()
        arena = nil
        world = nil
        guard let window = window else { return }
        UIView.transition(with: window, duration: 0.25, options: .transitionCrossDissolve) {
            window.rootViewController = MenuController(game: self)
        }
    }

    func showAlert(_ title: String, _ message: String) {
        guard let window = window else { return }
        let ac = UIAlertController(title: title, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "好", style: .default))
        window.rootViewController?.present(ac, animated: true)
    }
}

/// Full-screen host for the arena; owns rotation and the home-button/back behaviour.
final class ArenaController: UIViewController {
    private let arena: ArenaView

    init(arena: ArenaView) {
        self.arena = arena
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    override func loadView() {
        view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black
        view.addSubview(arena)
        arena.frame = view.bounds
        arena.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
}