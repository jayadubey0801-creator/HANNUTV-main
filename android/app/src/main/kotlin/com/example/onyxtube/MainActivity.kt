package com.example.onyxtube

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.horis.cncverse.CNCVersePlugin
import com.horis.cncverse.NetflixMirrorStorage

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.horis.cncverse/stream"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize Native Cookie & API Base storage
        NetflixMirrorStorage.init(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStreamUrl" -> {
                    val title = call.argument<String>("title") ?: ""
                    val mediaType = call.argument<String>("mediaType") ?: "movie"
                    val provider = call.argument<String>("provider") ?: "netflix"
                    val season = call.argument<Int>("season") ?: 1
                    val episode = call.argument<Int>("episode") ?: 1

                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val streamUrl = CNCVersePlugin.fetchStreamUrl(
                                context = applicationContext,
                                title = title,
                                mediaType = mediaType,
                                provider = provider,
                                season = season,
                                episode = episode
                            )
                            withContext(Dispatchers.Main) {
                                if (!streamUrl.isNullOrEmpty()) {
                                    result.success(streamUrl)
                                } else {
                                    result.error("NOT_FOUND", "Direct stream URL could not be resolved", null)
                                }
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("EXCEPTION", e.localizedMessage, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}