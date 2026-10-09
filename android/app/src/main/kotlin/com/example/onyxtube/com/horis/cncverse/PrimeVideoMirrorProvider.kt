package com.horis.cncverse

import android.content.Context
import android.util.Log

object PrimeVideoMirrorProvider {
    private const val TAG = "PrimeVideoMirrorProvider"
    private const val mainUrl = "https://net52.cc"

    suspend fun getStreamUrl(title: String, mediaType: String, season: Int, episode: Int): String? {
        return try {
            val cookie = Utils.bypass(mainUrl)
            val cleanQuery = Utils.encode(title.trim())
            val time = System.currentTimeMillis()

            val cookies = mapOf("t_hash_t" to cookie, "hd" to "on", "ott" to "pv")
            val searchUrl = "$mainUrl/mobile/pv/search.php?s=$cleanQuery&t=$time"
            val searchRes = Utils.getText(searchUrl, cookies = cookies)
            val searchJson = Utils.parseJson(searchRes) ?: return null

            val results = searchJson.optJSONArray("searchResult") ?: return null
            if (results.length() == 0) return null

            val matchedItem = results.getJSONObject(0)
            val contentId = matchedItem.optString("id")
            if (contentId.isBlank()) return null

            val apiBase = Utils.resolveApiUrl()
            val playerUrl = "$apiBase/newtv/player.php?id=$contentId"
            val headers = Utils.buildNewTvHeaders("pv")
            val playerRes = Utils.getText(playerUrl, headers = headers)
            val playerJson = Utils.parseJson(playerRes)

            val videoLink = playerJson?.optString("video_link")
            if (!videoLink.isNullOrBlank()) {
                Log.d(TAG, "Prime Video NewTV link: $videoLink")
                return videoLink
            }
            null
        } catch (e: Exception) {
            Log.e(TAG, "PrimeVideoMirrorProvider error: ${e.localizedMessage}")
            null
        }
    }
}