import ActivityKit
import SwiftUI
import WidgetKit

@main
struct UnourLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        UnourTableLiveActivity()
    }
}

struct UnourTableLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UnourTableAttributes.self) { context in
            TableActivityView(context: context)
                .padding(14)
                .activityBackgroundTint(Color(red: 0.10, green: 0.08, blue: 0.14))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(tableURL(context.attributes))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Unour", systemImage: "rectangle.on.rectangle")
                        .font(.caption.weight(.bold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("第 \(context.state.round) 局")
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TableActivityView(context: context)
                }
            } compactLeading: {
                Image(systemName: stale(context) ? "clock" : context.state.isYourTurn ? "hand.point.up.left.fill" : "rectangle.on.rectangle")
                    .foregroundStyle(stale(context) ? .secondary : tableTint(context.state.activeColor))
                    .accessibilityLabel(stale(context) ? "牌况待刷新" : "Unour 牌桌")
            } compactTrailing: {
                Text(stale(context) ? "…" : context.state.isYourTurn ? "你" : context.state.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(stale(context) ? .secondary : .primary)
            } minimal: {
                Image(systemName: stale(context) ? "clock" : "rectangle.on.rectangle")
                    .foregroundStyle(stale(context) ? .secondary : tableTint(context.state.activeColor))
            }
            .widgetURL(tableURL(context.attributes))
            .keylineTint(tableTint(context.state.activeColor))
        }
    }
}

private struct TableActivityView: View {
    let context: ActivityViewContext<UnourTableAttributes>
    private var state: UnourTableAttributes.ContentState { context.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(stale(context) ? "牌况待刷新" : state.phase == "lobby" ? "等待开局" : state.isYourTurn ? "轮到你出牌" : "\(state.turnName) 正在出牌")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                Text(context.attributes.roomId)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(state.symbol)
                    .font(.title2.bold())
                    .frame(minWidth: 34, minHeight: 38)
                    .background(tableTint(state.activeColor).opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel(state.topCard)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(state.topCard) · 当前\(colorName(state.activeColor))")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("\(state.direction == 1 ? "顺时针" : "逆时针")\(state.spectator ? " · 观战" : " · 你有 \(state.myCount) 张")\(state.pendingDraw > 0 ? " · 罚牌 +\(state.pendingDraw)" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(state.players)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(stale(context) ? "最近同步" : "同步于")
                Text(Date(timeIntervalSince1970: state.updatedAt), style: .time)
                if stale(context) { Text("· 打开牌桌刷新") }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
    }
}

private func stale(_ context: ActivityViewContext<UnourTableAttributes>) -> Bool {
    context.isStale || !context.state.connected
}

private func tableURL(_ attributes: UnourTableAttributes) -> URL? {
    var url = URLComponents()
    url.scheme = "unour"
    url.host = "table"
    url.path = "/\(attributes.roomId)"
    if attributes.spectator { url.queryItems = [URLQueryItem(name: "spectator", value: "true")] }
    return url.url
}

private func colorName(_ value: String) -> String {
    switch value {
    case "red": return "红色"
    case "yellow": return "黄色"
    case "green": return "绿色"
    case "blue": return "蓝色"
    default: return "万能"
    }
}

private func tableTint(_ value: String) -> Color {
    switch value {
    case "red": return Color(red: 0.95, green: 0.35, blue: 0.38)
    case "yellow": return Color(red: 0.98, green: 0.78, blue: 0.25)
    case "green": return Color(red: 0.24, green: 0.75, blue: 0.54)
    case "blue": return Color(red: 0.35, green: 0.62, blue: 0.98)
    default: return Color(red: 0.78, green: 0.69, blue: 1)
    }
}
