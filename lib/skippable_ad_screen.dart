import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'dart:io'; 
import 'dart:convert';
import 'package:http/http.dart' as http;
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
  bool _clientBlocked = false; // WebView ke andar ka blocker (sticky)
  bool _checking = false;
  Timer? _watchdog;
  late String _selectedAd;

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
    _selectedAd = _fullScreenAdLinks[_random.nextInt(_fullScreenAdLinks.length)];
    final String selectedAd = _selectedAd;

    // 🚀 TRAP: turant check + har 4 sec watchdog (AdGuard/PvtDNS beech me on ho to bhi pakdega,
    // aur off karte hi screen apne aap wapas chalu) 🚀
    _runBlockCheck();
    _watchdog = Timer.periodic(const Duration(seconds: 4), (_) => _runBlockCheck());

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
            // 🔥 Sirf AdBlocker confirm hone par rokenge, slow internet par nahi 🔥
            if (desc.contains('err_blocked_by_client')) {
              _clientBlocked = true;
              _triggerBlock();
            } else if ((error.isForMainFrame ?? false) &&
                (desc.contains('name_not_resolved') ||
                    desc.contains('connection_refused') ||
                    desc.contains('address_invalid') ||
                    desc.contains('address_unreachable'))) {
              _runBlockCheck(); // DNS-level block ho sakta hai → verify
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(selectedAd));

    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft > 0) {
        if (mounted) setState(() => _timeLeft--);
      } else {
        if (mounted) setState(() => _canSkip = true);
        _timer?.cancel();
      }
    });
  }

  // 🔥 MULTI-DOMAIN + DoH CROSS-CHECK DNS LOGIC 🔥
  static const List<String> _probeHosts = <String>[
    'omg10.com',
    'www.profitableratecpmnetwork.com',
    'highrevenueformat.com',
  ];

  bool _isSinkhole(InternetAddress a) =>
      a.isLoopback || a.address == '0.0.0.0' || a.address == '::';

  /// 0 = resolve ho gaya, 1 = sinkhole (0.0.0.0 / 127.x), 2 = fail
  Future<int> _probe(String host) async {
    try {
      final List<InternetAddress> r =
          await InternetAddress.lookup(host).timeout(const Duration(seconds: 3));
      if (r.isEmpty) return 2;
      return r.any(_isSinkhole) ? 1 : 0;
    } catch (_) {
      return 2;
    }
  }

  /// Google DoH se asli answer: true = host asli me exist karta hai, false = nahi, null = DoH unreachable
  Future<bool?> _dohResolves(String host) async {
    try {
      final http.Response r = await http
          .get(Uri.parse('https://dns.google/resolve?name=$host&type=A'))
          .timeout(const Duration(seconds: 4));
      if (r.statusCode != 200) return null;
      final dynamic d = json.decode(r.body);
      if (d is! Map) return null;
      final dynamic ans = d['Answer'];
      if (ans is! List) return false;
      for (final dynamic a in ans) {
        if (a is Map && a['type'] == 1) {
          final String ip = (a['data'] ?? '').toString();
          if (ip.isNotEmpty && ip != '0.0.0.0' && !ip.startsWith('127.')) return true;
        }
      }
      return false;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isDnsBlocked() async {
    final List<int> res = await Future.wait(_probeHosts.map(_probe));
    if (res.contains(1)) return true; // clear sinkhole = AdGuard / PvtDNS
    if (!res.contains(2)) return false; // sab normal resolve
    // Kuch fail hue → pehle dekho internet chal raha hai ya nahi
    try {
      final List<InternetAddress> g =
          await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
      if (g.isEmpty) return false;
    } catch (_) {
      return false; // internet band/slow → adblock mat maano
    }
    // Internet theek hai, ad domain fail: DoH se confirm
    for (int i = 0; i < _probeHosts.length; i++) {
      if (res[i] != 2) continue;
      final bool? real = await _dohResolves(_probeHosts[i]);
      if (real == true || real == null) return true;
    }
    return false;
  }

  Future<void> _runBlockCheck() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final bool blocked = await _isDnsBlocked();
      if (!mounted) return;
      if (blocked && !_isAdblockDetected) {
        _triggerBlock();
      } else if (!blocked && _isAdblockDetected && !_clientBlocked) {
        _recover(); // user ne AdGuard/PvtDNS off kar diya
      }
    } catch (_) {
    } finally {
      _checking = false;
    }
  }

  void _recover() {
    if (!mounted) return;
    setState(() {
      _isAdblockDetected = false;
      _timeLeft = widget.adDuration;
      _canSkip = false;
    });
    _controller.loadRequest(Uri.parse(_selectedAd));
    _startCountdown();
  }

  void _triggerBlock() {
    if (mounted) {
      setState(() {
        _isAdblockDetected = true;
        _timer?.cancel(); 
        _canSkip = false; 
      });
      _controller.loadRequest(Uri.parse('about:blank')); // ad freeze
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
    _watchdog?.cancel();
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