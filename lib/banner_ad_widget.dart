import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'unity_ads_service.dart';

const String _kDefaultBannerSnippet = '''
<script type="text/javascript">
  atOptions = { 'key' : 'a39df283f6ad10c34e229e5715bceff5', 'format' : 'iframe', 'height' : 50, 'width' : 320, 'params' : {} };
</script>
<script type="text/javascript" src="https://www.highrevenueformat.com/a39df283f6ad10c34e229e5715bceff5/invoke.js"></script>
''';

class CustomBannerAd extends StatefulWidget {
  final String htmlBannerCode;

  const CustomBannerAd({
    Key? key,
    this.htmlBannerCode = _kDefaultBannerSnippet,
  }) : super(key: key);

  @override
  State<CustomBannerAd> createState() => _CustomBannerAdState();
}

class _CustomBannerAdState extends State<CustomBannerAd> {
  late final WebViewController _webController;

  bool _isUnityInit = false;
  bool _unityBannerLoaded = false;
  bool _isAdblockDetected = false;

  Timer? _watchdog;
  Timer? _unityRetryTimer;

  Offset? _tapDownPos;
  DateTime? _lastTapTime;
  DateTime? _lastLaunchTime;

  bool get _userTappedRecently =>
      _lastTapTime != null &&
      DateTime.now().difference(_lastTapTime!) < const Duration(milliseconds: 1500);

  String get _effectiveHtml =>
      widget.htmlBannerCode.trim().isNotEmpty ? widget.htmlBannerCode : _kDefaultBannerSnippet;

  @override
  void initState() {
    super.initState();

    _checkDeepBannerAdblock();
    _watchdog = Timer.periodic(const Duration(seconds: 3), (_) => _checkDeepBannerAdblock());

    _initUnityBanner();
    _initWebViewBanner();
  }

  void _initUnityBanner() {
    UnityAdsService.init().then((ok) {
      if (mounted) {
        setState(() => _isUnityInit = true);
      }
    });
  }

  void _initWebViewBanner() {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'BannerBridge',
        onMessageReceived: (JavaScriptMessage msg) {
          final String url = msg.message.trim();
          if (_userTappedRecently && url.isNotEmpty && url != 'about:blank') {
            _launchExternalBrowser(url);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final String rawUrl = request.url;
            final String url = rawUrl.toLowerCase();

            if (url.startsWith('data:') ||
                url.startsWith('about:blank') ||
                url.contains('hannutv.blogspot.com') ||
                (url.contains('highrevenueformat.com') && !_userTappedRecently)) {
              return NavigationDecision.navigate;
            }

            if (_userTappedRecently) {
              _launchExternalBrowser(rawUrl);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            final desc = error.description.toLowerCase();
            if (desc.contains('err_blocked_by_client')) {
              if (mounted) setState(() => _isAdblockDetected = true);
            }
          },
        ),
      )
      ..loadHtmlString(
        '''
        <!DOCTYPE html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
              * { margin: 0; padding: 0; box-sizing: border-box; }
              html, body {
                width: 320px;
                height: 50px;
                margin: 0 auto;
                display: flex;
                justify-content: center;
                align-items: center;
                background: transparent;
                overflow: hidden;
              }
            </style>
          </head>
          <body>
            $_effectiveHtml
            <script>
              try { Object.defineProperty(window, 'top', { value: window, writable: false }); } catch(e) {}

              window.open = function(url) {
                if (url) {
                  try {
                    var full = new URL(url, window.location.href).href;
                    BannerBridge.postMessage(full);
                  } catch(e) {
                    BannerBridge.postMessage(url.toString());
                  }
                }
                return null;
              };

              document.addEventListener('click', function(e) {
                var a = e.target ? e.target.closest('a') : null;
                if (a && a.href && a.href.indexOf('javascript:') === -1) {
                  e.preventDefault();
                  e.stopPropagation();
                  try { BannerBridge.postMessage(a.href); } catch(err) {}
                  return false;
                }
              }, true);
            </script>
          </body>
        </html>
        ''',
        baseUrl: 'https://hannutv.blogspot.com',
      );

    final platform = _webController.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
  }

  Future<void> _checkDeepBannerAdblock() async {
    bool isBlocked = false;
    try {
      final addresses = await InternetAddress.lookup('highrevenueformat.com')
          .timeout(const Duration(seconds: 2));
      for (var addr in addresses) {
        if (addr.address == '0.0.0.0' ||
            addr.address == '127.0.0.1' ||
            addr.address == '::1' ||
            addr.address == '::') {
          isBlocked = true;
          break;
        }
      }
    } catch (_) {
      try {
        final googleCheck = await InternetAddress.lookup('google.com')
            .timeout(const Duration(seconds: 2));
        if (googleCheck.isNotEmpty) {
          isBlocked = true;
        }
      } catch (_) {}
    }

    if (mounted && isBlocked != _isAdblockDetected) {
      setState(() => _isAdblockDetected = isBlocked);
    }
  }

  Future<void> _launchExternalBrowser(String urlString) async {
    if (_lastLaunchTime != null &&
        DateTime.now().difference(_lastLaunchTime!) < const Duration(milliseconds: 1000)) {
      return;
    }
    _lastLaunchTime = DateTime.now();

    final Uri? url = Uri.tryParse(urlString);
    if (url == null) return;
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch banner link: $e');
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _unityRetryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Exact 320x50 inner space without extra vertical margin so AdSlot (height: 62) never clips it!
    return Center(
      child: Container(
        width: 324,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF14141F),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _isAdblockDetected
              ? Container(
                  color: Colors.grey[900],
                  alignment: Alignment.center,
                  child: const Text(
                    "Please off pvtdns / adguard",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : SizedBox(
                  width: 320,
                  height: 50,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Layer 1: Always-ready Adsterra 320x50 Banner (taaki box kabhi khali na rahe)
                      Positioned.fill(
                        child: Listener(
                          onPointerDown: (e) => _tapDownPos = e.position,
                          onPointerUp: (e) {
                            final down = _tapDownPos;
                            if (down != null && (e.position - down).distance < 30) {
                              _lastTapTime = DateTime.now();
                            }
                          },
                          child: WebViewWidget(controller: _webController),
                        ),
                      ),

                      // Layer 2: Unity Banner Ad (jab load ho jaye toh upar dikhega)
                      if (_isUnityInit)
                        IgnorePointer(
                          ignoring: !_unityBannerLoaded,
                          child: Opacity(
                            opacity: _unityBannerLoaded ? 1.0 : 0.0,
                            child: UnityBannerAd(
                              placementId: UnityAdsService.bannerPlacement,
                              size: BannerSize.standard,
                              onLoad: (id) {
                                debugPrint('[UnityBanner] Loaded: $id');
                                if (mounted) {
                                  setState(() => _unityBannerLoaded = true);
                                }
                              },
                              onClick: (id) => debugPrint('[UnityBanner] Clicked: $id'),
                              onShown: (id) => debugPrint('[UnityBanner] Shown: $id'),
                              onFailed: (id, error, message) {
                                debugPrint('[UnityBanner] Failed: $id | $error | $message');
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
      ),
    );
  }
}