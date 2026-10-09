package com.horis.cncverse

import android.content.Context
import android.util.Log

object DisneyPlusProvider {
    private const val TAG = "DisneyPlusProvider"
    private const val mainUrl = "https://net52.cc"

    suspend fun getStreamUrl(title: String, mediaType: String, season: Int, episode: Int): String? {
        return try {
            val cookie = Utils.bypass(mainUrl)
            val cleanQuery = Utils.encode(title.trim())
            val time = System.currentTimeMillis()

            val cookies = mapOf("t_hash_t" to cookie, "hd" to "on", "ott" to "dp")
            val searchUrl = "$mainUrl/mobile/hs/search.php?s=$cleanQuery&t=$time"
            val searchRes = Utils.getText(searchUrl, cookies = cookies)
            val searchJson = Utils.parseJson(searchRes) ?: return null

            val results = searchJson.optJSONArray("searchResult") ?: return null
            if (results.length() == 0) return null

            val matchedItem = results.getJSONObject(0)
            val contentId = matchedItem.optString("id")
            if (contentId.isBlank()) return null

            val apiBase = Utils.resolveApiUrl()
            val playerUrl = "$apiBase/newtv/player.php?id=$contentId"
            val headers = Utils.buildNewTvHeaders("hs")
            val playerRes = Utils.getText(playerUrl, headers = headers)
            val playerJson = Utils.parseJson(playerRes)

            val videoLink = playerJson?.optString("video_link")
            if (!videoLink.isNullOrBlank()) {
                Log.d(TAG, "DisneyPlus NewTV link: $videoLink")
                return videoLink
            }
            null
        } catch (e: Exception) {
            Log.e(TAG, "DisneyPlusProvider error: ${e.localizedMessage}")
            null
        }
    }
}