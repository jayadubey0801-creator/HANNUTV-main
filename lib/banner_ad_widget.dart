import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart'; 
import 'dart:io';
import 'dart:async'; // 🔥 Timer ke liye add kiya

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
  Timer? _watchdog; // 🔥 Har second scan karne wala kuta 🐕
  bool _checking = false; // 🔧 ek time pe ek hi DNS check
  int _failStreak = 0; // 🔧 lagatar kitni baar domain resolve nahi hua

  // 🛡️ AUTO-OPEN FIX
  Offset? _tapDownPos;
  DateTime? _lastTapTime;
  
  // STRICT 1 SECOND TAP VALIDATION
  bool get _userTappedRecently =>
      _lastTapTime != null &&
      DateTime.now().difference(_lastTapTime!) < const Duration(seconds: 1);

  @override
  void initState() {
    super.initState();
    
    _checkDeepBannerAdblock(); 
    // 🔥 BRUTAL SCAN: Har 2 second me check karega ki usne beech me toh DNS on nahi kar liya
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) => _checkDeepBannerAdblock());
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url.toLowerCase();

            if (url.startsWith('data:') || 
                url.startsWith('about:blank') || 
                url.contains('hannutv.blogspot.com') || 
                url.contains('highrevenueformat.com')) {
              return NavigationDecision.navigate;
            }

            if (_userTappedRecently) {
              _launchExternalBrowser(request.url);
              return NavigationDecision.prevent; 
            }

            return NavigationDecision.prevent; 
          },
          // 🚀 PERFECTED ANTI-ADBLOCK SENSOR 🚀
          onWebResourceError: (WebResourceError error) {
            final desc = error.description.toLowerCase();
            if (desc.contains('err_blocked_by_client')) {
              if (mounted) {
                setState(() {
                  _isAdblockDetected = true; 
                });
              }
            } else if (desc.contains('err_name_not_resolved')) {
              // 🔧 ek resource ka DNS error = slow net bhi ho sakta hai → seedha block mat karo, sirf verify karo
              _checkDeepBannerAdblock();
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
              window.open = function(url, windowName, windowFeatures) {
                return null;
              };
              try { Object.defineProperty(window, 'top', { value: window, writable: false }); } catch(e) {}
              
            </script>
          </body>
        </html>
      ''', baseUrl: 'https://hannutv.blogspot.com');
  }

  // 🔧 FIXED DNS CHECK
  // Pehle: 1 second me domain resolve na ho (slow net / slow DNS) aur google.com ho jaye => "adblock" maan leta tha,
  // aur real users ka banner hat ke warning aa jaati thi => impressions/earning loss.
  // Ab: sinkhole (0.0.0.0 / 127.x) => turant block. Resolve fail => 4 sec timeout + lagatar 3 baar fail hone par hi block.
  Future<void> _checkDeepBannerAdblock() async {
    if (_checking || !mounted) return;
    _checking = true;
    bool isBlocked = false;
    try {
      bool resolved = false;
      try {
        final addresses = await InternetAddress.lookup('highrevenueformat.com').timeout(const Duration(seconds: 4));
        resolved = addresses.isNotEmpty;
        for (var addr in addresses) {
          if (addr.address == '0.0.0.0' || addr.address == '127.0.0.1' || addr.address == '::1' || addr.address == '::') {
            isBlocked = true;
            break;
          }
        }
      } catch (e) {
        resolved = false;
      }

      if (isBlocked || resolved) {
        _failStreak = 0;
      } else {
        // Domain resolve nahi hua: internet chal raha hai ya nahi?
        bool netOk = false;
        try {
          final googleCheck = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 4));
          netOk = googleCheck.isNotEmpty;
        } catch (e2) {}
        _failStreak = netOk ? _failStreak + 1 : 0; // net band hai to adblock mat maano
        isBlocked = _failStreak >= 3;
      }
    } finally {
      _checking = false;
    }

    if (mounted && isBlocked != _isAdblockDetected) {
      setState(() {
        _isAdblockDetected = isBlocked;
      });
    }
  }

  Future<void> _launchExternalBrowser(String urlString) async {
    final Uri url = Uri.parse(urlString);
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
                    style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)
                  )
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