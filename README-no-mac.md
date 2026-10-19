# 没有 Mac，怎么把 iOS 版做出来装上

三条路，从最省事到最麻烦。**都不需要你有 Mac。**

---

## 路线 A：GitHub 网页编译 + Windows 签名（推荐）

### 第 1 步：拿到 ipa（网页点几下，10 分钟）

1. 注册/登录 GitHub（免费）。
2. 新建一个仓库（New repository），名字随便，比如 `neon-strike-ios`，**Private 或 Public 都行**。
3. 把 `ios-port.zip` 解压，把里面的东西**全部上传到仓库根目录**：
   - `Shooter/`（文件夹）
   - `Shooter.xcodeproj/`（文件夹）
   - `build_ios.sh`、`build_ipa_unsigned.sh`、`README.md`
   - `.github/`（这个文件夹是隐藏的，网页拖拽整个 `.github` 进去；
     如果网页上传不认隐藏目录，就用下面的"命令行方式"）
4. 仓库页面 → **Actions** 标签 → 左边选 **build-ios-ipa** → 右边 **Run workflow** → 绿色按钮。
5. 等 5～15 分钟，跑完点进那次运行，页面最下面 **Artifacts** →
   下载 **Shooter-unsigned-ipa**，解压得到 **`Shooter-unsigned.ipa`**。

> 命令行方式（有 git 的话最稳，隐藏目录不会丢）：
> ```bash
> git init && git add -A && git commit -m "ios"
> git branch -M main
> git remote add origin https://github.com/你的用户名/neon-strike-ios.git
> git push -u origin main
> ```

### 第 2 步：装到 iPhone（Windows 电脑即可，不需要 Mac）

1. Windows 上装 **Sideloadly**（https://sideloadly.io）和 **iTunes**（微软商店版即可，
   提供驱动）。或者装 **AltStore**。
2. iPhone 用数据线插上 Windows，手机点"信任"。
3. Sideloadly 里：
   - IPA 选刚下载的 `Shooter-unsigned.ipa`
   - Apple ID 填你自己的（**免费账号就行**，不用开发者账号）
   - 点 **Start**，按提示输密码（会拿去做签名，只在本机）
4. 手机上：设置 → 通用 → VPN与设备管理 → 信任你的 Apple ID 证书。
5. 回到桌面，图标出现，开玩。

> 免费 Apple ID 签的 App **7 天过期**，到期用 Sideloadly 再点一次 Start 即可（存档不丢）。
> 有付费开发者账号（￥688/年）就是 1 年。

### 第 3 步：联机

- 你 Android 手机：菜单 → 开房 → 选模式。屏幕会显示 `热点模式 192.168.x.1 · UDP 45454`。
- 朋友 iPhone：连你的热点（或同一个 Wi-Fi）→ 菜单 → 搜索/加入。
- 第一次进游戏 iOS 会弹"允许访问本地网络"，必须点允许。

---

## 路线 B：找一台 Mac 借 5 分钟

任何 Mac（网吧、学校机房、朋友的 MacBook）都行，只要有 Xcode：

```bash
unzip ios-port.zip && cd ios
./build_ipa_unsigned.sh      # 出 out/ios/Shooter-unsigned.ipa
# 或者直接签好：
TEAM_ID=你的TeamID ./build_ios.sh ipa
```

然后同上，用 Sideloadly / AltStore 装，或 Xcode 直接连手机运行。

---

## 路线 C：Cloud Mac 租用（按小时付费）

- MacStadium、MacinCloud、Scaleway Apple Silicon：几美元/小时。
- 远程桌面进去，装 Xcode，跑 `./build_ios.sh ipa`，把 ipa 拖回本地。
- 适合"就想自己跑一遍、不碰 GitHub"的人。

---

## 为什么不在这里直接给你 ipa

iOS 的可执行文件必须用 **Apple 的 iOS SDK + Apple 的签名**。这台机器是 Android/Termux
（aarch64 Linux），没有 `swiftc`、没有 `iPhoneOS.sdk`、没有 `codesign`，
**任何工具链都补不出 Apple 的闭源 SDK**。所以"编译"这一步只能在 macOS 上做——
GitHub Actions 的 `macos-14` 机器就是替你做这一步的免费 Mac。
