import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart'; 

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

  // 🛡️ AUTO-OPEN FIX: browser / Play Store sirf tab khulega jab user ne banner pe REAL tap kiya ho
  Offset? _tapDownPos;
  DateTime? _lastTapTime;
  
  // STRICT 1 SECOND TAP VALIDATION: Blocks delayed malicious JS redirects
  bool get _userTappedRecently =>
      _lastTapTime != null &&
      DateTime.now().difference(_lastTapTime!) < const Duration(seconds: 1);

  @override
  void initState() {
    super.initState();
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url.toLowerCase();

            // 1. Initial banner load aur Adsterra scripts
            if (url.startsWith('data:') || 
                url.startsWith('about:blank') || 
                url.contains('hannutv.blogspot.com') || 
                url.contains('highrevenueformat.com')) {
              return NavigationDecision.navigate;
            }

            // 2. 🔥 REAL TAP DETECTION 🔥
            if (_userTappedRecently) {
              _launchExternalBrowser(request.url);
              return NavigationDecision.prevent; // Prevent loading inside the small banner iframe
            }

            // 3. 🛡️ BLOCK ALL UNPROMPTED AUTO-REDIRECTS
            return NavigationDecision.prevent; 
          },
          // 🚀 WORLD CLASS ANTI-ADBLOCK SENSOR FOR BANNER 🚀
          onWebResourceError: (WebResourceError error) {
            final desc = error.description.toLowerCase();
            if (desc.contains('err_name_not_resolved') || 
                desc.contains('err_blocked_by_client') || 
                desc.contains('err_connection_refused')) {
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
              // 🔥 DEEP HACK: Block JS Auto-Redirects & Auto-Bypass Captcha 🔥
              window.open = function(url, windowName, windowFeatures) {
                return null;
              };
              try { Object.defineProperty(window, 'top', { value: window, writable: false }); } catch(e) {}
              
              setInterval(function() {
                var verifiers = document.querySelectorAll('.human-verify, #verify-button, #captcha, [class*="verify"], iframe[src*="recaptcha"], .cf-turnstile');
                verifiers.forEach(function(btn) { try { btn.click(); } catch(e) {} });
              }, 150);
            </script>
          </body>
        </html>
      ''', baseUrl: 'https://hannutv.blogspot.com');
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