# 从零搓出 ipa —— 手机/电脑都能照做

目标：拿到 **`Shooter-unsigned.ipa`**，再用 AltStore / Sideloadly / TrollStore 装到 iPhone。
编译在 GitHub 的免费 Mac 上跑，你本地什么都不用装。

---

## 准备的两个文件

| 文件 | 用途 |
|---|---|
| `ios-port.zip` | 解压得到工程目录（下面说的"上传内容"就是它里面的东西） |
| `neon-ios.bundle` | 可选。已经是一个 git 仓库快照，一条命令就能推上去（见方案 B） |

---

# 方案 A：网页点着做（不用装任何东西）

## A1. 建仓库

1. 手机或电脑浏览器打开 <https://github.com/new>
2. **Repository name** 填 `neon-ios`
3. 选 **Private**（推荐）或 Public 都行
4. 其它都别勾，点绿色 **Create repository**

## A2. 上传文件

在新建的仓库页面点 **uploading an existing file**（或 `Add file → Upload files`）。

把 `ios-port.zip` 解压后，**把这 6 项拖进去**：

```
Shooter/                 ← 文件夹，12 个 .swift + Info.plist
Shooter.xcodeproj/       ← 文件夹
build_ios.sh
build_ipa_unsigned.sh
一键打包.command
打包说明.md
```

> 上传时**不要**建 `neon-ios/` 这一层，文件要直接在仓库根目录。
> 网页支持拖整个文件夹，`.swift` 会自己进去。

然后底部点绿色 **Commit changes**。

## A3. 加 CI 文件（关键的一步）

`.github` 是隐藏目录，网页上传经常漏掉，所以手动建：

1. 仓库页 → **Add file** → **Create new file**
2. 文件名框里输入（斜杠会自动建目录）：

   ```
   .github/workflows/build-ios-ipa.yml
   ```

3. 打开 `ios-port.zip` 里的 `.github/workflows/build-ios-ipa.yml`，
   把**全部内容**粘进编辑框
4. 底部 **Commit changes**

## A4. 跑起来

1. 仓库顶部 → **Actions** 标签
2. 如果提示 "Workflows aren't being run on this forked repository" 之类，点
   **I understand my workflows, go ahead and enable them**
3. 左边列表点 **build-ios-ipa**
4. 右边 **Run workflow** 下拉 → 绿色 **Run workflow** 按钮
5. 等 8～15 分钟（第一次会慢，要下载 macOS 镜像）

## A5. 下载 ipa

1. 刷新页面，点进这次运行（黄色的点变成绿色 ✓）
2. 页面**拉到最下面**，找到 **Artifacts**
3. 点 **Shooter-unsigned-ipa** → 下载一个 zip
4. 解压，里面就是 **`Shooter-unsigned.ipa`**

> 如果运行是红色的 ✗：点进去，点红色的那个 **Build (unsigned)** 步骤，
> 把报错最后 20 行复制出来，就能定位。常见只有两种：
> 文件没传全（少了 `Shooter/` 里某个 .swift），或者 scheme 名字不是 `Shooter`。

---

# 方案 B：一条命令推上去（有 git 就行，最快）

`neon-ios.bundle` 里已经是一个完整的 git 仓库（含全部代码和 CI 配置），
**不用上传、不用手建 CI 文件**：

```bash
# 1. 先在 GitHub 建一个空仓库（不要勾 README / .gitignore），比如叫 neon-ios
# 2. 然后：
git clone neon-ios.bundle neon-ios
cd neon-ios
git remote set-url origin https://github.com/你的用户名/neon-ios.git
git push -u origin main
```

推上去的瞬间 CI 会自动开始跑（workflow 里配了 `push` 触发），
去 **Actions** 等它变绿，然后同 A5 下载 Artifacts。

---

# 装到 iPhone

## 情况 1：iOS ≤ 17.0（部分版本）→ TrollStore，永久，不用证书

1. iPhone 上装 **TrollStore**（按 trollstore 官网的方式装）
2. 把 `Shooter-unsigned.ipa` 传到手机（微信/隔空/AirDrop 都行）
3. 用 TrollStore 打开这个 ipa → Install
4. 完成，不过期

## 情况 2：普通 iOS → Sideloadly（Windows 电脑插线一次）

1. Windows 装 [Sideloadly](https://sideloadly.io) 和 **iTunes**（微软商店版，提供驱动）
2. iPhone 插线，手机上点 **信任**
3. Sideloadly 里：IPA 选 `Shooter-unsigned.ipa`，Apple ID 填自己的（免费账号即可）
4. 点 **Start**，按提示输入密码（只在本机做签名）
5. iPhone：设置 → 通用 → VPN与设备管理 → **信任** 你的 Apple ID
6. 桌面上出现「霓虹突击」，开玩

> 免费账号 **7 天过期**，到期在 Sideloadly 再点一次 Start 就行，游戏存档不丢。

## 情况 3：纯手机、无电脑 → 买证书 + 全能签

1. 买一张个人 iOS 证书（几十块/年，淘宝搜"iOS 个人证书"）
2. 手机装 **全能签 / ESign / GBox**
3. 把 `Shooter-unsigned.ipa` 导入，用它签名，安装
4. 有效期跟证书一致，不用电脑

---

# 联机

1. **你（Android）**：开游戏 → 开房 → 选混战/1v1/2v2 → 屏幕会显示
   `热点模式 192.168.x.1 · UDP 45454`
2. **朋友（iPhone）**：连你的热点或同一个 Wi-Fi → 菜单 → 搜索/加入
3. iPhone 第一次进会弹「允许访问本地网络」，**必须点允许**（不点就搜不到房间）

两边是同一套协议和同一套种子地图（网格哈希、8 个补给点坐标逐个比对过完全一致），
所以 iOS 和 Android 可以互相进同一个房间。

---

# 出问题时

| 现象 | 原因 |
|---|---|
| Actions 里没有 build-ios-ipa | `.github/workflows/build-ios-ipa.yml` 没建对路径 |
| 红色 ✗ 在 Build 步骤 | 代码文件没传全，或 scheme 不是 Shooter |
| 能编译但装不上 | ipa 未签名，必须走 TrollStore/Sideloadly/证书 |
| 装上了搜不到房间 | 没允许"本地网络"，或不在同一个网段 |
| 7 天后打不开 | 免费账号过期，重签一次 |
