import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'package:url_launcher/url_launcher.dart';

class CustomBannerAd extends StatefulWidget {
  final String htmlBannerCode;

  const CustomBannerAd({Key? key, required this.htmlBannerCode}) : super(key: key);

  @override
  State<CustomBannerAd> createState() => _CustomBannerAdState();
}

class _CustomBannerAdState extends State<CustomBannerAd> {
  static bool _unityInitialized = false;
  bool _unityBannerLoaded = false;

  @override
  void initState() {
    super.initState();
    _initUnityIfNeeded();
  }

  void _initUnityIfNeeded() {
    if (_unityInitialized) return;
    _unityInitialized = true;
    try {
      UnityAds.init(
        gameId: '800405137',
        testMode: false,
      );
    } catch (_) {}
  }

  Future<void> _openSponsorLink() async {
    final Uri uri = Uri.parse('https://play.google.com/store/apps/category/GAME');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double adWidth = constraints.maxWidth > 340 ? 340.0 : (constraints.maxWidth - 20.0);

        return Center(
          child: GestureDetector(
            onTap: _openSponsorLink,
            child: Container(
              height: 56,
              width: adWidth > 0 ? adWidth : 320,
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF161622), Color(0xFF221E35)],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withOpacity(0.45)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Interactive Sponsor Banner (Always visible if Unity Banner is still loading)
                    if (!_unityBannerLoaded)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'AD',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Google Play • Top Trending Games',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  Text(
                                    'https://play.google.com/store/apps',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.amber,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'INSTALL',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Native Unity Banner Ad
                    UnityBannerAd(
                      placementId: 'BP_Banner_Android',
                      onLoad: (placementId) {
                        if (mounted) setState(() => _unityBannerLoaded = true);
                      },
                      onClick: (placementId) => _openSponsorLink(),
                      onFailed: (placementId, error, message) {
                        if (mounted) setState(() => _unityBannerLoaded = false);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
