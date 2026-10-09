package com.horis.cncverse

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

object NetflixMirrorProvider {
    private const val TAG = "NetflixMirrorProvider"
    private const val mainUrl = "https://net52.cc"
    private const val playUrl = "https://net77.cc/play.php"
    private const val playlistBaseUrl = "https://net52.cc/playlist.php"
    private const val nativeReferer = "https://net77.cc/home"
    private const val nativeOrigin = "https://net77.cc"

    suspend fun getStreamUrl(title: String, mediaType: String, season: Int, episode: Int): String? {
        return try {
            val cookie = Utils.bypass(mainUrl)
            val cleanQuery = Utils.encode(title.trim())
            val time = System.currentTimeMillis()

            val cookies = mapOf("t_hash_t" to cookie, "hd" to "on", "ott" to "nf")
            val searchUrl = "$mainUrl/mobile/search.php?s=$cleanQuery&t=$time"
            val searchRes = Utils.getText(searchUrl, cookies = cookies)
            val searchJson = Utils.parseJson(searchRes) ?: return null

            val results = searchJson.optJSONArray("searchResult") ?: return null
            if (results.length() == 0) return null

            val matchedItem = results.getJSONObject(0)
            val contentId = matchedItem.optString("id")
            if (contentId.isBlank()) return null

            // 1. Primary: NewTV Player API Link
            val apiBase = Utils.resolveApiUrl()
            val playerUrl = "$apiBase/newtv/player.php?id=$contentId"
            val headers = Utils.buildNewTvHeaders("nf")
            val playerRes = Utils.getText(playerUrl, headers = headers)
            val playerJson = Utils.parseJson(playerRes)

            val videoLink = playerJson?.optString("video_link")
            if (!videoLink.isNullOrBlank()) {
                Log.d(TAG, "Successfully resolved NewTV video link: $videoLink")
                return videoLink
            }

            // 2. Secondary: Play.php -> Playlist.php Token Flow
            val playData = mapOf("id" to contentId)
            val playHeaders = mapOf(
                "Accept" to "application/json, text/javascript, */*; q=0.01",
                "Content-Type" to "application/x-www-form-urlencoded; charset=UTF-8",
                "Origin" to nativeOrigin,
                "Referer" to nativeReferer,
                "User-Agent" to Utils.USER_AGENT
            )
            val playRes = Utils.postText(playUrl, data = playData, headers = playHeaders, cookies = cookies)
            val playJson = Utils.parseJson(playRes)
            val tokenH = playJson?.optString("h")

            if (!tokenH.isNullOrBlank()) {
                val tm = System.currentTimeMillis()
                val playlistUrl = "$playlistBaseUrl?id=$contentId&t=${Utils.encode(title)}&tm=$tm&h=${Utils.encode(tokenH)}"
                val playlistRes = Utils.getText(playlistUrl, headers = playHeaders, cookies = cookies)
                
                if (playlistRes.startsWith("[")) {
                    val arr = JSONArray(playlistRes)
                    if (arr.length() > 0) {
                        val firstObj = arr.getJSONObject(0)
                        val sources = firstObj.optJSONArray("sources")
                        if (sources != null && sources.length() > 0) {
                            val file = sources.getJSONObject(0).optString("file")
                            if (file.isNotBlank()) {
                                return if (file.startsWith("http")) file else "https://net52.cc$file"
                            }
                        }
                    }
                } else {
                    val obj = Utils.parseJson(playlistRes)
                    val sources = obj?.optJSONArray("sources")
                    if (sources != null && sources.length() > 0) {
                        val file = sources.getJSONObject(0).optString("file")
                        if (file.isNotBlank()) {
                            return if (file.startsWith("http")) file else "https://net52.cc$file"
                        }
                    }
                }
            }

            null
        } catch (e: Exception) {
            Log.e(TAG, "NetflixMirrorProvider error: ${e.localizedMessage}")
            null
        }
    }
}