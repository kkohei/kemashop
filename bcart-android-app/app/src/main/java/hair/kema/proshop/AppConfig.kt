package hair.kema.proshop

/** アプリ全体の設定(iOS版 AppConfig.swift と同内容) */
object AppConfig {
    /** Bカートの買い手向けサイトURL */
    const val BCART_URL = "https://kema.i17.bcart.jp"

    /** 中継サーバー(XServer VPS)のベースURL */
    const val RELAY_BASE_URL = "https://relay.kema.hair"

    const val LOGIN_PATH = "/login.php"
    const val REGISTER_PATH = "/regist.php"
    const val ORDER_HISTORY_PATH = "/mypage.php"

    /** ログイン後にのみ現れるパス(端末登録のトリガー判定) */
    val LOGGED_IN_PATH_HINTS = listOf("/mypage", "/order", "/member")
}
