import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'dart:io'; 
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart'; 

class SkippableAdScreen extends StatefulWidget {
  final Widget nextScreen; 
  final int adDuration; 

  const SkippableAdScreen({
    Key? key, 
    required this.nextScreen,
    this.adDuration = 10, // 🚀 FIXED TO 10 SECONDS FOR MOVIES (Live TV dynamically overrides this)
  }) : super(key: key);

  @override
  State<SkippableAdScreen> createState() => _SkippableAdScreenState();
}

class _SkippableAdScreenState extends State<SkippableAdScreen> {
  late final WebViewController _controller;
  late int _timeLeft; 
  bool _canSkip = false;
  Timer? _timer;

  // 🔥 DEEP LOGIC: ANTI-ADBLOCK FLAG 🔥
  bool _isAdblockDetected = false;

  // 🛡️ STRICT 1 SECOND TAP VALIDATION
  Offset? _tapDownPos;
  DateTime? _lastTapTime;
  bool get _userTappedRecently =>
      _lastTapTime != null &&
      DateTime.now().difference(_lastTapTime!) < const Duration(seconds: 1);

  final List<String> _fullScreenAdLinks = [
    "https://omg10.com/4/11914244", 
    "https://omg10.com/4/11914245", 
    "https://www.profitableratecpmnetwork.com/qftskbqkm?key=6a0072dfddbd45e6f448fa2a00d2df90" 
  ];

  @override
  void initState() {
    super.initState();
    _timeLeft = widget.adDuration; 
    
    final _random = Random();
    String selectedAd = _fullScreenAdLinks[_random.nextInt(_fullScreenAdLinks.length)];

    // 🚀 TRAP 1: APP START HOTE HI DNS CHECK KAREGA 🚀
    _checkAdGuardDNS(selectedAd);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            // 🔥 JS INJECTION: CAPTCHA KILLER & JS POPUP KILLER 🔥
            _controller.runJavaScript('''
              window.open = function() { return null; };
              try { Object.defineProperty(window, 'top', { value: window, writable: false }); } catch(e) {}
              setInterval(function() {
                var verifiers = document.querySelectorAll('.human-verify, #verify-button, #captcha, [class*="verify"], iframe[src*="recaptcha"], .cf-turnstile');
                verifiers.forEach(function(btn) { try { btn.click(); } catch(e) {} });
              }, 150);
            ''');
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url.toLowerCase();
            
            // 🔥 AGGRESSIVE ANTI-REDIRECT: PLAY STORE AUR INTENTS KO PAKDEGA 🔥
            if (url.startsWith('intent://') || 
                url.startsWith('market://') || 
                url.contains('play.google.com') ||
                url.contains('play.app.goo.gl') ||
                url.startsWith('whatsapp://') ||
                url.startsWith('tg://')) {
              
              if (_userTappedRecently) _launchExternalBrowser(request.url);
              return NavigationDecision.prevent; 
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            final desc = error.description.toLowerCase();
            if (desc.contains('net::err_') || desc.contains('blocked') || desc.contains('refused') || desc.contains('resolved') || desc.contains('closed')) {
              _triggerBlock();
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(selectedAd));

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft > 0) {
        if (mounted) setState(() => _timeLeft--);
      } else {
        if (mounted) setState(() => _canSkip = true);
        _timer?.cancel();
      }
    });
  }

  Future<void> _checkAdGuardDNS(String adUrl) async {
    try {
      final uri = Uri.parse(adUrl);
      final addresses = await InternetAddress.lookup(uri.host);
      bool blocked = false;
      for (var addr in addresses) {
        if (addr.address == '0.0.0.0' || addr.address == '127.0.0.1' || addr.address == '::1') {
          blocked = true;
          break;
        }
      }
      if (blocked || addresses.isEmpty) {
        _triggerBlock(); 
      }
    } catch (e) {
      _triggerBlock(); 
    }
  }

  void _triggerBlock() {
    if (mounted) {
      setState(() {
        _isAdblockDetected = true;
        _timer?.cancel(); 
        _canSkip = false; 
      });
    }
  }

  Future<void> _launchExternalBrowser(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Could not launch $urlString");
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _skipAd() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => widget.nextScreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, 
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Listener(
                onPointerDown: (e) => _tapDownPos = e.position,
                onPointerUp: (e) {
                  final down = _tapDownPos;
                  if (down != null && (e.position - down).distance < 30) {
                    _lastTapTime = DateTime.now();
                  }
                },
                child: WebViewWidget(controller: _controller),
              ),
              
              if (_isAdblockDetected)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.98), 
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: 80),
                        SizedBox(height: 20),
                        Text(
                          "AdBlocker Detected!", 
                          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)
                        ),
                        SizedBox(height: 12),
                        Text(
                          "Please off pvtdns / adguard\nto continue watching.", 
                          textAlign: TextAlign.center, 
                          style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)
                        ),
                      ],
                    ),
                  ),
                ),
              
              Positioned(
                top: 15,
                right: 15,
                child: GestureDetector(
                  onTap: (_canSkip && !_isAdblockDetected) ? _skipAd : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: (_canSkip && !_isAdblockDetected) ? Colors.white : Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: (_canSkip && !_isAdblockDetected) ? Colors.white : Colors.grey),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isAdblockDetected 
                              ? "Loading..." 
                              : (_canSkip ? "Skip Ad" : "Skip in $_timeLeft"),
                          style: TextStyle(
                            color: (_canSkip && !_isAdblockDetected) ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (_canSkip && !_isAdblockDetected) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.skip_next, color: Colors.black, size: 20),
                        ]
                      ],
                    ),
                  ),
                ),
              ),

              Positioned(
                bottom: 20, left: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4)),
                  child: const Text("Ad", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  } 
}