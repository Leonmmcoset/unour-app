# 后台牌桌

在「设置 → 后台牌桌」开启。首次开启 Android 会请求通知权限；iOS 需要允许应用的实时活动。
卡片展示当前牌、有效颜色、出牌者、本人及其他玩家的牌数、方向和罚牌池。
点击卡片返回当前牌桌；冷启动只恢复当前账户的最近牌桌，不凭外部链接加入陌生房间。
本人手牌的具体牌面、Cookie 和房间凭证不进入系统卡片内容。

## Android

切到后台时启动可见的 `dataSync` 前台服务，每两秒读取一次真实房间接口。
回到前台即停止服务，由 Flutter 恢复原来的状态同步。
Android 16 请求 Live Updates 展示；系统不提升通知或旧版 Android 使用普通持续通知。
原始 API 36 使用系统支持的彩色持续通知模板，提供显式提升请求的新版本使用其公开接口。
系统是否提升取决于设备及通知设置。

连接失败后保留最近同步时间，标记「牌况待刷新」，按 4–30 秒退避重试。
15 秒没有成功读取也会标记待刷新。收到 401、403、404 或本局结束时停止显示。
「停止显示」停止本局后台读取；关闭开关、退出牌桌和移除应用任务也会停止。
不注册开机启动，不绕过省电限制。Android 对 `dataSync` 服务的运行时限仍然生效，
超时后停止服务，回到游戏可重新同步。

原生读取只使用 GET，禁止重定向和明文 HTTP，不替玩家摸牌、出牌或喊 UNO。
后台凭证只留在进程内存中，进程被杀不会自动重启服务；响应中轮换的 Cookie
在回到前台时交还 Dart，写回现有安全存储。

## iOS

iOS 16.2 及以上支持锁屏实时活动；支持灵动岛的设备同时提供紧凑、展开与最小布局。
旧版系统继续使用正常牌桌。扩展的 Bundle ID 为 `chat.csac.unour.LiveActivity`，
会随未签名 IPA 一起打包，安装时须和主应用一起签名。

**当前默认构建显示最近同步的牌况，尚未接通 csac.chat 的后台推送。**
App 在前台时更新实时活动，切到后台后系统挂起 App，WidgetKit 扩展不能自行联网。
超过 15 秒未同步时显示「牌况待刷新」，并提示打开牌桌刷新，不继续显示旧的「轮到你」。
这不是 iOS 后台持续联网方案，也不使用无声音乐或虚假的后台运行模式。

后台持续更新需要 Apple Developer Program、主应用的 Push Notifications capability，
以及服务器通过 APNs 发送 ActivityKit 更新。客户端已接收活动专用推送令牌及其轮换，
并预留受房间凭证保护的注册入口。默认不调用任何假定存在的接口。

### 服务端接入约定（尚未部署）

先在 Xcode 为 Runner 配置真实 Team、Push Notifications 和对应的 `aps-environment`。
APNs 私钥保留在服务器，不放入 App、仓库或构建产物。
服务端新增注册接口后，通过编译参数指定其相对 `/api/v1/` 的路径，例如：

```sh
flutter build ios --release --no-codesign \
  --dart-define='LIVE_ACTIVITY_REGISTRATION_PATH=rooms/{roomId}/live-activities'
```

上面路径是接口约定示例，当前后端 API 说明未提供它。未设置此参数时使用本地活动，
不会申请 APNs 活动令牌。设置参数后，以现有 Cookie、账户 ID 和房间 Bearer 凭证发送：

```json
{
  "activity_id": "ActivityKit 活动 ID",
  "push_token": "活动专用令牌的十六进制字符串",
  "attributes_type": "UnourTableAttributes",
  "round": 2
}
```

服务器需验证账户、房间、角色和局数，绑定令牌到该参与者，并在令牌轮换时更新。
成功响应为 200 或 204。注册失败时应用保留最近同步模式。
服务端应从该参与者可见的权威状态生成内容，不能将任何人的私有手牌放进推送。
轮到本人、牌面或牌数变化时合并发送更新；房间解散、退出或结算时发送 `end`。
APNs 返回失效令牌时删除注册。不要将 APNs 的传输时间当成严格实时保证。

APNs 主题是 **`chat.csac.unour.push-type.liveactivity`**，不是扩展的 Bundle ID。
使用 `apns-push-type: liveactivity`；普通更新使用低优先级，避免无意义的高频推送。
`content-state` 的结构对应 [UnourTableAttributes.swift](../ios/Shared/UnourTableAttributes.swift)：

```json
{
  "aps": {
    "timestamp": 1793271600,
    "event": "update",
    "stale-date": 1793271615,
    "content-state": {
      "round": 2,
      "phase": "playing",
      "spectator": false,
      "turnName": "小林",
      "isYourTurn": false,
      "myCount": 3,
      "topCard": "万能加四",
      "symbol": "+4",
      "activeColor": "blue",
      "pendingDraw": 4,
      "direction": -1,
      "players": "本人 3 · 小林 1",
      "connected": true,
      "updatedAt": 1793271600
    }
  }
}
```

时间为 Unix 秒；结束事件改为 `event: end`，携带最后状态和 `dismissal-date`。
静态属性为 `roomId` 与 `spectator`；内容与属性总计须小于 ActivityKit 的 4 KB 上限。
系统对推送频率、活动时长和展示方式的限制仍然适用。

Apple 官方说明：[Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)。

## 验证

静态检查及 57 项 Dart 测试通过，新增覆盖内容脱敏、权限拒绝、切换后台、退出清理、
重复快照合并、旧系统降级、推送令牌作用域、后台 Cookie 轮换、快速前后台切换和未配置推送时的明确状态。测试使用内存响应，不注册账户或创建线上牌桌。
Android 真机通知提升、后台省电行为、iOS 真机显示和 APNs 仍需手动验收；
未签名构建通过不能代替推送联调。

2026-10-29，提交 `714bb5c` 的 [Android／iOS 手动构建](https://github.com/Leonmmcoset/unour-app/actions/runs/40865882645)
均已通过，APK 和未签名 IPA 上传为 Actions 产物，保留至 2026-11-01（UTC）。
已解包核对 IPA 包含 `Payload/Runner.app/PlugIns/UnourLiveActivity.appex`，
主应用与扩展版本均为 `1.0.0 (1)`，最低系统分别为 iOS 15.0 与 16.2；
两者的可执行文件均无代码签名，也未嵌入描述文件。
