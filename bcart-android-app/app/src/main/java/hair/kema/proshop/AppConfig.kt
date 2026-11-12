package hair.kema.proshop

import android.net.Uri

/** アプリ全体の設定(iOS版 AppConfig.swift と同内容) */
object AppConfig {
    /** Bカートの買い手向けサイトのホスト(完全一致のみ許可) */
    const val shopHost = "kema.i17.bcart.jp"

    /** Bカートの買い手向けサイトURL */
    const val BCART_URL = "https://$shopHost"

    /** 中継サーバー(XServer VPS)のベースURL */
    const val RELAY_BASE_URL = "https://relay.kema.hair"

    /**
     * 中継サーバーの APP_REGISTER_SECRET と「必ず同じ値」にすること。
     * 空文字の間は X-App-Token ヘッダを送らない。本物の値はここへ手で入れる(リポジトリには実値をコミットしない運用を推奨)。
     */
    val appRegisterSecret: String = ""

    const val LOGIN_PATH = "/login.php"
    const val REGISTER_PATH = "/regist.php"
    const val ORDER_HISTORY_PATH = "/mypage.php"

    /**
     * ログイン後にのみ現れるパス(端末登録のトリガー判定)。
     * "/order" "/member" は未ログインでも到達しうる(カート・会員登録系)ため外した。
     */
    val LOGGED_IN_PATH_HINTS = listOf("/mypage")

    fun shopUrl(path: String): String = BCART_URL + (if (path.startsWith("/")) path else "/$path")

    fun isShopHost(host: String?): Boolean = host != null && host.equals(shopHost, ignoreCase = true)

    fun isShopUrl(url: String?): Boolean {
        if (url.isNullOrEmpty()) return false
        val uri = Uri.parse(url)
        return (uri.scheme == "https" || uri.scheme == "http") && isShopHost(uri.host)
    }

    /**
     * 通知・ディープリンク等の外部入力を、ショップ内URLにのみ解決する。
     * 許可: 「/」始まりの相対パス、または https://kema.i17.bcart.jp の絶対URL。それ以外は null。
     */
    fun resolveShopUrl(raw: String?): String? {
        val s = raw?.trim() ?: return null
        if (s.isEmpty() || s.any { it.isISOControl() || it == '\\' }) return null
        if (s.startsWith("/")) {
            return if (s.startsWith("//")) null else shopUrl(s)
        }
        val uri = Uri.parse(s)
        val ok = uri.scheme.equals("https", ignoreCase = true) &&
            isShopHost(uri.host) &&
            uri.userInfo == null &&
            (uri.port == -1 || uri.port == 443) &&
            uri.encodedAuthority.let { a -> a != null && (a.equals(shopHost, true) || a.equals("$shopHost:443", true)) }
        return if (ok) s else null
    }
}
