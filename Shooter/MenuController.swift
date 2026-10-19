import UIKit

/// Main menu: solo, host, join, plus the LAN status line so the player can read the
/// address a friend has to type. Ported from the Android `MenuView`.
final class MenuController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let game: Game
    private let table = UITableView(frame: .zero, style: .plain)
    private var hosts: [Net.HostInfo] = []
    private var discovering = false
    private var statusLabel: UILabel?

    init(game: Game) {
        self.game = game
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)
        buildUI()
        refreshNetwork()
        startDiscovery()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshNetwork()
        startDiscovery()
    }

    // ------------------------------------------------------------------ ui

    private func buildUI() {
        let title = UILabel()
        title.text = "NEON STRIKE"
        title.font = UIFont.monospacedSystemFont(ofSize: 30, weight: .heavy)
        title.textColor = UIColor(red: 0.3, green: 0.95, blue: 1, alpha: 1)
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)

        let sub = UILabel()
        sub.text = "局域网联机 · 单人混战 · 热点直连"
        sub.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        sub.textColor = UIColor(white: 0.65, alpha: 1)
        sub.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sub)

        let net = UILabel()
        net.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        net.textColor = UIColor(red: 1, green: 0.78, blue: 0.35, alpha: 1)
        net.numberOfLines = 0
        net.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(net)
        statusLabel = net

        let nameField = UITextField()
        nameField.text = game.name
        nameField.textColor = .white
        nameField.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
        nameField.borderStyle = .roundedRect
        nameField.backgroundColor = UIColor(white: 1, alpha: 0.08)
        nameField.returnKeyType = .done
        nameField.delegate = self
        nameField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nameField)
        self.nameField = nameField

        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.separatorColor = UIColor(white: 1, alpha: 0.08)
        table.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)

        let solo = makeButton("单人混战", #selector(soloTapped))
        let host = makeButton("开房", #selector(hostTapped))
        let join = makeButton("搜索/加入", #selector(joinTapped))
        let stack = UIStackView(arrangedSubviews: [solo, host, join])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            sub.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            net.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            net.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 8),
            net.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            nameField.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            nameField.topAnchor.constraint(equalTo: net.bottomAnchor, constant: 10),
            nameField.widthAnchor.constraint(equalToConstant: 220),
            stack.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            stack.heightAnchor.constraint(equalToConstant: 54),
            table.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            table.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            table.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 10),
            table.bottomAnchor.constraint(equalTo: stack.topAnchor, constant: -12)
        ])
    }

    private var nameField: UITextField?

    private func makeButton(_ title: String, _ action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .bold)
        b.setTitleColor(UIColor(red: 0.05, green: 0.1, blue: 0.14, alpha: 1), for: .normal)
        b.backgroundColor = UIColor(red: 0.35, green: 0.95, blue: 1, alpha: 0.9)
        b.layer.cornerRadius = 12
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    private func refreshNetwork() {
        let n = Net.localNet()
        var line = Net.describe()
        if n.usable() {
            line += "\n好友输入：\(n.ip)  端口 \(Net.PORT)"
        }
        statusLabel?.text = line
    }

    private func startDiscovery() {
        if discovering { return }
        discovering = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = Net.discover(timeoutMs: 2600)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.hosts = found
                self.discovering = false
                self.table.reloadData()
                self.refreshNetwork()
            }
        }
    }

    // ------------------------------------------------------------------ actions

    @objc private func soloTapped() {
        commitName()
        game.startSolo()
    }

    @objc private func hostTapped() {
        commitName()
        let ac = UIAlertController(title: "开房", message: "选择模式", preferredStyle: .actionSheet)
        ac.addAction(UIAlertAction(title: "混战房（各自一队，先到 20 分）", style: .default) { _ in
            self.game.startHost(mode: "ffa")
        })
        ac.addAction(UIAlertAction(title: "1v1 单挑房", style: .default) { _ in
            self.game.startHost(mode: "1v1")
        })
        ac.addAction(UIAlertAction(title: "2v2 团队房", style: .default) { _ in
            self.game.startHost(mode: "2v2")
        })
        ac.addAction(UIAlertAction(title: "无尽波次房（打人机）", style: .default) { _ in
            self.game.startHost(mode: "waves")
        })
        ac.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = ac.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 60, width: 1, height: 1)
        }
        present(ac, animated: true)
    }

    @objc private func joinTapped() {
        commitName()
        let ac = UIAlertController(title: "加入房间", message: "输入主机地址", preferredStyle: .alert)
        ac.addTextField { tf in
            tf.placeholder = "192.168.43.1"
            tf.keyboardType = .numbersAndPunctuation
            tf.text = self.hosts.first?.ip
        }
        ac.addAction(UIAlertAction(title: "连接", style: .default) { _ in
            guard let ip = ac.textFields?.first?.text, !ip.isEmpty else { return }
            self.game.startClient(ip: ip)
        })
        ac.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(ac, animated: true)
    }

    private func commitName() {
        if let t = nameField?.text?.trimmingCharacters(in: .whitespaces), !t.isEmpty {
            game.name = String(t.prefix(12))
        }
    }

    // ------------------------------------------------------------------ table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(1, hosts.count)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "c", for: indexPath)
        cell.backgroundColor = .clear
        cell.textLabel?.textColor = .white
        cell.textLabel?.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        if hosts.isEmpty {
            cell.textLabel?.text = discovering ? "正在搜索局域网房间…" : "没找到房间 · 点“搜索/加入”手动输入地址"
            cell.textLabel?.textColor = UIColor(white: 0.6, alpha: 1)
        } else {
            let h = hosts[indexPath.row]
            let kind = h.ffa ? "混战" : (h.isRoom ? "\(h.teamSize)v\(h.teamSize)" : "WAVE \(h.wave)")
            cell.textLabel?.text = "\(h.ip)   \(h.room)   \(h.players)/\(h.max)   \(kind)"
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < hosts.count else {
            startDiscovery()
            return
        }
        commitName()
        game.startClient(ip: hosts[indexPath.row].ip)
    }
}

extension MenuController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        commitName()
        return true
    }
}