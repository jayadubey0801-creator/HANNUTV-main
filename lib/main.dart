import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'dashboard_screen.dart';
import 'skippable_ad_screen.dart';
import 'tmdb_service.dart';
import 'video_player_page.dart';
import 'widgets.dart';

// 🔥 YEH TEEN IMPORTS TERE PURANE CODE MEIN MISSING THE 🔥
import 'pages.dart';
import 'stores.dart';
import 'hero.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    debugPrint('Background Notification Hit: ${message.messageId}');
  } catch (e) {
    debugPrint('Background Error: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 🔥 FIREBASE SAFE BOOT 🔥 (App crash nahi hogi)
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(hours: 1),
      ),
    );
    await remoteConfig.setDefaults(const {'show_ads': true, 'maintenance_mode': false});
    await remoteConfig.fetchAndActivate();
  } catch (error) {
    debugPrint('🔥 Firebase Startup error (Bypassed for Safe Boot): $error');
  }

  runApp(const HannuTvApp());
}

class HannuTvApp extends StatefulWidget {
  const HannuTvApp({super.key});

  @override
  State<HannuTvApp> createState() => _HannuTvAppState();
}

class _HannuTvAppState extends State<HannuTvApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();
    try {
      final Uri? initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) _handleDeepLink(initialUri);
    } catch (error) {
      debugPrint('Initial deep-link error: $error');
    }

    _linkSubscription = _appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri != null) _handleDeepLink(uri);
    }, onError: (Object error) {
      debugPrint('Deep-link stream error: $error');
    });
  }

  void _handleDeepLink(Uri uri) {
    if (uri.pathSegments.isEmpty || uri.pathSegments.first != 'watch') return;
    String type = uri.queryParameters['type'] ?? 'movie';
    int id = int.tryParse(uri.queryParameters['id'] ?? '') ?? 0;
    if (uri.pathSegments.length >= 3) {
      type = uri.pathSegments[1];
      id = int.tryParse(uri.pathSegments[2]) ?? id;
    }
    if (id <= 0) return;

    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => SkippableAdScreen(
          adDuration: 10,
          nextScreen: VideoPlayerPage(tmdbId: id, mediaType: type, movieTitle: 'Loading...'),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'HANNUTV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red, brightness: Brightness.dark),
      ),
      home: const SplashScreen(),
    );
  }
}

// 🔥 TERA PURANA SPLASH SCREEN WAAPAS LA DIYA 🔥
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HannuDashboard()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/logo.png', height: 130, errorBuilder: (_, __, ___) => const Text('HANNUTV', style: TextStyle(color: Colors.red, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 2))),
            const SizedBox(height: 50),
            const CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 3),
            const SizedBox(height: 25),
            const Text('Connecting to Secure Servers...', style: TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

/// -------------------------------------------------------------------------
/// 🔥 MISSING HANNUDASHBOARD WALI CLASS YAHAN ADD KAR DI HAI 🔥
class HannuDashboard extends StatefulWidget {
  const HannuDashboard({super.key, this.hooks = const DashboardHooks()});
  final DashboardHooks hooks;
  @override
  State<HannuDashboard> createState() => _HannuDashboardState();
}

class _HannuDashboardState extends State<HannuDashboard> {
  @override
  void initState() {
    super.initState();
    Hooks.cfg = widget.hooks;
  }

  @override
  void didUpdateWidget(covariant HannuDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    Hooks.cfg = widget.hooks;
  }

  void _openSearch() {
    if (widget.hooks.onOpenSearch != null) {
      widget.hooks.onOpenSearch!();
      return;
    }
    openSearch(context);
  }

  void _openLiveTv() {
    if (widget.hooks.onOpenLiveTv != null) {
      widget.hooks.onOpenLiveTv!();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LiveTvScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HC.bg,
      body: CustomScrollView(
        cacheExtent: 1200,
        slivers: <Widget>[
          SliverAppBar(
            pinned: true, floating: true, backgroundColor: HC.bg, surfaceTintColor: Colors.transparent, elevation: 0, titleSpacing: 16,
            title: const Text('HANNUTV', style: TextStyle(color: Colors.redAccent, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
            actions: <Widget>[
              IconButton(tooltip: 'Search', onPressed: _openSearch, icon: const Icon(Icons.search_rounded)),
              IconButton(tooltip: 'Live TV', onPressed: _openLiveTv, icon: const Icon(Icons.live_tv_rounded)),
              IconButton(tooltip: 'Watchlist', onPressed: () => openWatchlist(context), icon: const Icon(Icons.bookmark_outline_rounded)),
              IconButton(tooltip: 'Notifications', onPressed: () => showNotifications(context), icon: const Icon(Icons.notifications_none_rounded)),
              const SizedBox(width: 4),
            ],
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _DashboardHero(onWatchNow: _openLiveTv, onSearch: _openSearch),
                const SizedBox(height: 10),
                const ContinueWatchingRow(),
                PosterRow(title: 'Trending Movies', subtitle: 'This week', width: 124, hideIfEmpty: false, loader: () => Tmdb.I.list('/trending/movie/week', <String, String>{}, count: 30, tv: false)),
                PosterRow(title: 'Trending Web Series', subtitle: 'This week', width: 124, hideIfEmpty: false, loader: () => Tmdb.I.list('/trending/tv/week', <String, String>{}, count: 30, tv: true)),
                const AdSlot(),
                PosterRow(title: 'Popular Movies', subtitle: 'Most watched right now', width: 118, loader: () => Tmdb.I.list('/movie/popular', <String, String>{}, count: 30, tv: false)),
                PosterRow(title: 'Top Rated Movies', subtitle: 'Highest rated', ranked: true, width: 118, loader: () => Tmdb.I.list('/movie/top_rated', <String, String>{}, count: 30, tv: false)),
                PosterRow(title: 'Top Rated Series', subtitle: 'Highest rated web series', ranked: true, width: 118, loader: () => Tmdb.I.list('/tv/top_rated', <String, String>{}, count: 30, tv: true)),
                const _DashboardSectionTitle('Browse Categories'),
                _CategoryGrid(onTap: (CategoryKind kind) => openCategory(context, kind)),
                const SizedBox(height: 8),
                const _DashboardSectionTitle('Browse by Genre'),
                for (final GenreDef genre in kAllGenres) GenreBlock(g: genre, onSeeAll: () => openGenre(context, genre)),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({required this.onWatchNow, required this.onSearch});
  final VoidCallback onWatchNow;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 12), padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[Color(0xFFE50914), Color(0xFF7A0710), Color(0xFF161616)]), borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Unlimited Entertainment', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 8),
          const Text('Movies, web series, anime aur live TV ek hi jagah.', style: TextStyle(fontSize: 14, color: Colors.white70, height: 1.4)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: <Widget>[
              ElevatedButton.icon(onPressed: onWatchNow, icon: const Icon(Icons.live_tv_rounded), label: const Text('Live TV'), style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13))),
              OutlinedButton.icon(onPressed: onSearch, icon: const Icon(Icons.search_rounded), label: const Text('Search'), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13))),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardSectionTitle extends StatelessWidget {
  const _DashboardSectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 10), child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)));
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.onTap});
  final void Function(CategoryKind kind) onTap;

  @override
  Widget build(BuildContext context) {
    const List<_CategoryData> categories = <_CategoryData>[
      _CategoryData(title: 'Movies', icon: Icons.local_movies_rounded, color: Color(0xFFB91C1C), kind: CategoryKind.movies),
      _CategoryData(title: 'Web Series', icon: Icons.tv_rounded, color: Color(0xFF0369A1), kind: CategoryKind.series),
      _CategoryData(title: 'Anime', icon: Icons.animation_rounded, color: Color(0xFF6D28D9), kind: CategoryKind.anime),
      _CategoryData(title: 'Kids', icon: Icons.child_care_rounded, color: Color(0xFF16A34A), kind: CategoryKind.kids),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: categories.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.45),
        itemBuilder: (_, int index) {
          final _CategoryData item = categories[index];
          return InkWell(
            borderRadius: BorderRadius.circular(16), onTap: () => onTap(item.kind),
            child: Ink(
              decoration: BoxDecoration(color: item.color, borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    Icon(item.icon, color: Colors.white, size: 27),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800))),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CategoryData {
  const _CategoryData({required this.title, required this.icon, required this.color, required this.kind});
  final String title;
  final IconData icon;
  final Color color;
  final CategoryKind kind;
}

class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({super.key});
  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> {
  List<Map<String, String>> channels = <Map<String, String>>[];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchChannels();
  }

  Future<void> _fetchChannels() async {
    try {
      final http.Response response = await http.get(Uri.parse('https://raw.githubusercontent.com/Hritik862/Onyxtube/refs/heads/main/assets/channels.json'));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        setState(() {
          channels = data.map((dynamic entry) {
            final Map<dynamic, dynamic> item = entry as Map<dynamic, dynamic>;
            return <String, String>{'name': item['name']?.toString() ?? 'Live TV', 'logo': item['logo']?.toString() ?? '', 'url': item['url']?.toString() ?? ''};
          }).toList();
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (error) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Live TV', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF111111), iconTheme: const IconThemeData(color: Colors.white)),
      body: isLoading ? const Center(child: CircularProgressIndicator(color: Colors.redAccent)) : channels.isEmpty ? const Center(child: Text('No Live Channels Available', style: TextStyle(color: Colors.white))) : GridView.builder(
        padding: const EdgeInsets.all(12), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.85), itemCount: channels.length,
        itemBuilder: (_, int index) {
          final Map<String, String> channel = channels[index];
          final String name = channel['name'] ?? 'Live TV';
          final String logo = channel['logo'] ?? '';
          final String url = channel['url'] ?? '';

          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: url.isEmpty ? null : () {
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SkippableAdScreen(adDuration: 30, nextScreen: VideoPlayerPage(tmdbId: 0, mediaType: 'tv', season: 1, episode: 1, movieTitle: name, overview: 'Live TV Broadcast', rating: 'Live', year: 'Now', customUrl: url))));
            },
            child: Container(
              decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Expanded(child: Padding(padding: const EdgeInsets.all(8), child: logo.isNotEmpty ? CachedNetworkImage(imageUrl: logo, fit: BoxFit.contain, errorWidget: (_, __, ___) => const Icon(Icons.tv, color: Colors.white54, size: 40)) : const Icon(Icons.tv, color: Colors.white54, size: 40))),
                  Container(width: double.infinity, padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.vertical(bottom: Radius.circular(12))), child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}