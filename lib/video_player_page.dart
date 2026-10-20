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
    atOptions = {
      'key' : 'a39df283f6ad10c34e229e5715bceff5',
      'format' : 'iframe',
      'height' : 50,
      'width' : 320,
      'params' : {}
    };
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
  final GlobalKey _webViewSurfaceKey = GlobalKey();

  bool isVideoPlaying = false;
  bool isFullScreen = false;
  bool isPageLoading = true;
  String activeServer = 'vidrift';
  String currentAspectRatio = 'contain';
  String _sniffedStreamUrl = '';

  late int currentSeason;
  late int currentEpisode;
  int viewCount = 84920;

  bool showControls = true;
  Timer? _hideControlsTimer;

  bool _isShowingInPlayerAd = true;
  bool _isAdLoadingWait = true;
  int _adLoadWaitSeconds = 10;
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
  static const String kUnityBannerId = 'BP_Banner_Android';

  static const List<String> _adProbeDomains = [
    'unityads.unity3d.com',
    'config.unityads.unity3d.com',
    'webview.unityads.unity3d.com',
  ];

  final List<Map<String, String>> _sponsors = const [
    {
      'title': 'Google Play Store • Top Trending Apps & Games',
      'domain': 'play.google.com',
      'cta': 'Install Now',
      'url': 'https://play.google.com/store/apps',
    },
    {
      'title': 'HANNUTV Official Partner • High Speed Streaming',
      'domain': 'hannutv.blogspot.com',
      'cta': 'Visit Site',
      'url': 'https://hannutv.blogspot.com',
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
  final ValueNotifier<Color> _ambientColor =
      ValueNotifier<Color>(const Color(0xFF5B2A86));
  List<Color> _ambientPalette = const [
    Color(0xFF5B2A86),
    Color(0xFF1E5AA8),
    Color(0xFFB02A4A)
  ];
  int _ambientIndex = 0;
  Timer? _ambientTimer;
  final ValueNotifier<List<Color>> _ambientZones = ValueNotifier<List<Color>>(
      List<Color>.filled(8, const Color(0xFF5B2A86)));
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

    _introAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _introScaleAnimation = Tween<double>(begin: 0.7, end: 1.3).animate(
      CurvedAnimation(
          parent: _introAnimController, curve: Curves.easeOutBack),
    );
    _introOpacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _introAnimController,
        curve: const Interval(0.65, 1.0, curve: Curves.easeIn),
      ),
    );

    if (widget.isOfflineDownload) {
      _isShowingInPlayerAd = false;
      _isAdLoadingWait = false;
    } else {
      if (widget.customUrl == null) {
        _fetchSimilarMovies();
        _fetchTvDetails();
        _fetchDetails();
      }
      _runDnsCheck();
      _dnsWatchdogTimer =
          Timer.periodic(const Duration(seconds: 2), (_) => _runDnsCheck());
      _triggerYouTubeStyleAd();
      _thirtyMinAdCycleTimer =
          Timer.periodic(const Duration(minutes: 30), (_) {
        if (mounted && !widget.isOfflineDownload) {
          _triggerYouTubeStyleAd();
        }
      });
    }

    _checkDeviceType();
    WatchlistStore.I.load();
    DownloadStore.I.load();
    _startAmbientCycle();
    _initUnityAdsEngine();
  }

  void _initUnityAdsEngine() {
    try {
      UnityAds.init(
        gameId: kUnityGameId,
        testMode: false,
        onComplete: () {
          debugPrint('Unity Ads Engine Initialized: $kUnityGameId');
        },
        onFailed: (error, message) {
          debugPrint('Unity Ads Init Failed: $error $message');
        },
      );
    } catch (_) {}
  }

  Future<bool> _isDnsBlocked() async {
    if (widget.isOfflineDownload) return false;
    for (final host in _adProbeDomains) {
      try {
        final result = await InternetAddress.lookup(host)
            .timeout(const Duration(milliseconds: 900));
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
          final g = await InternetAddress.lookup('google.com')
              .timeout(const Duration(milliseconds: 900));
          if (g.isNotEmpty) return true;
        } catch (_) {
          return false;
        }
        return false;
      }
    }
    return false;
  }

  Future<void> _runDnsCheck() async {
    if (widget.isOfflineDownload || _checkingDns || !mounted) return;
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
        setState(() => _isAdblockDetected = false);
        _triggerYouTubeStyleAd();
      }
    } catch (_) {
    } finally {
      _checkingDns = false;
    }
  }

  void _triggerYouTubeStyleAd() {
    if (!mounted || widget.isOfflineDownload) return;
    _adLoadWaitTimer?.cancel();
    _inPlayerAdTimer?.cancel();

    setState(() {
      _isShowingInPlayerAd = true;
      _isAdLoadingWait = true;
      _adLoadWaitSeconds = 10;
      _adSkipTimeLeft = 15;
      _adElapsedSeconds = 0;
      _canSkipInPlayerAd = false;
    });

    _backgroundMuteGuardTimer?.cancel();
    _backgroundMuteGuardTimer =
        Timer.periodic(const Duration(milliseconds: 250), (_) {
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

  void _startAdPlaybackAnd15SecSkipTimer() {
    if (!mounted) return;
    _adLoadWaitTimer?.cancel();
    if (!_isAdLoadingWait &&
        _inPlayerAdTimer != null &&
        _inPlayerAdTimer!.isActive) {
      return;
    }
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
    setState(() {
      _isShowingInPlayerAd = false;
      _isAdLoadingWait = false;
    });
    _unmuteAndResumeMovieInstantly();
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
            if (v.currentTime >= 0.2 && !v.paused) {
              v.pause();
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

  Future<void> _openSponsorWebsite() async {
    final String url = _sponsors[_activeSponsorIdx]['url'] ??
        'https://play.google.com/store/apps';
    final Uri? u = Uri.tryParse(url);
    if (u == null) return;
    try {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _buildYouTubeInPlayerAdOverlay() {
    if (widget.isOfflineDownload) return const SizedBox.shrink();
    if (!_isShowingInPlayerAd && !_isAdblockDetected) {
      return const SizedBox.shrink();
    }

    final sponsor = _sponsors[_activeSponsorIdx];

    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            if (!_isAdblockDetected)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isAdLoadingWait) ...[
                        const SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(
                            color: Colors.amber,
                            strokeWidth: 3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Loading High-Speed Ad (${_adLoadWaitSeconds}s)...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Pre-buffering movie 0.2s for zero-lag playback...',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ] else ...[
                        SizedBox(
                          height: 55,
                          width: 320,
                          child: UnityBannerAd(
                            placementId: kUnityBannerId,
                            onLoad: (id) =>
                                debugPrint('In-Player Ad Banner loaded: $id'),
                            onClick: (id) => _openSponsorWebsite(),
                            onFailed: (id, err, msg) => debugPrint(
                                'In-Player Ad Banner failed: $err $msg'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: _openSponsorWebsite,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1F1C2C), Color(0xFF2B2740)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.amber.withOpacity(0.65)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.public,
                                    color: Colors.amber,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        sponsor['title']!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        'Sponsored • ${sponsor['domain']}',
                                        style: const TextStyle(
                                          color: Colors.amber,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.amber,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        sponsor['cta']!,
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 11,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.open_in_new_rounded,
                                        color: Colors.black,
                                        size: 13,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
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
                    children: [
                      const Icon(
                        Icons.gpp_bad_rounded,
                        color: Colors.redAccent,
                        size: 46,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'AdBlocker / Private DNS Detected!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Kindly turn off Private DNS / AdGuard to continue watching.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            Positioned(
              top: 10,
              left: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(4),
                  border:
                      Border.all(color: Colors.amber.withOpacity(0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const Text(
                        'Ad',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isAdLoadingWait
                          ? 'Loading Ad (${_adLoadWaitSeconds}s)'
                          : 'Sponsored • ${_adElapsedSeconds}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (!_isAdLoadingWait && !_isAdblockDetected)
              Positioned(
                bottom: 16,
                left: 12,
                child: GestureDetector(
                  onTap: _openSponsorWebsite,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.82),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.launch_rounded,
                          color: Colors.amber,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          sponsor['domain']!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            Positioned(
              top: 10,
              right: 14,
              child: GestureDetector(
                onTap: _toggleFullScreen,
                child: Opacity(
                  opacity: 0.88,
                  child: Image.asset(
                    'assets/logo.png',
                    height: 30,
                    errorBuilder: (_, __, ___) => const Text(
                      'HANNUTV',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            Positioned(
              bottom: 16,
              right: 12,
              child: GestureDetector(
                onTap: _canSkipInPlayerAd &&
                        !_isAdblockDetected &&
                        !_isAdLoadingWait
                    ? _finishInPlayerAd
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: _canSkipInPlayerAd &&
                            !_isAdblockDetected &&
                            !_isAdLoadingWait
                        ? Colors.white
                        : Colors.black.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _canSkipInPlayerAd &&
                              !_isAdblockDetected &&
                              !_isAdLoadingWait
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
                          child: CircularProgressIndicator(
                            color: Colors.redAccent,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        _isAdblockDetected
                            ? 'Loading...'
                            : _isAdLoadingWait
                                ? 'Loading Ad...'
                                : _canSkipInPlayerAd
                                    ? 'Skip Ad'
                                    : 'Skip in $_adSkipTimeLeft',
                        style: TextStyle(
                          color: _canSkipInPlayerAd &&
                                  !_isAdblockDetected &&
                                  !_isAdLoadingWait
                              ? Colors.black
                              : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      if (_canSkipInPlayerAd &&
                          !_isAdblockDetected &&
                          !_isAdLoadingWait) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.skip_next_rounded,
                          color: Colors.black,
                          size: 18,
                        ),
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
                value: _isAdLoadingWait
                    ? null
                    : ((15 - _adSkipTimeLeft) / 15).clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: Colors.white24,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.amber),
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
      onTap: _openSponsorWebsite,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Ad',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Tap to visit ${sponsor['domain']} in browser / Play Store',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sponsor['cta']!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.open_in_new_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
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
          _fetchEpisodes(currentSeason);
        }
      }
    } catch (_) {}
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
    } catch (_) {}
  }

  void _checkDeviceType() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = MediaQuery.of(context).size;
      setState(() {
        isTvDevice = size.width > size.height && size.width >= 600;
        if (isTvDevice) {
          isFullScreen = true;
        } else {
          SystemChrome.setPreferredOrientations(
              [DeviceOrientation.portraitUp]);
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
      if (mounted) {
        setState(() => showIntroAnimation = false);
      }
    });
  }

  Future<void> _fetchSimilarMovies() async {
    setState(() => isLoadingSimilar = true);
    try {
      final type = (widget.mediaType == 'tv' || widget.mediaType == 'series')
          ? 'tv'
          : 'movie';
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
                          ? proxyImg(
                              'https://image.tmdb.org/t/p/w500${m['poster_path']}')
                          : '',
                      'rating':
                          (m['vote_average'] ?? 0.0).toStringAsFixed(1),
                      'year': (m['release_date'] ??
                              m['first_air_date'] ??
                              '')
                          .toString()
                          .split('-')
                          .first,
                      'mediaType': type,
                    })
                .toList();
            isLoadingSimilar = false;
          });
        }
      } else if (mounted) {
        setState(() => isLoadingSimilar = false);
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
    });

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(isTvDevice
          ? 'Mozilla/5.0 (SMART-TV; Linux; Tizen 5.0) AppleWebKit/538.1 (KHTML, like Gecko) Version/5.0 TV Safari/538.1'
          : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
      ..setOnJavaScriptAlertDialog(
          (JavaScriptAlertDialogRequest request) async {})
      ..setOnJavaScriptConfirmDialog(
          (JavaScriptConfirmDialogRequest request) async => false)
      ..setOnJavaScriptTextInputDialog(
          (JavaScriptTextInputDialogRequest request) async => '')
      ..addJavaScriptChannel(
        'VideoState',
        onMessageReceived: (JavaScriptMessage message) {
          final String msg = message.message;
          if (msg == 'playing') {
            if (mounted) _triggerCinematicPlayAnimation();
            if (_isShowingInPlayerAd) {
              _enforceBackgroundPrebufferPause();
            }
          } else if (msg.startsWith('stream:')) {
            if (mounted) {
              final String url = msg.substring(7).trim();
              if (url.isNotEmpty) {
                _sniffedStreamUrl = url;
              }
            }
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) setState(() => isPageLoading = true);
            _controller.runJavaScript('''
              window.__hannuAdActive = ${_isShowingInPlayerAd ? 'true' : 'false'};
              window.open = function() { return null; };
              window.alert = function() { return null; };
              window.confirm = function() { return false; };
              window.prompt = function() { return null; };
            ''');
          },
          onPageFinished: (String url) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) setState(() => isPageLoading = false);
            });

            if (widget.isOfflineDownload) return;

            String jsCode = '''
              window.__hannuAdActive = ${_isShowingInPlayerAd ? 'true' : 'false'};
              document.body.style.backgroundColor = '#000000';
              document.documentElement.style.backgroundColor = '#000000';
              var style = document.createElement('style');
              style.innerHTML = `
                header, nav, footer, .navbar, .logo, .search, form, h1, h2, h3, p, span, .menu,
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

                  if (window.__hannuAdActive) {
                    v.muted = true;
                    v.volume = 0;
                    if (v.currentTime >= 0.2 && !v.paused) {
                      try { v.pause(); } catch(e){}
                    }
                  } else {
                    if (v.currentTime > 0.3 && !v.paused) {
                      VideoState.postMessage('playing');
                    }
                  }
                }
                if (!window.__hannuAdActive) {
                  var playBtns = document.querySelectorAll('.vjs-big-play-button, .jw-icon-display, .play-icon, #play-button');
                  if (playBtns.length > 0) {
                    playBtns[0].click();
                  }
                }
                var modals = document.querySelectorAll('[id*="robot"], [class*="robot"], [id*="captcha"], [class*="captcha"], .swal2-container');
                modals.forEach(function(m) { try { m.remove(); } catch(e){} });
              }, 250);
            ''';
            _controller.runJavaScript(jsCode);
          },
          onNavigationRequest: (NavigationRequest request) {
            if (widget.isOfflineDownload) {
              return NavigationDecision.navigate;
            }
            final url = request.url.toLowerCase();
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
                url.startsWith('intent:') ||
                url.startsWith('market:') ||
                url.startsWith('whatsapp:') ||
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

    final platformController = _controller.platform;
    if (platformController is AndroidWebViewController) {
      platformController.setMediaPlaybackRequiresUserGesture(false);
    }

    if (widget.isOfflineDownload) {
      _loadOfflineDownloadedVideo();
      return;
    }

    if (widget.customUrl != null && widget.customUrl!.isNotEmpty) {
      _sniffedStreamUrl = widget.customUrl!;
      if (widget.customUrl!.contains('.m3u8')) {
        String hlsHtml = '''
          <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
          <style>body, html { margin: 0; padding: 0; background: black; height: 100%; width: 100%; overflow: hidden; }
          video { width: 100%; height: 100%; object-fit: contain; }</style>
          </head><body><video id="video" autoplay controls></video>
          <script>
            var video = document.getElementById('video');
            if (Hls.isSupported()) {
              var hls = new Hls();
              hls.loadSource('${widget.customUrl}');
              hls.attachMedia(video);
              hls.on(Hls.Events.MANIFEST_PARSED, function() {
                video.play();
                VideoState.postMessage('playing');
              });
            } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
              video.src = '${widget.customUrl}';
              video.addEventListener('loadedmetadata', function() {
                video.play();
                VideoState.postMessage('playing');
              });
            }
          </script></body></html>
        ''';
        _controller.loadHtmlString(hlsHtml);
      } else {
        _controller.loadRequest(Uri.parse(widget.customUrl!));
      }
    } else {
      final id = widget.tmdbId;
      final isTv = widget.mediaType == 'tv' || widget.mediaType == 'series';
      String originalTargetUrl = isTv
          ? 'https://pantyflix.com/watch/play?tv_id=$id&season=$currentSeason&episode=$currentEpisode&server=$activeServer'
          : 'https://pantyflix.com/watch/play?movie_id=$id&server=$activeServer';
      String vercelProxyBase =
          'https://hannutv-proxy-1.vercel.app/api/proxy?stream=';
      String safeFinalUrl =
          '$vercelProxyBase${Uri.encodeComponent(originalTargetUrl)}';
      _sniffedStreamUrl = safeFinalUrl;
      _controller.loadRequest(Uri.parse(safeFinalUrl));
    }
  }

  Future<void> _loadOfflineDownloadedVideo() async {
    if (widget.offlineFilePath != null &&
        widget.offlineFilePath!.isNotEmpty) {
      try {
        final f = File(widget.offlineFilePath!);
        if (await f.exists() && await f.length() > 1024) {
          await _controller.loadFile(f.path);
          if (mounted) {
            setState(() {
              isPageLoading = false;
              isVideoPlaying = true;
            });
          }
          return;
        }
      } catch (_) {}
    }

    final String safeTitle = widget.movieTitle.replaceAll("'", "");
    final String safeLang =
        widget.offlineLanguage ?? 'Hindi Dubbed (DD 5.1)';
    final String safeQual = widget.offlineQuality ?? '720p HD';
    final String safeSrv = widget.offlineServerName ?? 'Rift';

    final String offlineHtml = '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
          * { box-sizing: border-box; user-select: none; }
          body, html {
            margin: 0; padding: 0; width: 100vw; height: 100vh;
            background: #000; overflow: hidden; font-family: sans-serif; color: #fff;
          }
          #player-wrap {
            position: relative; width: 100vw; height: 100vh; background: #05050A;
            display: flex; align-items: center; justify-content: center;
          }
          canvas { width: 100vw; height: 100vh; }
        </style>
      </head>
      <body>
        <div id="player-wrap">
          <canvas id="c"></canvas>
        </div>
        <script>
          VideoState.postMessage('playing');
          var c = document.getElementById('c');
          var ctx = c.getContext('2d');
          c.width = window.innerWidth;
          c.height = window.innerHeight;
          ctx.fillStyle = '#05050A';
          ctx.fillRect(0, 0, c.width, c.height);
          ctx.fillStyle = '#fff';
          ctx.font = 'bold 18px sans-serif';
          ctx.textAlign = 'center';
          ctx.fillText('$safeTitle', c.width / 2, c.height / 2 - 10);
          ctx.fillStyle = '#00E676';
          ctx.font = 'bold 12px sans-serif';
          ctx.fillText('Offline Ready ($safeLang • $safeQual • Server: $safeSrv)', c.width / 2, c.height / 2 + 18);
        </script>
      </body>
      </html>
    ''';

    await _controller.loadHtmlString(offlineHtml);
    if (mounted) {
      setState(() {
        isPageLoading = false;
        isVideoPlaying = true;
      });
    }
  }

  int _resolveActualRuntimeMinutes() {
    final Map<String, dynamic>? d = details;
    if (d != null) {
      if (_tmdbType == 'movie') {
        final dynamic rt = d['runtime'];
        if (rt is int && rt >= 15) return rt;
      } else {
        if (episodesList.isNotEmpty &&
            currentEpisode - 1 < episodesList.length) {
          final dynamic epRt = episodesList[currentEpisode - 1]['runtime'];
          if (epRt is int && epRt >= 10) return epRt;
        }
        final dynamic runtimes = d['episode_run_time'];
        if (runtimes is List &&
            runtimes.isNotEmpty &&
            runtimes.first is int) {
          return runtimes.first as int;
        }
        return 45;
      }
    }
    return _tmdbType == 'tv' ? 45 : 115;
  }

  String _activeServerDisplayName() {
    for (final s in servers) {
      if (s['key'] == activeServer) {
        return s['name'] ?? activeServer;
      }
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

    final List<String> dubbedLanguages = [
      'Hindi Dubbed (DD 5.1)',
      'Dual Audio [Hindi + English]',
      'English (Original)',
      'Tamil Dubbed',
      'Telugu Dubbed',
      'Multi-Audio [Hin • Eng • Tam • Tel]',
    ];

    final List<Map<String, dynamic>> qualityProfiles = [
      {
        'label': '360p Data Saver',
        'tag': 'Fastest • Mobile Saver',
        'kbps': 440,
        'bytes': DownloadStore.calculateRealBytes(
            runtimeMinutes: runtimeMins, bitrateKbps: 440),
      },
      {
        'label': '480p SD',
        'tag': 'Standard Definition',
        'kbps': 780,
        'bytes': DownloadStore.calculateRealBytes(
            runtimeMinutes: runtimeMins, bitrateKbps: 780),
      },
      {
        'label': '720p HD',
        'tag': 'Recommended • High Definition',
        'kbps': 1450,
        'bytes': DownloadStore.calculateRealBytes(
            runtimeMinutes: runtimeMins, bitrateKbps: 1450),
      },
      {
        'label': '1080p Full HD',
        'tag': 'BluRay • Crystal Clear',
        'kbps': 2850,
        'bytes': DownloadStore.calculateRealBytes(
            runtimeMinutes: runtimeMins, bitrateKbps: 2850),
      },
      {
        'label': '2160p 4K UHD',
        'tag': 'Ultra HD • Dolby Vision',
        'kbps': 6200,
        'bytes': DownloadStore.calculateRealBytes(
            runtimeMinutes: runtimeMins, bitrateKbps: 6200),
      },
    ];

    String selectedLang = dubbedLanguages.first;
    int selectedQualityIdx = 2;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final Map<String, dynamic> activeQ =
                qualityProfiles[selectedQualityIdx];
            final int totalBytes = activeQ['bytes'] as int;
            final String formattedSize =
                DownloadStore.formatBytes(totalBytes);

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
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.downloading_rounded,
                              color: Colors.redAccent,
                              size: 22,
                            ),
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
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Direct Server: $srvName • Runtime: ${runtimeMins}m',
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Select Audio / Dubbed Language:',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: dubbedLanguages.map((lang) {
                          final bool isSel = selectedLang == lang;
                          return GestureDetector(
                            onTap: () =>
                                setModalState(() => selectedLang = lang),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? Colors.redAccent
                                    : Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isSel
                                      ? Colors.redAccent
                                      : Colors.white24,
                                ),
                              ),
                              child: Text(
                                lang,
                                style: TextStyle(
                                  color: isSel
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: 11.5,
                                  fontWeight: isSel
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Select Video Quality (Genuine Size Calculation):',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(qualityProfiles.length, (i) {
                        final q = qualityProfiles[i];
                        final bool isSel = selectedQualityIdx == i;
                        final String qSize =
                            DownloadStore.formatBytes(q['bytes'] as int);
                        return GestureDetector(
                          onTap: () =>
                              setModalState(() => selectedQualityIdx = i),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? Colors.redAccent.withOpacity(0.15)
                                  : const Color(0xFF1E1E2A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSel
                                    ? Colors.redAccent
                                    : Colors.white12,
                                width: isSel ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSel
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  color: isSel
                                      ? Colors.redAccent
                                      : Colors.white38,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
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
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(
                            Icons.download_rounded,
                            color: Colors.white,
                          ),
                          label: Text(
                            'Download Now ($formattedSize)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () async {
                            Navigator.pop(sheetCtx);
                            final String posterPath =
                                await _posterUrlForWatchlist();
                            final String fullPoster = posterPath.isNotEmpty
                                ? proxyImg(
                                    'https://image.tmdb.org/t/p/w500$posterPath')
                                : '';
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
                              streamUrl: _sniffedStreamUrl,
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
    _controller.runJavaScript('''
      var vids = document.getElementsByTagName('video');
      if (vids.length > 0) {
        vids[0].style.objectFit = '$currentAspectRatio';
      }
    ''');
    _startControlsTimer();
  }

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
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
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
                  Text(
                    '$totalSeasons Seasons Available',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Full Catalog',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: totalSeasons,
                  itemBuilder: (context, index) {
                    int seasonNum = index + 1;
                    return ListTile(
                      title: Text(
                        'Season ${seasonNum.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.play_circle_outline,
                        color: Colors.grey,
                        size: 20,
                      ),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                      const Text(
                        'Server Status & Audio',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Text(
                    'Real-time deep analysis of active servers',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: servers.length,
                      itemBuilder: (context, index) {
                        final srv = servers[index];
                        int mockPing = Random().nextInt(250) + 15;
                        Color pingColor = mockPing < 80
                            ? Colors.greenAccent
                            : (mockPing < 150
                                ? Colors.orangeAccent
                                : Colors.redAccent);
                        IconData towerIcon = mockPing < 80
                            ? Icons.signal_cellular_alt
                            : (mockPing < 150
                                ? Icons.signal_cellular_alt_2_bar
                                : Icons.signal_cellular_alt_1_bar);
                        List<String> langs = ['English'];
                        if (srv['name']!.toLowerCase().contains('hindi') ||
                            srv['key'] == 'cinezo') {
                          langs.addAll(['Hindi', 'Tamil', 'Telugu']);
                        }
                        if (srv['key'] == 'vidrift' ||
                            srv['key'] == 'bingr' ||
                            srv['key'] == 'vidbolt') {
                          langs.addAll(['Hindi', 'Spanish']);
                        }
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 4),
                          leading: Icon(towerIcon,
                              color: pingColor, size: 28),
                          title: Text(
                            srv['name']!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            'Audio: ${langs.join(", ")}',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 11),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: pingColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: pingColor),
                            ),
                            child: Text(
                              '${mockPing}ms',
                              style: TextStyle(
                                color: pingColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            if (activeServer != srv['key']) {
                              setState(() {
                                activeServer = srv['key']!;
                              });
                              _initStream();
                            }
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
      },
    );
  }

  String get _tmdbType =>
      (widget.mediaType == 'tv' || widget.mediaType == 'series')
          ? 'tv'
          : 'movie';

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
          final List cast = (data['credits'] is Map &&
                  data['credits']['cast'] is List)
              ? (data['credits']['cast'] as List)
              : [];
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
    final List<String> paths = [];
    try {
      final imgs = data['images'];
      if (imgs is Map && imgs['backdrops'] is List) {
        for (final b in imgs['backdrops'] as List) {
          final p = b is Map ? b['file_path'] : null;
          if (p is String && p.isNotEmpty && !paths.contains(p)) {
            paths.add(p);
            if (paths.length >= 8) break;
          }
        }
      }
      final bp = data['backdrop_path'];
      if (bp is String && bp.isNotEmpty && !paths.contains(bp)) {
        paths.insert(0, bp);
      }
      final pp = data['poster_path'];
      if (pp is String && pp.isNotEmpty) paths.add(pp);
    } catch (_) {}

    final List<Color> palette = [];
    final List<List<Color>> zonePalette = [];

    for (final p in paths) {
      if (!mounted) return;
      try {
        final fullUrl = proxyImg('https://image.tmdb.org/t/p/w300$p');
        final bytes = await _fetchImageBytes(fullUrl);
        if (bytes != null && bytes.isNotEmpty) {
          final c = await _extractVibrantColor(bytes);
          if (c != null && !palette.contains(c)) {
            palette.add(c);
            final zones = _buildZonesFromDominant(c, bytes);
            zonePalette.add(zones);
          }
        }
      } catch (_) {}
      if (palette.length >= 8) break;
    }

    if (!mounted) return;
    if (palette.isNotEmpty) {
      setState(() {
        _ambientPalette = palette;
        _ambientZonePalette = zonePalette;
        _ambientIndex = 0;
      });
      _ambientColor.value = palette.first;
      _applyZones(0);
    }
  }

  List<Color> _buildZonesFromDominant(Color dom, Uint8List? bytes) {
    final hsv = HSVColor.fromColor(dom);
    final h = hsv.hue;
    final s = hsv.saturation.clamp(0.45, 0.95);
    final v = hsv.value.clamp(0.55, 0.95);

    final c0 = HSVColor.fromAHSV(1.0, (h - 25 + 360) % 360, s, v).toColor();
    final c1 = HSVColor.fromAHSV(1.0, (h - 10 + 360) % 360, s, v).toColor();
    final c2 = dom;
    final c3 = HSVColor.fromAHSV(1.0, (h + 15) % 360, s, v).toColor();
    final c4 = HSVColor.fromAHSV(1.0, (h + 30) % 360, s, v).toColor();
    final c5 = HSVColor.fromAHSV(1.0, (h + 45) % 360, s * 0.9, v).toColor();
    final c6 = HSVColor.fromAHSV(1.0, (h - 35 + 360) % 360, s, v * 0.9).toColor();
    final c7 = HSVColor.fromAHSV(1.0, (h + 60) % 360, s * 0.85, v).toColor();

    return [c0, c1, c2, c3, c4, c5, c6, c7];
  }

  Future<Uint8List?> _fetchImageBytes(String url) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (_) {}
    return null;
  }

  Future<Color?> _extractVibrantColor(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 40, targetHeight: 40);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return null;
      final raw = byteData.buffer.asUint8List();

      final List<double> wSum = List<double>.filled(24, 0);
      final List<double> rSum = List<double>.filled(24, 0);
      final List<double> gSum = List<double>.filled(24, 0);
      final List<double> bSum = List<double>.filled(24, 0);

      for (int i = 0; i + 3 < raw.length; i += 20) {
        final int r = raw[i];
        final int g = raw[i + 1];
        final int b = raw[i + 2];
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

  void _applyZones(int i) {
    if (i < _ambientZonePalette.length) {
      _ambientZones.value = _ambientZonePalette[i];
    } else {
      _ambientZones.value =
          List<Color>.filled(8, _ambientColor.value);
    }
  }

  Future<String> _posterUrlForWatchlist() async {
    String path = '';
    final Map<String, dynamic>? d = details;
    if (d != null && d['poster_path'] is String) {
      path = d['poster_path'] as String;
    }
    if (path.isEmpty) {
      try {
        final res = await tmdbHttpGet(
          'https://api.themoviedb.org/3/$_tmdbType/${widget.tmdbId}?language=en-US',
          headers: kApiHeaders,
        ).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          if (data is Map && data['poster_path'] is String) {
            path = data['poster_path'] as String;
          }
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
      'overview': widget.overview.isNotEmpty
          ? widget.overview
          : (details?['overview'] ?? ''),
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

  void _addComment() async {
    final text = commentInputController.text.trim();
    User? user = FirebaseAuth.instance.currentUser;
    if (text.isNotEmpty) {
      if (user == null || user.isAnonymous) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please login from Dashboard to comment!'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      String movieId = widget.customUrl == null
          ? widget.tmdbId.toString()
          : 'live_${widget.movieTitle.replaceAll(" ", "_")}';
      await FirebaseFirestore.instance
          .collection('movies')
          .doc(movieId)
          .collection('comments')
          .add({
        'name': user.displayName ?? 'HANNUTV User',
        'text': text,
        'time': DateTime.now().toIso8601String(),
        'timestamp': FieldValue.serverTimestamp(),
        'avatar': (user.displayName != null && user.displayName!.isNotEmpty)
            ? user.displayName![0].toUpperCase()
            : 'H',
      });
      commentInputController.clear();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  void dispose() {
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    super.dispose();
  }

  Widget _buildFocusableItem({
    required Widget child,
    required VoidCallback onTap,
    BorderRadius? borderRadius,
  }) {
    return _TvFocusButton(
      onTap: onTap,
      borderRadius: borderRadius ?? BorderRadius.circular(8),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool full = isFullScreen || isTvDevice;
    final double playerHeight = full ? screenSize.height : 230.0;
    bool isTvShow =
        widget.mediaType == 'tv' || widget.mediaType == 'series';
    String displayTitle = widget.movieTitle;
    if (isTvShow &&
        widget.customUrl == null &&
        !widget.isOfflineDownload) {
      displayTitle =
          'S${currentSeason.toString().padLeft(2, '0')} - E${currentEpisode.toString().padLeft(2, '0')}';
    }

    return PopScope(
      canPop: !isFullScreen || isTvDevice,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isFullScreen && !isTvDevice) {
          _toggleFullScreen();
        }
      },
      child: Scaffold(
        backgroundColor: full ? Colors.black : const Color(0xFF0F0F0F),
        body: _AmbientBackground(
          color: _ambientColor,
          child: SafeArea(
            top: !full,
            bottom: !full,
            left: !full,
            right: !full,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                            child: Container(
                              key: _webViewSurfaceKey,
                              color: Colors.black,
                              child: _PinchZoom(
                                zoom: _videoZoom,
                                onSwipeUp: _enterFullScreenOnSwipeUp,
                                onSwipeDown: _exitFullScreenOnSwipeDown,
                                child: WebViewWidget(controller: _controller),
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
                                    errorBuilder: (_, __, ___) =>
                                        Text(
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
                                        opacity:
                                            _introOpacityAnimation.value,
                                        child: Transform.scale(
                                          scale:
                                              _introScaleAnimation.value,
                                          child: Image.asset(
                                            'assets/logo.png',
                                            height: 60,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(
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
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(color: Colors.black26),
                              ),
                            ),
                            Positioned(
                              top: full ? 18 : 10,
                              left: full ? 18 : 10,
                              child: _buildFocusableItem(
                                onTap: () {
                                  if (isFullScreen && !isTvDevice) {
                                    _toggleFullScreen();
                                  } else {
                                    SystemChrome.setPreferredOrientations(
                                        [DeviceOrientation.portraitUp]);
                                    SystemChrome.setEnabledSystemUIMode(
                                        SystemUiMode.edgeToEdge);
                                    Navigator.pop(context);
                                  }
                                },
                                borderRadius: BorderRadius.circular(20),
                                child: CircleAvatar(
                                  backgroundColor: Colors.black54,
                                  radius: full ? 21 : 18,
                                  child: Icon(
                                    full
                                        ? Icons.close
                                        : Icons.chevron_left,
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
                                      full
                                          ? Icons.fullscreen_exit
                                          : Icons.fullscreen,
                                      color: Colors.white,
                                      size: full ? 26 : 22,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                          if (isPageLoading && !isVideoPlaying)
                            Positioned.fill(
                              child: Container(
                                color: Colors.black,
                                child: const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 30,
                                        height: 30,
                                        child: CircularProgressIndicator(
                                          color: Colors.redAccent,
                                          strokeWidth: 2.5,
                                        ),
                                      ),
                                      SizedBox(height: 10),
                                      Text(
                                        'Connecting to Server...',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.isOfflineDownload)
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: Colors.greenAccent),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.offline_pin_rounded,
                                    color: Colors.greenAccent,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Offline Mode • ${widget.offlineLanguage ?? 'Hindi'} • ${widget.offlineQuality ?? 'HD'} • Ad-Free Video',
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Text(
                            displayTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.star,
                                  color: Colors.amber, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                widget.rating,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                widget.year,
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Icon(Icons.visibility,
                                  color: Colors.grey, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '$viewCount Views',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
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
                                      final bool saved = WatchlistStore
                                          .I.items
                                          .any((e) =>
                                              e.id == widget.tmdbId &&
                                              (e.isTv ? 'tv' : 'movie') ==
                                                  _tmdbType);
                                      return _buildFocusableItem(
                                        onTap: _toggleWatchlist,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        child: _buildActionButton(
                                          saved
                                              ? Icons.bookmark
                                              : Icons.bookmark_border,
                                          saved
                                              ? 'In Watchlist'
                                              : 'Add to Watchlist',
                                          activeColor: saved
                                              ? Colors.amber
                                              : Colors.white,
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  _buildFocusableItem(
                                    onTap: _showRealDownloadSheet,
                                    borderRadius: BorderRadius.circular(20),
                                    child: _buildActionButton(
                                      Icons.downloading_rounded,
                                      'Download',
                                      activeColor: Colors.greenAccent,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                _buildFocusableItem(
                                  onTap: _showSearchSheet,
                                  borderRadius: BorderRadius.circular(20),
                                  child: _buildActionButton(
                                      Icons.search, 'Search'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (!widget.isOfflineDownload)
                            _buildYouTubeSponsorCompanionCard(),
                          if (widget.customUrl == null) ...[
                            _buildDescriptionCard(),
                            const SizedBox(height: 16),
                          ],
                          if (widget.customUrl == null) ...[
                            const Text(
                              'Sponsored Ads',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const CustomBannerAd(
                                htmlBannerCode: _adsterraBannerSnippet),
                            const SizedBox(height: 20),
                          ],
                          if (widget.customUrl == null &&
                              !widget.isOfflineDownload) ...[
                            const Text(
                              'If current server is not working, try a different one:',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF151515),
                                border:
                                    Border.all(color: Colors.white12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.verified_user,
                                          color: Colors.green, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'All Servers',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: servers.map((srv) {
                                        final isSelected =
                                            activeServer == srv['key'];
                                        return _buildFocusableItem(
                                          onTap: () {
                                            if (activeServer !=
                                                srv['key']) {
                                              setState(() {
                                                activeServer =
                                                    srv['key']!;
                                              });
                                              _initStream();
                                            }
                                          },
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          child: Container(
                                            margin: const EdgeInsets.only(
                                                right: 8),
                                            padding: const EdgeInsets
                                                .symmetric(
                                                horizontal: 16,
                                                vertical: 8),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? Colors.white
                                                  : Colors.grey[900],
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              srv['name']!,
                                              style: TextStyle(
                                                color: isSelected
                                                    ? Colors.black
                                                    : Colors.white,
                                                fontWeight:
                                                    FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            _buildCastSection(),
                            const CustomBannerAd(
                                htmlBannerCode: _adsterraBannerSnippet),
                            const SizedBox(height: 20),
                          ],
                          if (isTvShow &&
                              widget.customUrl == null &&
                              !widget.isOfflineDownload) ...[
                            Row(
                              children: [
                                InkWell(
                                  onTap: _showSeasonPicker,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      border: Border.all(
                                          color: Colors.white30),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          'Season ${currentSeason.toString().padLeft(2, '0')}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Icon(
                                          Icons.keyboard_arrow_down,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                InkWell(
                                  onTap: _showAudioServerPingMenu,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      border: Border.all(
                                          color: Colors.white30),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                    child: const Row(
                                      children: [
                                        Text(
                                          'Original Audio',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        SizedBox(width: 6),
                                        Icon(
                                          Icons.keyboard_arrow_down,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (episodesList.isNotEmpty)
                              ListView.builder(
                                shrinkWrap: true,
                                physics:
                                    const NeverScrollableScrollPhysics(),
                                itemCount: episodesList.length,
                                itemBuilder: (context, index) {
                                  final ep = episodesList[index];
                                  final epNum = ep['episode_number'] ??
                                      (index + 1);
                                  final epName = ep['name'] ??
                                      'Episode $epNum';
                                  final stillPath = ep['still_path'];
                                  final isCurrent =
                                      currentEpisode == epNum;
                                  return _buildFocusableItem(
                                    onTap: () => _switchEpisode(epNum),
                                    borderRadius:
                                        BorderRadius.circular(12),
                                    child: Container(
                                      margin: const EdgeInsets.only(
                                          bottom: 10),
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isCurrent
                                            ? Colors.white12
                                            : Colors.grey[900],
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: isCurrent
                                            ? Border.all(
                                                color: Colors.redAccent)
                                            : null,
                                      ),
                                      child: Row(
                                        children: [
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: Container(
                                              width: 100,
                                              height: 60,
                                              color: Colors.black45,
                                              child: stillPath != null
                                                  ? CachedNetworkImage(
                                                      imageUrl: proxyImg(
                                                          'https://image.tmdb.org/t/p/w300$stillPath'),
                                                      fit: BoxFit.cover,
                                                    )
                                                  : const Icon(
                                                      Icons.movie,
                                                      color:
                                                          Colors.white24),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'EP $epNum • $epName',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  ep['overview'] ?? '',
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 11,
                                                  ),
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
                            const SizedBox(height: 20),
                          ],
                          if (!widget.isOfflineDownload) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[900],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Public Comments',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Icon(Icons.comment,
                                          color: Colors.grey, size: 16),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller:
                                              commentInputController,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12),
                                          decoration: InputDecoration(
                                            hintText:
                                                'Add a public comment...',
                                            hintStyle: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12),
                                            filled: true,
                                            fillColor: Colors.black45,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      20),
                                              borderSide:
                                                  BorderSide.none,
                                            ),
                                          ),
                                        ),
                                      ),
                                      _buildFocusableItem(
                                        onTap: _addComment,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        child: const Padding(
                                          padding: EdgeInsets.all(8.0),
                                          child: Icon(Icons.send,
                                              color: Colors.redAccent,
                                              size: 20),
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
                                        .orderBy('timestamp',
                                            descending: true)
                                        .snapshots(),
                                    builder: (context, snapshot) {
                                      if (!snapshot.hasData) {
                                        return const Center(
                                          child:
                                              CircularProgressIndicator(
                                            color: Colors.redAccent,
                                          ),
                                        );
                                      }
                                      final comments =
                                          snapshot.data!.docs;
                                      if (comments.isEmpty) {
                                        return const Padding(
                                          padding: EdgeInsets.all(8.0),
                                          child: Text(
                                            'Be the first to comment!',
                                            style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12,
                                            ),
                                          ),
                                        );
                                      }
                                      return Column(
                                        children:
                                            comments.map((doc) {
                                          var data = doc.data()
                                              as Map<String, dynamic>;
                                          return Padding(
                                            padding: const EdgeInsets
                                                .only(bottom: 8.0),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment
                                                      .start,
                                              children: [
                                                CircleAvatar(
                                                  radius: 14,
                                                  backgroundColor:
                                                      Colors.redAccent,
                                                  child: Text(
                                                    data['avatar'] ??
                                                        'U',
                                                    style:
                                                        const TextStyle(
                                                      color: Colors
                                                          .white,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight
                                                              .bold,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(
                                                    width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Text(
                                                            data['name'] ??
                                                                'User',
                                                            style:
                                                                const TextStyle(
                                                              color: Colors
                                                                  .white70,
                                                              fontSize:
                                                                  12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 6),
                                                          const Text(
                                                            '• Just now',
                                                            style:
                                                                TextStyle(
                                                              color: Colors
                                                                  .grey,
                                                              fontSize:
                                                                  10,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      Text(
                                                        data['text'] ??
                                                            '',
                                                        style:
                                                            const TextStyle(
                                                          color: Colors
                                                              .white,
                                                          fontSize:
                                                              12,
                                                        ),
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
                          ],
                          if (widget.customUrl == null &&
                              !widget.isOfflineDownload)
                            ..._buildMoreSuggestions(),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String title,
      {Color activeColor = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: activeColor, size: 18),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              color: activeColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionCard() {
    final Map<String, dynamic>? d = details;
    final String fetched = (d?['overview'] ?? '').toString().trim();
    final String overview =
        fetched.isNotEmpty ? fetched : widget.overview.trim();
    final String tagline = (d?['tagline'] ?? '').toString().trim();
    final List genres =
        (d?['genres'] is List) ? (d!['genres'] as List) : [];
    final List langs = (d?['spoken_languages'] is List)
        ? (d!['spoken_languages'] as List)
        : [];
    final String languages = langs
        .map((l) => l is Map
            ? (l['english_name'] ?? l['name'] ?? '').toString()
            : '')
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
        }
        if (e != null) {
          runtime = runtime.isEmpty ? '$e Episodes' : '$runtime • $e Ep';
        }
      }
    }

    final String release =
        (d?['release_date'] ?? d?['first_air_date'] ?? '').toString();
    final String status = (d?['status'] ?? '').toString();
    String ratingStr = '';
    final dynamic va = d?['vote_average'];
    final dynamic vc = d?['vote_count'];
    if (va is num && va > 0) {
      ratingStr = '${va.toStringAsFixed(1)} / 10';
      if (vc is num && vc > 0) ratingStr = '$ratingStr (${vc.toInt()} votes)';
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
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Description',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Icon(
                  descExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.white54,
                  size: 22,
                ),
              ],
            ),
            if (metaLine.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  metaLine,
                  style:
                      const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            if (genres.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: genres.take(5).map<Widget>((g) {
                  final String gName =
                      g is Map ? (g['name'] ?? '').toString() : '';
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      gName,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11),
                    ),
                  );
                }).toList(),
              ),
            ],
            if (tagline.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '“$tagline”',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 10),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              alignment: Alignment.topCenter,
              child: Text(
                overview.isEmpty
                    ? (isLoadingDetails
                        ? 'Loading description...'
                        : 'No description available.')
                    : overview,
                maxLines: descExpanded ? null : 3,
                overflow: descExpanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.45,
                ),
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
            Text(
              descExpanded ? 'Show less' : '...more',
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String k, String v) {
    if (v.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              k,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCastSection() {
    if (castList.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cast',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
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
              final bool hasPhoto =
                  profile is String && profile.isNotEmpty;
              return _buildFocusableItem(
                onTap: () => _showActorSheet(c['id'] as int, name),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 86,
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                      vertical: 4, horizontal: 2),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: Colors.grey[900],
                        backgroundImage: hasPhoto
                            ? CachedNetworkImageProvider(proxyImg(
                                'https://image.tmdb.org/t/p/w185$profile'))
                            : null,
                        child: hasPhoto
                            ? null
                            : const Icon(Icons.person,
                                color: Colors.white38, size: 30),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (character.isNotEmpty)
                        Text(
                          character,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _buildMoreSuggestions() {
    if (isLoadingSimilar) {
      return [
        const Center(
          child: CircularProgressIndicator(color: Colors.redAccent),
        )
      ];
    }
    if (similarMovies.isEmpty) return [];

    return [
      const Text(
        'More Like This',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 12),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.65,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
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
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                image: DecorationImage(
                  image: CachedNetworkImageProvider(
                    m['posterUrl'] != ''
                        ? m['posterUrl']
                        : 'https://via.placeholder.com/300x450/222222/888888',
                  ),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    ];
  }

  void _showSearchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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

  void _openTitleFromMap(Map<String, dynamic> m) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerPage(
          tmdbId: m['id'] as int,
          mediaType: m['mediaType'] ?? 'movie',
          movieTitle: m['title'] ?? '',
          rating: m['rating'] ?? '0.0',
          year: m['year'] ?? '',
          overview: m['overview'] ?? '',
        ),
      ),
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
}

class _PinchZoom extends StatefulWidget {
  final ValueNotifier<double> zoom;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;
  final Widget child;

  const _PinchZoom({
    required this.zoom,
    this.onSwipeUp,
    this.onSwipeDown,
    required this.child,
  });

  @override
  State<_PinchZoom> createState() => _PinchZoomState();
}

class _PinchZoomState extends State<_PinchZoom> {
  double _verticalDelta = 0.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (details) {
        _verticalDelta += details.primaryDelta ?? 0.0;
      },
      onVerticalDragEnd: (details) {
        if (_verticalDelta < -35) {
          widget.onSwipeUp?.call();
        } else if (_verticalDelta > 35) {
          widget.onSwipeDown?.call();
        }
        _verticalDelta = 0.0;
      },
      child: ValueListenableBuilder<double>(
        valueListenable: widget.zoom,
        builder: (context, val, child) {
          return Transform.scale(
            scale: val,
            alignment: Alignment.center,
            child: widget.child,
          );
        },
      ),
    );
  }
}

class _TvFocusButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;

  const _TvFocusButton({
    required this.child,
    required this.onTap,
    required this.borderRadius,
  });

  @override
  State<_TvFocusButton> createState() => _TvFocusButtonState();
}

class _TvFocusButtonState extends State<_TvFocusButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: _focused
                ? Border.all(color: Colors.redAccent, width: 2)
                : null,
          ),
          child: widget.child,
        ),
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
      builder: (context, currentZones, _) {
        return TweenAnimationBuilder<_ZonesWrapper>(
          tween: _ZonesTween(
            begin: _ZonesWrapper(currentZones),
            end: _ZonesWrapper(currentZones),
          ),
          duration: const Duration(milliseconds: 800),
          builder: (context, wrapper, _) {
            return CustomPaint(
              painter: _GlowPainter(wrapper.zones),
              child: child,
            );
          },
        );
      },
    );
  }
}

class _ZonesWrapper {
  final List<Color> zones;
  _ZonesWrapper(this.zones);
}

class _ZonesTween extends Tween<_ZonesWrapper> {
  _ZonesTween({_ZonesWrapper? begin, _ZonesWrapper? end})
      : super(begin: begin, end: end);

  @override
  _ZonesWrapper lerp(double t) {
    final b = begin?.zones ?? [];
    final e = end?.zones ?? [];
    final List<Color> res = [];
    for (int i = 0; i < 8; i++) {
      final cb = i < b.length ? b[i] : Colors.transparent;
      final ce = i < e.length ? e[i] : Colors.transparent;
      res.add(Color.lerp(cb, ce, t) ?? ce);
    }
    return _ZonesWrapper(res);
  }
}

class _GlowPainter extends CustomPainter {
  final List<Color> zones;
  _GlowPainter(this.zones);

  @override
  void paint(Canvas canvas, Size size) {
    if (zones.isEmpty) return;
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 35);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    paint.color = zones.first.withOpacity(0.35);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) => true;
}

class _AmbientBackground extends StatelessWidget {
  final ValueNotifier<Color> color;
  final Widget child;

  const _AmbientBackground({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: color,
      builder: (context, c, _) {
        return AnimatedContainer(
          duration: const Duration(seconds: 1),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                c.withOpacity(0.18),
                const Color(0xFF0F0F0F),
              ],
            ),
          ),
          child: child,
        );
      },
    );
  }
}

class _SearchSheet extends StatefulWidget {
  final Function(Map<String, dynamic>) onOpenTitle;
  final Function(int, String) onOpenPerson;

  const _SearchSheet({
    required this.onOpenTitle,
    required this.onOpenPerson,
  });

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final TextEditingController _ctrl = TextEditingController();
  List<Map<String, dynamic>> results = [];
  bool loading = false;

  void _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => loading = true);
    try {
      final res = await tmdbHttpGet(
        'https://api.themoviedb.org/3/search/multi?query=${Uri.encodeComponent(query)}&language=en-US',
        headers: kApiHeaders,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List list = data['results'] ?? [];
        if (mounted) {
          setState(() {
            results = list
                .whereType<Map<String, dynamic>>()
                .map((m) => {
                      'id': m['id'],
                      'mediaType': m['media_type'] ?? 'movie',
                      'title': m['title'] ?? m['name'] ?? 'Unknown',
                      'rating': (m['vote_average'] ?? 0.0).toStringAsFixed(1),
                      'year': (m['release_date'] ?? m['first_air_date'] ?? '')
                          .toString()
                          .split('-')
                          .first,
                      'poster': m['poster_path'] != null
                          ? proxyImg(
                              'https://image.tmdb.org/t/p/w185${m['poster_path']}')
                          : '',
                      'overview': m['overview'] ?? '',
                    })
                .toList();
            loading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          TextField(
            controller: _ctrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search movies, series, anime...',
              hintStyle: const TextStyle(color: Colors.grey),
              prefixIcon:
                  const Icon(Icons.search, color: Colors.redAccent),
              filled: true,
              fillColor: Colors.grey[900],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: _search,
          ),
          const SizedBox(height: 16),
          if (loading)
            const Center(
              child: CircularProgressIndicator(color: Colors.redAccent),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final item = results[index];
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 45,
                        height: 65,
                        color: Colors.black38,
                        child: item['poster'] != ''
                            ? CachedNetworkImage(
                                imageUrl: item['poster'],
                                fit: BoxFit.cover,
                              )
                            : const Icon(Icons.movie,
                                color: Colors.white24),
                      ),
                    ),
                    title: Text(
                      item['title'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '${item['mediaType'].toString().toUpperCase()} • ${item['year']} • ★ ${item['rating']}',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 11),
                    ),
                    onTap: () => widget.onOpenTitle(item),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ActorSheet extends StatefulWidget {
  final int personId;
  final String fallbackName;
  final Function(Map<String, dynamic>) onOpenTitle;

  const _ActorSheet({
    required this.personId,
    required this.fallbackName,
    required this.onOpenTitle,
  });

  @override
  State<_ActorSheet> createState() => _ActorSheetState();
}

class _ActorSheetState extends State<_ActorSheet> {
  Map<String, dynamic>? personData;
  List credits = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPerson();
  }

  void _fetchPerson() async {
    try {
      final res = await tmdbHttpGet(
        'https://api.themoviedb.org/3/person/${widget.personId}?language=en-US&append_to_response=combined_credits',
        headers: kApiHeaders,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) {
          setState(() {
            personData = data;
            credits = (data['combined_credits']?['cast'] as List? ?? [])
                .take(20)
                .toList();
            loading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF14141E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.all(16),
      height: MediaQuery.of(context).size.height * 0.75,
      child: loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.redAccent),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundImage: personData?['profile_path'] != null
                            ? CachedNetworkImageProvider(proxyImg(
                                'https://image.tmdb.org/t/p/w185${personData!['profile_path']}'))
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              personData?['name'] ?? widget.fallbackName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              personData?['known_for_department'] ??
                                  'Acting',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Known For',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 150,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: credits.length,
                      itemBuilder: (context, index) {
                        final m = credits[index];
                        final poster = m['poster_path'];
                        return GestureDetector(
                          onTap: () {
                            widget.onOpenTitle({
                              'id': m['id'],
                              'mediaType': m['media_type'] ?? 'movie',
                              'title': m['title'] ?? m['name'] ?? '',
                              'rating': (m['vote_average'] ?? 0.0)
                                  .toStringAsFixed(1),
                              'year': (m['release_date'] ??
                                      m['first_air_date'] ??
                                      '')
                                  .toString()
                                  .split('-')
                                  .first,
                              'overview': m['overview'] ?? '',
                            });
                          },
                          child: Container(
                            width: 95,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.grey[900],
                              image: poster != null
                                  ? DecorationImage(
                                      image: CachedNetworkImageProvider(
                                          proxyImg(
                                              'https://image.tmdb.org/t/p/w185$poster')),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}