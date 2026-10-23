import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CustomBannerAd extends StatefulWidget {
  final String htmlBannerCode;

  const CustomBannerAd({Key? key, required this.htmlBannerCode})
      : super(key: key);

  @override
  State<CustomBannerAd> createState() => _CustomBannerAdState();
}

class _CustomBannerAdState extends State<CustomBannerAd> {
  static bool _unityInitialized = false;
  bool _unityBannerLoaded = false;
  late final WebViewController _webController;

  static const String kUnityGameId = '800405137';
  static const String kUnityBannerId = 'BP_Banner_Android';
  static const String _fallbackDirectLink =
      'https://www.profitableratecpmnetwork.com/qftskbqkm?key=6a0072dfddbd45e6f448fa2a00d2df90';

  @override
  void initState() {
    super.initState();
    _initUnityIfNeeded();

    final String fullHtml = '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body {
            width: 100%;
            height: 100%;
            background-color: transparent;
            overflow: hidden;
            display: flex;
            align-items: center;
            justify-content: center;
          }
        </style>
      </head>
      <body>
        ${widget.htmlBannerCode}
        <script>
          window.open = function(u) {
            if (u) { try { BannerClickBridge.postMessage(u.toString()); } catch(e) {} }
            return null;
          };
          document.addEventListener('click', function(e) {
            var a = e.target ? e.target.closest('a') : null;
            if (a && a.href && a.href.indexOf('javascript:') === -1) {
              e.preventDefault();
              try { BannerClickBridge.postMessage(a.href); } catch(err) {}
            }
          }, true);
        </script>
      </body>
      </html>
    ''';

    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'BannerClickBridge',
        onMessageReceived: (JavaScriptMessage msg) {
          final String url = msg.message.trim();
          if (url.startsWith('http')) {
            _openInDefaultBrowser(url);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final String url = request.url;
            if (url.startsWith('http') &&
                !url.contains('highrevenueformat.com') &&
                !url.contains('about:blank')) {
              _openInDefaultBrowser(url);
              return NavigationDecision.prevent;
            }
            if (url.startsWith('intent://') || url.startsWith('market://')) {
              _openInDefaultBrowser(url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(fullHtml);
  }

  void _initUnityIfNeeded() {
    if (_unityInitialized) return;
    _unityInitialized = true;
    try {
      UnityAds.init(
        gameId: kUnityGameId,
        testMode: false,
      );
    } catch (_) {}
  }

  Future<void> _openInDefaultBrowser(String urlString) async {
    final Uri? uri = Uri.tryParse(urlString);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(
          Uri.parse(_fallbackDirectLink),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 320,
        height: 55,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. Real Adsterra 320x50 HTML Banner WebView
              Positioned.fill(
                child: WebViewWidget(controller: _webController),
              ),

              // 2. Unity Banner Ad (BP_Banner_Android) — only intercepts touches when loaded
              IgnorePointer(
                ignoring: !_unityBannerLoaded,
                child: Opacity(
                  opacity: _unityBannerLoaded ? 1.0 : 0.0,
                  child: UnityBannerAd(
                    placementId: kUnityBannerId,
                    onLoad: (placementId) {
                      if (mounted) {
                        setState(() => _unityBannerLoaded = true);
                      }
                    },
                    onClick: (placementId) {},
                    onFailed: (placementId, error, message) {
                      if (mounted) {
                        setState(() => _unityBannerLoaded = false);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}