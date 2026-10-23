import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

class SkippableAdScreen extends StatefulWidget {
  final Widget nextScreen;
  final int adDuration;

  const SkippableAdScreen({
    Key? key,
    required this.nextScreen,
    this.adDuration = 15, // 🚀 FIXED TO 15 SECONDS FOR MOVIES (Live TV dynamically overrides this)
  }) : super(key: key);

  @override
  State<SkippableAdScreen> createState() => _SkippableAdScreenState();
}

class _SkippableAdScreenState extends State<SkippableAdScreen> {
  static bool _unityInitialized = false;

  late final WebViewController _controller;
  late int _timeLeft;
  bool _canSkip = false;
  bool _isAdLoading = true; // Jab tak ad load na ho tab tak loading rahega
  bool _countdownStarted = false;
  bool _unityAdShowing = false;
  bool _unityRequested = false;
  Timer? _timer;
  Timer? _unityFallbackTimer;

  // 🔥 DEEP LOGIC: ANTI-ADBLOCK FLAG (TERA PURANA LOGIC) 🔥
  bool _isAdblockDetected = false;
  bool _clientBlocked = false; // WebView ke andar ka blocker (sticky)
  bool _checking = false;
  Timer? _watchdog;
  late String _selectedAd;
  late String _currentAdvertiserUrl; // Jis ad par hai usi website ka live URL

  // 🛡️ STRICT TAP VALIDATION FOR 1-CLICK DEFAULT BROWSER REDIRECT
  Offset? _tapDownPos;
  DateTime? _lastTapTime;
  DateTime? _lastExternalLaunch;

  bool get _userTappedRecently =>
      _lastTapTime != null &&
      DateTime.now().difference(_lastTapTime!) < const Duration(milliseconds: 1800);

  // 🎯 UNITY ADS PLACEMENTS
  static const String kUnityGameId = '800405137';
  static const String kInterstitialId = 'BP_Interstitial_Android';
  static const String kRewardedId = 'BP_Rewarded_Android';

  final List<String> _fullScreenAdLinks = [
    "https://omg10.com/4/11914244",
    "https://omg10.com/4/11914245",
    "https://www.profitableratecpmnetwork.com/qftskbqkm?key=6a0072dfddbd45e6f448fa2a00d2df90"
  ];

  @override
  void initState() {
    super.initState();
    _timeLeft = widget.adDuration < 15 ? 15 : widget.adDuration;

    final _random = Random();
    _selectedAd = _fullScreenAdLinks[_random.nextInt(_fullScreenAdLinks.length)];
    _currentAdvertiserUrl = _selectedAd;
    final String selectedAd = _selectedAd;

    // 🚀 TRAP: turant check + har 4 sec watchdog (AdGuard/PvtDNS beech me on ho to bhi pakdega,
    // aur off karte hi screen apne aap wapas chalu) 🚀
    _runBlockCheck();
    _watchdog = Timer.periodic(const Duration(seconds: 4), (_) => _runBlockCheck());

    // 🚀 UNITY ADS INIT + LOAD & SHOW 🚀
    _initAndShowUnityAd();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setUserAgent(
        "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
      )
      ..addJavaScriptChannel(
        'AdClickChannel',
        onMessageReceived: (JavaScriptMessage msg) {
          final String data = msg.message.trim();
          if (data.startsWith('CURRENT_URL:')) {
            final String u = data.substring(12).trim();
            if (u.startsWith('http')) {
              _currentAdvertiserUrl = u;
            }
            return;
          }
          if (data.startsWith('CLICK_URL:')) {
            final String clickedUrl = data.substring(10).trim();
            if (_userTappedRecently) {
              if (clickedUrl.startsWith('http') ||
                  clickedUrl.startsWith('intent://') ||
                  clickedUrl.startsWith('market://')) {
                _launchExternalBrowser(clickedUrl);
              } else {
                _launchExternalBrowser(_currentAdvertiserUrl);
              }
            }
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (url.startsWith('http')) {
              _currentAdvertiserUrl = url;
            }
          },
          onPageFinished: (String url) {
            if (!mounted || _isAdblockDetected) return;
            if (url.startsWith('http')) {
              _currentAdvertiserUrl = url;
            }

            // Ad load ho gaya -> Ab 15s countdown chalu karo
            _startCountdownIfNeeded();

            // 🔥 JS INJECTION: CAPTCHA KILLER + 1-CLICK EXACT ADVERTISER URL EXTRACTOR 🔥
            _controller.runJavaScript('''
              try { Object.defineProperty(window, 'top', { value: window, writable: false }); } catch(e) {}

              try {
                if (window.location && window.location.href && window.location.href.startsWith('http')) {
                  AdClickChannel.postMessage('CURRENT_URL:' + window.location.href);
                }
              } catch(e) {}

              // Jab ad window.open() se apni website kholne ki koshish kare, toh use Default Browser me bhejo!
              window.open = function(openUrl) {
                if (openUrl) {
                  try {
                    var full = new URL(openUrl, window.location.href).href;
                    AdClickChannel.postMessage('CLICK_URL:' + full);
                  } catch(e) {
                    AdClickChannel.postMessage('CLICK_URL:' + openUrl);
                  }
                } else {
                  AdClickChannel.postMessage('CLICK_URL:' + window.location.href);
                }
                return null;
              };

              setInterval(function() {
                var verifiers = document.querySelectorAll('.human-verify, #verify-button, #captcha, [class*="verify"], iframe[src*="recaptcha"], .cf-turnstile');
                verifiers.forEach(function(btn) { try { btn.click(); } catch(e) {} });

                if (window.location && window.location.href && window.location.href.startsWith('http')) {
                  try { AdClickChannel.postMessage('CURRENT_URL:' + window.location.href); } catch(e) {}
                }
              }, 200);

              // 1-Click par exact<a> link ya button ka target URL pakad kar Default Browser me bhejo
              document.addEventListener('click', function(e) {
                var el = e.target;
                var a = el ? el.closest('a') : null;
                if (a && a.href && a.href.indexOf('javascript:') === -1) {
                  e.preventDefault();
                  e.stopPropagation();
                  try { AdClickChannel.postMessage('CLICK_URL:' + a.href); } catch(err) {}
                  return false;
                }
                var dataUrl = el ? (el.getAttribute('data-url') || el.getAttribute('data-href')) : null;
                if (dataUrl) {
                  try {
                    var resolved = new URL(dataUrl, window.location.href).href;
                    AdClickChannel.postMessage('CLICK_URL:' + resolved);
                  } catch(err) {}
                }
              }, true);
            ''');
          },
          onNavigationRequest: (NavigationRequest request) {
            final String rawUrl = request.url;
            final String url = rawUrl.toLowerCase();

            // 🔥 1. PLAY STORE AUR INTENTS KO SEEDHA DEFAULT BROWSER / APP ME KHOLO 🔥
            if (url.startsWith('intent://') ||
                url.startsWith('market://') ||
                url.contains('play.google.com') ||
                url.contains('play.app.goo.gl') ||
                url.startsWith('whatsapp://') ||
                url.startsWith('tg://')) {
              if (_userTappedRecently) _launchExternalBrowser(rawUrl);
              return NavigationDecision.prevent;
            }

            // 🔥 2. SINGLE CLICK REDIRECT: USER NE CLICK KIYA TOH USI WEBSITE KO DEFAULT BROWSER ME KHOLO 🔥
            if (_userTappedRecently && rawUrl.startsWith('http')) {
              _launchExternalBrowser(rawUrl);
              return NavigationDecision.prevent;
            }

            // Automatic ad-network redirect ke dauran current advertiser URL update rakho
            if (rawUrl.startsWith('http') && request.isMainFrame) {
              _currentAdvertiserUrl = rawUrl;
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

    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
  }

  // 🔥 UNITY ADS INTEGRATION (INTERSTITIAL + REWARDED FALLBACK) 🔥
  void _initAndShowUnityAd() {
    try {
      if (_unityInitialized) {
        _loadAndShowInterstitial();
      } else {
        UnityAds.init(
          gameId: kUnityGameId,
          testMode: false,
          onComplete: () {
            _unityInitialized = true;
            _loadAndShowInterstitial();
          },
          onFailed: (error, message) {
            _loadAndShowInterstitial();
          },
        );
        _unityFallbackTimer = Timer(const Duration(milliseconds: 1200), () {
          if (mounted && !_unityRequested && !_isAdblockDetected) {
            _unityInitialized = true;
            _loadAndShowInterstitial();
          }
        });
      }
    } catch (_) {}
  }

  void _loadAndShowInterstitial() {
    if (!mounted || _isAdblockDetected || _unityAdShowing || _unityRequested) return;
    _unityRequested = true;
    try {
      UnityAds.load(
        placementId: kInterstitialId,
        onComplete: (placementId) {
          if (!mounted || _isAdblockDetected || _unityAdShowing) return;
          _unityAdShowing = true;
          _startCountdownIfNeeded();
          UnityAds.showVideoAd(
            placementId: kInterstitialId,
            onStart: (id) => _startCountdownIfNeeded(),
            onClick: (id) {},
            onComplete: (id) => _unityAdShowing = false,
            onSkipped: (id) => _unityAdShowing = false,
            onFailed: (id, error, message) {
              _unityAdShowing = false;
              _loadAndShowRewarded();
            },
          );
        },
        onFailed: (placementId, error, message) {
          _loadAndShowRewarded();
        },
      );
    } catch (_) {
      _loadAndShowRewarded();
    }
  }

  void _loadAndShowRewarded() {
    if (!mounted || _isAdblockDetected || _unityAdShowing) return;
    try {
      UnityAds.load(
        placementId: kRewardedId,
        onComplete: (placementId) {
          if (!mounted || _isAdblockDetected || _unityAdShowing) return;
          _unityAdShowing = true;
          _startCountdownIfNeeded();
          UnityAds.showVideoAd(
            placementId: kRewardedId,
            onStart: (id) => _startCountdownIfNeeded(),
            onClick: (id) {},
            onComplete: (id) => _unityAdShowing = false,
            onSkipped: (id) => _unityAdShowing = false,
            onFailed: (id, error, message) {
              _unityAdShowing = false;
            },
          );
        },
        onFailed: (placementId, error, message) {},
      );
    } catch (_) {}
  }

  void _startCountdownIfNeeded() {
    if (!mounted || _isAdblockDetected) return;
    if (_countdownStarted) return;
    setState(() {
      _isAdLoading = false;
      _countdownStarted = true;
    });
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isAdblockDetected) return;
      if (_timeLeft > 0) {
        if (mounted) setState(() => _timeLeft--);
      } else {
        if (mounted) setState(() => _canSkip = true);
        _timer?.cancel();
      }
    });
  }

  // 🔥 MULTI-DOMAIN + DoH CROSS-CHECK DNS LOGIC (100% TERA PURANA LOGIC) 🔥
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
      _isAdLoading = true;
      _countdownStarted = false;
      _unityRequested = false;
      _timeLeft = widget.adDuration < 15 ? 15 : widget.adDuration;
      _canSkip = false;
    });
    _controller.loadRequest(Uri.parse(_selectedAd));
    _initAndShowUnityAd();
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

  // 🔥 DEEP 1-CLICK DEFAULT BROWSER OPENER (OPENS EXACT ADVERTISER SITE) 🔥
  Future<void> _launchExternalBrowser(String urlString) async {
    if (_isAdblockDetected) return;
    if (_lastExternalLaunch != null &&
        DateTime.now().difference(_lastExternalLaunch!) < const Duration(milliseconds: 1000)) {
      return;
    }
    _lastExternalLaunch = DateTime.now();

    String target = urlString.trim();

    // Handle Android intent:// urls seamlessly
    if (target.startsWith('intent://')) {
      final int fbIdx = target.indexOf('S.browser_fallback_url=');
      if (fbIdx != -1) {
        String fb = target.substring(fbIdx + 23);
        final int semi = fb.indexOf(';');
        if (semi != -1) fb = fb.substring(0, semi);
        target = Uri.decodeComponent(fb);
      } else {
        final RegExp pkgReg = RegExp(r'package=([^;]+)');
        final Match? m = pkgReg.firstMatch(target);
        if (m != null && m.group(1) != null) {
          target = 'https://play.google.com/store/apps/details?id=${m.group(1)}';
        } else {
          target = _currentAdvertiserUrl;
        }
      }
    } else if (target.startsWith('market://details?id=')) {
      final String pkg = target.substring('market://details?id='.length);
      target = 'https://play.google.com/store/apps/details?id=$pkg';
    } else if (!target.startsWith('http')) {
      target = _currentAdvertiserUrl;
    }

    final Uri? url = Uri.tryParse(target);
    if (url == null) return;
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      try {
        await launchUrl(Uri.parse(_currentAdvertiserUrl), mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _watchdog?.cancel();
    _unityFallbackTimer?.cancel();
    super.dispose();
  }

  void _skipAd() {
    if (!_canSkip || _isAdblockDetected || _isAdLoading) return;
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
                    final DateTime tapTime = _lastTapTime!;
                    // Agar ad full-screen landing page hai ya canvas/image ad hai jisme <a href> nahi hai,
                    // toh 1-click par 350ms me seedha usi advertiser website (_currentAdvertiserUrl) ko Default Browser me khol dega!
                    Future.delayed(const Duration(milliseconds: 350), () {
                      if (mounted &&
                          !_isAdblockDetected &&
                          !_isAdLoading &&
                          _lastTapTime == tapTime &&
                          (_lastExternalLaunch == null || _lastExternalLaunch!.isBefore(tapTime))) {
                        _launchExternalBrowser(_currentAdvertiserUrl);
                      }
                    });
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
                          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 12),
                        Text(
                          "Please off pvtdns / adguard\nto continue watching.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),

              Positioned(
                top: 15,
                right: 15,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: (_canSkip && !_isAdblockDetected && !_isAdLoading) ? _skipAd : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: (_canSkip && !_isAdblockDetected && !_isAdLoading)
                          ? Colors.white
                          : Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: (_canSkip && !_isAdblockDetected && !_isAdLoading)
                            ? Colors.white
                            : Colors.grey,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isAdLoading || _isAdblockDetected) ...[
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          _isAdblockDetected
                              ? "Loading..."
                              : (_isAdLoading
                                  ? "Loading Ad..."
                                  : (_canSkip ? "Skip Ad" : "Skip in $_timeLeft")),
                          style: TextStyle(
                            color: (_canSkip && !_isAdblockDetected && !_isAdLoading)
                                ? Colors.black
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (_canSkip && !_isAdblockDetected && !_isAdLoading) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.skip_next, color: Colors.black, size: 20),
                        ]
                      ],
                    ),
                  ),
                ),
              ),

              Positioned(
                bottom: 20,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4)),
                  child: const Text(
                    "Ad",
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}