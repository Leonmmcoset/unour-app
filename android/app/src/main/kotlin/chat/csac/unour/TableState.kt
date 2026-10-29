package chat.csac.unour

import org.json.JSONObject

internal data class TableState(val data: JSONObject) {
    val roomId: String get() = data.optString("roomId")
    val round: Int get() = data.optInt("round", 1)
    val phase: String get() = data.optString("phase")
    val spectator: Boolean get() = data.optBoolean("spectator")
    val yourTurn: Boolean get() = data.optBoolean("isYourTurn")
    val updatedAt: Long get() = (data.optDouble("updatedAt", 0.0) * 1000).toLong()
    val connected: Boolean get() = data.optBoolean("connected", true)
    val key: String get() = "$roomId:$round"
    val color: String get() = colorName(data.optString("activeColor"))
    val turn: String get() = when {
        !connected -> "牌况待刷新"
        phase == "lobby" -> "等待开局"
        phase == "finished" -> "本局结束"
        yourTurn -> "轮到你出牌"
        else -> "${data.optString("turnName")} 正在出牌"
    }
    val summary: String get() = buildString {
        append("${data.optString("topCard")} · 当前$color")
        if (!spectator) append(" · 你有 ${data.optInt("myCount")} 张")
        if (data.optInt("pendingDraw") > 0) append(" · 罚牌 +${data.optInt("pendingDraw")}")
    }

    fun disconnected(): TableState = TableState(JSONObject(data.toString()).put("connected", false))

    companion object {
        fun colorName(color: String): String = when (color) {
            "red" -> "红色"
            "yellow" -> "黄色"
            "green" -> "绿色"
            "blue" -> "蓝色"
            else -> "万能"
        }

        fun fromRoom(room: JSONObject): TableState {
            val state = room.getJSONObject("state")
            val you = state.optString("you")
            val turn = state.optString("turn")
            val spectator = room.optString("role", "player") == "spectator"
            val players = state.optJSONArray("players")
            val departed = room.optJSONArray("departed")
            val departedIds = (0 until (departed?.length() ?: 0)).map { departed!!.optString(it) }.toSet()
            var myCount = 0
            var turnName = "玩家"
            val counts = mutableListOf<String>()
            for (index in 0 until (players?.length() ?: 0)) {
                val player = players!!.getJSONObject(index)
                val name = player.optString("name", "玩家")
                if (player.optString("id") == you) myCount = player.optInt("hand_count")
                if (player.optString("id") == turn) turnName = name
                val count = if (player.optBoolean("eliminated") || player.optString("id") in departedIds) "–"
                    else player.optInt("hand_count").toString()
                if (index < 10) counts += "${short(name, 12)} $count"
            }
            val card = state.optJSONObject("top_card")
            val symbol = when (card?.optString("kind")) {
                "number" -> card.optInt("number").toString()
                "skip" -> "⊘"
                "reverse" -> "⇄"
                "draw_two" -> "+2"
                "wild_draw_four" -> "+4"
                "wild" -> "✦"
                else -> "U"
            }
            val kind = when (card?.optString("kind")) {
                "number" -> card.optInt("number").toString()
                "skip" -> "跳过"
                "reverse" -> "反转"
                "draw_two" -> "加二"
                "wild_draw_four" -> "加四"
                "wild" -> "换色"
                else -> ""
            }
            return TableState(JSONObject().apply {
                put("roomId", room.getString("id"))
                put("round", room.optInt("round", 1))
                put("revision", room.optInt("revision"))
                put("version", state.optInt("version"))
                put("phase", state.optString("phase", "lobby"))
                put("spectator", spectator)
                put("turnName", short(turnName, 24))
                put("isYourTurn", turn == you && !spectator)
                put("myCount", myCount)
                put("topCard", if (card == null) "等待发牌" else colorName(card.optString("color")) + kind)
                put("symbol", symbol)
                put("activeColor", state.optString("active_color", "wild"))
                put("pendingDraw", state.optInt("pending_draw"))
                put("direction", state.optInt("direction", 1))
                put("players", counts.joinToString(" · "))
                put("connected", true)
                put("updatedAt", System.currentTimeMillis() / 1000.0)
            })
        }

        private fun short(value: String, count: Int): String =
            String(value.codePoints().limit(count.toLong()).toArray(), 0, value.codePointCount(0, value.length).coerceAtMost(count))
    }
}
