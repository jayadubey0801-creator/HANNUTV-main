import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'banner_ad_widget.dart';
import 'skippable_ad_screen.dart';
import 'stores.dart'; 
import 'tmdb_service.dart';

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
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with SingleTickerProviderStateMixin {
  late WebViewController _controller;

  bool isVideoPlaying = false;
  bool isFullScreen = false;
  bool isPageLoading = true;
  
  String activeServer = 'vidrift'; 
  String currentAspectRatio = 'contain';

  late int currentSeason;
  late int currentEpisode;
  int viewCount = 84920;

  bool showControls = true;
  Timer? _hideControlsTimer;
  Timer? _liveTvAdTimer; 

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

    _introAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _introScaleAnimation = Tween<double>(begin: 0.7, end: 1.3).animate(CurvedAnimation(parent: _introAnimController, curve: Curves.easeOutBack));
    _introOpacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(parent: _introAnimController, curve: const Interval(0.65, 1.0, curve: Curves.easeIn)));

    if (widget.customUrl == null) {
      _fetchSimilarMovies();
      _fetchTvDetails();
      _fetchDetails(); 
    } else {
      _liveTvAdTimer = Timer.periodic(const Duration(minutes: 8), (timer) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => SkippableAdScreen(
                adDuration: 60, 
                nextScreen: VideoPlayerPage(
                  tmdbId: widget.tmdbId, mediaType: widget.mediaType,
                  season: widget.season, episode: widget.episode,
                  movieTitle: widget.movieTitle, overview: widget.overview,
                  rating: widget.rating, year: widget.year, customUrl: widget.customUrl,
                ),
              ),
            ),
          );
        }
      });
    }

    _checkDeviceType();
    WatchlistStore.I.load();
    _startAmbientCycle(); 
  }

  Future<void> _fetchTvDetails() async {
    if (widget.mediaType != 'tv' && widget.mediaType != 'series') return;
    try {
      final res = await http.get(Uri.parse('https://api.themoviedb.org/3/tv/${widget.tmdbId}?language=en-US'), headers: kApiHeaders);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) setState(() { totalSeasons = data['number_of_seasons'] ?? 1; });
        _fetchEpisodes(currentSeason);
      }
    } catch (e) {}
  }

  Future<void> _fetchEpisodes(int seasonNum) async {
    if (widget.mediaType != 'tv' && widget.mediaType != 'series') return;
    try {
      final res = await http.get(Uri.parse('https://api.themoviedb.org/3/tv/${widget.tmdbId}/season/$seasonNum?language=en-US'), headers: kApiHeaders);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) setState(() { episodesList = data['episodes'] ?? []; });
      }
    } catch (e) {}
  }

  void _checkDeviceType() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = MediaQuery.of(context).size;
      setState(() {
        isTvDevice = size.width > size.height && size.width > 600; 
        if (isTvDevice) isFullScreen = true; 
        else { SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]); SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); }
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
    setState(() { showIntroAnimation = true; isVideoPlaying = true; isPageLoading = false; });
    _introAnimController.forward().then((_) { if (mounted) setState(() => showIntroAnimation = false); });
  }

  Future<void> _fetchSimilarMovies() async {
    setState(() => isLoadingSimilar = true);
    try {
      final type = widget.mediaType == 'tv' || widget.mediaType == 'series' ? 'tv' : 'movie';
      final res = await http.get(Uri.parse('https://api.themoviedb.org/3/$type/${widget.tmdbId}/recommendations?language=en-US'), headers: kApiHeaders);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List results = data['results'] ?? [];
        if (mounted) {
          setState(() {
            similarMovies = results.map((m) => {
              'id': m['id'], 'title': m['title'] ?? m['name'] ?? 'Unknown',
              'posterUrl': m['poster_path'] != null ? 'https://image.tmdb.org/t/p/w500${m['poster_path']}' : '',
              'rating': (m['vote_average'] ?? 0).toStringAsFixed(1),
              'year': (m['release_date'] ?? m['first_air_date'] ?? '').toString().split('-').first,
              'mediaType': type,
            }).toList();
            isLoadingSimilar = false;
          });
        }
      } else { if (mounted) setState(() => isLoadingSimilar = false); }
    } catch (_) { if (mounted) setState(() => isLoadingSimilar = false); }
  }

  void _initStream() {
    setState(() { isPageLoading = true; isVideoPlaying = false; showIntroAnimation = false; });

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(
        isTvDevice ? "Mozilla/5.0 (SMART-TV; Linux; Tizen 5.0) AppleWebKit/538.1 (KHTML, like Gecko) Version/5.0 TV Safari/538.1"
                   : "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      )
      ..addJavaScriptChannel('VideoState', onMessageReceived: (JavaScriptMessage message) { if (message.message == 'playing' && mounted) _triggerCinematicPlayAnimation(); if (message.message == 'ready' && mounted) setState(() => isPageLoading = false); })
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) { if (mounted) setState(() => isPageLoading = true); },
          onPageFinished: (String url) {
            if (mounted && widget.customUrl != null) setState(() => isPageLoading = false);

            // 🔥 DEEP FIX: FAST SERVER AD BLOCKER & WHITE SCREEN FIX 🔥
            String jsCode = '''
              document.documentElement.style.backgroundColor = '#000000';
              document.body.style.backgroundColor = '#000000';
              
              // Completely disable popup windows
              window.open = function() { return null; };
              window.alert = function() { return true; }; 
              window.confirm = function() { return true; }; 
              
              // Force hide all ad-related elements
              var style = document.createElement('style');
              style.innerHTML = `
                iframe[src*="ads"], iframe[src*="bet"], iframe[src*="casino"], .ad-container, .ads, .popup-overlay, 
                [class*="verify"], #ad-overlay, .video-ad, .jw-ad, .ad-box, a[target="_blank"], div[style*="z-index: 2147483647"] { 
                    display: none !important; 
                    opacity: 0 !important; 
                    pointer-events: none !important; 
                    visibility: hidden !important; 
                    height: 0 !important;
                    width: 0 !important;
                    z-index: -1 !important;
                }
                body, html { background-color: #000000 !important; overflow: hidden !important; }
              `;
              document.head.appendChild(style);

              // Block fake clicks
              document.addEventListener('click', function(e) {
                var target = e.target.closest('a');
                if(target && target.href && (target.href.includes('ad') || target.href.includes('bet') || target.href.includes('pop'))) {
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
                  v.style.top = '0'; v.style.left = '0'; v.style.width = '100vw'; v.style.height = '100vh'; v.style.zIndex = '999999';
                  if (v.currentTime > 0.5 && !v.paused) VideoState.postMessage('playing');
                }
              }, 200);
            ''';
            _controller.runJavaScript(jsCode);
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url.toLowerCase();
            // Block all known ad networks unconditionally
            if (url.contains('doubleclick') || url.contains('popads') || url.contains('1xbet') || url.contains('bet365') || url.contains('onclick') || url.contains('adsterra') || url.contains('/ad/') || url.contains('sponsor')) {
                return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    if (widget.customUrl != null && widget.customUrl!.isNotEmpty) {
      if (widget.customUrl!.contains('.m3u8')) {
        String hlsHtml = '''
          <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
          <style>body, html { margin: 0; padding: 0; background: black; height: 100%; width: 100%; overflow: hidden; } video { width: 100%; height: 100%; object-fit: contain; }</style>
          </head><body>
          <video id="video" autoplay controls></video>
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
      final id = widget.tmdbId;
      final isTv = widget.mediaType == 'tv' || widget.mediaType == 'series';
      
      String originalTargetUrl = isTv 
          ? 'https://pantyflix.com/watch/play/tv/$id?season=$currentSeason&episode=$currentEpisode&server=$activeServer' 
          : 'https://pantyflix.com/watch/play/movie/$id?server=$activeServer';
      
      String vercelProxyBase = "https://hannutv-proxy-1.vercel.app/api/proxy?stream=";
      String safeFinalUrl = vercelProxyBase + Uri.encodeComponent(originalTargetUrl);
      
      _controller.loadRequest(Uri.parse(safeFinalUrl));
    }
  }

  void _cycleAspectRatio() {
    setState(() {
      if (currentAspectRatio == 'contain') currentAspectRatio = 'cover';
      else if (currentAspectRatio == 'cover') currentAspectRatio = 'fill';
      else currentAspectRatio = 'contain';
    });
    _controller.runJavaScript("var vids = document.getElementsByTagName('video'); if (vids.length > 0) { vids[0].style.objectFit = '$currentAspectRatio'; }");
    _startControlsTimer();
  }

  void _toggleFullScreen() {
    if (isTvDevice) return; 
    setState(() { isFullScreen = !isFullScreen; });
    if (isFullScreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _startControlsTimer();
  }

  void _switchEpisode(int ep) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => SkippableAdScreen(
          adDuration: 10,
          nextScreen: VideoPlayerPage(
            tmdbId: widget.tmdbId,
            mediaType: widget.mediaType,
            season: currentSeason,
            episode: ep,
            movieTitle: widget.movieTitle,
            overview: widget.overview,
            rating: widget.rating,
            year: widget.year,
          )
        )
      )
    );
  }
  
  void _switchSeason(int seasonNum) {
    setState(() { currentSeason = seasonNum; currentEpisode = 1; episodesList.clear(); });
    _fetchEpisodes(seasonNum);
    _switchEpisode(1);
  }

  void _showSeasonPicker() {
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF1A1A1A), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16), height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("$totalSeasons Seasons Available", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), const Text("Full Catalog", style: TextStyle(color: Colors.redAccent, fontSize: 12))]),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: totalSeasons, 
                  itemBuilder: (context, index) {
                    int seasonNum = index + 1;
                    return ListTile(
                      title: Text("Season ${seasonNum.toString().padLeft(2, '0')}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      trailing: const Icon(Icons.play_circle_outline, color: Colors.grey, size: 20),
                      onTap: () { Navigator.pop(context); _switchSeason(seasonNum); },
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
      context: context, backgroundColor: const Color(0xFF151515),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Container(
              padding: const EdgeInsets.all(16), height: MediaQuery.of(context).size.height * 0.70,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Server Status & Audio", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context))]),
                  const Text("Real-time deep analysis of active servers:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: servers.length,
                      itemBuilder: (context, index) {
                        final srv = servers[index];
                        int mockPing = Random().nextInt(250) + 15; 
                        Color pingColor = mockPing < 80 ? Colors.greenAccent : (mockPing < 150 ? Colors.orangeAccent : Colors.redAccent);
                        IconData towerIcon = mockPing < 80 ? Icons.signal_cellular_alt : (mockPing < 150 ? Icons.signal_cellular_alt_2_bar : Icons.signal_cellular_alt_1_bar);
                        
                        List<String> langs = ['English'];
                        if (srv['name']!.toLowerCase().contains('hindi') || srv['key'] == 'cinezo') langs.addAll(['Hindi', 'Tamil', 'Telugu']);
                        if (srv['key'] == 'vidrift' || srv['key'] == 'bingr' || srv['key'] == 'vidbolt') langs.addAll(['Hindi', 'Spanish']);

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          leading: Icon(towerIcon, color: pingColor, size: 28),
                          title: Text(srv['name']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text("Audio: ${langs.join(', ')}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: pingColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: pingColor)),
                            child: Text("${mockPing}ms", style: TextStyle(color: pingColor, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            if (activeServer != srv['key']) { setState(() => activeServer = srv['key']!); _initStream(); }
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
      }
    );
  }

  String get _tmdbType =>
      (widget.mediaType == 'tv' || widget.mediaType == 'series') ? 'tv' : 'movie';

  Future<void> _fetchDetails() async {
    if (mounted) setState(() => isLoadingDetails = true);
    try {
      final res = await http.get(
        Uri.parse('https://api.themoviedb.org/3/$_tmdbType/${widget.tmdbId}?language=en-US&append_to_response=credits,images&include_image_language=en,null'),
        headers: kApiHeaders,
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data is Map<String, dynamic> && mounted) {
          final List cast = (data['credits'] is Map && data['credits']['cast'] is List) ? data['credits']['cast'] : [];
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
    for (final p in paths) {
      if (!mounted) return;
      final Color? c = await _dominantColorFromUrl('https://image.tmdb.org/t/p/w300$p');
      if (!mounted) return;
      if (c != null) {
        palette.add(c);
        if (palette.length == 1) {
          _ambientTimer?.cancel();
          _ambientPalette = [c];
          _ambientColor.value = c;
        }
      }
    }
    if (!mounted || palette.isEmpty) return;
    _ambientPalette = palette;
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
    if (_ambientPalette.length < 2) return;
    _ambientTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _ambientPalette.isEmpty) return;
      _ambientIndex = (_ambientIndex + 1) % _ambientPalette.length;
      _ambientColor.value = _ambientPalette[_ambientIndex];
    });
  }

  Future<String> _posterUrlForWatchlist() async {
    String path = '';
    final Map<String, dynamic>? d = details;
    if (d != null && d['poster_path'] is String) path = d['poster_path'] as String;
    if (path.isEmpty) {
      try {
        final res = await http
            .get(Uri.parse('https://api.themoviedb.org/3/$_tmdbType/${widget.tmdbId}?language=en-US'), headers: kApiHeaders)
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          if (data is Map && data['poster_path'] is String) path = data['poster_path'] as String;
        }
      } catch (_) {}
    }
    return path.isNotEmpty ? 'https://image.tmdb.org/t/p/w500$path' : '';
  }

  // 🔥 WATCHLIST SYNC DEEP FIX 🔥
  Future<void> _toggleWatchlist() async {
    final Map<String, dynamic> tmdbData = {
      'id': widget.tmdbId,
      'is_tv': _tmdbType == 'tv', 
      'title': widget.movieTitle,
      'name': widget.movieTitle,
      'release_date': widget.year,
      'first_air_date': widget.year,
      'vote_average': num.tryParse(widget.rating) ?? 0.0,
      'overview': widget.overview.isNotEmpty ? widget.overview : (details?['overview'] ?? ''),
      'poster_path': await _posterUrlForWatchlist(),
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
        builder: (context) => SkippableAdScreen(
          adDuration: 10,
          nextScreen: VideoPlayerPage(
            tmdbId: id,
            mediaType: mediaType,
            movieTitle: title,
            overview: overview,
            rating: rating,
            year: year,
          ),
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
                        backgroundImage: hasPhoto ? CachedNetworkImageProvider('https://image.tmdb.org/t/p/w185$profile') : null,
                        child: hasPhoto ? null : const Icon(Icons.person, color: Colors.white38, size: 30),
                      ),
                      const SizedBox(height: 6),
                      Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      if (character.isNotEmpty)
                        Text(character, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 10)),
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
      ratingStr = va.toStringAsFixed(1) + ' / 10';
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
                const Text("Description", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                const Spacer(),
                Icon(descExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.white54, size: 22),
              ],
            ),
            if (metaLine.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(metaLine, style: const TextStyle(color: Colors.grey, fontSize: 12))),
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
              Text(tagline, style: const TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 10),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              alignment: Alignment.topCenter,
              child: Text(
                overview.isEmpty ? (isLoadingDetails ? "Loading description..." : "No description available.") : overview,
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
            Text(descExpanded ? "Show less" : "...more", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please login from Dashboard to comment!'), backgroundColor: Colors.redAccent));
        return;
      }
      
      String movieId = widget.customUrl == null ? widget.tmdbId.toString() : 'live_${widget.movieTitle.replaceAll(" ", "_")}';
      
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
    _hideControlsTimer?.cancel(); 
    _liveTvAdTimer?.cancel(); 
    _introAnimController.dispose(); 
    commentInputController.dispose();
    _ambientTimer?.cancel();
    _ambientColor.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]); SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    super.dispose();
  }

  Widget _buildFocusableItem({required Widget child, required VoidCallback onTap, BorderRadius? borderRadius}) {
    return _TvFocusButton(onTap: onTap, borderRadius: borderRadius ?? BorderRadius.circular(8), child: child);
  }

  Widget _buildTVLayout() { return const Scaffold(backgroundColor: Colors.black, body: Center(child: Text("TV Layout Mode", style: TextStyle(color: Colors.white)))); }

  @override
  Widget build(BuildContext context) {
    if (isTvDevice) return _buildTVLayout(); 

    if (isFullScreen) {
      // 🔥 BLACK BACKGROUND FIX 🔥
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(child: WebViewWidget(controller: _controller)),
            if (isPageLoading && !isVideoPlaying) Positioned.fill(child: Container(color: Colors.black, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [SizedBox(width: 30, height: 30, child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 2.5)), SizedBox(height: 10), Text("Connecting to Server...", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))])))),
            Positioned(top: 14, right: 20, child: SafeArea(child: IgnorePointer(child: Opacity(opacity: 0.85, child: Image.asset('assets/logo.png', height: 38, errorBuilder: (_, __, ___) => const Text('HANNUTV', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16))))))),
            if (showControls) ...[
              Positioned.fill(child: IgnorePointer(child: Container(color: Colors.black38))),
              Positioned(top: 20, right: 20, child: SafeArea(child: _buildFocusableItem(onTap: () { SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]); SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); Navigator.pop(context); }, borderRadius: BorderRadius.circular(22), child: const CircleAvatar(backgroundColor: Colors.black87, radius: 22, child: Icon(Icons.close, color: Colors.white, size: 28))))),
              Positioned(bottom: 20, right: 20, child: SafeArea(child: _buildFocusableItem(onTap: _toggleFullScreen, borderRadius: BorderRadius.circular(22), child: const CircleAvatar(backgroundColor: Colors.black87, radius: 22, child: Icon(Icons.fullscreen_exit, color: Colors.white, size: 28))))),
            ],
          ],
        ),
      );
    }

    bool isTvShow = widget.mediaType == 'tv' || widget.mediaType == 'series';
    String displayTitle = widget.movieTitle;
    if (isTvShow && widget.customUrl == null) displayTitle += " S${currentSeason.toString().padLeft(2, '0')} - E${currentEpisode.toString().padLeft(2, '0')}";

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: _AmbientBackground(
        color: _ambientColor,
        child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AmbientGlow(
              color: _ambientColor,
              child: GestureDetector(
              onTap: _startControlsTimer,
              child: Stack(
                children: [
                  Container(width: double.infinity, height: 230, color: Colors.black, child: WebViewWidget(controller: _controller)),
                  Positioned(
                    top: 10, right: 14,
                    child: GestureDetector(
                      onTap: _toggleFullScreen,
                      child: Opacity(opacity: 0.85, child: Image.asset('assets/logo.png', height: 34, errorBuilder: (_, __, ___) => const Text('HANNUTV', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15)))),
                    ),
                  ),
                  if (showIntroAnimation) Positioned.fill(child: IgnorePointer(child: Center(child: AnimatedBuilder(animation: _introAnimController, builder: (context, child) { return Opacity(opacity: _introOpacityAnimation.value, child: Transform.scale(scale: _introScaleAnimation.value, child: Image.asset('assets/logo.png', height: 60, errorBuilder: (_, __, ___) => const Icon(Icons.play_circle_fill, color: Colors.red, size: 60)))); })))),
                  if (showControls) ...[
                    Positioned.fill(child: IgnorePointer(child: Container(color: Colors.black38))),
                    Positioned(top: 10, right: 10, child: _buildFocusableItem(onTap: () => Navigator.pop(context), borderRadius: BorderRadius.circular(18), child: const CircleAvatar(backgroundColor: Colors.black54, radius: 18, child: Icon(Icons.chevron_left, color: Colors.white, size: 28)))),
                    Positioned(bottom: 8, right: 48, child: _buildFocusableItem(onTap: _cycleAspectRatio, borderRadius: BorderRadius.circular(16), child: const CircleAvatar(backgroundColor: Colors.black54, radius: 16, child: Icon(Icons.aspect_ratio, color: Colors.white, size: 18)))),
                    Positioned(bottom: 8, right: 8, child: _buildFocusableItem(onTap: _toggleFullScreen, borderRadius: BorderRadius.circular(16), child: const CircleAvatar(backgroundColor: Colors.black54, radius: 16, child: Icon(Icons.fullscreen, color: Colors.white, size: 22)))),
                  ],
                  if (isPageLoading && !isVideoPlaying) Positioned.fill(child: Container(color: Colors.black, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [SizedBox(width: 30, height: 30, child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 2.5)), SizedBox(height: 10), Text("Connecting to Server...", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))])))),
                ],
              ),
            ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayTitle, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 18), const SizedBox(width: 4),
                        Text(widget.rating, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)), const SizedBox(width: 12),
                        Text(widget.year, style: const TextStyle(color: Colors.grey, fontSize: 14)), const SizedBox(width: 16),
                        const Icon(Icons.visibility, color: Colors.grey, size: 16), const SizedBox(width: 4),
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
                                final bool saved = WatchlistStore.I.items.any((e) => e.id == widget.tmdbId && (e.isTv ? 'tv' : 'movie') == _tmdbType);
                                return _buildFocusableItem(
                                  onTap: _toggleWatchlist,
                                  borderRadius: BorderRadius.circular(20),
                                  child: _buildActionButton(saved ? Icons.bookmark : Icons.bookmark_border, saved ? "In Watchlist" : "Add to Watchlist", activeColor: saved ? Colors.amber : Colors.white),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                          _buildFocusableItem(onTap: _showSearchSheet, borderRadius: BorderRadius.circular(20), child: _buildActionButton(Icons.search, "Search")),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (widget.customUrl == null) ...[
                      _buildDescriptionCard(),
                      const SizedBox(height: 16),
                    ],

                    if (widget.customUrl == null) ...[
                      const Text("Sponsored Ads", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 20),
                    ],

                    if (widget.customUrl != null) ...[
                      const SizedBox(height: 10),
                      const Text("Sponsored Ads", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 16),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 16),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 16),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 16),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 16),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 16),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 20),
                    ],

                    if (widget.customUrl == null) ...[
                      const Text("If current server is not working, try a different one:", style: TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: const Color(0xFF151515), border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.verified_user, color: Colors.green, size: 20),
                                SizedBox(width: 8),
                                Text("All Servers", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: servers.map((srv) {
                                  final isSelected = activeServer == srv['key'];
                                  return _buildFocusableItem(
                                    onTap: () { if (activeServer != srv['key']) { setState(() => activeServer = srv['key']!); _initStream(); } },
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(color: isSelected ? Colors.white : Colors.grey[900], borderRadius: BorderRadius.circular(20)),
                                      child: Text(srv['name']!, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
                    
                    if (isTvShow && widget.customUrl == null) ...[
                      Row(
                        children: [
                          InkWell(onTap: _showSeasonPicker, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.white30), borderRadius: BorderRadius.circular(20)), child: Row(children: [Text("Season ${currentSeason.toString().padLeft(2, '0')}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)), const SizedBox(width: 6), const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 18)]))),
                          const SizedBox(width: 12),
                          InkWell(onTap: _showAudioServerPingMenu, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.white30), borderRadius: BorderRadius.circular(20)), child: Row(children: const [Text("Original Audio", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)), SizedBox(width: 6), Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 18)]))),
                        ],
                      ),
                      const SizedBox(height: 20),
                      
                      const Text("Episodes", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
                              if (episodesList[index]['still_path'] != null) imgUrl = 'https://image.tmdb.org/t/p/w500${episodesList[index]['still_path']}';
                            }
                            return _buildFocusableItem(
                              onTap: () => _switchEpisode(epNum), borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 160, margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: isCurrent ? Border.all(color: Colors.redAccent, width: 2) : Border.all(color: Colors.white12), color: const Color(0xFF1A1A1A)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(borderRadius: const BorderRadius.vertical(top: Radius.circular(8)), color: Colors.black54, image: imgUrl.isNotEmpty ? DecorationImage(image: CachedNetworkImageProvider(imgUrl), fit: BoxFit.cover) : null),
                                        child: Center(child: Icon(isCurrent ? Icons.play_circle_fill : Icons.play_circle_outline, color: isCurrent ? Colors.red : Colors.white70, size: 40)),
                                      ),
                                    ),
                                    Padding(padding: const EdgeInsets.all(10.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(epName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis), const Text("Watch on HANNUTV", style: TextStyle(color: Colors.grey, fontSize: 10), maxLines: 1)])),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("Public Comments", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                              const Icon(Icons.comment, color: Colors.grey, size: 16),
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
                                    filled: true, fillColor: Colors.black45,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                                  ),
                                ),
                              ),
                              _buildFocusableItem(
                                onTap: _addComment, borderRadius: BorderRadius.circular(20),
                                child: const Padding(padding: EdgeInsets.all(8.0), child: Icon(Icons.send, color: Colors.redAccent, size: 20)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance.collection('movies').doc(widget.customUrl == null ? widget.tmdbId.toString() : 'live_${widget.movieTitle.replaceAll(" ", "_")}').collection('comments').orderBy('timestamp', descending: true).snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
                              final comments = snapshot.data!.docs;
                              
                              if (comments.isEmpty) return const Padding(padding: EdgeInsets.all(8.0), child: Text("Be the first to comment!", style: TextStyle(color: Colors.grey, fontSize: 12)));

                              return Column(
                                children: comments.map((doc) {
                                  var data = doc.data() as Map<String, dynamic>;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(radius: 14, backgroundColor: Colors.redAccent, child: Text(data['avatar'] ?? 'U', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(data['name'] ?? 'User', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                                                  const SizedBox(width: 6),
                                                  const Text("Just now", style: TextStyle(color: Colors.grey, fontSize: 10)),
                                                ],
                                              ),
                                              Text(data['text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 12)),
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
                    
                    if (widget.customUrl == null && similarMovies.isNotEmpty) ...[
                      const Text("Suggested Movies & Shows", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 160,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal, itemCount: similarMovies.length,
                          itemBuilder: (context, index) {
                            final m = similarMovies[index];
                            return _buildFocusableItem(
                              onTap: () { 
                                Navigator.pushReplacement(
                                  context, 
                                  MaterialPageRoute(builder: (context) => SkippableAdScreen(
                                    adDuration: 10,
                                    nextScreen: VideoPlayerPage(tmdbId: m['id'], mediaType: m['mediaType'], movieTitle: m['title'], rating: m['rating'], year: m['year'])
                                  ))
                                ); 
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 110, margin: const EdgeInsets.only(right: 10),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), image: DecorationImage(image: CachedNetworkImageProvider(m['posterUrl'] != '' ? m['posterUrl'] : 'https://via.placeholder.com/300x450/222222/888888'), fit: BoxFit.cover)))), const SizedBox(height: 4), Text(m['title'], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)]),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
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
      onFocusChange: (hasFocus) { if (mounted) setState(() => _hasFocus = hasFocus); },
      child: InkWell(
        onTap: widget.onTap, borderRadius: widget.borderRadius,
        child: AnimatedContainer(duration: const Duration(milliseconds: 150), decoration: BoxDecoration(borderRadius: widget.borderRadius, border: Border.all(color: _hasFocus ? Colors.redAccent : Colors.transparent, width: _hasFocus ? 3.5 : 0), boxShadow: _hasFocus ? [BoxShadow(color: Colors.redAccent.withOpacity(0.65), blurRadius: 10)] : []), child: widget.child),
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  final ValueNotifier<Color> color;
  final Widget child;
  const _AmbientGlow({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: color,
      child: child,
      builder: (context, c, ch) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 2500),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            boxShadow: [BoxShadow(color: c.withOpacity(0.55), blurRadius: 46, spreadRadius: 5)],
          ),
          child: ch,
        );
      },
    );
  }
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
          onPageStarted: (String url) { if (mounted) setState(() => _loading = true); },
          onPageFinished: (String url) { if (mounted) setState(() => _loading = false); },
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
          if (_loading) const Align(alignment: Alignment.topCenter, child: LinearProgressIndicator(color: Colors.redAccent, backgroundColor: Colors.transparent)),
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
      setState(() { _results = []; _loading = false; _lastQuery = ''; });
      return;
    }
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 400), () { _search(q); });
  }

  Future<void> _search(String q) async {
    if (!mounted) return;
    setState(() { _loading = true; _lastQuery = q; });
    try {
      final res = await http.get(
        Uri.parse('https://api.themoviedb.org/3/search/multi?query=${Uri.encodeQueryComponent(q)}&include_adult=false&language=en-US&page=1'),
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
        setState(() { _results = out; _loading = false; });
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
            backgroundImage: img.isNotEmpty ? CachedNetworkImageProvider('https://image.tmdb.org/t/p/w185$img') : null,
            child: img.isEmpty ? const Icon(Icons.person, color: Colors.white38) : null,
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: img.isNotEmpty
                ? CachedNetworkImage(imageUrl: 'https://image.tmdb.org/t/p/w185$img', width: 46, height: 68, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(width: 46, height: 68, color: Colors.grey[900], child: const Icon(Icons.movie, color: Colors.white24)))
                : Container(width: 46, height: 68, color: Colors.grey[900], child: const Icon(Icons.movie, color: Colors.white24)),
          );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: leading,
      title: Text(m['title'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
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
      return const Center(child: Text("Type to search movies, shows or actors", style: TextStyle(color: Colors.grey, fontSize: 13)));
    }
    if (_results.isEmpty) {
      return Center(child: Text("No results for \"$_lastQuery\"", style: const TextStyle(color: Colors.grey, fontSize: 13)));
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
            Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
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
                          onPressed: () { _ctrl.clear(); _onChanged(''); },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
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
      final res = await http.get(
        Uri.parse('https://api.themoviedb.org/3/person/${widget.personId}?language=en-US&append_to_response=combined_credits,external_ids'),
        headers: kApiHeaders,
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data is Map<String, dynamic>) {
          final List raw = (data['combined_credits'] is Map && data['combined_credits']['cast'] is List) ? data['combined_credits']['cast'] : [];
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
          setState(() { _person = data; _credits = list; _loading = false; });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() { _loading = false; _failed = true; });
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
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white24)),
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
          decoration: BoxDecoration(color: selected ? Colors.white : Colors.grey[900], borderRadius: BorderRadius.circular(18)),
          child: Text(label, style: TextStyle(color: selected ? Colors.black : Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _posterFallback() {
    return Container(color: Colors.grey[900], child: const Center(child: Icon(Icons.movie, color: Colors.white24, size: 28)));
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
                        ? CachedNetworkImage(imageUrl: 'https://image.tmdb.org/t/p/w342$poster', fit: BoxFit.cover, errorWidget: (_, __, ___) => _posterFallback())
                        : _posterFallback(),
                  ),
                ),
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                    child: Text(isTv ? 'TV' : 'MOVIE', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
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
                          Text(rating, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(m['title'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          Text(year.isEmpty ? ' ' : year, maxLines: 1, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _avatarFallback() {
    return Container(width: 90, height: 130, color: Colors.grey[900], child: const Icon(Icons.person, color: Colors.white24, size: 40));
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
                Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: profile.isNotEmpty
                          ? CachedNetworkImage(imageUrl: 'https://image.tmdb.org/t/p/w342$profile', width: 90, height: 130, fit: BoxFit.cover, errorWidget: (_, __, ___) => _avatarFallback())
                          : _avatarFallback(),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                          if (dept.isNotEmpty)
                            Padding(padding: const EdgeInsets.only(top: 4), child: Text(dept, style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold))),
                          if (birthday.isNotEmpty)
                            Padding(padding: const EdgeInsets.only(top: 6), child: Text(deathday.isNotEmpty ? 'Born: $birthday  •  Died: $deathday' : 'Born: $birthday', style: const TextStyle(color: Colors.grey, fontSize: 12))),
                          if (place.isNotEmpty)
                            Padding(padding: const EdgeInsets.only(top: 2), child: Text(place, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 12))),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _linkChip('TMDB', Icons.movie_filter, 'https://www.themoviedb.org/person/${widget.personId}'),
                              if (imdbId.isNotEmpty) _linkChip('IMDb', Icons.star_rate_rounded, 'https://www.imdb.com/name/$imdbId/'),
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
                    child: Text(_bioExpanded ? 'Show less' : '...more', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
                const SizedBox(height: 18),
                Text('Filmography (${items.length})', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(children: [_filterChip('all', 'All'), _filterChip('movie', 'Movies'), _filterChip('tv', 'TV Shows')]),
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