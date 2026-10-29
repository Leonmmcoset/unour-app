import ActivityKit
import Flutter
import Foundation
import UIKit

final class LiveTablePlugin: NSObject, FlutterPlugin {
    static var pendingOpen: [String: Any]?
    private static weak var instance: LiveTablePlugin?
    private let channel: FlutterMethodChannel
    private var manager: Any?
    private var ready = false

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "chat.csac.unour/live_table", binaryMessenger: registrar.messenger())
        let plugin = LiveTablePlugin(channel: channel)
        instance = plugin
        registrar.addMethodCallDelegate(plugin, channel: channel)
    }

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
        if #available(iOS 16.2, *) {
            manager = TableActivityManager { [weak self] token in
                self?.channel.invokeMethod("pushToken", arguments: token)
            }
        }
    }

    static func open(_ url: URL) -> Bool {
        guard url.scheme == "unour", url.host == "table",
              url.pathComponents.count == 2 else { return false }
        let room = url.lastPathComponent
        guard !room.isEmpty, room.count <= 64 else { return false }
        let spectator = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.contains(where: { $0.name == "spectator" && $0.value == "true" }) ?? false
        let open: [String: Any] = ["roomId": room, "spectator": spectator]
        if let plugin = instance, plugin.ready { plugin.channel.invokeMethod("openTable", arguments: open) }
        else { pendingOpen = open }
        return true
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "status" {
            ready = true
            let supported: Bool
            let allowed: Bool
            if #available(iOS 16.2, *) {
                supported = true
                allowed = ActivityAuthorizationInfo().areActivitiesEnabled
            } else { supported = false; allowed = false }
            var status: [String: Any] = ["supported": supported, "allowed": allowed, "realtime": false, "platform": "ios"]
            if let open = Self.pendingOpen { status["openTable"] = open; Self.pendingOpen = nil }
            result(status)
            return
        }
        guard #available(iOS 16.2, *), let manager = manager as? TableActivityManager else {
            result(call.method == "requestPermission" ? false : nil)
            return
        }
        let arguments = call.arguments as? [String: Any] ?? [:]
        Task { @MainActor in
            do {
                switch call.method {
                case "requestPermission":
                    manager.suppressedKey = nil
                    result(ActivityAuthorizationInfo().areActivitiesEnabled)
                case "foreground":
                    result(["cookies": []])
                case "sync":
                    if let state = arguments["snapshot"] as? [String: Any] {
                        try await manager.sync(state,
                            foreground: arguments["foreground"] as? Bool ?? true,
                            pushEnabled: arguments["pushEnabled"] as? Bool ?? false)
                    }
                    result(nil)
                case "stop":
                    await manager.stop()
                    result(nil)
                default: result(FlutterMethodNotImplemented)
                }
            } catch {
                result(FlutterError(code: "live_activity", message: "无法显示系统牌桌，请检查实时活动设置", details: nil))
            }
        }
    }
}

@available(iOS 16.2, *)
private final class TableActivityManager {
    var suppressedKey: String?
    private var activity: Activity<UnourTableAttributes>?
    private var key: String?
    private var tokenTask: Task<Void, Never>?
    private let onToken: ([String: Any]) -> Void

    init(onToken: @escaping ([String: Any]) -> Void) { self.onToken = onToken }

    @MainActor func sync(_ snapshot: [String: Any], foreground: Bool, pushEnabled: Bool) async throws {
        guard let roomId = snapshot["roomId"] as? String,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let data = try JSONSerialization.data(withJSONObject: snapshot)
        let state = try JSONDecoder().decode(UnourTableAttributes.ContentState.self, from: data)
        let nextKey = "\(roomId):\(state.round)"
        if let active = activity, active.activityState == .dismissed || active.activityState == .ended {
            suppressedKey = key
            activity = nil
        }
        if nextKey == suppressedKey { return }
        if key != nextKey {
            await stop()
            key = nextKey
        }
        let content = ActivityContent(state: state, staleDate: Date(timeIntervalSince1970: state.updatedAt + 15), relevanceScore: state.isYourTurn ? 100 : 50)
        if let activity = activity {
            await activity.update(content)
        } else if foreground, UIApplication.shared.applicationState != .background {
            // Reconcile after a process restart instead of leaking old lock-screen cards.
            for old in Activity<UnourTableAttributes>.activities {
                await old.end(nil, dismissalPolicy: .immediate)
            }
            let attributes = UnourTableAttributes(roomId: roomId, spectator: state.spectator)
            let started = try Activity.request(attributes: attributes, content: content, pushType: pushEnabled ? .token : nil)
            activity = started
            if pushEnabled {
                tokenTask = Task { @MainActor [weak self] in
                    for await data in started.pushTokenUpdates {
                        if Task.isCancelled { break }
                        self?.onToken([
                            "roomId": roomId, "round": state.round, "activityId": started.id,
                            "pushToken": data.map { String(format: "%02x", $0) }.joined()
                        ])
                    }
                }
            }
        }
    }

    @MainActor func stop() async {
        tokenTask?.cancel()
        tokenTask = nil
        for active in Activity<UnourTableAttributes>.activities {
            await active.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        key = nil
    }
}
