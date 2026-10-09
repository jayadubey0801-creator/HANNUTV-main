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

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Background Error: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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
    debugPrint('Firebase Startup error (Bypassed for Safe Boot): $error');
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
          MaterialPageRoute(builder: (context) => HannuDashboard(
            // 🔥 YAHAN TERI LIVE TV SCREEN CONNECT HO GAYI HAI 🔥
            hooks: DashboardHooks(
              onOpenLiveTv: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveTvScreen()));
              }
            ),
          )),
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