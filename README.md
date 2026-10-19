# 霓虹突击 iOS

和 Android 版 `com.suicode.shooter` 同一套模拟器与网络协议（UDP 45454、快照字节一致、
地图/补给点同种子），可以和 Android 手机互相联机（含手机热点）。

## 在 Mac 上出包（这一步必须在 macOS + Xcode 上做，Android 上无法编译 iOS）

```bash
cd shooter/ios
./build_ios.sh ipa        # 真机 .ipa（需要 Xcode 里登录过 Apple ID）
./build_ios.sh            # 模拟器包，免签名，用来快速验证能编译
```

产物：
- `out/ios/Shooter.ipa`        ← 真机安装包
- `out/ios/Shooter.app`        ← 真机 .app
- `out/ios/Shooter.app`        ← 模拟器（sim 模式同名目录）

签名 team 自动从钥匙串里找；也可以 `TEAM_ID=XXXXXXXXXX ./build_ios.sh ipa`。

## 热点联机

- 主机：菜单 → 开房 → 选模式，屏幕会显示 `热点模式 192.168.x.1 · UDP 45454`。
- 客机：连上同一个 Wi-Fi / 主机的热点 → 菜单 → 搜索/加入（或手动输 IP）。
- JOIN 包同时单播目标地址和所有网卡的广播地址，主机回包用真实来源地址，
  所以那些会吞掉 client→AP 单播的热点 ROM 也能进。
- Info.plist 已带 `NSLocalNetworkUsageDescription`（iOS 14+ 首次联机会弹权限）。
