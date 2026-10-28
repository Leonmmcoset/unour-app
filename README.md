# Unour

Flutter 编写的竖屏 UNO 派对游戏，面向 Android 与 iOS。默认连接 https://csac.chat/。

## 开发

使用 Flutter stable，执行 `flutter pub get`、`flutter run`。可通过
`--dart-define=API_BASE_URL=https://csac.chat/` 指定真实服务。

- `flutter analyze`：静态检查
- `flutter test`：解析、状态与组件测试（不启动模拟服务）
- `flutter build apk --debug`：Android 开发安装包
- `flutter build ios --no-codesign`：在 macOS/Xcode 中验证 iOS 工程

不在客户端实现规则引擎，所有牌局以服务端状态和合法动作为准。
不自动创建线上测试账户。真实服务验收见 `docs/acceptance.md`。
后端提供的接口说明保存在 `docs/backend-api.md`。

包名 / Bundle ID：`chat.csac.unour`。Logo 与正式发行签名待配置。
