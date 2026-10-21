import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CustomBannerAd extends StatefulWidget {
  final String htmlBannerCode;

  const CustomBannerAd({Key? key, required this.htmlBannerCode}) : super(key: key);

  @override
  State<CustomBannerAd> createState() => _CustomBannerAdState();
}

class _CustomBannerAdState extends State<CustomBannerAd> {
  static bool _unityInitialized = false;
  bool _unityBannerLoaded = false;
  late final WebViewController _webController;
  bool _webBannerReady = false;

  @override
  void initState() {
    super.initState();
    _initUnityIfNeeded();
    _initWebBanner();
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

  void _initWebBanner() {
    final String snippet = widget.htmlBannerCode.trim().isNotEmpty
        ? widget.htmlBannerCode
        : '''
          <script type="text/javascript">
            atOptions = { 'key' : 'a39df283f6ad10c34e229e5715bceff5', 'format' : 'iframe', 'height' : 50, 'width' : 320, 'params' : {} };
          </script>
          <script type="text/javascript" src="https://www.highrevenueformat.com/a39df283f6ad10c34e229e5715bceff5/invoke.js"></script>
        ''';

    final String fullHtml = '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body {
            width: 320px;
            height: 50px;
            background: transparent;
            overflow: hidden;
            display: flex;
            align-items: center;
            justify-content: center;
          }
        </style>
      </head>
      <body>
        $snippet
      </body>
      </html>
    ''';

    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _webBannerReady = true);
          },
          onNavigationRequest: (NavigationRequest req) {
            final String u = req.url;
            if (!req.isMainFrame ||
                u.contains('highrevenueformat.com') ||
                u.contains('about:blank')) {
              return NavigationDecision.navigate;
            }
            if (u.startsWith('http://') ||
                u.startsWith('https://') ||
                u.startsWith('market://') ||
                u.startsWith('intent://')) {
              _openExternalAdLink(u);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(fullHtml);
  }

  Future<void> _openExternalAdLink(String rawUrl) async {
    final Uri? uri = Uri.tryParse(rawUrl);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: 54,
        width: 320,
        margin: const EdgeInsets.symmetric(vertical: 4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF151525), Color(0xFF1E1B32)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber.withOpacity(0.38)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Layer 1: Guaranteed Interactive Sponsor Banner (Always visible if network/Unity is loading)
            GestureDetector(
              onTap: () => _openExternalAdLink(
                  'https://play.google.com/store/apps/category/GAME'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'AD',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
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
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'https://play.google.com/store/apps',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'INSTALL',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Layer 2: Live HTML Iframe Ad Banner
            if (_webBannerReady)
              Positioned.fill(
                child: WebViewWidget(controller: _webController),
              ),

            // Layer 3: Official Unity Banner Ad (BP_Banner_Android)
            Positioned.fill(
              child: Opacity(
                opacity: _unityBannerLoaded ? 1.0 : 0.01,
                child: UnityBannerAd(
                  placementId: 'BP_Banner_Android',
                  onLoad: (placementId) {
                    if (mounted) setState(() => _unityBannerLoaded = true);
                  },
                  onClick: (placementId) =>
                      debugPrint('Unity Banner clicked: $placementId'),
                  onFailed: (placementId, error, message) {
                    if (mounted) setState(() => _unityBannerLoaded = false);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}