package com.horis.cncverse

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object CNCVersePlugin {
    private const val TAG = "CNCVersePlugin"

    suspend fun fetchStreamUrl(
        context: Context,
        title: String,
        mediaType: String,
        provider: String = "netflix",
        season: Int = 1,
        episode: Int = 1
    ): String? = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "Request: Title='$title', Type='$mediaType', Provider='$provider', S$season:E$episode")

            // 1. Netflix Mirror Scraper
            if (provider.equals("netflix", ignoreCase = true) || provider.equals("netmirror", ignoreCase = true)) {
                val stream = NetflixMirrorProvider.getStreamUrl(title, mediaType, season, episode)
                if (!stream.isNullOrEmpty()) return@withContext stream
            }

            // 2. HotStar Mirror Scraper
            if (provider.equals("hotstar", ignoreCase = true)) {
                val stream = HotStarMirrorProvider.getStreamUrl(title, mediaType, season, episode)
                if (!stream.isNullOrEmpty()) return@withContext stream
            }

            // 3. Prime Video Mirror Scraper
            if (provider.equals("prime", ignoreCase = true)) {
                val stream = PrimeVideoMirrorProvider.getStreamUrl(title, mediaType, season, episode)
                if (!stream.isNullOrEmpty()) return@withContext stream
            }

            // 4. Disney Plus Scraper
            if (provider.equals("disney", ignoreCase = true) || provider.equals("disneyplus", ignoreCase = true)) {
                val stream = DisneyPlusProvider.getStreamUrl(title, mediaType, season, episode)
                if (!stream.isNullOrEmpty()) return@withContext stream
            }

            // Fallback: Check NetflixMirrorProvider first, then HotStar
            val fallback = NetflixMirrorProvider.getStreamUrl(title, mediaType, season, episode)
                ?: HotStarMirrorProvider.getStreamUrl(title, mediaType, season, episode)
                ?: PrimeVideoMirrorProvider.getStreamUrl(title, mediaType, season, episode)

            return@withContext fallback
        } catch (e: Exception) {
            Log.e(TAG, "fetchStreamUrl Error: ${e.localizedMessage}")
            return@withContext null
        }
    }
}