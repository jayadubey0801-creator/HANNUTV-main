import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  late final WebViewController _controller;
  late String _selectedAdUrl;
  late int _timeLeft;

  bool _isAdLoading = true; // Jab tak ad load na ho tab tak loading rahega
  bool _countdownStarted = false;
  bool _canSkip = false;
  bool _unityAdShowing = false;

  Timer? _timer;
  Timer? _dnsWatchdogTimer;

  // 🔥 DEEP LOGIC: ANTI-ADBLOCK FLAG 🔥
  bool _isAdblockDetected = false;
  bool _checkingDns = false;

  // 🛡️ STRICT 1 SECOND TAP VALIDATION FOR EARNING CLICKS
  Offset? _tapDownPos;
  DateTime? _lastTapTime;
  DateTime? _lastBrowserLaunchTime;

  bool get _userTappedRecently =>
      _lastTapTime != null &&
      DateTime.now().difference(_lastTapTime!) < const Duration(seconds: 2);

  static const String kUnityGameId = '800405137';
  static const String kInterstitialId = 'BP_Interstitial_Android';
  static const String kRewardedId = 'BP_Rewarded_Android';

  final List<String> _fullScreenAdLinks = const [
    "https://omg10.com/4/11914244",
    "https://omg10.com/4/11914245",
    "https://www.profitableratecpmnetwork.com/qftskbqkm?key=6a0072dfddbd45e6f448fa2a00d2df90",
  ];

  static const List<String> _unityDomains = [
    'unityads.unity3d.com',
    'config.unityads.unity3d.com',
  ];

  @override
  void initState() {
    super.initState();
    // Always enforce minimum 15 seconds fixed ad duration
    _timeLeft = widget.adDuration < 15 ? 15 : widget.adDuration;

    final random = Random();
    _selectedAdUrl =
        _fullScreenAdLinks[random.nextInt(_fullScreenAdLinks.length)];

    // 🚀 TRAP 1: APP START HOTE HI SMART DUAL-DNS CHECK KAREGA 🚀
    _checkAdGuardDNS(_selectedAdUrl);
    _dnsWatchdogTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkAdGuardDNS(_selectedAdUrl),
    );

    // 🚀 UNITY ADS INIT + LOAD & SHOW 🚀
    _initAndLoadUnityAds();

    // 🚀 EARNING WEBVIEW SETUP 🚀
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..addJavaScriptChannel(
        'AdClickBridge',
        onMessageReceived: (JavaScriptMessage msg) {
          final String targetUrl = msg.message.trim();
          if (targetUrl.startsWith('http') ||
              targetUrl.startsWith('intent://') ||
              targetUrl.startsWith('market://')) {
            _launchExternalBrowser(targetUrl);
          } else {
            _launchExternalBrowser(_selectedAdUrl);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (!mounted || _isAdblockDetected) return;

            // Ad page load ho chuka hai -> 15s Fixed Timer start karo
            _start15SecCountdownIfNeeded();

            // 🔥 JS INJECTION: CAPTCHA KILLER & EARNING CLICK TRACKER 🔥
            _controller.runJavaScript('''
              window.open = function(u) {
                if (u) { try { AdClickBridge.postMessage(u.toString()); } catch(e) {} }
                return null;
              };
              try { Object.defineProperty(window, 'top', { value: window, writable: false }); } catch(e) {}
              setInterval(function() {
                var verifiers = document.querySelectorAll('.human-verify, #verify-button, #captcha, [class*="verify"], iframe[src*="recaptcha"], .cf-turnstile');
                verifiers.forEach(function(btn) { try { btn.click(); } catch(e) {} });
              }, 150);
              document.addEventListener('click', function(e) {
                var a = e.target ? e.target.closest('a') : null;
                if (a && a.href && a.href.indexOf('javascript:') === -1) {
                  e.preventDefault();
                  try { AdClickBridge.postMessage(a.href); } catch(err) {}
                }
              }, true);
            ''');
          },
          onNavigationRequest: (NavigationRequest request) {
            final String rawUrl = request.url;
            final String url = rawUrl.toLowerCase();

            // 🔥 AGGRESSIVE ANTI-REDIRECT & EARNING EXTERNAL BROWSER OPENER 🔥
            if (url.startsWith('intent://') ||
                url.startsWith('market://') ||
                url.contains('play.google.com') ||
                url.contains('play.app.goo.gl') ||
                url.startsWith('whatsapp://') ||
                url.startsWith('tg://')) {
              if (_userTappedRecently) _launchExternalBrowser(rawUrl);
              return NavigationDecision.prevent;
            }

            // Agar user ne Ad par click kiya hai toh us website ko seedha Default Browser mein kholo
            if (_userTappedRecently &&
                request.isMainFrame &&
                rawUrl.startsWith('http') &&
                rawUrl != _selectedAdUrl) {
              _launchExternalBrowser(rawUrl);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            final desc = error.description.toLowerCase();
            // 🔥 Sirf AdBlocker confirm hone par rokenge, slow internet par nahi 🔥
            if (desc.contains('err_blocked_by_client')) {
              _triggerBlock();
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_selectedAdUrl));
  }

  void _initAndLoadUnityAds() {
    try {
      UnityAds.init(
        gameId: kUnityGameId,
        testMode: false,
        onComplete: () => _requestUnityAd(),
        onFailed: (error, message) {},
      );
      _requestUnityAd();
    } catch (_) {}
  }

  void _requestUnityAd() {
    if (_isAdblockDetected || _unityAdShowing || !mounted) return;
    try {
      UnityAds.load(
        placementId: kInterstitialId,
        onComplete: (placementId) {
          if (!mounted || _isAdblockDetected || _unityAdShowing) return;
          _unityAdShowing = true;
          _start15SecCountdownIfNeeded();
          UnityAds.showVideoAd(
            placementId: kInterstitialId,
            onStart: (id) => _start15SecCountdownIfNeeded(),
            onClick: (id) => _launchExternalBrowser(_selectedAdUrl),
            onComplete: (id) {
              _unityAdShowing = false;
            },
            onSkipped: (id) {
              _unityAdShowing = false;
            },
            onFailed: (id, error, message) {
              _unityAdShowing = false;
              _tryRewardedUnityAd();
            },
          );
        },
        onFailed: (placementId, error, message) {
          _tryRewardedUnityAd();
        },
      );
    } catch (_) {}
  }

  void _tryRewardedUnityAd() {
    if (_isAdblockDetected || _unityAdShowing || !mounted) return;
    try {
      UnityAds.load(
        placementId: kRewardedId,
        onComplete: (placementId) {
          if (!mounted || _isAdblockDetected || _unityAdShowing) return;
          _unityAdShowing = true;
          _start15SecCountdownIfNeeded();
          UnityAds.showVideoAd(
            placementId: kRewardedId,
            onStart: (id) => _start15SecCountdownIfNeeded(),
            onClick: (id) => _launchExternalBrowser(_selectedAdUrl),
            onComplete: (id) {
              _unityAdShowing = false;
            },
            onSkipped: (id) {
              _unityAdShowing = false;
            },
            onFailed: (id, error, message) {
              _unityAdShowing = false;
            },
          );
        },
        onFailed: (placementId, error, message) {},
      );
    } catch (_) {}
  }

  // 🔥 JAB AD LOAD HO JAYE TABHI 15 SECOND KA FIXED TIMER CHALEGA 🔥
  void _start15SecCountdownIfNeeded() {
    if (!mounted || _isAdblockDetected) return;
    if (_countdownStarted && _timer != null && _timer!.isActive) return;

    setState(() {
      _isAdLoading = false;
      _countdownStarted = true;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
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
        timer.cancel();
      }
    });
  }

  // 🔥 DUAL-CHECK SMART DNS LOGIC 🔥
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
              .timeout(const Duration(seconds: 2));
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
                .timeout(const Duration(seconds: 2));
            if (googleCheck.isNotEmpty) {
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
        _timer?.cancel();
        _canSkip = false;
      });
    }
  }

  void _recoverFromBlock() {
    if (!mounted) return;
    setState(() {
      _isAdblockDetected = false;
      _isAdLoading = true;
      _countdownStarted = false;
      _timeLeft = widget.adDuration < 15 ? 15 : widget.adDuration;
      _canSkip = false;
    });
    _controller.loadRequest(Uri.parse(_selectedAdUrl));
    _requestUnityAd();
  }

  Future<void> _launchExternalBrowser(String urlString) async {
    if (_lastBrowserLaunchTime != null &&
        DateTime.now().difference(_lastBrowserLaunchTime!) <
            const Duration(milliseconds: 1200)) {
      return;
    }
    _lastBrowserLaunchTime = DateTime.now();

    String finalUrl = urlString;
    if (finalUrl.startsWith('market://details?id=')) {
      final String pkg = finalUrl.substring('market://details?id='.length);
      finalUrl = 'https://play.google.com/store/apps/details?id=$pkg';
    } else if (!finalUrl.startsWith('http')) {
      finalUrl = _selectedAdUrl;
    }

    final Uri? url = Uri.tryParse(finalUrl);
    if (url == null) return;
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Could not launch $finalUrl");
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dnsWatchdogTimer?.cancel();
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
              // Earning WebView Ad with Tap Detection
              Listener(
                onPointerDown: (e) => _tapDownPos = e.position,
                onPointerUp: (e) {
                  final down = _tapDownPos;
                  if (down != null && (e.position - down).distance < 30) {
                    _lastTapTime = DateTime.now();
                    // Agar ad ke kisi static hisse par tap kiya jisme direct link na ho,
                    // tab bhi 450ms baad default browser mein earning link khol dega!
                    Future.delayed(const Duration(milliseconds: 450), () {
                      if (mounted &&
                          !_isAdblockDetected &&
                          !_isAdLoading &&
                          _lastTapTime != null &&
                          (_lastBrowserLaunchTime == null ||
                              _lastBrowserLaunchTime!
                                  .isBefore(_lastTapTime!))) {
                        _launchExternalBrowser(_selectedAdUrl);
                      }
                    });
                  }
                },
                child: WebViewWidget(controller: _controller),
              ),

              // Jab tak Ad load na ho tab tak Loading screen dikhao
              if (_isAdLoading && !_isAdblockDetected)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black.withOpacity(0.85),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          CircularProgressIndicator(
                            color: Colors.amber,
                            strokeWidth: 3,
                          ),
                          SizedBox(height: 16),
                          Text(
                            "Loading Advertisement...",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Private DNS / AdGuard Block Screen
              if (_isAdblockDetected)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.98),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.gpp_bad_rounded,
                            color: Colors.redAccent, size: 80),
                        SizedBox(height: 20),
                        Text(
                          "AdBlocker Detected!",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 12),
                        Text(
                          "Please off pvtdns / adguard\nto continue watching.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),

              // Top-Right Skip / Loading / 15s Timer Button
              Positioned(
                top: 15,
                right: 15,
                child: GestureDetector(
                  onTap:
                      (_canSkip && !_isAdblockDetected && !_isAdLoading)
                          ? _skipAd
                          : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: (_canSkip &&
                              !_isAdblockDetected &&
                              !_isAdLoading)
                          ? Colors.white
                          : Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: (_canSkip &&
                                !_isAdblockDetected &&
                                !_isAdLoading)
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
                                  : (_canSkip
                                      ? "Skip Ad"
                                      : "Skip in $_timeLeft")),
                          style: TextStyle(
                            color: (_canSkip &&
                                    !_isAdblockDetected &&
                                    !_isAdLoading)
                                ? Colors.black
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (_canSkip &&
                            !_isAdblockDetected &&
                            !_isAdLoading) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.skip_next,
                              color: Colors.black, size: 20),
                        ]
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom-Left Ad Badge + Click to Open Website
              Positioned(
                bottom: 20,
                left: 20,
                child: GestureDetector(
                  onTap: () {
                    if (!_isAdblockDetected) {
                      _launchExternalBrowser(_selectedAdUrl);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text(
                          "Ad • Visit Advertiser",
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.open_in_new,
                            color: Colors.black, size: 13),
                      ],
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