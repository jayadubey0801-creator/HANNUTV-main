import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart'; // 🔥 Update URL Launch karne ke liye

import 'config.dart';
import 'dashboard_screen.dart';
import 'skippable_ad_screen.dart';
import 'tmdb_service.dart';
import 'video_player_page.dart';
import 'widgets.dart';

import 'stores.dart';
import 'pages.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 🔥 APP KA CURRENT VERSION (Tera naya update 1.4.0) 🔥
const String currentAppVersion = "1.4.0"; 

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    debugPrint('Background Notification Hit: \${message.messageId}');
    final AppNotification? n = AppNotification.fromMessage(message);
    if (n != null) await NotificationStore.appendRaw(n);
  } catch (e) {
    debugPrint('Background Error: \$e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp();
    
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(minutes: 1), // Turant update catch karne ke liye
      ),
    );
    
    // 🔥 DEFAULT SETTINGS JO FIREBASE SE MATCH KARENGI 🔥
    await remoteConfig.setDefaults(const {
      'show_ads': true, 
      'maintenance_mode': false,
      'latest_version': '1.4.0',
      'update_link': 'https://hannutv.blogspot.com'
    });
    
    await remoteConfig.fetchAndActivate();
  } catch (error) {
    debugPrint('Firebase Startup error (Bypassed for Safe Boot): \$error');
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
      debugPrint('Initial deep-link error: \$error');
    }

    _linkSubscription = _appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri != null) _handleDeepLink(uri);
    }, onError: (Object error) {
      debugPrint('Deep-link stream error: \$error');
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
        // 🔥 UPDATE AUR MAINTENANCE CHECK LOGIC 🔥
        final remoteConfig = FirebaseRemoteConfig.instance;
        bool maintenanceMode = remoteConfig.getBool('maintenance_mode');
        String latestVer = remoteConfig.getString('latest_version');
        String updateLink = remoteConfig.getString('update_link');

        bool needsUpdate = false;
        try {
          List<int> currentV = currentAppVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
          List<int> latestV = latestVer.split('.').map((e) => int.tryParse(e) ?? 0).toList();
          int len = max(currentV.length, latestV.length);
          for (int i = 0; i < len; i++) {
            int cVal = i < currentV.length ? currentV[i] : 0;
            int lVal = i < latestV.length ? latestV[i] : 0;
            if (lVal > cVal) { needsUpdate = true; break; }
            if (lVal < cVal) break;
          }
        } catch (_) {}

        if (maintenanceMode) {
          // Maintenance mode ON
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MaintenanceScreen()));
        } else if (needsUpdate) {
          // Naya Update aa gaya (Firebase wala version bada hai)
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ForceUpdateScreen(updateUrl: updateLink)));
        } else {
          // Sab perfectly theek hai toh dashboard par jao
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HannuDashboard(
              hooks: DashboardHooks(
                onOpenLiveTv: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveTvScreen()));
                },
                onOpenSearch: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage()));
                }
              ),
            )),
          );
        }
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

// ─────────────────────────────────────────────────────────
// 🔥 FORCE UPDATE & MAINTENANCE SCREENS 🔥
// ─────────────────────────────────────────────────────────

class ForceUpdateScreen extends StatelessWidget {
  final String updateUrl;
  const ForceUpdateScreen({Key? key, required this.updateUrl}) : super(key: key);

  Future<void> _launchUpdateUrl() async {
    final Uri url = Uri.parse(updateUrl);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch \$updateUrl');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Back button daba ke bahar nahi aa payega
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.system_update_rounded, color: Colors.redAccent, size: 100),
                const SizedBox(height: 30),
                const Text("New Update Available!", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 15),
                const Text("Your current version is out of date. Please update to the latest version of HANNUTV to continue watching seamlessly.", style: TextStyle(color: Colors.grey, fontSize: 14), textAlign: TextAlign.center),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity, height: 55,
                  child: ElevatedButton(
                    onPressed: _launchUpdateUrl,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                    child: const Text("Update Now", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.engineering_rounded, color: Colors.amber, size: 100),
                SizedBox(height: 30),
                Text("Under Maintenance", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                SizedBox(height: 15),
                Text("Our servers are currently undergoing maintenance to improve your experience. Please check back later.", style: TextStyle(color: Colors.grey, fontSize: 14), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 🔥 DEEP LIVE TV PARSING CODE (UNCHANGED) 🔥
// ─────────────────────────────────────────────────────────
class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({super.key});
  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> {
  List<Map<String, String>> allChannels = [];
  List<Map<String, String>> displayedChannels = [];
  
  List<String> availableCountries = [];
  String selectedCountry = 'IN'; 

  List<String> categories = ['All'];
  String selectedCategory = 'All';
  
  bool isLoading = true;
  bool isSearching = false;
  TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchChannels();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchChannels() async {
    try {
      final http.Response response = await http.get(Uri.parse('https://iptv-org.github.io/iptv/index.m3u'));
      if (!mounted) return;

      if (response.statusCode == 200) {
        final List<String> lines = response.body.split('\n');
        List<Map<String, String>> tempChannels = [];
        
        String currentName = '';
        String currentLogo = '';
        String currentGroup = 'Uncategorized';
        String currentCountry = 'GLOBAL';

        for (String line in lines) {
          line = line.trim();
          if (line.startsWith('#EXTINF:')) {
            final logoMatch = RegExp(r'tvg-logo="([^"]*)"', caseSensitive: false).firstMatch(line);
            currentLogo = logoMatch != null ? (logoMatch.group(1) ?? '') : '';

            final groupMatch = RegExp(r'group-title="([^"]*)"', caseSensitive: false).firstMatch(line);
            currentGroup = groupMatch != null ? (groupMatch.group(1) ?? 'Uncategorized') : 'Uncategorized';
            if (currentGroup.isEmpty) currentGroup = 'Uncategorized';

            final countryMatch = RegExp(r'tvg-country="([^"]*)"', caseSensitive: false).firstMatch(line);
            if (countryMatch != null && countryMatch.group(1)!.isNotEmpty) {
              currentCountry = countryMatch.group(1)!.toUpperCase();
            } else {
              final idMatch = RegExp(r'tvg-id="([^"]*)"', caseSensitive: false).firstMatch(line);
              if (idMatch != null) {
                final idStr = idMatch.group(1)!;
                if (idStr.contains('.')) {
                  currentCountry = idStr.split('.').last.toUpperCase();
                  if (currentCountry.length > 3) currentCountry = 'GLOBAL';
                } else {
                  currentCountry = 'GLOBAL';
                }
              } else {
                currentCountry = 'GLOBAL';
              }
            }

            final splitByComma = line.split(',');
            if (splitByComma.length > 1) {
              currentName = splitByComma.last.trim();
            } else {
              currentName = 'Live TV';
            }
          } else if (line.isNotEmpty && !line.startsWith('#')) {
            if (line.startsWith('http')) {
              tempChannels.add({
                'name': currentName.isEmpty ? 'Live TV' : currentName,
                'logo': currentLogo,
                'url': line,
                'group': currentGroup,
                'country': currentCountry,
              });
            }
            currentName = '';
            currentLogo = '';
            currentGroup = 'Uncategorized';
            currentCountry = 'GLOBAL';
          }
        }

        if (tempChannels.isNotEmpty) {
          allChannels = tempChannels;
          availableCountries = allChannels.map((c) => c['country']!).toSet().toList();
          availableCountries.sort();

          if (availableCountries.contains('IN')) {
            selectedCountry = 'IN';
          } else if (availableCountries.isNotEmpty) {
            selectedCountry = availableCountries.first;
          }

          _applyFilters();
          setState(() {
            isLoading = false;
          });
          return;
        }
      }
    } catch (error) {
      debugPrint("Live TV Error: \$error");
    }
    setState(() => isLoading = false);
  }

  void _applyFilters() {
    List<Map<String, String>> filtered = allChannels.where((c) => c['country'] == selectedCountry).toList();
    
    Set<String> cats = {'All'};
    for (var c in filtered) {
      cats.add(c['group']!);
    }
    categories = cats.toList();

    if (!categories.contains(selectedCategory)) {
      selectedCategory = 'All';
    }

    if (selectedCategory != 'All') {
      filtered = filtered.where((c) => c['group'] == selectedCategory).toList();
    }

    String query = searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((c) => c['name']!.toLowerCase().contains(query)).toList();
    }

    setState(() {
      displayedChannels = filtered;
    });
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("Select Country", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: availableCountries.length,
                itemBuilder: (ctx, idx) {
                  final c = availableCountries[idx];
                  return ListTile(
                    title: Text(c, style: const TextStyle(color: Colors.white)),
                    trailing: selectedCountry == c ? const Icon(Icons.check, color: Colors.redAccent) : null,
                    onTap: () {
                      setState(() {
                        selectedCountry = c;
                        selectedCategory = 'All'; 
                      });
                      _applyFilters();
                      Navigator.pop(context);
                    }
                  );
                }
              )
            )
          ]
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        iconTheme: const IconThemeData(color: Colors.white),
        title: isSearching
            ? TextField(
                controller: searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search channel...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (v) => _applyFilters(),
              )
            : const Text('Live TV', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(isSearching ? Icons.close : Icons.search_rounded),
            onPressed: () {
              setState(() {
                isSearching = !isSearching;
                if (!isSearching) {
                  searchController.clear();
                  _applyFilters();
                }
              });
            },
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: InkWell(
              onTap: _showCountryPicker,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24)
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.public, color: Colors.redAccent),
                    const SizedBox(width: 10),
                    Text("Choose Your Country : \$selectedCountry", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    const Icon(Icons.arrow_drop_down, color: Colors.white54),
                  ],
                ),
              ),
            ),
          ),
          if (categories.length > 1)
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final isSelected = selectedCategory == categories[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          selectedCategory = categories[index];
                        });
                        _applyFilters();
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: isSelected ? Colors.white : Colors.grey[900], borderRadius: BorderRadius.circular(20)),
                        child: Center(child: Text(categories[index], style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: isLoading 
              ? const Center(child: CircularProgressIndicator(color: Colors.redAccent)) 
              : displayedChannels.isEmpty 
                ? const Center(child: Text('No Live Channels Available', style: TextStyle(color: Colors.white))) 
                : GridView.builder(
                    padding: const EdgeInsets.all(12), 
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.85), 
                    itemCount: displayedChannels.length,
                    itemBuilder: (_, int index) {
                      final Map<String, String> channel = displayedChannels[index];
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
          ),
        ],
      ),
    );
  }
}