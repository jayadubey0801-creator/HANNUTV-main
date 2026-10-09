import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_analytics/firebase_analytics.dart'; 
import 'package:app_links/app_links.dart'; 
import 'package:package_info_plus/package_info_plus.dart'; 
import 'package:url_launcher/url_launcher.dart'; 

// 🔥 MODULE IMPORTS (Tumhari nayi files) 🔥
import 'dashboard_screen.dart'; 
import 'widgets.dart'; 
import 'tmdb_service.dart'; 
import 'video_player_page.dart';
import 'skippable_ad_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("🔥 Background Notification Hit: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp();

  // 🚀 LIVE ANALYTICS INITIALIZATION
  FirebaseAnalytics analytics = FirebaseAnalytics.instance;
  analytics.logEvent(name: 'app_open_hannutv_v1_3_0');

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  FirebaseMessaging messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(
    alert: true,
    announcement: true,
    badge: true,
    carPlay: false,
    criticalAlert: true,
    provisional: false,
    sound: true,
  );

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true, 
    badge: true, 
    sound: true, 
  );

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('🔥 Foreground Notification Hit!');
  });

  messaging.getToken().then((token) {
    debugPrint("📲 FIREBASE DEVICE TOKEN: $token");
  });

  runApp(const HannuTvApp());
}

class HannuTvApp extends StatelessWidget {
  const HannuTvApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const HannuTvAppWrapper();
  }
}

class HannuTvAppWrapper extends StatefulWidget {
  const HannuTvAppWrapper({Key? key}) : super(key: key);
  @override
  State<HannuTvAppWrapper> createState() => _HannuTvAppWrapperState();
}

class _HannuTvAppWrapperState extends State<HannuTvAppWrapper> {
  late AppLinks _appLinks; 
  StreamSubscription<Uri>? _sub;

  @override
  void initState() {
    super.initState();
    _initDeepLinkListener(); 
  }

  void _initDeepLinkListener() async {
    _appLinks = AppLinks();
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) _handleDeepLink(initialUri);
    } catch (e) { debugPrint(e.toString()); }

    _sub = _appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri != null) _handleDeepLink(uri);
    }, onError: (err) {});
  }

  void _handleDeepLink(Uri uri) {
    if (uri.path.contains('/watch')) {
      String? idStr = uri.queryParameters['id'];
      String? type = uri.queryParameters['type'] ?? 'movie';
      if (idStr != null) {
        int id = int.tryParse(idStr) ?? 0;
        if (id != 0) {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => VideoPlayerPage(
                tmdbId: id, mediaType: type, movieTitle: "Shared Stream",
              )
            )
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
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

// ── SPLASH SCREEN (Deep Kill Switch, Anti-Space Bug & Version Logic) ──
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool isMaintenance = false;
  bool isUpdateRequired = false; 
  String maintenanceMsg = "System Upgrade in Progress. Please update HANNUTV.";
  String updateLink = "https://hannutv.blogspot.com/"; 
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    checkMaintenance();
  }

  Future<void> checkMaintenance() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 15),
        minimumFetchInterval: const Duration(seconds: 0), 
      ));
      await remoteConfig.fetchAndActivate();

      // Firebase se values fetch ho rahi hain, but abhi testing ke liye hum unhe ignore karenge
      String fbUpdateLink = remoteConfig.getString('update_link').trim();
      String fbMsg = remoteConfig.getString('maintenance_message').trim();

      setState(() {
        // 🔥 TESTING BYPASS: Isko false set kar diya taaki screen block na ho 🔥
        isMaintenance = false; 
        isUpdateRequired = false; 
        
        if (fbUpdateLink.isNotEmpty) updateLink = fbUpdateLink;
        if (fbMsg.isNotEmpty) maintenanceMsg = fbMsg;
      });
    } catch (e) {
      debugPrint("⚠️ Remote Config Error: $e");
    }

    // 🔥 TESTING BYPASS: Seedha Dashboard par bhej rahe hain 🔥
    Timer(const Duration(milliseconds: 2500), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HannuDashboard(
            hooks: DashboardHooks(
              onOpenTitle: (ctx, TmdbItem item) {
                Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => SkippableAdScreen(
                      adDuration: 10,
                      nextScreen: VideoPlayerPage(
                        tmdbId: item.id,
                        mediaType: item.isTv ? 'tv' : 'movie',
                        movieTitle: item.title,
                        overview: item.overview,
                        rating: item.rating.toStringAsFixed(1),
                        year: item.year,
                      ),
                    ),
                  ),
                );
              },
              onOpenLiveTv: () {
                Navigator.push(
                  context, 
                  MaterialPageRoute(builder: (_) => const LiveTvChannelsPage())
                );
              },
            ),
          ),
        ), 
      );
    });
  }

  Future<void> _launchUpdateURL() async {
    try {
      final Uri url = Uri.parse(updateLink);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        debugPrint('Could not launch $url');
      }
    } catch (e) {
      debugPrint('URL Launch Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Yeh screen abhi kabhi show nahi hogi kyunki update bypass kar diya gaya hai
    if ((isMaintenance || isUpdateRequired) && !isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_rounded, color: Colors.redAccent, size: 85),
                const SizedBox(height: 25),
                const Text(
                  'MANDATORY UPDATE',
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                ),
                const SizedBox(height: 15),
                Text(
                  maintenanceMsg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
                ),
                const SizedBox(height: 45),
                ElevatedButton.icon(
                  onPressed: _launchUpdateURL,
                  icon: const Icon(Icons.download, color: Colors.white),
                  label: const Text(
                    "UPDATE NOW",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logo.png',
              height: 130,
              errorBuilder: (_, __, ___) => const Text(
                'HANNUTV',
                style: TextStyle(color: Colors.red, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 2),
              ),
            ),
            const SizedBox(height: 50),
            const CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 3),
            const SizedBox(height: 25),
            const Text(
              'Connecting to Secure Servers...',
              style: TextStyle(color: Colors.grey, fontSize: 14, letterSpacing: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// 🔥 LIVE TV CHANNELS (Restored here so it won't break if dashboard.dart is deleted) 🔥
// =====================================================================
class LiveTvChannelsPage extends StatefulWidget {
  const LiveTvChannelsPage({super.key});
  @override
  State<LiveTvChannelsPage> createState() => LiveTvChannelsPageState();
}
class LiveTvChannelsPageState extends State<LiveTvChannelsPage> {
  List<Map<String, String>> allChannels = [];
  List<Map<String, String>> filteredChannels = [];
  bool isLoading = true;
  final TextEditingController tvSearchController = TextEditingController();
  List<String> categories = ['All'];
  Map<String, int> categoryCounts = {};
  String selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    fetchIptvData();
  }

  Future<void> fetchIptvData() async {
    try {
      final response = await http.get(Uri.parse('https://iptv-org.github.io/iptv/index.category.m3u'));
      if (response.statusCode == 200) {
        List<String> lines = response.body.split('\n');
        final Map<String, Map<String, String>> byUrl = {}; 
        final Map<String, Set<String>> catsByUrl = {};
        String currentName = ''; String currentLogo = ''; String currentGroup = '';

        for (String rawLine in lines) {
          final String line = rawLine.trim();
          if (line.startsWith('#EXTINF:')) {
            RegExp logoRegex = RegExp(r'tvg-logo="([^"]*)"');
            var match = logoRegex.firstMatch(line);
            currentLogo = match != null ? match.group(1)! : '';
            var groupMatch = RegExp(r'group-title="([^"]*)"').firstMatch(line);
            currentGroup = groupMatch != null ? groupMatch.group(1)!.trim() : '';
            List<String> splitComma = line.split(',');
            if (splitComma.length > 1) currentName = splitComma.last.trim();
          } else if (line.startsWith('http')) {
            if (currentName.isNotEmpty) {
              final cats = currentGroup.split(';').map((c) => c.trim()).where((c) => c.isNotEmpty).map((c) => c.toLowerCase() == 'undefined' ? 'Other' : c).toList();
              if (cats.isEmpty) cats.add('Other');
              if (!cats.any((c) => c.toLowerCase() == 'xxx')) {
                byUrl.putIfAbsent(line, () => {'name': currentName, 'logo': currentLogo, 'url': line});
                catsByUrl.putIfAbsent(line, () => <String>{}).addAll(cats);
              }
            }
          }
        }

        final List<Map<String, String>> parsed = [];
        final Map<String, int> counts = {};
        byUrl.forEach((url, ch) {
          final cats = catsByUrl[url]!;
          ch['group'] = cats.join(';');
          for (final c in cats) { counts[c] = (counts[c] ?? 0) + 1; }
          parsed.add(ch);
        });

        final List<String> sortedCats = counts.keys.toList()..sort((a, b) {
            if (a == 'Other') return 1;
            if (b == 'Other') return -1;
            return counts[b]!.compareTo(counts[a]!);
          });

        setState(() {
          allChannels = parsed; filteredChannels = parsed; categoryCounts = counts;
          categories = ['All', ...sortedCats]; isLoading = false;
        });
      }
    } catch (_) { setState(() => isLoading = false); }
  }

  void filterChannels(String query) {
    setState(() {
      filteredChannels = allChannels.where((c) {
        final matchesName = c['name']!.toLowerCase().contains(query.toLowerCase());
        final matchesCategory = selectedCategory == 'All' || (c['group'] ?? '').split(';').contains(selectedCategory);
        return matchesName && matchesCategory;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(backgroundColor: const Color(0xFF151515), title: const Text('Live TV Channels', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), iconTheme: const IconThemeData(color: Colors.white)),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.all(16.0), child: TextField(controller: tvSearchController, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Search Live Channels...', hintStyle: const TextStyle(color: Colors.grey), filled: true, fillColor: Colors.black87, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), prefixIcon: const Icon(Icons.search, color: Colors.redAccent)), onChanged: filterChannels)),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final cat = categories[i]; final bool selected = cat == selectedCategory;
                return ChoiceChip(label: Text('$cat (${cat == 'All' ? allChannels.length : categoryCounts[cat]})'), selected: selected, selectedColor: Colors.redAccent, backgroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Colors.white12), labelStyle: TextStyle(color: Colors.white, fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.normal), onSelected: (_) { selectedCategory = cat; filterChannels(tvSearchController.text); });
              },
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
                : GridView.builder(
                    padding: const EdgeInsets.all(16), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.8), itemCount: filteredChannels.length,
                    itemBuilder: (context, index) {
                      final ch = filteredChannels[index];
                      return InkWell(
                        onTap: () { Navigator.push(context, MaterialPageRoute(builder: (context) => SkippableAdScreen(adDuration: 30, nextScreen: VideoPlayerPage(tmdbId: 0, mediaType: 'tv', season: 1, episode: 1, movieTitle: ch['name']!, overview: 'Live TV Broadcast', rating: 'Live', year: 'Now', customUrl: ch['url'])))); },
                        child: Container(
                          decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Expanded(child: Padding(padding: const EdgeInsets.all(8.0), child: ch['logo']!.isNotEmpty ? CachedNetworkImage(imageUrl: ch['logo']!, errorWidget: (_, __, ___) => const Icon(Icons.tv, color: Colors.white54, size: 40)) : const Icon(Icons.tv, color: Colors.white54, size: 40))), Container(padding: const EdgeInsets.all(8), width: double.infinity, decoration: const BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.vertical(bottom: Radius.circular(12))), child: Text(ch['name']!, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center))]),
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
