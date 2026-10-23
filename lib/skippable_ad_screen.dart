import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class SkippableAdScreen extends StatefulWidget {
  final Widget nextScreen;
  final int adDuration;

  const SkippableAdScreen({
    Key? key,
    required this.nextScreen,
    this.adDuration = 15, // 🚀 FIXED TO 15 SECONDS
  }) : super(key: key);

  @override
  State<SkippableAdScreen> createState() => _SkippableAdScreenState();
}

class _SkippableAdScreenState extends State<SkippableAdScreen> {
  static bool _unitySdkInitialized = false;

  // 🎯 UNITY CLOUD MONETIZATION IDS (Unity dashboard: app Hannutv / 800405137, teeno placement Active)
  static const String kUnityGameId = '800405137';
  static const String kInterstitialId = 'BP_Interstitial_Android';
  static const String kRewardedId = 'BP_Rewarded_Android';

  // ⏱️ Ad load hone ka max wait = 10s, ad aane ke baad Skip = 15s
  static const int _loadWindowSeconds = 10;
  static const int _skipAfterSeconds = 15;

  // Unity ad 10s me na aaye to ye real-earning web ad chalega
  static const List<String> _fullScreenAdLinks = [
    "https://omg10.com/4/11914244",
    "https://omg10.com/4/11914245",
    "https://www.profitableratecpmnetwork.com/qftskbqkm?key=6a0072dfddbd45e6f448fa2a00d2df90",
  ];

  static const List<String> _unityDomains = [
    'unityads.unity3d.com',
    'config.unityads.unity3d.com',
    'webview.unityads.unity3d.com',
  ];

  late final WebViewController _controller;
  late final String _selectedAdUrl;
  late int _timeLeft;
  int _loadLeft = _loadWindowSeconds;

  // Jab tak ad actual mein start na ho tab tak "Loading Ad..." rahega
  bool _isAdLoading = true;
  bool _adStarted = false;
  bool _canSkip = false;
  bool _webFallbackStarted = false;
  bool _unityAdRequested = false;
  bool _unityAdShowing = false;
  bool _navigatedToNext = false;

  Timer? _loadTimer;
  Timer? _countdownTimer;
  Timer? _dnsWatchdogTimer;
  Timer? _unityRetryTimer;
  Timer? _webReadyTimer;

  // 🔥 DEEP LOGIC: ANTI-ADBLOCK FLAG 🔥
  bool _isAdblockDetected = false;
  bool _checkingDns = false;

  // 🛡️ SIRF REAL USER TAP PAR HI BROWSER KHULEGA (auto-open / auto-click bilkul nahi)
  Offset? _tapDownPos;
  DateTime? _lastTapTime;
  DateTime? _lastBrowserLaunchTime;

  bool get _userTappedRecently =>
      _lastTapTime != null &&
      DateTime.now().difference(_lastTapTime!) < const Duration(seconds: 2);

  int get _fixedSkipSeconds =>
      widget.adDuration < _skipAfterSeconds ? _skipAfterSeconds : widget.adDuration;

  @override
  void initState() {
    super.initState();
    _timeLeft = _fixedSkipSeconds;
    _selectedAdUrl = _fullScreenAdLinks[Random().nextInt(_fullScreenAdLinks.length)];

    _buildWebController();

    // 🚀 APP START HOTE HI SMART DUAL-DNS CHECK (pehle jaisa) 🚀
    _checkAdGuardDNS(_selectedAdUrl);
    _dnsWatchdogTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkAdGuardDNS(_selectedAdUrl),
    );

    _startAdFlow();
  }

  // ───────────────────────── fallback web ad (real-tap only) ─────────────────────────
  void _buildWebController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setUserAgent(
        "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
      )
      ..addJavaScriptChannel(
        'AdClickBridge',
        onMessageReceived: (JavaScriptMessage msg) {
          final String payload = msg.message.trim();
          if (payload.startsWith('OPEN:')) {
            final String u = payload.substring(5).trim();
            // page ka apna (bina tap wala) window.open / popup ignore; sirf real tap par
            if (u.isNotEmpty && _userTappedRecently) {
              _launchExternalBrowser(u);
            }
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (!mounted || _isAdblockDetected) return;
            if (url.startsWith('http')) _onAdStarted();

            // Sirf trusted (asli user) click ko default browser tak bhejta hai, scripted click ignore
            _controller.runJavaScript('''
              if (!window.__hannuAdHook) {
                window.__hannuAdHook = true;
                window.open = function(u) {
                  if (u) { try { AdClickBridge.postMessage('OPEN:' + u.toString()); } catch(e) {} }
                  return null;
                };
                document.addEventListener('click', function(e) {
                  if (!e.isTrusted) return;
                  var a = e.target && e.target.closest ? e.target.closest('a') : null;
                  if (a && a.href && a.href.indexOf('javascript:') === -1) {
                    e.preventDefault();
                    e.stopPropagation();
                    try { AdClickBridge.postMessage('OPEN:' + a.href); } catch(err) {}
                  }
                }, true);
              }
            ''');
          },
          onNavigationRequest: (NavigationRequest request) {
            final String rawUrl = request.url;
            final String url = rawUrl.toLowerCase();

            // 🔥 PLAY STORE / INTENTS: sirf user tap karne par external app/browser me 🔥
            if (url.startsWith('intent://') ||
                url.startsWith('market://') ||
                url.contains('play.google.com') ||
                url.contains('play.app.goo.gl') ||
                url.startsWith('whatsapp://') ||
                url.startsWith('tg://')) {
              if (_userTappedRecently) _launchExternalBrowser(rawUrl);
              return NavigationDecision.prevent;
            }

            // 🔥 USER NE AD PAR TAP KIYA → US WEBSITE KO DEFAULT BROWSER ME KHOLO 🔥
            if (_userTappedRecently &&
                request.isMainFrame &&
                rawUrl.startsWith('http')) {
              _launchExternalBrowser(rawUrl);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            final String desc = error.description.toLowerCase();
            // 🔥 Sirf AdBlocker confirm hone par rokenge, slow internet par nahi 🔥
            if (desc.contains('err_blocked_by_client')) {
              _triggerBlock();
            }
          },
        ),
      );

    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
  }

  // ───────────────────────── ad flow: 10s load window → ad → 15s → Skip ─────────────────────────
  void _startAdFlow() {
    _loadLeft = _loadWindowSeconds;
    _loadTimer?.cancel();
    _loadTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_isAdblockDetected || _adStarted) return;
      if (_loadLeft > 1) {
        setState(() => _loadLeft--);
      } else {
        t.cancel();
        // 10 second me Unity ad start nahi hua → real-earning web ad
        _startWebFallback();
      }
    });
    _setupAndShowUnityAds();
  }

  // 🔥 UNITY ADS INIT + LOAD + SHOW 🔥
  void _setupAndShowUnityAds() {
    if (_isAdblockDetected) return;
    try {
      if (_unitySdkInitialized) {
        _loadAndShowUnity(kInterstitialId, rewardedFallback: true);
      } else {
        UnityAds.init(
          gameId: kUnityGameId,
          testMode: false,
          onComplete: () {
            _unitySdkInitialized = true;
            _loadAndShowUnity(kInterstitialId, rewardedFallback: true);
          },
          onFailed: (error, message) {
            // main.dart ne pehle init kar diya ho to bhi load try karo
            _loadAndShowUnity(kInterstitialId, rewardedFallback: true);
          },
        );
        // Agar SDK pehle se init tha aur onComplete dubara fire nahi hua to 1.2s baad load
        _unityRetryTimer?.cancel();
        _unityRetryTimer = Timer(const Duration(milliseconds: 1200), () {
          if (mounted && !_unityAdRequested && !_isAdblockDetected) {
            _unitySdkInitialized = true;
            _loadAndShowUnity(kInterstitialId, rewardedFallback: true);
          }
        });
      }
    } catch (_) {
      _startWebFallback();
    }
  }

  void _loadAndShowUnity(String placementId, {required bool rewardedFallback}) {
    if (!mounted || _isAdblockDetected || _unityAdShowing || _navigatedToNext) return;
    if (placementId == kInterstitialId) {
      if (_unityAdRequested) return;
      _unityAdRequested = true;
    }

    void next() {
      if (!mounted) return;
      if (rewardedFallback) {
        _loadAndShowUnity(kRewardedId, rewardedFallback: false);
      } else {
        _startWebFallback();
      }
    }

    try {
      UnityAds.load(
        placementId: placementId,
        onComplete: (loadedId) {
          if (!mounted || _isAdblockDetected || _unityAdShowing || _navigatedToNext) return;
          _unityAdShowing = true;
          _onAdStarted();
          try {
            UnityAds.showVideoAd(
              placementId: placementId,
              onStart: (id) => _onAdStarted(),
              onClick: (id) {
                // Unity SDK khud advertiser ka link default browser / Play Store me kholta hai
              },
              onComplete: (id) {
                _unityAdShowing = false;
                _continueToNext();
              },
              onSkipped: (id) {
                _unityAdShowing = false;
                _continueToNext();
              },
              onFailed: (id, error, message) {
                _unityAdShowing = false;
                next();
              },
            );
          } catch (_) {
            _unityAdShowing = false;
            next();
          }
        },
        onFailed: (failedId, error, message) => next(),
      );
    } catch (_) {
      next();
    }
  }

  void _startWebFallback() {
    if (!mounted || _isAdblockDetected || _webFallbackStarted || _navigatedToNext) return;
    _webFallbackStarted = true;
    _loadTimer?.cancel();
    setState(() {});
    _controller.loadRequest(Uri.parse(_selectedAdUrl));
    // Page render hote hi countdown; warna 3s baad bhi shuru ho jayega
    _webReadyTimer?.cancel();
    _webReadyTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isAdblockDetected) _onAdStarted();
    });
  }

  // 🔥 JAB AD ACTUAL MEIN START HO TABHI 15 SECOND KA FIXED TIMER CHALEGA 🔥
  void _onAdStarted() {
    if (!mounted || _adStarted) return;
    _loadTimer?.cancel();
    _webReadyTimer?.cancel();
    setState(() {
      _adStarted = true;
      _isAdLoading = false;
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_isAdblockDetected) return;
      if (_timeLeft > 1) {
        setState(() => _timeLeft--);
      } else {
        setState(() {
          _timeLeft = 0;
          _canSkip = true;
        });
        t.cancel();
      }
    });
  }

  // 🔥 DUAL-CHECK SMART DNS LOGIC (PEHLE JAISA EXACT WORKING) 🔥
  Future<void> _checkAdGuardDNS(String adUrl) async {
    if (_checkingDns || !mounted) return;
    _checkingDns = true;
    try {
      final uri = Uri.parse(adUrl);
      final List<String> hostsToCheck = [uri.host, ..._unityDomains];
      bool blocked = false;

      for (final host in hostsToCheck) {
        try {
          final addresses = await InternetAddress.lookup(host)
              .timeout(const Duration(seconds: 3));
          if (addresses.isEmpty) {
            blocked = true;
            break;
          }
          for (var addr in addresses) {
            if (addr.isLoopback ||
                addr.address == '0.0.0.0' ||
                addr.address == '127.0.0.1' ||
                addr.address == '::1' ||
                addr.address == '::') {
              blocked = true;
              break;
            }
          }
          if (blocked) break;
        } catch (_) {
          // DNS resolve fail hua, Google ping karke dekho internet chal raha hai ya nahi
          try {
            final googleCheck = await InternetAddress.lookup('google.com')
                .timeout(const Duration(seconds: 3));
            if (googleCheck.isNotEmpty) {
              // Internet ekdum theek hai, par ad domain block ho gaya = AdBlocker / Pvt DNS!
              blocked = true;
              break;
            }
          } catch (_) {
            // Internet band/slow hai, isko adblock mat maano
          }
        }
      }

      if (!mounted) return;
      if (blocked && !_isAdblockDetected) {
        _triggerBlock();
      } else if (!blocked && _isAdblockDetected) {
        _recoverFromBlock();
      }
    } finally {
      _checkingDns = false;
    }
  }

  void _triggerBlock() {
    if (mounted) {
      setState(() {
        _isAdblockDetected = true;
        _countdownTimer?.cancel();
        _canSkip = false;
      });
    }
  }

  void _recoverFromBlock() {
    if (!mounted) return;
    _countdownTimer?.cancel();
    _webReadyTimer?.cancel();
    setState(() {
      _isAdblockDetected = false;
      _isAdLoading = true;
      _adStarted = false;
      _canSkip = false;
      _webFallbackStarted = false;
      _unityAdRequested = false;
      _unityAdShowing = false;
      _timeLeft = _fixedSkipSeconds;
      _loadLeft = _loadWindowSeconds;
    });
    _startAdFlow();
  }

  // 🔥 USER TAP KARE TO ASLI ADVERTISER WEBSITE PHONE KE DEFAULT BROWSER ME 🔥
  Future<void> _launchExternalBrowser(String urlString) async {
    if (_navigatedToNext || _isAdblockDetected) return;
    final DateTime now = DateTime.now();
    if (_lastBrowserLaunchTime != null &&
        now.difference(_lastBrowserLaunchTime!) < const Duration(milliseconds: 1200)) {
      return;
    }

    String target = urlString.trim();
    if (target.startsWith('intent://')) {
      final int fallbackIdx = target.indexOf('S.browser_fallback_url=');
      if (fallbackIdx == -1) return;
      String fb = target.substring(fallbackIdx + 23);
      final int endIdx = fb.indexOf(';');
      if (endIdx != -1) fb = fb.substring(0, endIdx);
      target = Uri.decodeComponent(fb);
    } else if (target.startsWith('market://details?id=')) {
      final String pkg = target.substring('market://details?id='.length);
      target = 'https://play.google.com/store/apps/details?id=$pkg';
    }
    if (!target.startsWith('http')) return;

    final Uri? url = Uri.tryParse(target);
    if (url == null) return;
    _lastBrowserLaunchTime = now;
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _continueToNext() {
    if (_navigatedToNext || _isAdblockDetected || !mounted) return;
    _navigatedToNext = true;
    _lastTapTime = null;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => widget.nextScreen),
    );
  }

  void _skipAd() {
    if (!_canSkip || _isAdblockDetected || _isAdLoading) return;
    _continueToNext();
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    _countdownTimer?.cancel();
    _dnsWatchdogTimer?.cancel();
    _unityRetryTimer?.cancel();
    _webReadyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool skipReady = _canSkip && !_isAdblockDetected && !_isAdLoading;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Real-earning web ad (sirf fallback me) — sirf asli tap gine jaate hain
              if (_webFallbackStarted)
                Listener(
                  onPointerDown: (e) => _tapDownPos = e.position,
                  onPointerUp: (e) {
                    final Offset? down = _tapDownPos;
                    if (down != null && (e.position - down).distance < 30) {
                      _lastTapTime = DateTime.now();
                    }
                  },
                  child: WebViewWidget(controller: _controller),
                ),

              // 2. Jab tak ad start na ho tab tak "Loading Ad..."
              if (_isAdLoading && !_isAdblockDetected)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black.withOpacity(0.90),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                            color: Colors.amber,
                            strokeWidth: 3,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            (!_webFallbackStarted && _loadLeft > 0)
                                ? "Loading Ad... (${_loadLeft}s)"
                                : "Loading Ad...",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 3. Private DNS / AdGuard Block Screen (pehle jaisa exact working)
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
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          "Please off pvtdns / adguard\nto continue watching.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 4. Top-Right: Loading Ad / Skip in N / Skip Ad
              Positioned(
                top: 15,
                right: 15,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: skipReady ? _skipAd : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: skipReady ? Colors.white : Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: skipReady ? Colors.white : Colors.grey),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isAdLoading || _isAdblockDetected) ...[
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              color: Colors.amber,
                              strokeWidth: 2,
                            ),
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
                            color: skipReady ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (skipReady) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.skip_next, color: Colors.black, size: 20),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // 5. Bottom-Left "Ad" badge (sirf label)
              Positioned(
                bottom: 20,
                left: 20,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      "Ad",
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
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
