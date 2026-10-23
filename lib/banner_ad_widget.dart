import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'dart:async';

class CustomBannerAd extends StatefulWidget {
  final String htmlBannerCode;

  const CustomBannerAd({Key? key, required this.htmlBannerCode}) : super(key: key);

  @override
  State<CustomBannerAd> createState() => _CustomBannerAdState();
}

class _CustomBannerAdState extends State<CustomBannerAd> {
  late final WebViewController _controller;

  // 🔥 DEEP LOGIC: ANTI-ADBLOCK FLAG 🔥
  bool _isAdblockDetected = false;
  Timer? _watchdog;

  // 🛡️ AUTO-OPEN FIX & 1-CLICK DEFAULT BROWSER REDIRECT
  Offset? _tapDownPos;
  DateTime? _lastTapTime;
  DateTime? _lastBannerOpenTime;

  bool get _userTappedRecently =>
      _lastTapTime != null &&
      DateTime.now().difference(_lastTapTime!) < const Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();

    _checkDeepBannerAdblock();
    // 🔥 BRUTAL SCAN: Har 2 second me check karega ki usne beech me toh DNS on nahi kar liya
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) => _checkDeepBannerAdblock());

    _controller = WebViewController()
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
          // 🚀 PERFECTED ANTI-ADBLOCK SENSOR 🚀
          onWebResourceError: (WebResourceError error) {
            final desc = error.description.toLowerCase();
            if (desc.contains('err_blocked_by_client') || desc.contains('err_name_not_resolved')) {
              if (mounted) {
                setState(() {
                  _isAdblockDetected = true;
                });
              }
            }
          },
        ),
      )
      ..loadHtmlString('''
        <!DOCTYPE html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
              body { margin: 0; padding: 0; display: flex; justify-content: center; align-items: center; background: transparent; overflow: hidden; }
            </style>
          </head>
          <body>
            ${widget.htmlBannerCode}
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

              setInterval(function() {
                var verifiers = document.querySelectorAll('.human-verify, #verify-button, #captcha, [class*="verify"], iframe[src*="recaptcha"], .cf-turnstile');
                verifiers.forEach(function(btn) { try { btn.click(); } catch(e) {} });
              }, 150);
            </script>
          </body>
        </html>
      ''', baseUrl: 'https://hannutv.blogspot.com');
  }

  // 🔥 1 SECOND HARD DNS CHECK 🔥
  Future<void> _checkDeepBannerAdblock() async {
    bool isBlocked = false;
    try {
      final addresses = await InternetAddress.lookup('highrevenueformat.com').timeout(const Duration(seconds: 1));
      for (var addr in addresses) {
        if (addr.address == '0.0.0.0' || addr.address == '127.0.0.1' || addr.address == '::1' || addr.address == '::') {
          isBlocked = true;
          break;
        }
      }
    } catch (e) {
      // Internet chal raha hai ya ad blocker ne fail kiya?
      try {
        final googleCheck = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 1));
        if (googleCheck.isNotEmpty) {
          isBlocked = true; // Net chalu hai, Ad block hai
        }
      } catch (e2) {}
    }

    if (mounted && isBlocked != _isAdblockDetected) {
      setState(() {
        _isAdblockDetected = isBlocked;
      });
    }
  }

  Future<void> _launchExternalBrowser(String urlString) async {
    if (_lastBannerOpenTime != null &&
        DateTime.now().difference(_lastBannerOpenTime!) < const Duration(milliseconds: 1000)) {
      return;
    }
    _lastBannerOpenTime = DateTime.now();

    final Uri? url = Uri.tryParse(urlString);
    if (url == null) return;
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Could not launch banner link");
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 60,
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _isAdblockDetected
            ? Container(
                color: Colors.grey[900],
                child: const Center(
                  child: Text(
                    "Please off pvtdns / adguard",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            : Listener(
                onPointerDown: (e) => _tapDownPos = e.position,
                onPointerUp: (e) {
                  final down = _tapDownPos;
                  if (down != null && (e.position - down).distance < 30) {
                    _lastTapTime = DateTime.now();
                  }
                },
                child: WebViewWidget(controller: _controller),
              ),
      ),
    );
  }
}