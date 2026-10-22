import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'banner_ad_widget.dart';
import 'config.dart' show kAllGenres, GenreDef;
import 'skippable_ad_screen.dart';
import 'stores.dart';
import 'tmdb_service.dart';
import 'widgets.dart';

const String kTmdbToken =
    'eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiIzZDJkOTExNmM5ZGU3MjA5ZWUyNzdiYjhjYzlhZWVkOCIsIm5iZiI6MTc5MDI2OTE4NC42MjksInN1YiI6IjZhYjU1NzAwNzZiMTg1ODU3MGFjNDM4NSIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.xZJX8fowhVhVJsgl-5wOW6Y7ZfUr9Zu_Ey1qMkhnPd0';

const Map<String, String> kApiHeaders = {
  'Authorization': 'Bearer $kTmdbToken',
  'accept': 'application/json',
};

const String _adsterraBannerSnippet = '''
  <script type="text/javascript">
    atOptions = { 'key' : 'a39df283f6ad10c34e229e5715bceff5', 'format' : 'iframe', 'height' : 50, 'width' : 320, 'params' : {} };
  </script>
  <script type="text/javascript" src="https://www.highrevenueformat.com/a39df283f6ad10c34e229e5715bceff5/invoke.js"></script>
''';

class VideoPlayerPage extends StatefulWidget {
  final int tmdbId;
  final String mediaType;
  final int season;
  final int episode;
  final String movieTitle;
  final String overview;
  final String rating;
  final String year;
  final String? customUrl;
  final bool isOfflineDownload;
  final String? offlineFilePath;
  final String? offlineLanguage;
  final String? offlineQuality;
  final String? offlineServerName;

  const VideoPlayerPage({
    super.key,
    required this.tmdbId,
    required this.mediaType,
    this.season = 1,
    this.episode = 1,
    required this.movieTitle,
    this.overview = '',
    this.rating = '9.0',
    this.year = '2024',
    this.customUrl,
    this.isOfflineDownload = false,
    this.offlineFilePath,
    this.offlineLanguage,
    this.offlineQuality,
    this.offlineServerName,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with SingleTickerProviderStateMixin {
  late WebViewController _controller;
  WebViewController? _adWebViewController;

  final GlobalKey _webViewSurfaceKey = GlobalKey();

  // 100% Working Offline Loopback Server!
  HttpServer? _offlineLoopbackServer;

  bool _effectiveOfflineMode = false;
  String? _effectiveOfflinePath;
  String? _effectiveOfflineLang;
  String? _effectiveOfflineQual;
  String? _effectiveOfflineSrv;

  bool isVideoPlaying = false;
  bool isFullScreen = false;
  bool isPageLoading = true;

  String activeServer = 'vidrift';
  String currentAspectRatio = 'contain';
  String _sniffedStreamUrl = '';
  String _currentProxyTargetUrl = '';
  final List<String> _detectedServerAudioTracks = <String>[];
  final List<String> _detectedServerQualities = <String>[];

  late int currentSeason;
  late int currentEpisode;
  int viewCount = 84920;

  bool showControls = true;
  Timer? _hideControlsTimer;

  bool _isShowingInPlayerAd = true;
  bool _isAdLoadingWait = true;
  bool _isAdMuted = false;
  int _adLoadWaitSeconds = 3;
  int _adSkipTimeLeft = 15;
  int _adElapsedSeconds = 0;
  bool _canSkipInPlayerAd = false;
  bool _isAdblockDetected = false;
  bool _checkingDns = false;
  Timer? _adLoadWaitTimer;
  Timer? _inPlayerAdTimer;
  Timer? _thirtyMinAdCycleTimer;
  Timer? _dnsWatchdogTimer;
  Timer? _backgroundMuteGuardTimer;

  static const String kUnityGameId = '800405137';
  static const String kUnityInterstitialId = 'BP_Interstitial_Android';
  static const String kUnityRewardedId = 'BP_Rewarded_Android';
  static const String kUnityBannerId = 'BP_Banner_Android';

  static const List<String> _adProbeDomains = [
    'unityads.unity3d.com',
    'config.unityads.unity3d.com',
    'webview.unityads.unity3d.com',
  ];

  final List<Map<String, String>> _sponsors = const [
    {
      'title': 'BGMI / Action Battle Royale • Play Now',
      'subtitle': 'Download Official Battle Royale Game on Google Play',
      'domain': 'play.google.com',
      'fullUrl': 'https://play.google.com/store/apps/details?id=com.pubg.imobile',
      'cta': 'Download Game',
      'adVideo': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
    },
    {
      'title': 'Color Water Sort Puzzle • 3D Brain Game',
      'subtitle': 'Play the #1 Trending Bottle Sort Game on Android',
      'domain': 'play.google.com',
      'fullUrl': 'https://play.google.com/store/apps/details?id=com.IEC.WaterSort',
      'cta': 'Install Now',
      'adVideo': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
    },
    {
      'title': 'Google Play Store • Top Racing & Action Games',
      'subtitle': 'Explore Trending Android Games & Apps Instantly',
      'domain': 'play.google.com',
      'fullUrl': 'https://play.google.com/store/apps/category/GAME',
      'cta': 'Open Play Store',
      'adVideo': 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
    },
  ];
  int _activeSponsorIdx = 0;

  bool showIntroAnimation = false;
  late AnimationController _introAnimController;
  late Animation<double> _introScaleAnimation;
  late Animation<double> _introOpacityAnimation;

  final TextEditingController commentInputController = TextEditingController();

  Map<String, dynamic>? details;
  List castList = [];
  bool isLoadingDetails = false;
  bool descExpanded = false;
  final ValueNotifier<Color> _ambientColor = ValueNotifier<Color>(const Color(0xFF5B2A86));
  List<Color> _ambientPalette = const [Color(0xFF5B2A86), Color(0xFF1E5AA8), Color(0xFFB02A4A)];
  int _ambientIndex = 0;
  Timer? _ambientTimer;
  final ValueNotifier<List<Color>> _ambientZones =
      ValueNotifier<List<Color>>(List<Color>.filled(8, const Color(0xFF5B2A86)));
  List<List<Color>> _ambientZonePalette = <List<Color>>[];
  final ValueNotifier<double> _videoZoom = ValueNotifier<double>(1.0);

  final List<Map<String, String>> servers = const [
    {'key': 'vidrift', 'name': 'Rift'},
    {'key': 'bingr', 'name': 'Fast'},
    {'key': 'vidcore', 'name': 'Fast (Ads)'},
    {'key': 'vidbolt', 'name': 'Bolt'},
    {'key': 'cinezo', 'name': 'Cinezo'},
    {'key': 'peachify', 'name': 'Peach'},
    {'key': 'vidlink', 'name': 'Mega'},
    {'key': 'vidfast', 'name': 'Alpha'},
    {'key': 'vidrock', 'name': 'Orion'},
    {'key': 'hindi-new', 'name': 'Hindi New'},
    {'key': 'screenscape', 'name': 'Hindi'},
    {'key': 'zxcstream', 'name': 'Vidgod'},
    {'key': 'cinesrc', 'name': 'CineSrc'},
  ];

  List similarMovies = [];
  bool isLoadingSimilar = false;
  bool isTvDevice = false;

  int totalSeasons = 1;
  List episodesList = [];

  @override
  void initState() {
    super.initState();
    currentSeason = widget.season;
    currentEpisode = widget.episode;
    _activeSponsorIdx = Random().nextInt(_sponsors.length);

    _introAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _introScaleAnimation = Tween<double>(begin: 0.7, end: 1.3)
        .animate(CurvedAnimation(parent: _introAnimController, curve: Curves.easeOutBack));
    _introOpacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _introAnimController, curve: const Interval(0.65, 1.0, curve: Curves.easeIn)));

    final DownloadTaskItem? downloadedTask = DownloadStore.I.findTaskForMedia(
      tmdbId: widget.tmdbId,
      mediaType: _tmdbType,
      season: currentSeason,
      episode: currentEpisode,
    );

    if (widget.isOfflineDownload &&
        downloadedTask != null &&
        downloadedTask.status == 'completed') {
      _effectiveOfflineMode = true;
      _effectiveOfflinePath = widget.offlineFilePath ?? downloadedTask.localFilePath;
      _effectiveOfflineLang = widget.offlineLanguage ?? downloadedTask.language;
      _effectiveOfflineQual = widget.offlineQuality ?? downloadedTask.quality;
      _effectiveOfflineSrv = widget.offlineServerName ?? downloadedTask.serverName;
      _isShowingInPlayerAd = false;
      _isAdLoadingWait = false;
    } else {
      _effectiveOfflineMode = false;
      _initInPlayerAdWebView();
      _ensureUnityInitialized();
      if (widget.customUrl == null) {
        _fetchSimilarMovies();
        _fetchTvDetails();
        _fetchDetails();
      }
      _runDnsCheck();
      _dnsWatchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) => _runDnsCheck());
      _triggerYouTubeStyleAd();
      _thirtyMinAdCycleTimer = Timer.periodic(const Duration(minutes: 30), (_) {
        if (mounted && !_effectiveOfflineMode) _triggerYouTubeStyleAd();
      });
    }

    _checkDeviceType();
    WatchlistStore.I.load();
    DownloadStore.I.load();
    _startAmbientCycle();
  }

  void _ensureUnityInitialized() {
    try {
      UnityAds.init(
        gameId: kUnityGameId,
        testMode: false,
      );
    } catch (_) {}
  }

  void _initInPlayerAdWebView() {
    final WebViewController adCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('AdBridge', onMessageReceived: (JavaScriptMessage msg) {
        if (!mounted) return;
        if (msg.message == 'started') {
          if (_isAdLoadingWait) _startAdPlaybackAnd15SecSkipTimer();
        } else if (msg.message == 'ended') {
          _finishInPlayerAd();
        } else if (msg.message == 'clicked') {
          _openSponsorWebsite();
        }
      });

    final platform = adCtrl.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    _adWebViewController = adCtrl;
  }

  void _loadVideoAdIntoAdWebView() {
    if (_adWebViewController == null || _effectiveOfflineMode) return;
    final sponsor = _sponsors[_activeSponsorIdx];
    final String adVideoUrl = sponsor['adVideo']!;
    
    // Deep Ad Size Fix: object-fit: contain makes sure the video automatically adjusts perfectly
    final String adHtml = '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; user-select: none; }
          html, body {
            width: 100vw; height: 100vh; background: #000000; overflow: hidden;
            display: flex; align-items: center; justify-content: center;
          }
          video {
            width: 100vw; height: 100vh; object-fit: contain; background: #000;
            cursor: pointer;
          }
        </style>
      </head>
      <body>
        <video id="adVid" src="$adVideoUrl" autoplay playsinline></video>
        <script>
          var v = document.getElementById('adVid');
          v.muted = false;
          v.volume = 1.0;
          var playPromise = v.play();
          if (playPromise !== undefined) {
            playPromise.catch(function() {
              v.muted = true;
              v.play();
            });
          }
          v.addEventListener('playing', function() {
            try { AdBridge.postMessage('started'); } catch(e) {}
          });
          v.addEventListener('ended', function() {
            try { AdBridge.postMessage('ended'); } catch(e) {}
          });
          document.body.addEventListener('click', function() {
            try { AdBridge.postMessage('clicked'); } catch(e) {}
          });
        </script>
      </body>
      </html>
    ''';
    _adWebViewController!.loadHtmlString(adHtml);
  }

  void _toggleAdMute() {
    setState(() => _isAdMuted = !_isAdMuted);
    try {
      _adWebViewController?.runJavaScript('''
        var v = document.getElementById('adVid');
        if (v) { v.muted = ${_isAdMuted ? 'true' : 'false'}; }
      ''');
    } catch (_) {}
  }

  Future<bool> _isDnsBlocked() async {
    if (_effectiveOfflineMode) return false;
    for (final host in _adProbeDomains) {
      try {
        final result = await InternetAddress.lookup(host).timeout(const Duration(milliseconds: 900));
        if (result.isEmpty) return true;
        if (result.any((a) =>
            a.isLoopback ||
            a.address == '0.0.0.0' ||
            a.address == '127.0.0.1' ||
            a.address == '::1' ||
            a.address == '::')) {
          return true;
        }
      } catch (_) {
        try {
          final g = await InternetAddress.lookup('google.com').timeout(const Duration(milliseconds: 900));
          if (g.isNotEmpty) return true;
        } catch (_) {
          return false;
        }
      }
    }
    return false;
  }

  Future<void> _runDnsCheck() async {
    if (_effectiveOfflineMode || _checkingDns || !mounted) return;
    _checkingDns = true;
    try {
      final bool blocked = await _isDnsBlocked();
      if (!mounted) return;
      if (blocked && !_isAdblockDetected) {
        setState(() {
          _isAdblockDetected = true;
          _isShowingInPlayerAd = true;
          _canSkipInPlayerAd = false;
        });
        _enforceBackgroundPrebufferPause();
      } else if (!blocked && _isAdblockDetected) {
        setState(() {
          _isAdblockDetected = false;
        });
        _triggerYouTubeStyleAd();
      }
    } catch (_) {
    } finally {
      _checkingDns = false;
    }
  }

  void _triggerYouTubeStyleAd() {
    if (!mounted || _effectiveOfflineMode) return;
    _adLoadWaitTimer?.cancel();
    _inPlayerAdTimer?.cancel();

    setState(() {
      _activeSponsorIdx = Random().nextInt(_sponsors.length);
      _isShowingInPlayerAd = true;
      _isAdLoadingWait = true;
      _isAdMuted = false;
      _adLoadWaitSeconds = 3;
      _adSkipTimeLeft = 15;
      _adElapsedSeconds = 0;
      _canSkipInPlayerAd = false;
    });

    _loadVideoAdIntoAdWebView();
    _preloadInPlayerUnityAd();

    _backgroundMuteGuardTimer?.cancel();
    _backgroundMuteGuardTimer = Timer.periodic(const Duration(milliseconds: 180), (_) {
      if (_isShowingInPlayerAd && mounted) {
        _enforceBackgroundPrebufferPause();
      }
    });

    _adLoadWaitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_isAdblockDetected) return;

      if (_adLoadWaitSeconds > 1) {
        setState(() => _adLoadWaitSeconds--);
      } else {
        timer.cancel();
        if (_isAdLoadingWait) {
          _startAdPlaybackAnd15SecSkipTimer();
        }
      }
    });
  }

  void _preloadInPlayerUnityAd() {
    if (_isAdblockDetected || _effectiveOfflineMode) return;
    try {
      UnityAds.load(
        placementId: kUnityInterstitialId,
        onComplete: (placementId) {
          if (!mounted || !_isShowingInPlayerAd || _isAdblockDetected) return;
          _startAdPlaybackAnd15SecSkipTimer();
        },
        onFailed: (placementId, error, message) {
          UnityAds.load(
            placementId: kUnityRewardedId,
            onComplete: (id) {
              if (!mounted || !_isShowingInPlayerAd || _isAdblockDetected) return;
              _startAdPlaybackAnd15SecSkipTimer();
            },
            onFailed: (id, err, msg) {},
          );
        },
      );
    } catch (_) {}
  }

  void _startAdPlaybackAnd15SecSkipTimer() {
    if (!mounted) return;
    _adLoadWaitTimer?.cancel();
    if (!_isAdLoadingWait && _inPlayerAdTimer != null && _inPlayerAdTimer!.isActive) return;

    setState(() {
      _isAdLoadingWait = false;
      _adSkipTimeLeft = 15;
      _canSkipInPlayerAd = false;
    });

    _inPlayerAdTimer?.cancel();
    _inPlayerAdTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_isAdblockDetected) return;

      setState(() {
        _adElapsedSeconds++;
        if (_adSkipTimeLeft > 1) {
          _adSkipTimeLeft--;
        } else {
          _adSkipTimeLeft = 0;
          _canSkipInPlayerAd = true;
        }
      });
    });
  }

  void _finishInPlayerAd() {
    if (_isAdblockDetected || !mounted) return;
    _adLoadWaitTimer?.cancel();
    _inPlayerAdTimer?.cancel();
    _backgroundMuteGuardTimer?.cancel();
    try {
      _adWebViewController?.loadHtmlString('<html><body style="background:#000;"></body></html>');
    } catch (_) {}
    setState(() {
      _isShowingInPlayerAd = false;
      _isAdLoadingWait = false;
      isPageLoading = true;
    });
    _loadOnlineMovieStreamIntoWebView();
  }

  void _enforceBackgroundPrebufferPause() {
    try {
      _controller.runJavaScript('''
        window.__hannuAdActive = true;
        var vids = document.querySelectorAll('video, audio');
        vids.forEach(function(v) {
          try {
            v.muted = true;
            v.volume = 0;
            if (!v.paused) v.pause();
          } catch(e) {}
        });
        var ifs = document.querySelectorAll('iframe');
        ifs.forEach(function(f) {
          try {
            var s = f.getAttribute('src') || '';
            if (s && s !== 'about:blank' && !s.includes('ads') && !s.includes('bet')) {
              f.setAttribute('data-hannu-src', s);
              try { VideoState.postMessage('stream:' + s); } catch(e) {}
              f.setAttribute('src', 'about:blank');
            }
          } catch(e) {}
        });
      ''');
    } catch (_) {}
  }

  void _unmuteAndResumeMovieInstantly() {
    try {
      _controller.runJavaScript('''
        window.__hannuAdActive = false;
        var ifs = document.querySelectorAll('iframe');
        ifs.forEach(function(f) {
          try {
            var saved = f.getAttribute('data-hannu-src');
            if (saved && (f.getAttribute('src') === 'about:blank' || !f.getAttribute('src'))) {
              f.setAttribute('src', saved);
            }
          } catch(e) {}
        });
        var vids = document.querySelectorAll('video, audio');
        vids.forEach(function(v) {
          try {
            v.muted = false;
            v.volume = 1.0;
            v.play();
          } catch(e) {}
        });
        var playBtns = document.querySelectorAll('.vjs-big-play-button, .jw-icon-display, .play-icon, #play-button');
        if (playBtns.length > 0) {
          try { playBtns[0].click(); } catch(e) {}
        }
      ''');
    } catch (_) {}
  }

  Future<void> _openSponsorWebsite([String? customLink]) async {
    final String url = customLink ??
        _sponsors[_activeSponsorIdx]['fullUrl'] ??
        'https://play.google.com/store/apps';
    final Uri? u = Uri.tryParse(url);
    if (u == null) return;
    try {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _buildYouTubeInPlayerAdOverlay() {
    if (_effectiveOfflineMode) return const SizedBox.shrink();
    if (!_isShowingInPlayerAd && !_isAdblockDetected) return const SizedBox.shrink();

    final sponsor = _sponsors[_activeSponsorIdx];
    final bool full = isFullScreen || isTvDevice;

    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            if (!_isAdblockDetected && _adWebViewController != null)
              Positioned.fill(
                child: WebViewWidget(controller: _adWebViewController!),
              ),

            if (_isAdLoadingWait && !_isAdblockDetected)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.82),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 3),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Loading High-Speed Video Ad (${_adLoadWaitSeconds}s)...",
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            if (_isAdblockDetected)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.98),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: 46),
                      SizedBox(height: 8),
                      Text(
                        "AdBlocker / Private DNS Detected!",
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Kindly turn off Private DNS / AdGuard\nto continue watching your movie.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),

            Positioned(
              top: full ? 14 : 8,
              left: 12,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.78),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.amber.withOpacity(0.65)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(2)),
                          child: const Text(
                            "Ad",
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isAdLoadingWait
                              ? "Loading Ad (${_adLoadWaitSeconds}s)"
                              : "Sponsored • 0:${_adElapsedSeconds.toString().padLeft(2, '0')}",
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _toggleAdMute,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Icon(
                        _isAdMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              top: full ? 14 : 8,
              right: 12,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _toggleFullScreen,
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white30),
                      ),
                      child: Icon(
                        full ? Icons.fullscreen_exit : Icons.fullscreen,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _toggleFullScreen,
                    child: Opacity(
                      opacity: 0.9,
                      child: Image.asset(
                        'assets/logo.png',
                        height: 28,
                        errorBuilder: (_, __, ___) => const Text(
                          'HANNUTV',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (!_isAdblockDetected)
              Positioned(
                bottom: full ? 20 : 10,
                left: 10,
                right: 132,
                child: GestureDetector(
                  onTap: () => _openSponsorWebsite(sponsor['fullUrl']),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: full ? 14 : 10,
                      vertical: full ? 10 : 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.84),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withOpacity(0.7), width: 1.1),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.sports_esports_rounded, color: Colors.amber, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                sponsor['title']!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: full ? 13 : 11,
                                ),
                              ),
                              Text(
                                sponsor['fullUrl']!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: full ? 11 : 9.5,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                sponsor['cta']!,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(Icons.open_in_new_rounded, color: Colors.black, size: 11),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            Positioned(
              bottom: full ? 20 : 12,
              right: 10,
              child: GestureDetector(
                onTap: (_canSkipInPlayerAd && !_isAdblockDetected && !_isAdLoadingWait)
                    ? _finishInPlayerAd
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: (_canSkipInPlayerAd && !_isAdblockDetected && !_isAdLoadingWait)
                        ? Colors.white
                        : Colors.black.withOpacity(0.88),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: (_canSkipInPlayerAd && !_isAdblockDetected && !_isAdLoadingWait)
                          ? Colors.white
                          : Colors.white54,
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isAdblockDetected || _isAdLoadingWait) ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 2),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        _isAdblockDetected
                            ? "Loading..."
                            : (_isAdLoadingWait
                                ? "Loading Ad..."
                                : (_canSkipInPlayerAd ? "Skip Ad" : "Skip in $_adSkipTimeLeft")),
                        style: TextStyle(
                          color: (_canSkipInPlayerAd && !_isAdblockDetected && !_isAdLoadingWait)
                              ? Colors.black
                              : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                      if (_canSkipInPlayerAd && !_isAdblockDetected && !_isAdLoadingWait) ...[
                        const SizedBox(width: 5),
                        const Icon(Icons.skip_next_rounded, color: Colors.black, size: 17),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                value: _isAdLoadingWait ? null : ((15 - _adSkipTimeLeft) / 15).clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYouTubeSponsorCompanionCard() {
    final sponsor = _sponsors[_activeSponsorIdx];
    return GestureDetector(
      onTap: () => _openSponsorWebsite(sponsor['fullUrl']),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF171722),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.withOpacity(0.45)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Ad',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sponsor['title']!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sponsor['fullUrl']!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 11,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sponsor['cta']!,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.open_in_new_rounded, color: Colors.white, size: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchTvDetails() async {
    if (widget.mediaType != 'tv' && widget.mediaType != 'series') return;
    try {
      final res = await tmdbHttpGet(
        'https://api.themoviedb.org/3/tv/${widget.tmdbId}?language=en-US',
        headers: kApiHeaders,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) {
          setState(() {
            totalSeasons = data['number_of_seasons'] ?? 1;
          });
        }
        _fetchEpisodes(currentSeason);
      }
    } catch (e) {}
  }

  Future<void> _fetchEpisodes(int seasonNum) async {
    if (widget.mediaType != 'tv' && widget.mediaType != 'series') return;
    try {
      final res = await tmdbHttpGet(
        'https://api.themoviedb.org/3/tv/${widget.tmdbId}/season/$seasonNum?language=en-US',
        headers: kApiHeaders,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) {
          setState(() {
            episodesList = data['episodes'] ?? [];
          });
        }
      }
    } catch (e) {}
  }

  void _checkDeviceType() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = MediaQuery.of(context).size;
      setState(() {
        isTvDevice = size.width > size.height && size.width > 600;
        if (isTvDevice) {
          isFullScreen = true;
        } else {
          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      });
      _startControlsTimer();
      _initStream();
    });
  }

  void _startControlsTimer() {
    _hideControlsTimer?.cancel();
    if (mounted) setState(() => showControls = true);
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => showControls = false);
    });
  }

  void _triggerCinematicPlayAnimation() {
    if (showIntroAnimation || isVideoPlaying) return;
    setState(() {
      showIntroAnimation = true;
      isVideoPlaying = true;
      isPageLoading = false;
    });
    _introAnimController.forward().then((_) {
      if (mounted) setState(() => showIntroAnimation = false);
    });
  }

  Future<void> _fetchSimilarMovies() async {
    setState(() => isLoadingSimilar = true);
    try {
      final type = widget.mediaType == 'tv' || widget.mediaType == 'series' ? 'tv' : 'movie';
      final res = await tmdbHttpGet(
        'https://api.themoviedb.org/3/$type/${widget.tmdbId}/recommendations?language=en-US',
        headers: kApiHeaders,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List results = data['results'] ?? [];
        if (mounted) {
          setState(() {
            similarMovies = results
                .map((m) => {
                      'id': m['id'],
                      'title': m['title'] ?? m['name'] ?? 'Unknown',
                      'posterUrl': m['poster_path'] != null
                          ? proxyImg('https://image.tmdb.org/t/p/w500${m['poster_path']}')
                          : '',
                      'rating': (m['vote_average'] ?? 0).toStringAsFixed(1),
                      'year': (m['release_date'] ?? m['first_air_date'] ?? '').toString().split('-').first,
                      'mediaType': type,
                    })
                .toList();
            isLoadingSimilar = false;
          });
        }
      } else {
        if (mounted) setState(() => isLoadingSimilar = false);
      }
    } catch (_) {
      if (mounted) setState(() => isLoadingSimilar = false);
    }
  }

  void _initStream() {
    setState(() {
      isPageLoading = true;
      isVideoPlaying = false;
      showIntroAnimation = false;
      _detectedServerAudioTracks.clear();
      _detectedServerQualities.clear();
    });

    final id = widget.tmdbId;
    final isTv = widget.mediaType == 'tv' || widget.mediaType == 'series';
    String originalTargetUrl = isTv
        ? 'https://pantyflix.com/watch/play/tv/$id?season=$currentSeason&episode=$currentEpisode&server=$activeServer'
        : 'https://pantyflix.com/watch/play/movie/$id?server=$activeServer';
    String vercelProxyBase = "https://hannutv-proxy-1.vercel.app/api/proxy?stream=";
    _currentProxyTargetUrl = vercelProxyBase + Uri.encodeComponent(originalTargetUrl);
    if (_sniffedStreamUrl.isEmpty) {
      _sniffedStreamUrl = _currentProxyTargetUrl;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(isTvDevice
          ? "Mozilla/5.0 (SMART-TV; Linux; Tizen 5.0) AppleWebKit/538.1 (KHTML, like Gecko) Version/5.0 TV Safari/538.1"
          : "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
      ..setOnJavaScriptAlertDialog((JavaScriptAlertDialogRequest request) async {})
      ..setOnJavaScriptConfirmDialog((JavaScriptConfirmDialogRequest request) async => false)
      ..setOnJavaScriptTextInputDialog((JavaScriptTextInputDialogRequest request) async => '')
      ..addJavaScriptChannel('VideoState', onMessageReceived: (JavaScriptMessage message) {
        final String msg = message.message;
        if (msg == 'playing' && mounted) {
          _triggerCinematicPlayAnimation();
        } else if (msg == 'ad_finished' && mounted) {
          if (_canSkipInPlayerAd) _finishInPlayerAd();
        } else if (msg == 'ad_clicked' && mounted) {
          _openSponsorWebsite();
        } else if (msg.startsWith('stream:') && mounted) {
          final String url = msg.substring(7).trim();
          if (url.isNotEmpty && url.startsWith('http')) {
            _sniffedStreamUrl = url;
          }
        } else if (msg.startsWith('audio:') && mounted) {
          final String track = msg.substring(6).trim();
          if (track.isNotEmpty && !_detectedServerAudioTracks.contains(track)) {
            setState(() => _detectedServerAudioTracks.add(track));
          }
        } else if (msg.startsWith('quality:') && mounted) {
          final String q = msg.substring(8).trim();
          if (q.isNotEmpty && !_detectedServerQualities.contains(q)) {
            setState(() => _detectedServerQualities.add(q));
          }
        }
      });

    final platformController = _controller.platform;
    if (platformController is AndroidWebViewController) {
      platformController.setMediaPlaybackRequiresUserGesture(false);
      platformController.setAllowFileAccess(true); 
    }

    if (_effectiveOfflineMode) {
      _loadOfflineDownloadedVideo();
      return;
    }

    if (_isShowingInPlayerAd) {
      _triggerYouTubeStyleAd();
    } else {
      _loadOnlineMovieStreamIntoWebView();
    }
  }

  void _loadOnlineMovieStreamIntoWebView() {
    _controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (String url) {
          if (mounted) setState(() => isPageLoading = true);
          _controller.runJavaScript('''
            window.open = function() { return null; };
            window.alert = function() { return null; };
            window.confirm = function() { return false; };
            window.prompt = function() { return null; };

            (function() {
              if (window.__hannuSnifferInstalled) return;
              window.__hannuSnifferInstalled = true;
              function checkStreamUrl(u) {
                if (!u || typeof u !== 'string') return;
                if (u.indexOf('.m3u8') !== -1 || u.indexOf('.mp4') !== -1 || u.indexOf('/master.') !== -1 || u.indexOf('index.m3u8') !== -1) {
                  if (u.startsWith('http')) {
                    try { VideoState.postMessage('stream:' + u); } catch(e) {}
                  }
                }
              }
              var origFetch = window.fetch;
              if (origFetch) {
                window.fetch = function() {
                  try { checkStreamUrl(arguments[0] && arguments[0].url ? arguments[0].url : arguments[0]); } catch(e) {}
                  return origFetch.apply(this, arguments);
                };
              }
              var origOpen = XMLHttpRequest.prototype.open;
              XMLHttpRequest.prototype.open = function(method, url) {
                try { checkStreamUrl(url); } catch(e) {}
                return origOpen.apply(this, arguments);
              };
            })();
          ''');
        },
        onPageFinished: (String url) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) setState(() => isPageLoading = false);
          });

          String jsCode = '''
            document.body.style.backgroundColor = '#000000';
            document.documentElement.style.backgroundColor = '#000000';
            
            var style = document.createElement('style');
            style.innerHTML = `
              header, nav, footer, .navbar, .logo, .search, form, 
              h1, h2, h3, p, span, .menu,
              .ad-container, .ads, [class*="ad-"], a[target="_blank"], iframe[src*="ads"], iframe[src*="bet"] { 
                  display: none !important; 
                  opacity: 0 !important; 
                  visibility: hidden !important; 
                  pointer-events: none !important;
              }
              
              body, html { 
                  background-color: #000000 !important; 
                  overflow: hidden !important; 
                  margin: 0 !important; 
                  padding: 0 !important; 
                  width: 100% !important;
                  height: 100% !important;
              }
              
              iframe:not([src*="ads"]) {
                  position: fixed !important;
                  top: 0 !important;
                  left: 0 !important;
                  width: 100vw !important;
                  height: 100vh !important;
                  z-index: 99998 !important;
                  border: none !important;
                  background-color: #000000 !important;
              }
            `;
            document.head.appendChild(style);

            window.open = function() { return null; };
            window.alert = function() { return null; };
            window.confirm = function() { return false; };
            window.prompt = function() { return null; };
            
            document.addEventListener('click', function(e) {
                var target = e.target;
                if(target.tagName === 'A' || target.closest('a')) {
                    e.preventDefault();
                    e.stopPropagation();
                }
            }, true);

            setInterval(function() {
              var vids = document.getElementsByTagName('video');
              if (vids.length > 0) {
                var v = vids[0];
                v.style.backgroundColor = '#000000';
                v.style.objectFit = '$currentAspectRatio';
                v.style.position = 'fixed';
                v.style.top = '0'; 
                v.style.left = '0'; 
                v.style.width = '100vw'; 
                v.style.height = '100vh'; 
                v.style.zIndex = '999999';
                
                if (v.currentSrc && v.currentSrc.startsWith('http')) {
                  VideoState.postMessage('stream:' + v.currentSrc);
                } else if (v.src && v.src.startsWith('http')) {
                  VideoState.postMessage('stream:' + v.src);
                }

                if (v.currentTime > 0.3 && !v.paused) {
                  VideoState.postMessage('playing');
                }
              }
              
              var playBtns = document.querySelectorAll('.vjs-big-play-button, .jw-icon-display, .play-icon, #play-button');
              if (playBtns.length > 0 && !window.__hannuClickedMainPlay) {
                  window.__hannuClickedMainPlay = true;
                  playBtns[0].click();
              }

              var modals = document.querySelectorAll('[id*="robot"], [class*="robot"], [id*="captcha"], [class*="captcha"], .swal2-container');
              modals.forEach(function(m) {
                try { m.remove(); } catch(e) {}
              });
            }, 250);
          ''';
          _controller.runJavaScript(jsCode);
        },
        onNavigationRequest: (NavigationRequest request) {
          final url = request.url.toLowerCase();

          if (url.contains('.m3u8') || url.contains('.mp4')) {
            _sniffedStreamUrl = request.url;
          }

          if (url.contains('google.com') ||
              url.contains('doubleclick') ||
              url.contains('popads') ||
              url.contains('1xbet') ||
              url.contains('1win') ||
              url.contains('bet365') ||
              url.contains('adsterra') ||
              url.contains('highrevenueformat') ||
              url.contains('profitableratecpm') ||
              url.contains('omg10.com') ||
              url.contains('redirect') ||
              url.contains('onclick') ||
              url.startsWith('intent://') ||
              url.startsWith('market://') ||
              url.startsWith('whatsapp://') ||
              url.contains('about:blank')) {
            return NavigationDecision.prevent;
          }

          if (request.isMainFrame) {
            if (!url.contains('pantyflix') && !url.contains('vercel.app')) {
              return NavigationDecision.prevent;
            }
          }

          return NavigationDecision.navigate;
        },
      ),
    );

    if (widget.customUrl != null && widget.customUrl!.isNotEmpty) {
      _sniffedStreamUrl = widget.customUrl!;
      _currentProxyTargetUrl = widget.customUrl!;
      if (widget.customUrl!.contains('.m3u8')) {
        String hlsHtml = '''
          <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
          <style>body, html { margin: 0; padding: 0; background: black; height: 100%; width: 100%; overflow: hidden; } video { width: 100%; height: 100%; object-fit: contain; }</style>
          </head><body>
          <video id="video" autoplay controls playsinline></video>
          <script>
            var video = document.getElementById('video');
            if (Hls.isSupported()) {
              var hls = new Hls();
              hls.loadSource('${widget.customUrl}');
              hls.attachMedia(video);
              hls.on(Hls.Events.MANIFEST_PARSED, function() { video.play(); VideoState.postMessage('playing'); });
            } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
              video.src = '${widget.customUrl}';
              video.addEventListener('loadedmetadata', function() { video.play(); VideoState.postMessage('playing'); });
            }
          </script></body></html>
        ''';
        _controller.loadHtmlString(hlsHtml);
      } else {
        _controller.loadRequest(Uri.parse(widget.customUrl!));
      }
    } else {
      _controller.loadRequest(Uri.parse(_currentProxyTargetUrl));
    }
  }

  // 🔥 100% Guaranteed Offline File Logic with Loopback Server + Fallback 🔥
  Future<void> _loadOfflineDownloadedVideo() async {
    try {
      await _offlineLoopbackServer?.close(force: true);
    } catch (_) {}

    File? validVideoFile;
    if (_effectiveOfflinePath != null && _effectiveOfflinePath!.isNotEmpty) {
      try {
        final File f = File(_effectiveOfflinePath!);
        if (await f.exists() && await f.length() > 1024) {
          validVideoFile = f;
        }
      } catch (_) {}
    }

    if (validVideoFile != null) {
      try {
        _offlineLoopbackServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final int port = _offlineLoopbackServer!.port;
        final String localStreamUrl = 'http://127.0.0.1:$port/video.mp4';

        _offlineLoopbackServer!.listen((HttpRequest request) async {
          try {
            final response = request.response;
            response.headers.contentType = ContentType('video', 'mp4');
            response.headers.set('Accept-Ranges', 'bytes');
            response.headers.set('Access-Control-Allow-Origin', '*');

            final int fileLength = await validVideoFile!.length();
            final String? rangeHeader = request.headers.value('range');

            if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
              final parts = rangeHeader.substring(6).split('-');
              final int start = int.tryParse(parts[0]) ?? 0;
              final int end = parts.length > 1 && parts[1].isNotEmpty
                  ? int.tryParse(parts[1]) ?? (fileLength - 1)
                  : (fileLength - 1);

              response.statusCode = HttpStatus.partialContent;
              response.headers.set('Content-Range', 'bytes $start-$end/$fileLength');
              response.contentLength = (end - start) + 1;

              final stream = validVideoFile!.openRead(start, end + 1);
              await response.addStream(stream);
            } else {
              response.statusCode = HttpStatus.ok;
              response.contentLength = fileLength;
              await response.addStream(validVideoFile!.openRead());
            }
            await response.close();
          } catch (_) {}
        });

        final String offlineVideoHtml = '''
          <!DOCTYPE html>
          <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
              * { box-sizing: border-box; margin: 0; padding: 0; user-select: none; }
              html, body {
                width: 100vw; height: 100vh; background: #000; overflow: hidden;
                display: flex; align-items: center; justify-content: center;
              }
              video { width: 100vw; height: 100vh; object-fit: $currentAspectRatio; background: #000; }
            </style>
          </head>
          <body>
            <video id="v" src="$localStreamUrl" autoplay controls playsinline></video>
            <script>
              var v = document.getElementById('v');
              v.addEventListener('loadeddata', function() {
                try { VideoState.postMessage('playing'); } catch(e) {}
                try { v.play(); } catch(e) {}
              });
              v.addEventListener('playing', function() {
                try { VideoState.postMessage('playing'); } catch(e) {}
              });
            </script>
          </body>
          </html>
        ''';

        await _controller.loadHtmlString(offlineVideoHtml);
        if (mounted) {
          setState(() {
            isPageLoading = false;
            isVideoPlaying = true;
          });
        }
      } catch (e) {
        _fallbackToOnlineStreaming();
      }
    } else {
      // Data file absent or corrupted => Fallback to Online automatically
      _fallbackToOnlineStreaming();
    }
  }

  void _fallbackToOnlineStreaming() {
    if (mounted) {
      setState(() {
        _effectiveOfflineMode = false;
        _isShowingInPlayerAd = true;
      });
      _triggerYouTubeStyleAd();
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 🔥 DEEP SERVER STREAM ANALYZER & MULTI-AUDIO / QUALITY DOWNLOAD SHEET 🔥
  // ───────────────────────────────────────────────────────────────────────────

  int _resolveActualRuntimeMinutes() {
    final Map<String, dynamic>? d = details;
    if (d != null) {
      if (_tmdbType == 'movie') {
        final dynamic rt = d['runtime'];
        if (rt is int && rt > 15) return rt;
      } else {
        if (episodesList.isNotEmpty && currentEpisode - 1 < episodesList.length) {
          final dynamic epRt = episodesList[currentEpisode - 1]['runtime'];
          if (epRt is int && epRt > 10) return epRt;
        }
        final dynamic runtimes = d['episode_run_time'];
        if (runtimes is List && runtimes.isNotEmpty && runtimes.first is int) {
          return runtimes.first as int;
        }
        return 45;
      }
    }
    return _tmdbType == 'tv' ? 45 : 115;
  }

  String _activeServerDisplayName() {
    for (final s in servers) {
      if (s['key'] == activeServer) return s['name'] ?? activeServer;
    }
    return activeServer.toUpperCase();
  }

  void _showRealDownloadSheet() {
    final int runtimeMins = _resolveActualRuntimeMinutes();
    final String srvName = _activeServerDisplayName();
    final bool isTv = _tmdbType == 'tv';
    final String fullTitle = isTv
        ? '${widget.movieTitle} S${currentSeason.toString().padLeft(2, '0')}E${currentEpisode.toString().padLeft(2, '0')}'
        : widget.movieTitle;

    bool isAnalyzingServer = true;
    ServerStreamAnalysis? analysisResult;
    String selectedLang = '';
    int selectedQualityIdx = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141D),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            if (isAnalyzingServer && analysisResult == null) {
              DownloadStore.I
                  .analyzeServerStream(
                sniffedUrl: _sniffedStreamUrl,
                proxyUrl: _currentProxyTargetUrl,
                serverKey: activeServer,
                serverName: srvName,
                runtimeMinutes: runtimeMins,
                jsDetectedAudio: _detectedServerAudioTracks,
                jsDetectedQualities: _detectedServerQualities,
              )
                  .then((res) {
                if (!ctx.mounted) return;
                setModalState(() {
                  analysisResult = res;
                  isAnalyzingServer = false;
                  selectedLang = res.availableLanguages.first;
                  selectedQualityIdx = res.qualities.length > 2 ? 2 : 0;
                });
              });
            }

            if (isAnalyzingServer || analysisResult == null) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 42,
                        height: 42,
                        child: CircularProgressIndicator(color: Colors.greenAccent, strokeWidth: 3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Deep Analyzing Server ($srvName) Player...',
                        style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Verifying movie stream URL, available audio tracks & video qualities from server...',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            }

            final ServerStreamAnalysis res = analysisResult!;
            final List<String> dubbedLanguages = res.availableLanguages;
            final List<Map<String, dynamic>> qualityProfiles = res.qualities;
            final Map<String, dynamic> activeQ =
                qualityProfiles[selectedQualityIdx.clamp(0, qualityProfiles.length - 1)];
            final int totalBytes = activeQ['bytes'] as int;
            final String formattedSize = DownloadStore.formatBytes(totalBytes);
            final String streamToDownload =
                (activeQ['streamUrl']?.toString().isNotEmpty ?? false)
                    ? activeQ['streamUrl'].toString()
                    : res.confirmedStreamUrl;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.verified_rounded, color: Colors.greenAccent, size: 22),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fullTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Server Confirmed: $srvName (${res.streamProtocol}) • ${dubbedLanguages.length} Audio Tracks',
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'URL: ${res.confirmedStreamUrl}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Available Audio on $srvName Server:',
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: dubbedLanguages.map((lang) {
                          final bool isSel = selectedLang == lang;
                          return GestureDetector(
                            onTap: () => setModalState(() => selectedLang = lang),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: isSel ? Colors.redAccent : Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: isSel ? Colors.redAccent : Colors.white24),
                              ),
                              child: Text(
                                lang,
                                style: TextStyle(
                                  color: isSel ? Colors.white : Colors.white70,
                                  fontSize: 11.5,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Available Video Qualities on $srvName Server:',
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(qualityProfiles.length, (i) {
                        final q = qualityProfiles[i];
                        final bool isSel = selectedQualityIdx == i;
                        final String qSize = DownloadStore.formatBytes(q['bytes'] as int);
                        return GestureDetector(
                          onTap: () => setModalState(() => selectedQualityIdx = i),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSel ? Colors.redAccent.withOpacity(0.15) : const Color(0xFF1E1E2A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSel ? Colors.redAccent : Colors.white12,
                                width: isSel ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSel ? Icons.radio_button_checked : Icons.radio_button_off,
                                  color: isSel ? Colors.redAccent : Colors.white38,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        q['label'] as String,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                      Text(
                                        '${q['tag']} • ${q['kbps']} kbps',
                                        style: const TextStyle(color: Colors.grey, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    qSize,
                                    style: const TextStyle(
                                      color: Colors.amber,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.download_rounded, color: Colors.white),
                          label: Text(
                            'Download from $srvName ($formattedSize)',
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () async {
                            Navigator.pop(sheetCtx);
                            final String posterPath = await _posterUrlForWatchlist();
                            final String fullPoster =
                                posterPath.isNotEmpty ? proxyImg('https://image.tmdb.org/t/p/w500$posterPath') : '';

                            await DownloadStore.I.startDownload(
                              tmdbId: widget.tmdbId,
                              mediaType: _tmdbType,
                              season: currentSeason,
                              episode: currentEpisode,
                              title: fullTitle,
                              posterUrl: fullPoster,
                              serverName: srvName,
                              language: selectedLang,
                              quality: activeQ['label'] as String,
                              streamUrl: streamToDownload,
                              estimatedBytes: totalBytes,
                              year: widget.year,
                              rating: widget.rating,
                              overview: widget.overview,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _cycleAspectRatio() {
    setState(() {
      if (currentAspectRatio == 'contain') {
        currentAspectRatio = 'cover';
      } else if (currentAspectRatio == 'cover') {
        currentAspectRatio = 'fill';
      } else {
        currentAspectRatio = 'contain';
      }
    });
    _controller.runJavaScript(
        "var vids = document.getElementsByTagName('video'); if (vids.length > 0) { vids[0].style.objectFit = '$currentAspectRatio'; }");
    _startControlsTimer();
  }

  // Zero-Black-Screen Rotation (Both Swipe-Up & HANNUTV Logo Tap — UNTOUCHED!)
  void _toggleFullScreen() {
    if (isTvDevice) return;
    final bool targetFull = !isFullScreen;
    setState(() {
      isFullScreen = targetFull;
    });
    if (targetFull) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
    Future.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      try {
        _controller.runJavaScript('''
          window.dispatchEvent(new Event('resize'));
          var vids = document.getElementsByTagName('video');
          if (vids.length > 0) {
            vids[0].style.width = '100vw';
            vids[0].style.height = '100vh';
            vids[0].style.objectFit = '$currentAspectRatio';
          }
        ''');
      } catch (_) {}
    });
    _startControlsTimer();
  }

  void _enterFullScreenOnSwipeUp() {
    if (isTvDevice || isFullScreen) return;
    _toggleFullScreen();
  }

  void _exitFullScreenOnSwipeDown() {
    if (isTvDevice || !isFullScreen) return;
    _toggleFullScreen();
  }

  void _switchEpisode(int ep) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerPage(
          tmdbId: widget.tmdbId,
          mediaType: widget.mediaType,
          season: currentSeason,
          episode: ep,
          movieTitle: widget.movieTitle,
          overview: widget.overview,
          rating: widget.rating,
          year: widget.year,
        ),
      ),
    );
  }

  void _switchSeason(int seasonNum) {
    setState(() {
      currentSeason = seasonNum;
      currentEpisode = 1;
      episodesList.clear();
    });
    _fetchEpisodes(seasonNum);
    _switchEpisode(1);
  }

  void _showSeasonPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("$totalSeasons Seasons Available",
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const Text("Full Catalog", style: TextStyle(color: Colors.redAccent, fontSize: 12))
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: totalSeasons,
                  itemBuilder: (context, index) {
                    int seasonNum = index + 1;
                    return ListTile(
                      title: Text("Season ${seasonNum.toString().padLeft(2, '0')}",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      trailing: const Icon(Icons.play_circle_outline, color: Colors.grey, size: 20),
                      onTap: () {
                        Navigator.pop(context);
                        _switchSeason(seasonNum);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAudioServerPingMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151515),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.70,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Server Status & Audio",
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                          icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context))
                    ],
                  ),
                  const Text("Real-time deep analysis of active servers:",
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: servers.length,
                      itemBuilder: (context, index) {
                        final srv = servers[index];
                        int mockPing = Random().nextInt(250) + 15;
                        Color pingColor = mockPing < 80
                            ? Colors.greenAccent
                            : (mockPing < 150 ? Colors.orangeAccent : Colors.redAccent);
                        IconData towerIcon = mockPing < 80
                            ? Icons.signal_cellular_alt
                            : (mockPing < 150 ? Icons.signal_cellular_alt_2_bar : Icons.signal_cellular_alt_1_bar);

                        List<String> langs = ['English'];
                        if (srv['name']!.toLowerCase().contains('hindi') || srv['key'] == 'cinezo') {
                          langs.addAll(['Hindi', 'Tamil', 'Telugu']);
                        }
                        if (srv['key'] == 'vidrift' || srv['key'] == 'bingr' || srv['key'] == 'vidbolt') {
                          langs.addAll(['Hindi', 'Spanish']);
                        }

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          leading: Icon(towerIcon, color: pingColor, size: 28),
                          title: Text(srv['name']!,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle:
                              Text("Audio: ${langs.join(', ')}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: pingColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: pingColor)),
                            child: Text("${mockPing}ms",
                                style: TextStyle(color: pingColor, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            if (activeServer != srv['key']) {
                              setState(() => activeServer = srv['key']!);
                              _loadOnlineMovieStreamIntoWebView();
                            }
                          },
                        );
                      },
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  String get _tmdbType => (widget.mediaType == 'tv' || widget.mediaType == 'series') ? 'tv' : 'movie';

  Future<void> _fetchDetails() async {
    if (mounted) setState(() => isLoadingDetails = true);
    try {
      final res = await tmdbHttpGet(
        'https://api.themoviedb.org/3/$_tmdbType/${widget.tmdbId}?language=en-US&append_to_response=credits,images&include_image_language=en,null',
        headers: kApiHeaders,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data is Map<String, dynamic> && mounted) {
          final List cast =
              (data['credits'] is Map && data['credits']['cast'] is List) ? data['credits']['cast'] : [];
          setState(() {
            details = data;
            castList = cast.take(30).toList();
            isLoadingDetails = false;
          });
          _buildAmbientPalette(data);
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => isLoadingDetails = false);
  }

  Future<void> _buildAmbientPalette(Map<String, dynamic> data) async {
    if (_effectiveOfflineMode) return;
    final List<String> paths = [];
    try {
      final imgs = data['images'];
      if (imgs is Map && imgs['backdrops'] is List) {
        for (final b in (imgs['backdrops'] as List)) {
          final p = b is Map ? b['file_path'] : null;
          if (p is String && p.isNotEmpty && !paths.contains(p)) paths.add(p);
          if (paths.length >= 8) break;
        }
      }
      final bp = data['backdrop_path'];
      if (bp is String && bp.isNotEmpty && !paths.contains(bp)) paths.insert(0, bp);
      final pp = data['poster_path'];
      if (pp is String && pp.isNotEmpty) paths.add(pp);
    } catch (_) {}

    final List<Color> palette = [];
    final List<List<Color>> zonePalette = [];
    for (final p in paths) {
      if (!mounted) return;
      final Color? c = await _dominantColorFromUrl(proxyImg('https://image.tmdb.org/t/p/w300$p'));
      if (!mounted) return;
      final List<Color>? z = await _zoneColorsFromUrl(proxyImg('https://image.tmdb.org/t/p/w300$p'));
      if (!mounted) return;
      if (c != null) {
        palette.add(c);
        zonePalette.add(z ?? List<Color>.filled(8, c));
        if (palette.length == 1) {
          _ambientTimer?.cancel();
          _ambientPalette = [c];
          _ambientZonePalette = [zonePalette.first];
          _ambientColor.value = c;
          _ambientZones.value = zonePalette.first;
        }
      }
    }
    if (!mounted || palette.isEmpty) return;
    _ambientPalette = palette;
    _ambientZonePalette = zonePalette;
    _startAmbientCycle();
  }

  Future<Color?> _dominantColorFromUrl(String url) async {
    try {
      final Completer<ui.Image> completer = Completer<ui.Image>();
      final ImageStream stream = NetworkImage(url).resolve(const ImageConfiguration());
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool _) {
          if (!completer.isCompleted) completer.complete(info.image);
          stream.removeListener(listener);
        },
        onError: (Object error, StackTrace? stackTrace) {
          if (!completer.isCompleted) completer.completeError(error);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      final ui.Image img = await completer.future.timeout(const Duration(seconds: 10));
      final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final Uint8List bytes = data.buffer.asUint8List();

      final List<double> wSum = List<double>.filled(24, 0);
      final List<double> rSum = List<double>.filled(24, 0);
      final List<double> gSum = List<double>.filled(24, 0);
      final List<double> bSum = List<double>.filled(24, 0);
      for (int i = 0; i + 3 < bytes.length; i += 20) {
        final int r = bytes[i];
        final int g = bytes[i + 1];
        final int b = bytes[i + 2];
        final HSVColor hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
        final double wgt = hsv.saturation * hsv.value;
        if (wgt < 0.05) continue;
        int bin = (hsv.hue / 15).floor();
        if (bin > 23) bin = 23;
        if (bin < 0) bin = 0;
        wSum[bin] += wgt;
        rSum[bin] += r * wgt;
        gSum[bin] += g * wgt;
        bSum[bin] += b * wgt;
      }
      int best = -1;
      double bestW = 0;
      for (int k = 0; k < 24; k++) {
        if (wSum[k] > bestW) {
          bestW = wSum[k];
          best = k;
        }
      }
      if (best < 0) return null;
      final Color avg = Color.fromARGB(
        255,
        (rSum[best] / bestW).round().clamp(0, 255).toInt(),
        (gSum[best] / bestW).round().clamp(0, 255).toInt(),
        (bSum[best] / bestW).round().clamp(0, 255).toInt(),
      );
      final HSVColor h = HSVColor.fromColor(avg);
      return HSVColor.fromAHSV(
        1.0,
        h.hue,
        h.saturation.clamp(0.5, 1.0).toDouble(),
        h.value.clamp(0.55, 0.95).toDouble(),
      ).toColor();
    } catch (_) {
      return null;
    }
  }

  void _startAmbientCycle() {
    _ambientTimer?.cancel();
    if (_ambientPalette.isEmpty) return;
    _ambientIndex = 0;
    _ambientColor.value = _ambientPalette[0];
    _applyZones(0);
    if (_ambientPalette.length < 2) return;
    _ambientTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _ambientPalette.isEmpty) return;
      _ambientIndex = (_ambientIndex + 1) % _ambientPalette.length;
      _ambientColor.value = _ambientPalette[_ambientIndex];
      _applyZones(_ambientIndex);
    });
  }

  Future<String> _posterUrlForWatchlist() async {
    if (_effectiveOfflineMode) return '';
    String path = '';
    final Map<String, dynamic>? d = details;
    if (d != null && d['poster_path'] is String) path = d['poster_path'] as String;
    if (path.isEmpty) {
      try {
        final res = await tmdbHttpGet(
          'https://api.themoviedb.org/3/$_tmdbType/${widget.tmdbId}?language=en-US',
          headers: kApiHeaders,
        ).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          if (data is Map && data['poster_path'] is String) path = data['poster_path'] as String;
        }
      } catch (_) {}
    }
    return path;
  }

  Future<void> _toggleWatchlist() async {
    final String posterPath = await _posterUrlForWatchlist();
    final Map<String, dynamic> tmdbData = {
      'id': widget.tmdbId,
      'is_tv': _tmdbType == 'tv',
      'title': widget.movieTitle,
      'name': widget.movieTitle,
      'release_date': widget.year,
      'first_air_date': widget.year,
      'vote_average': num.tryParse(widget.rating) ?? 0.0,
      'overview': widget.overview.isNotEmpty ? widget.overview : (details?['overview'] ?? ''),
      'poster_path': posterPath.isEmpty ? null : posterPath,
    };
    final item = TmdbItem.fromStored(tmdbData);
    await WatchlistStore.I.toggle(item);

    if (!mounted) return;
    final bool saved = WatchlistStore.I.contains(item);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? 'Added to Watchlist' : 'Removed from Watchlist'),
        backgroundColor: saved ? Colors.green : Colors.grey[800],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _applyZones(int i) {
    if (i < _ambientZonePalette.length) {
      _ambientZones.value = _ambientZonePalette[i];
    } else {
      _ambientZones.value = List<Color>.filled(8, _ambientColor.value);
    }
  }

  Future<List<Color>?> _zoneColorsFromUrl(String url) async {
    try {
      final Completer<ui.Image> completer = Completer<ui.Image>();
      final ImageStream stream = NetworkImage(url).resolve(const ImageConfiguration());
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool _) {
          if (!completer.isCompleted) completer.complete(info.image);
          stream.removeListener(listener);
        },
        onError: (Object error, StackTrace? stackTrace) {
          if (!completer.isCompleted) completer.completeError(error);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      final ui.Image img = await completer.future.timeout(const Duration(seconds: 10));
      final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final Uint8List bytes = data.buffer.asUint8List();
      final int w = img.width;
      final int h = img.height;
      const List<List<int>> cells = <List<int>>[
        [0, 0],
        [1, 0],
        [2, 0],
        [2, 1],
        [2, 2],
        [1, 2],
        [0, 2],
        [0, 1],
      ];
      final List<Color?> raw = <Color?>[];
      for (final List<int> c in cells) {
        raw.add(_zoneCellColor(
          bytes,
          w,
          (w * c[0] / 3).floor(),
          (w * (c[0] + 1) / 3).floor(),
          (h * c[1] / 3).floor(),
          (h * (c[1] + 1) / 3).floor(),
        ));
      }
      Color fallback = const Color(0xFF3A2A6A);
      for (final Color? c in raw) {
        if (c != null) {
          fallback = c;
          break;
        }
      }
      final HSVColor fh = HSVColor.fromColor(fallback);
      final Color dim =
          HSVColor.fromAHSV(1.0, fh.hue, fh.saturation, (fh.value * 0.6).clamp(0.0, 1.0).toDouble()).toColor();
      return raw.map((Color? c) => c ?? dim).toList();
    } catch (_) {
      return null;
    }
  }

  Color? _zoneCellColor(Uint8List bytes, int w, int x0, int x1, int y0, int y1) {
    final List<double> wS = List<double>.filled(12, 0);
    final List<double> rS = List<double>.filled(12, 0);
    final List<double> gS = List<double>.filled(12, 0);
    final List<double> bS = List<double>.filled(12, 0);
    for (int y = y0; y < y1; y += 3) {
      for (int x = x0; x < x1; x += 3) {
        final int i = (y * w + x) * 4;
        if (i + 2 >= bytes.length) continue;
        final int r = bytes[i];
        final int g = bytes[i + 1];
        final int b = bytes[i + 2];
        final HSVColor hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
        final double wgt = hsv.saturation * hsv.value;
        if (wgt < 0.04) continue;
        int bin = (hsv.hue / 30).floor();
        if (bin > 11) bin = 11;
        if (bin < 0) bin = 0;
        wS[bin] += wgt;
        rS[bin] += r * wgt;
        gS[bin] += g * wgt;
        bS[bin] += b * wgt;
      }
    }
    int best = -1;
    double bestW = 0;
    for (int k = 0; k < 12; k++) {
      if (wS[k] > bestW) {
        bestW = wS[k];
        best = k;
      }
    }
    if (best < 0 || bestW < 0.5) return null;
    final Color base = Color.fromARGB(
      255,
      (rS[best] / bestW).round().clamp(0, 255).toInt(),
      (gS[best] / bestW).round().clamp(0, 255).toInt(),
      (bS[best] / bestW).round().clamp(0, 255).toInt(),
    );
    final HSVColor hh = HSVColor.fromColor(base);
    return HSVColor.fromAHSV(
      1.0,
      hh.hue,
      hh.saturation.clamp(0.45, 1.0).toDouble(),
      hh.value.clamp(0.5, 0.95).toDouble(),
    ).toColor();
  }

  Future<List<TmdbItem>> _sameGenreLoader() async {
    final dynamic gl = details?['genres'];
    final List<String> ids = <String>[];
    if (gl is List) {
      for (final dynamic g in gl) {
        if (g is Map && g['id'] != null) ids.add('${g['id']}');
        if (ids.length >= 2) break;
      }
    }
    if (ids.isEmpty) return <TmdbItem>[];
    return Tmdb.I.discover(tv: _tmdbType == 'tv', genres: ids.join(','), count: 20);
  }

  List<Widget> _buildMoreSuggestions() {
    final bool tv = _tmdbType == 'tv';
    void open(TmdbItem it) => _openTitle(
          id: it.id,
          mediaType: it.isTv ? 'tv' : 'movie',
          title: it.title,
          rating: it.rating.toStringAsFixed(1),
          year: it.year,
          overview: it.overview,
        );
    final List<Widget> rows = <Widget>[const SizedBox(height: 10)];
    if (details != null) {
      rows.add(_SuggestRow(
        key: ValueKey('same-${widget.tmdbId}'),
        title: 'More Like This',
        excludeId: widget.tmdbId,
        loader: _sameGenreLoader,
        onOpen: open,
        focusable: _buildFocusableItem,
      ));
    }
    for (final String label in const <String>['Action', 'Comedy', 'Romance', 'Horror', 'Thriller']) {
      final GenreDef g = kAllGenres.firstWhere((GenreDef d) => d.label == label, orElse: () => kAllGenres.first);
      rows.add(_SuggestRow(
        key: ValueKey('$label-${widget.tmdbId}'),
        title: tv ? '$label Series' : '$label Movies',
        excludeId: widget.tmdbId,
        loader: () => Tmdb.I.genreRow(g, tv ? RowKind.series : RowKind.movie, count: 20),
        onOpen: open,
        focusable: _buildFocusableItem,
      ));
    }
    return rows;
  }

  void _openTitle({
    required int id,
    required String mediaType,
    required String title,
    String rating = '0.0',
    String year = '',
    String overview = '',
  }) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerPage(
          tmdbId: id,
          mediaType: mediaType,
          movieTitle: title,
          overview: overview,
          rating: rating,
          year: year,
        ),
      ),
    );
  }

  void _openTitleFromMap(Map<String, dynamic> m) {
    _openTitle(
      id: m['id'] as int,
      mediaType: (m['mediaType'] ?? 'movie').toString(),
      title: (m['title'] ?? '').toString(),
      rating: (m['rating'] ?? '0.0').toString(),
      year: (m['year'] ?? '').toString(),
      overview: (m['overview'] ?? '').toString(),
    );
  }

  void _showSearchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return _SearchSheet(
          onOpenTitle: (Map<String, dynamic> m) {
            Navigator.pop(sheetContext);
            _openTitleFromMap(m);
          },
          onOpenPerson: (int id, String name) {
            Navigator.pop(sheetContext);
            _showActorSheet(id, name);
          },
        );
      },
    );
  }

  void _showActorSheet(int personId, String name) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _ActorSheet(
          personId: personId,
          fallbackName: name,
          onOpenTitle: (Map<String, dynamic> m) {
            Navigator.pop(sheetContext);
            _openTitleFromMap(m);
          },
        );
      },
    );
  }

  Widget _buildCastSection() {
    if (castList.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Cast", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: castList.length,
            itemBuilder: (context, index) {
              final c = castList[index];
              final String name = (c['name'] ?? '').toString();
              final String character = (c['character'] ?? '').toString();
              final dynamic profile = c['profile_path'];
              final bool hasPhoto = profile is String && profile.isNotEmpty;
              return _buildFocusableItem(
                onTap: () => _showActorSheet(c['id'] as int, name),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 86,
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: Colors.grey[900],
                        backgroundImage: hasPhoto
                            ? CachedNetworkImageProvider(proxyImg('https://image.tmdb.org/t/p/w185$profile'))
                            : null,
                        child: hasPhoto ? null : const Icon(Icons.person, color: Colors.white38, size: 30),
                      ),
                      const SizedBox(height: 6),
                      Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      if (character.isNotEmpty)
                        Text(character,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey, fontSize: 10)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _infoRow(String k, String v) {
    if (v.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(k, style: const TextStyle(color: Colors.grey, fontSize: 12))),
          Expanded(child: Text(v, style: const TextStyle(color: Colors.white, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildDescriptionCard() {
    final Map<String, dynamic>? d = details;
    final String fetched = (d?['overview'] ?? '').toString().trim();
    final String overview = fetched.isNotEmpty ? fetched : widget.overview.trim();
    final String tagline = (d?['tagline'] ?? '').toString().trim();
    final List genres = (d?['genres'] is List) ? d!['genres'] as List : [];
    final List langs = (d?['spoken_languages'] is List) ? d!['spoken_languages'] as List : [];
    final String languages = langs
        .map((l) => (l is Map ? (l['english_name'] ?? l['name'] ?? '') : '').toString())
        .where((s) => s.isNotEmpty)
        .join(', ');

    String runtime = '';
    if (d != null) {
      if (_tmdbType == 'movie') {
        final dynamic rt = d['runtime'];
        if (rt is int && rt > 0) {
          runtime = rt >= 60 ? '${rt ~/ 60}h ${rt % 60}m' : '${rt}m';
        }
      } else {
        final dynamic s = d['number_of_seasons'];
        final dynamic e = d['number_of_episodes'];
        if (s != null) {
          runtime = s == 1 ? '1 Season' : '$s Seasons';
          if (e != null) runtime += ' • $e Episodes';
        }
      }
    }

    final String release = (d?['release_date'] ?? d?['first_air_date'] ?? '').toString();
    final String status = (d?['status'] ?? '').toString();
    String ratingStr = '';
    final dynamic va = d?['vote_average'];
    final dynamic vc = d?['vote_count'];
    if (va is num && va > 0) {
      ratingStr = '${va.toStringAsFixed(1)} / 10';
      if (vc is num && vc > 0) ratingStr += '  (${vc.toInt()} votes)';
    }

    final List<String> metaParts = [];
    if (widget.year.isNotEmpty) metaParts.add(widget.year);
    if (runtime.isNotEmpty) metaParts.add(runtime);
    if (widget.rating.isNotEmpty) metaParts.add('★ ${widget.rating}');
    final String metaLine = metaParts.join('  •  ');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => descExpanded = !descExpanded),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text("Description",
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                const Spacer(),
                Icon(descExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.white54, size: 22),
              ],
            ),
            if (metaLine.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(metaLine, style: const TextStyle(color: Colors.grey, fontSize: 12))),
            if (genres.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: genres.take(5).map<Widget>((g) {
                  final String gName = (g is Map ? (g['name'] ?? '') : '').toString();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
                    child: Text(gName, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  );
                }).toList(),
              ),
            ],
            if (tagline.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(tagline,
                  style: const TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 10),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              alignment: Alignment.topCenter,
              child: Text(
                overview.isEmpty
                    ? (isLoadingDetails ? "Loading description..." : "No description available.")
                    : overview,
                maxLines: descExpanded ? null : 3,
                overflow: descExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
              ),
            ),
            if (descExpanded) ...[
              const SizedBox(height: 12),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 10),
              _infoRow('Released', release),
              _infoRow('Runtime', runtime),
              _infoRow('Languages', languages),
              _infoRow('Status', status),
              _infoRow('Rating', ratingStr),
            ],
            const SizedBox(height: 8),
            Text(descExpanded ? "Show less" : "...more",
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _addComment() async {
    final text = commentInputController.text.trim();
    User? user = FirebaseAuth.instance.currentUser;

    if (text.isNotEmpty) {
      if (user == null || user.isAnonymous) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Please login from Dashboard to comment!'), backgroundColor: Colors.redAccent));
        return;
      }

      String movieId =
          widget.customUrl == null ? widget.tmdbId.toString() : 'live_${widget.movieTitle.replaceAll(" ", "_")}';

      await FirebaseFirestore.instance.collection('movies').doc(movieId).collection('comments').add({
        'name': user.displayName ?? 'HANNUTV User',
        'text': text,
        'time': DateTime.now().toIso8601String(),
        'timestamp': FieldValue.serverTimestamp(),
        'avatar': (user.displayName != null && user.displayName!.isNotEmpty) ? user.displayName![0].toUpperCase() : 'H',
      });

      commentInputController.clear();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  void dispose() {
    try {
      _offlineLoopbackServer?.close(force: true);
    } catch (_) {}
    _hideControlsTimer?.cancel();
    _adLoadWaitTimer?.cancel();
    _inPlayerAdTimer?.cancel();
    _thirtyMinAdCycleTimer?.cancel();
    _dnsWatchdogTimer?.cancel();
    _backgroundMuteGuardTimer?.cancel();
    _introAnimController.dispose();
    commentInputController.dispose();
    _ambientTimer?.cancel();
    _ambientColor.dispose();
    _ambientZones.dispose();
    _videoZoom.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    super.dispose();
  }

  Widget _buildFocusableItem({required Widget child, required VoidCallback onTap, BorderRadius? borderRadius}) {
    return _TvFocusButton(onTap: onTap, borderRadius: borderRadius ?? BorderRadius.circular(8), child: child);
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool full = isFullScreen || isTvDevice;
    final double playerHeight = full ? screenSize.height : 230.0;

    bool isTvShow = widget.mediaType == 'tv' || widget.mediaType == 'series';
    String displayTitle = widget.movieTitle;
    if (isTvShow && widget.customUrl == null && !_effectiveOfflineMode) {
      displayTitle += " S${currentSeason.toString().padLeft(2, '0')} - E${currentEpisode.toString().padLeft(2, '0')}";
    }

    return WillPopScope(
      onWillPop: () async {
        if (isFullScreen && !isTvDevice) {
          _toggleFullScreen();
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: full ? Colors.black : const Color(0xFF0F0F0F),
        body: Stack(
          children: [
            _AmbientBackground(
              color: _ambientColor,
              child: SafeArea(
                top: !full,
                bottom: !full,
                left: !full,
                right: !full,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── PERSISTENT VIDEO PLAYER CONTAINER ───
                    _AmbientGlow(
                      zones: _ambientZones,
                      child: GestureDetector(
                        onTap: _startControlsTimer,
                        child: SizedBox(
                          width: double.infinity,
                          height: playerHeight,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: RepaintBoundary(
                                  key: _webViewSurfaceKey,
                                  child: Container(
                                    color: Colors.black,
                                    child: _PinchZoom(
                                      zoom: _videoZoom,
                                      onSwipeUp: _enterFullScreenOnSwipeUp,
                                      onSwipeDown: _exitFullScreenOnSwipeDown,
                                      child: WebViewWidget(controller: _controller),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: full ? 16 : 10,
                                right: full ? 20 : 14,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _toggleFullScreen,
                                  child: Opacity(
                                    opacity: 0.88,
                                    child: Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: Image.asset(
                                        'assets/logo.png',
                                        height: full ? 38 : 34,
                                        errorBuilder: (_, __, ___) => Text(
                                          'HANNUTV',
                                          style: TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                            fontSize: full ? 16 : 15,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (showIntroAnimation)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: Center(
                                      child: AnimatedBuilder(
                                        animation: _introAnimController,
                                        builder: (context, child) {
                                          return Opacity(
                                            opacity: _introOpacityAnimation.value,
                                            child: Transform.scale(
                                              scale: _introScaleAnimation.value,
                                              child: Image.asset(
                                                'assets/logo.png',
                                                height: 60,
                                                errorBuilder: (_, __, ___) => const Icon(
                                                  Icons.play_circle_fill,
                                                  color: Colors.red,
                                                  size: 60,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              if (showControls) ...[
                                Positioned.fill(child: IgnorePointer(child: Container(color: Colors.black26))),
                                Positioned(
                                  top: full ? 18 : 10,
                                  left: full ? 18 : 10,
                                  child: _buildFocusableItem(
                                    onTap: () {
                                      if (isFullScreen && !isTvDevice) {
                                        _toggleFullScreen();
                                      } else {
                                        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                                        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                                        Navigator.pop(context);
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(20),
                                    child: CircleAvatar(
                                      backgroundColor: Colors.black54,
                                      radius: full ? 21 : 18,
                                      child: Icon(
                                        full ? Icons.close : Icons.chevron_left,
                                        color: Colors.white,
                                        size: full ? 26 : 28,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: full ? 18 : 8,
                                  right: full ? 64 : 48,
                                  child: _buildFocusableItem(
                                    onTap: _cycleAspectRatio,
                                    borderRadius: BorderRadius.circular(20),
                                    child: CircleAvatar(
                                      backgroundColor: Colors.black54,
                                      radius: full ? 20 : 16,
                                      child: Icon(
                                        Icons.aspect_ratio,
                                        color: Colors.white,
                                        size: full ? 22 : 18,
                                      ),
                                    ),
                                  ),
                                ),
                                if (!isTvDevice)
                                  Positioned(
                                    bottom: full ? 18 : 8,
                                    right: full ? 18 : 8,
                                    child: _buildFocusableItem(
                                      onTap: _toggleFullScreen,
                                      borderRadius: BorderRadius.circular(20),
                                      child: CircleAvatar(
                                        backgroundColor: Colors.black54,
                                        radius: full ? 20 : 16,
                                        child: Icon(
                                          full ? Icons.fullscreen_exit : Icons.fullscreen,
                                          color: Colors.white,
                                          size: full ? 26 : 22,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                              if (isPageLoading && !isVideoPlaying && !_isShowingInPlayerAd)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black,
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          SizedBox(
                                            width: 30,
                                            height: 30,
                                            child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 2.5),
                                          ),
                                          SizedBox(height: 10),
                                          Text(
                                            "Connecting to Server...",
                                            style: TextStyle(
                                                color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              _buildYouTubeInPlayerAdOverlay(),
                            ],
                          ),
                        ),
                      ),
                    ),

                    if (!full)
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_effectiveOfflineMode)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.greenAccent),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.offline_pin_rounded, color: Colors.greenAccent, size: 16),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Offline Mode • ${_effectiveOfflineLang ?? "Hindi"} • ${_effectiveOfflineQual ?? "HD"} (Server: ${_effectiveOfflineSrv ?? "Rift"})',
                                          style: const TextStyle(
                                            color: Colors.greenAccent,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Text(
                                displayTitle,
                                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.star, color: Colors.amber, size: 18),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.rating,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(widget.year, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                                  const SizedBox(width: 16),
                                  const Icon(Icons.visibility, color: Colors.grey, size: 16),
                                  const SizedBox(width: 4),
                                  Text("$viewCount Views", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 14),

                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    if (widget.customUrl == null) ...[
                                      AnimatedBuilder(
                                        animation: WatchlistStore.I,
                                        builder: (context, _) {
                                          final bool saved = WatchlistStore.I.items.any(
                                              (e) => e.id == widget.tmdbId && (e.isTv ? 'tv' : 'movie') == _tmdbType);
                                          return _buildFocusableItem(
                                            onTap: _toggleWatchlist,
                                            borderRadius: BorderRadius.circular(20),
                                            child: _buildActionButton(
                                              saved ? Icons.bookmark : Icons.bookmark_border,
                                              saved ? "In Watchlist" : "Add to Watchlist",
                                              activeColor: saved ? Colors.amber : Colors.white,
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      AnimatedBuilder(
                                        animation: DownloadStore.I,
                                        builder: (context, _) {
                                          final activeTask = DownloadStore.I.findTaskForMedia(
                                            tmdbId: widget.tmdbId,
                                            mediaType: _tmdbType,
                                            season: currentSeason,
                                            episode: currentEpisode,
                                          );
                                          if (activeTask == null) {
                                            return _buildFocusableItem(
                                              onTap: _showRealDownloadSheet,
                                              borderRadius: BorderRadius.circular(20),
                                              child: _buildActionButton(
                                                Icons.downloading_rounded,
                                                "Download",
                                                activeColor: Colors.greenAccent,
                                              ),
                                            );
                                          }
                                          final bool isDone = activeTask.status == 'completed';
                                          final bool isPaused = activeTask.status == 'paused';
                                          return Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _buildFocusableItem(
                                                onTap: () {
                                                  if (isDone) {
                                                    openMyDownloads(context);
                                                  } else if (isPaused) {
                                                    DownloadStore.I.resumeDownload(activeTask.id);
                                                  } else {
                                                    DownloadStore.I.pauseDownload(activeTask.id);
                                                  }
                                                },
                                                borderRadius: BorderRadius.circular(20),
                                                child: _buildActionButton(
                                                  isDone
                                                      ? Icons.download_done_rounded
                                                      : (isPaused
                                                          ? Icons.play_arrow_rounded
                                                          : Icons.pause_circle_filled_rounded),
                                                  isDone
                                                      ? "Downloaded (100%)"
                                                      : (isPaused
                                                          ? "Resume (${activeTask.percent}%)"
                                                          : "Pause (${activeTask.percent}%)"),
                                                  activeColor: isDone
                                                      ? Colors.greenAccent
                                                      : (isPaused ? Colors.amber : Colors.redAccent),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    if (!_effectiveOfflineMode)
                                      _buildFocusableItem(
                                        onTap: _showSearchSheet,
                                        borderRadius: BorderRadius.circular(20),
                                        child: _buildActionButton(Icons.search, "Search"),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),

                              if (!_effectiveOfflineMode) _buildYouTubeSponsorCompanionCard(),

                              if (widget.customUrl == null) ...[
                                _buildDescriptionCard(),
                                const SizedBox(height: 16),
                              ],

                              if (widget.customUrl == null && !_effectiveOfflineMode) ...[
                                const Text(
                                  "Sponsored Ads",
                                  style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 10),
                                const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                                const SizedBox(height: 20),
                              ],

                              if (widget.customUrl != null && !_effectiveOfflineMode) ...[
                                const SizedBox(height: 10),
                                const Text(
                                  "Sponsored Ads",
                                  style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 10),
                                const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                                const SizedBox(height: 16),
                                const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                                const SizedBox(height: 16),
                                const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                                const SizedBox(height: 20),
                              ],

                              if (widget.customUrl == null && !_effectiveOfflineMode) ...[
                                const Text(
                                  "If current server is not working, try a different one:",
                                  style: TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF151515),
                                    border: Border.all(color: Colors.white12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: const [
                                          Icon(Icons.verified_user, color: Colors.green, size: 20),
                                          SizedBox(width: 8),
                                          Text(
                                            "All Servers",
                                            style: TextStyle(
                                                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: servers.map((srv) {
                                            final isSelected = activeServer == srv['key'];
                                            return _buildFocusableItem(
                                              onTap: () {
                                                if (activeServer != srv['key']) {
                                                  setState(() => activeServer = srv['key']!);
                                                  _loadOnlineMovieStreamIntoWebView();
                                                }
                                              },
                                              borderRadius: BorderRadius.circular(20),
                                              child: Container(
                                                margin: const EdgeInsets.only(right: 8),
                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: isSelected ? Colors.white : Colors.grey[900],
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  srv['name']!,
                                                  style: TextStyle(
                                                    color: isSelected ? Colors.black : Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _buildCastSection(),
                                const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                                const SizedBox(height: 20),
                              ],

                              if (isTvShow && widget.customUrl == null && !_effectiveOfflineMode) ...[
                                Row(
                                  children: [
                                    InkWell(
                                      onTap: _showSeasonPicker,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: Colors.black,
                                          border: Border.all(color: Colors.white30),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          children: [
                                            Text(
                                              "Season ${currentSeason.toString().padLeft(2, '0')}",
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 18),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    InkWell(
                                      onTap: _showAudioServerPingMenu,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: Colors.black,
                                          border: Border.all(color: Colors.white30),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          children: const [
                                            Text(
                                              "Original Audio",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            SizedBox(width: 6),
                                            Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 18),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  "Episodes",
                                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 140,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: episodesList.isNotEmpty ? episodesList.length : 15,
                                    itemBuilder: (context, index) {
                                      final epNum = index + 1;
                                      final isCurrent = currentEpisode == epNum;
                                      String epName = "Episode $epNum";
                                      String imgUrl = '';
                                      if (episodesList.isNotEmpty && index < episodesList.length) {
                                        epName = episodesList[index]['name'] ?? "Episode $epNum";
                                        if (episodesList[index]['still_path'] != null) {
                                          imgUrl = proxyImg(
                                              'https://image.tmdb.org/t/p/w500${episodesList[index]['still_path']}');
                                        }
                                      }
                                      return _buildFocusableItem(
                                        onTap: () => _switchEpisode(epNum),
                                        borderRadius: BorderRadius.circular(10),
                                        child: Container(
                                          width: 160,
                                          margin: const EdgeInsets.only(right: 12),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(10),
                                            border: isCurrent
                                                ? Border.all(color: Colors.redAccent, width: 2)
                                                : Border.all(color: Colors.white12),
                                            color: const Color(0xFF1A1A1A),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        const BorderRadius.vertical(top: Radius.circular(8)),
                                                    color: Colors.black54,
                                                    image: imgUrl.isNotEmpty
                                                        ? DecorationImage(
                                                            image: CachedNetworkImageProvider(imgUrl),
                                                            fit: BoxFit.cover,
                                                          )
                                                        : null,
                                                  ),
                                                  child: Center(
                                                    child: Icon(
                                                      isCurrent ? Icons.play_circle_fill : Icons.play_circle_outline,
                                                      color: isCurrent ? Colors.red : Colors.white70,
                                                      size: 40,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.all(10.0),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      epName,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const Text(
                                                      "Watch on HANNUTV",
                                                      style: TextStyle(color: Colors.grey, fontSize: 10),
                                                      maxLines: 1,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],

                              if (!_effectiveOfflineMode)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[900],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: const [
                                          Text(
                                            "Public Comments",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Icon(Icons.comment, color: Colors.grey, size: 16),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: commentInputController,
                                              style: const TextStyle(color: Colors.white, fontSize: 12),
                                              decoration: InputDecoration(
                                                hintText: 'Add a public comment...',
                                                hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                                                filled: true,
                                                fillColor: Colors.black45,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(20),
                                                  borderSide: BorderSide.none,
                                                ),
                                              ),
                                            ),
                                          ),
                                          _buildFocusableItem(
                                            onTap: _addComment,
                                            borderRadius: BorderRadius.circular(20),
                                            child: const Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child: Icon(Icons.send, color: Colors.redAccent, size: 20),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      StreamBuilder<QuerySnapshot>(
                                        stream: FirebaseFirestore.instance
                                            .collection('movies')
                                            .doc(widget.customUrl == null
                                                ? widget.tmdbId.toString()
                                                : 'live_${widget.movieTitle.replaceAll(" ", "_")}')
                                            .collection('comments')
                                            .orderBy('timestamp', descending: true)
                                            .snapshots(),
                                        builder: (context, snapshot) {
                                          if (!snapshot.hasData) {
                                            return const Center(
                                              child: CircularProgressIndicator(color: Colors.redAccent),
                                            );
                                          }
                                          final comments = snapshot.data!.docs;

                                          if (comments.isEmpty) {
                                            return const Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child: Text(
                                                "Be the first to comment!",
                                                style: TextStyle(color: Colors.grey, fontSize: 12),
                                              ),
                                            );
                                          }

                                          return Column(
                                            children: comments.map((doc) {
                                              var data = doc.data() as Map<String, dynamic>;
                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: 8.0),
                                                child: Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    CircleAvatar(
                                                      radius: 14,
                                                      backgroundColor: Colors.redAccent,
                                                      child: Text(
                                                        data['avatar'] ?? 'U',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              Text(
                                                                data['name'] ?? 'User',
                                                                style: const TextStyle(
                                                                  color: Colors.white70,
                                                                  fontSize: 12,
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                              const SizedBox(width: 6),
                                                              const Text(
                                                                "Just now",
                                                                style: TextStyle(color: Colors.grey, fontSize: 10),
                                                              ),
                                                            ],
                                                          ),
                                                          Text(
                                                            data['text'] ?? '',
                                                            style:
                                                                const TextStyle(color: Colors.white, fontSize: 12),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 20),

                              if (widget.customUrl == null &&
                                  !_effectiveOfflineMode &&
                                  similarMovies.isNotEmpty) ...[
                                const Text(
                                  "Suggested Movies & Shows",
                                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 160,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: similarMovies.length,
                                    itemBuilder: (context, index) {
                                      final m = similarMovies[index];
                                      return _buildFocusableItem(
                                        onTap: () {
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => VideoPlayerPage(
                                                tmdbId: m['id'],
                                                mediaType: m['mediaType'],
                                                movieTitle: m['title'],
                                                rating: m['rating'],
                                                year: m['year'],
                                              ),
                                            ),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          width: 110,
                                          margin: const EdgeInsets.only(right: 10),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(8),
                                                    image: DecorationImage(
                                                      image: CachedNetworkImageProvider(m['posterUrl'] != ''
                                                          ? m['posterUrl']
                                                          : 'https://via.placeholder.com/300x450/222222/888888'),
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                m['title'],
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                              if (widget.customUrl == null && !_effectiveOfflineMode) ..._buildMoreSuggestions(),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const LiveDownloadNotificationBanner(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String title, {Color activeColor = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: activeColor, size: 16),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(color: activeColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _TvFocusButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;
  const _TvFocusButton({required this.child, required this.onTap, required this.borderRadius});
  @override
  State<_TvFocusButton> createState() => _TvFocusButtonState();
}

class _TvFocusButtonState extends State<_TvFocusButton> {
  bool _hasFocus = false;
  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) {
        if (mounted) setState(() => _hasFocus = hasFocus);
      },
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: widget.borderRadius,
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                border: Border.all(
                    color: _hasFocus ? Colors.redAccent : Colors.transparent, width: _hasFocus ? 3.5 : 0),
                boxShadow: _hasFocus ? [BoxShadow(color: Colors.redAccent.withOpacity(0.65), blurRadius: 10)] : []),
            child: widget.child),
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  final ValueNotifier<List<Color>> zones;
  final Widget child;
  const _AmbientGlow({required this.zones, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Color>>(
      valueListenable: zones,
      child: child,
      builder: (context, z, ch) {
        return TweenAnimationBuilder<List<Color>>(
          tween: _ZonesTween(end: z),
          duration: const Duration(milliseconds: 2500),
          curve: Curves.easeInOut,
          child: ch,
          builder: (context, colors, c) {
            return CustomPaint(painter: _GlowPainter(colors), child: c);
          },
        );
      },
    );
  }
}

class _ZonesTween extends Tween<List<Color>> {
  _ZonesTween({List<Color>? begin, required List<Color> end}) : super(begin: begin, end: end);

  @override
  List<Color> lerp(double t) {
    final List<Color> a = begin ?? end!;
    final List<Color> b = end!;
    return List<Color>.generate(
        b.length, (int i) => Color.lerp(i < a.length ? a[i] : b[i], b[i], t) ?? b[i]);
  }
}

class _GlowPainter extends CustomPainter {
  final List<Color> zones;
  _GlowPainter(this.zones);

  @override
  void paint(Canvas canvas, Size size) {
    if (zones.length < 8 || size.isEmpty) return;
    final double w = size.width;
    final double h = size.height;
    final List<Offset> pts = <Offset>[
      const Offset(0, 0),
      Offset(w / 2, 0),
      Offset(w, 0),
      Offset(w, h / 2),
      Offset(w, h),
      Offset(w / 2, h),
      Offset(0, h),
      Offset(0, h / 2),
    ];
    final double radius = h * 0.40;
    for (int i = 0; i < 8; i++) {
      final Paint p = Paint()
        ..color = zones[i].withAlpha(150)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34);
      canvas.drawCircle(pts[i], radius, p);
    }
  }

  @override
  bool shouldRepaint(covariant _GlowPainter old) => old.zones != zones;
}

class _AmbientBackground extends StatelessWidget {
  final ValueNotifier<Color> color;
  final Widget child;
  const _AmbientBackground({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: color,
      child: child,
      builder: (context, c, ch) {
        return AnimatedContainer(
          width: double.infinity,
          height: double.infinity,
          duration: const Duration(milliseconds: 2500),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c.withOpacity(0.32), const Color(0xFF0F0F0F)],
              stops: const [0.0, 0.6],
            ),
          ),
          child: ch,
        );
      },
    );
  }
}

class _ExternalWebPage extends StatefulWidget {
  final String title;
  final String url;
  const _ExternalWebPage({required this.title, required this.url});

  @override
  State<_ExternalWebPage> createState() => _ExternalWebPageState();
}

class _ExternalWebPageState extends State<_ExternalWebPage> {
  late final WebViewController _wc;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _wc),
          if (_loading)
            const Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(color: Colors.redAccent, backgroundColor: Colors.transparent)),
        ],
      ),
    );
  }
}

class _SearchSheet extends StatefulWidget {
  final void Function(Map<String, dynamic> item) onOpenTitle;
  final void Function(int id, String name) onOpenPerson;
  const _SearchSheet({required this.onOpenTitle, required this.onOpenPerson});

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  String _lastQuery = '';
  List<Map<String, dynamic>> _results = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final String q = v.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
        _lastQuery = '';
      });
      return;
    }
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search(q);
    });
  }

  Future<void> _search(String q) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _lastQuery = q;
    });
    try {
      final res = await tmdbHttpGet(
        'https://api.themoviedb.org/3/search/multi?query=${Uri.encodeQueryComponent(q)}&include_adult=false&language=en-US&page=1',
        headers: kApiHeaders,
      );
      if (!mounted || q != _lastQuery) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List raw = (data is Map && data['results'] is List) ? data['results'] : [];
        final List<Map<String, dynamic>> out = [];
        for (final r in raw) {
          if (r is! Map) continue;
          final String mt = r['media_type'].toString();
          if (mt != 'movie' && mt != 'tv' && mt != 'person') continue;
          final dynamic id = r['id'];
          if (id is! int) continue;
          final String date = (r['release_date'] ?? r['first_air_date'] ?? '').toString();
          final dynamic imgRaw = mt == 'person' ? r['profile_path'] : r['poster_path'];
          final String img = imgRaw is String ? imgRaw : '';
          out.add({
            'id': id,
            'mediaType': mt,
            'title': (r['title'] ?? r['name'] ?? 'Unknown').toString(),
            'year': date.isNotEmpty ? date.split('-').first : '',
            'rating': ((r['vote_average'] ?? 0) as num).toStringAsFixed(1),
            'image': img,
            'overview': (r['overview'] ?? '').toString(),
            'dept': (r['known_for_department'] ?? '').toString(),
          });
        }
        setState(() {
          _results = out;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildTile(Map<String, dynamic> m) {
    final String mt = m['mediaType'] as String;
    final String img = m['image'] as String;
    final bool isPerson = mt == 'person';
    final String year = m['year'] as String;
    final String rating = m['rating'] as String;
    final String dept = m['dept'] as String;

    String subtitle;
    if (isPerson) {
      subtitle = dept.isEmpty ? 'Person' : dept;
    } else {
      final List<String> parts = [mt == 'tv' ? 'TV Show' : 'Movie'];
      if (year.isNotEmpty) parts.add(year);
      if (rating != '0.0') parts.add('★ $rating');
      subtitle = parts.join(' • ');
    }

    final Widget leading = isPerson
        ? CircleAvatar(
            radius: 26,
            backgroundColor: Colors.grey[900],
            backgroundImage:
                img.isNotEmpty ? CachedNetworkImageProvider(proxyImg('https://image.tmdb.org/t/p/w185$img')) : null,
            child: img.isEmpty ? const Icon(Icons.person, color: Colors.white38) : null,
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: img.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: proxyImg('https://image.tmdb.org/t/p/w185$img'),
                    width: 46,
                    height: 68,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        Container(width: 46, height: 68, color: Colors.grey[900], child: const Icon(Icons.movie, color: Colors.white24)))
                : Container(
                    width: 46,
                    height: 68,
                    color: Colors.grey[900],
                    child: const Icon(Icons.movie, color: Colors.white24)),
          );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: leading,
      title: Text(m['title'] as String,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      trailing: Icon(isPerson ? Icons.person_outline : Icons.play_circle_outline, color: Colors.white38),
      onTap: () {
        if (isPerson) {
          widget.onOpenPerson(m['id'] as int, m['title'] as String);
        } else {
          widget.onOpenTitle(m);
        }
      },
    );
  }

  Widget _buildResults() {
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
    }
    if (_lastQuery.isEmpty) {
      return const Center(
          child: Text("Type to search movies, shows or actors", style: TextStyle(color: Colors.grey, fontSize: 13)));
    }
    if (_results.isEmpty) {
      return Center(
          child: Text("No results for \"$_lastQuery\"", style: const TextStyle(color: Colors.grey, fontSize: 13)));
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _results.length,
      itemBuilder: (context, index) => _buildTile(_results[index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) {
                  _debounce?.cancel();
                  final String q = v.trim();
                  if (q.isNotEmpty) _search(q);
                },
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search movies, shows, actors...',
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: _ctrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                          onPressed: () {
                            _ctrl.clear();
                            _onChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
              ),
            ),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }
}

class _ActorSheet extends StatefulWidget {
  final int personId;
  final String fallbackName;
  final void Function(Map<String, dynamic> item) onOpenTitle;
  const _ActorSheet({required this.personId, required this.fallbackName, required this.onOpenTitle});

  @override
  State<_ActorSheet> createState() => _ActorSheetState();
}

class _ActorSheetState extends State<_ActorSheet> {
  bool _loading = true;
  bool _failed = false;
  Map<String, dynamic>? _person;
  List<Map<String, dynamic>> _credits = [];
  String _filter = 'all';
  bool _bioExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await tmdbHttpGet(
        'https://api.themoviedb.org/3/person/${widget.personId}?language=en-US&append_to_response=combined_credits,external_ids',
        headers: kApiHeaders,
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data is Map<String, dynamic>) {
          final List raw = (data['combined_credits'] is Map && data['combined_credits']['cast'] is List)
              ? data['combined_credits']['cast']
              : [];
          final Map<String, Map<String, dynamic>> uniq = {};
          for (final c in raw) {
            if (c is! Map) continue;
            final String mt = c['media_type'].toString();
            if (mt != 'movie' && mt != 'tv') continue;
            final dynamic id = c['id'];
            if (id is! int) continue;
            final String key = '$mt-$id';
            if (uniq.containsKey(key)) continue;
            final String dateStr = (c['release_date'] ?? c['first_air_date'] ?? '').toString();
            uniq[key] = {
              'id': id,
              'mediaType': mt,
              'title': (c['title'] ?? c['name'] ?? 'Unknown').toString(),
              'year': dateStr.isNotEmpty ? dateStr.split('-').first : '',
              'rating': ((c['vote_average'] ?? 0) as num).toStringAsFixed(1),
              'poster': (c['poster_path'] ?? '').toString(),
              'overview': (c['overview'] ?? '').toString(),
              'popularity': ((c['popularity'] ?? 0) as num).toDouble(),
            };
          }
          final List<Map<String, dynamic>> list = uniq.values.toList();
          list.sort((a, b) {
            final int ap = (a['poster'] as String).isNotEmpty ? 1 : 0;
            final int bp = (b['poster'] as String).isNotEmpty ? 1 : 0;
            if (ap != bp) return bp - ap;
            return (b['popularity'] as double).compareTo(a['popularity'] as double);
          });
          setState(() {
            _person = data;
            _credits = list;
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'movie') return _credits.where((e) => e['mediaType'] == 'movie').toList();
    if (_filter == 'tv') return _credits.where((e) => e['mediaType'] == 'tv').toList();
    return _credits;
  }

  void _openExternal(String title, String url) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ExternalWebPage(title: title, url: url)));
  }

  Widget _linkChip(String label, IconData icon, String url) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _openExternal(label, url),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white24)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.amber, size: 15),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final bool selected = _filter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _filter = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.grey[900], borderRadius: BorderRadius.circular(18)),
          child: Text(label,
              style: TextStyle(
                  color: selected ? Colors.black : Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _posterFallback() {
    return Container(
        color: Colors.grey[900], child: const Center(child: Icon(Icons.movie, color: Colors.white24, size: 28)));
  }

  Widget _buildTitleTile(Map<String, dynamic> m) {
    final String poster = m['poster'] as String;
    final bool isTv = m['mediaType'] == 'tv';
    final String year = m['year'] as String;
    final String rating = m['rating'] as String;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => widget.onOpenTitle(m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: poster.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: proxyImg('https://image.tmdb.org/t/p/w342$poster'),
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _posterFallback())
                        : _posterFallback(),
                  ),
                ),
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                    child: Text(isTv ? 'TV' : 'MOVIE',
                        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                  ),
                ),
                if (rating != '0.0')
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 9),
                          const SizedBox(width: 2),
                          Text(rating,
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(m['title'] as String,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          Text(year.isEmpty ? ' ' : year, maxLines: 1, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _avatarFallback() {
    return Container(
        width: 90,
        height: 130,
        color: Colors.grey[900],
        child: const Icon(Icons.person, color: Colors.white24, size: 40));
  }

  Widget _buildContent(ScrollController sc) {
    final Map<String, dynamic> p = _person!;
    final String name = (p['name'] ?? widget.fallbackName).toString();
    final String profile = (p['profile_path'] ?? '').toString();
    final String dept = (p['known_for_department'] ?? '').toString();
    final String birthday = (p['birthday'] ?? '').toString();
    final String deathday = (p['deathday'] ?? '').toString();
    final String place = (p['place_of_birth'] ?? '').toString();
    final String bio = (p['biography'] ?? '').toString().trim();
    final dynamic ext = p['external_ids'];
    final String imdbId = (ext is Map ? (ext['imdb_id'] ?? '') : '').toString();
    final List<Map<String, dynamic>> items = _filtered;

    return CustomScrollView(
      controller: sc,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: profile.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: proxyImg('https://image.tmdb.org/t/p/w342$profile'),
                              width: 90,
                              height: 130,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _avatarFallback())
                          : _avatarFallback(),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                          if (dept.isNotEmpty)
                            Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(dept,
                                    style: const TextStyle(
                                        color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold))),
                          if (birthday.isNotEmpty)
                            Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                    deathday.isNotEmpty
                                        ? 'Born: $birthday  •  Died: $deathday'
                                        : 'Born: $birthday',
                                    style: const TextStyle(color: Colors.grey, fontSize: 12))),
                          if (place.isNotEmpty)
                            Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(place,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.grey, fontSize: 12))),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _linkChip(
                                  'TMDB', Icons.movie_filter, 'https://www.themoviedb.org/person/${widget.personId}'),
                              if (imdbId.isNotEmpty)
                                _linkChip('IMDb', Icons.star_rate_rounded, 'https://www.imdb.com/name/$imdbId/'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => setState(() => _bioExpanded = !_bioExpanded),
                    child: Text(
                      bio,
                      maxLines: _bioExpanded ? null : 4,
                      overflow: _bioExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.45),
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => setState(() => _bioExpanded = !_bioExpanded),
                    child: Text(_bioExpanded ? 'Show less' : '...more',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
                const SizedBox(height: 18),
                Text('Filmography (${items.length})',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(children: [
                  _filterChip('all', 'All'),
                  _filterChip('movie', 'Movies'),
                  _filterChip('tv', 'TV Shows')
                ]),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        if (items.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text("No titles found", style: TextStyle(color: Colors.grey, fontSize: 13))),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
              childAspectRatio: 0.52,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _buildTitleTile(items[i]),
              childCount: items.length,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      expand: false,
      builder: (context, scrollController) {
        Widget body;
        if (_loading) {
          body = ListView(
            controller: scrollController,
            children: const [
              SizedBox(height: 160),
              Center(child: CircularProgressIndicator(color: Colors.redAccent)),
            ],
          );
        } else if (_failed || _person == null) {
          body = ListView(
            controller: scrollController,
            children: const [
              SizedBox(height: 160),
              Center(child: Text("Could not load actor details.", style: TextStyle(color: Colors.grey, fontSize: 13))),
            ],
          );
        } else {
          body = _buildContent(scrollController);
        }
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF111111),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: body,
        );
      },
    );
  }
}

// 2-Finger Pinch Zoom + 1-Finger YouTube-Style Swipe Up/Down to Rotate (UNTOUCHED!)
class _PinchZoom extends StatefulWidget {
  final ValueNotifier<double> zoom;
  final Widget child;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;
  const _PinchZoom({
    required this.zoom,
    required this.child,
    this.onSwipeUp,
    this.onSwipeDown,
  });

  @override
  State<_PinchZoom> createState() => _PinchZoomState();
}

class _PinchZoomState extends State<_PinchZoom> {
  final Map<int, Offset> _pointers = <int, Offset>{};
  double _startDist = 0;
  double _startZoom = 1.0;
  Offset? _singleSwipeStart;
  bool _multiTouchSession = false;

  double _dist() {
    final List<Offset> v = _pointers.values.toList();
    return (v[0] - v[1]).distance;
  }

  void _down(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 1) {
      _singleSwipeStart = e.position;
      _multiTouchSession = false;
    } else if (_pointers.length >= 2) {
      _multiTouchSession = true;
      _singleSwipeStart = null;
      _startDist = _dist();
      _startZoom = widget.zoom.value;
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2 && _startDist > 0) {
      widget.zoom.value = (_startZoom * _dist() / _startDist).clamp(1.0, 2.2).toDouble();
    }
  }

  void _up(PointerEvent e) {
    if (!_multiTouchSession && _pointers.length == 1 && _singleSwipeStart != null) {
      final double dy = e.position.dy - _singleSwipeStart!.dy;
      final double dx = (e.position.dx - _singleSwipeStart!.dx).abs();
      if (dy < -40 && dx < 95) {
        widget.onSwipeUp?.call();
      } else if (dy > 45 && dx < 95) {
        widget.onSwipeDown?.call();
      }
    }
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) {
      _startDist = 0;
      if (widget.zoom.value < 1.06) widget.zoom.value = 1.0;
    }
    if (_pointers.isEmpty) {
      _singleSwipeStart = null;
      _multiTouchSession = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: ClipRect(
        child: ValueListenableBuilder<double>(
          valueListenable: widget.zoom,
          child: widget.child,
          builder: (context, z, ch) => Transform.scale(scale: z, child: ch),
        ),
      ),
    );
  }
}

class _SuggestRow extends StatefulWidget {
  final String title;
  final int excludeId;
  final Future<List<TmdbItem>> Function() loader;
  final void Function(TmdbItem item) onOpen;
  final Widget Function({required Widget child, required VoidCallback onTap, BorderRadius? borderRadius}) focusable;
  const _SuggestRow({
    super.key,
    required this.title,
    required this.excludeId,
    required this.loader,
    required this.onOpen,
    required this.focusable,
  });

  @override
  State<_SuggestRow> createState() => _SuggestRowState();
}

class _SuggestRowState extends State<_SuggestRow> {
  List<TmdbItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<TmdbItem> r = <TmdbItem>[];
    try {
      r = await widget.loader();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _items = r.where((TmdbItem e) => e.id != widget.excludeId).toList());
  }

  @override
  Widget build(BuildContext context) {
    final List<TmdbItem>? items = _items;
    if (items != null && items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          SizedBox(
            height: 175,
            child: items == null
                ? ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: 5,
                    itemBuilder: (context, index) => Container(
                      width: 110,
                      margin: const EdgeInsets.only(right: 10, bottom: 20),
                      decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(8)),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final TmdbItem it = items[index];
                      return widget.focusable(
                        onTap: () => widget.onOpen(it),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 110,
                          margin: const EdgeInsets.only(right: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    imageUrl: it.posterUrl('w342'),
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    placeholder: (BuildContext _, String __) => Container(color: Colors.grey[900]),
                                    errorWidget: (BuildContext _, String __, Object ___) => Container(
                                        color: Colors.grey[900],
                                        child: const Icon(Icons.movie, color: Colors.white24)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(it.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}