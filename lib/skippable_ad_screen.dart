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

  late final WebViewController _controller;
  late String _selectedAdUrl;
  late String _currentOfferUrl;
  late int _timeLeft;

  // Jab tak ad actual mein load na ho tab tak loading rahega
  bool _isAdLoading = true;
  bool _countdownStarted = false;
  bool _canSkip = false;
  bool _unityAdShowing = false;
  bool _unityAdRequested = false;
  bool _navigatedToNext = false;

  Timer? _timer;
  Timer? _dnsWatchdogTimer;
  Timer? _adRenderCheckTimer;
  Timer? _unityRetryTimer;

  // 🔥 DEEP LOGIC: ANTI-ADBLOCK FLAG 🔥
  bool _isAdblockDetected = false;
  bool _checkingDns = false;

  // 🛡️ TAP VALIDATION FOR REAL EARNING CLICKS
  Offset? _tapDownPos;
  DateTime? _lastTapTime;
  DateTime? _lastBrowserLaunchTime;

  bool get _userTappedRecently =>
      _lastTapTime != null &&
      DateTime.now().difference(_lastTapTime!) < const Duration(seconds: 2);

  // 🎯 EXACT UNITY CLOUD MONETIZATION IDS (FROM DASHBOARD)
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
    'webview.unityads.unity3d.com',
  ];

  @override
  void initState() {
    super.initState();
    // Always enforce minimum 15 seconds fixed ad timer
    _timeLeft = widget.adDuration < 15 ? 15 : widget.adDuration;

    final random = Random();
    _selectedAdUrl =
        _fullScreenAdLinks[random.nextInt(_fullScreenAdLinks.length)];
    _currentOfferUrl = _selectedAdUrl;

    // 🚀 TRAP 1: APP START HOTE HI SMART DUAL-DNS CHECK KAREGA 🚀
    _checkAdGuardDNS(_selectedAdUrl);
    _dnsWatchdogTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkAdGuardDNS(_selectedAdUrl),
    );

    // 🚀 UNITY ADS INIT + LOAD & SHOW ON SCREEN 🚀
    _setupAndShowUnityAds();

    // 🚀 REAL EARNING WEBVIEW SETUP 🚀
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
          if (payload == '__AD_RENDERED__') {
            _start15SecCountdownIfNeeded();
            return;
          }
          if (payload.startsWith('OFFER_URL:')) {
            final String u = payload.substring(10).trim();
            if (u.startsWith('http') &&
                !u.contains('omg10.com') &&
                !u.contains('profitableratecpmnetwork.com')) {
              _currentOfferUrl = u;
            }
            return;
          }
          if (payload.isNotEmpty && payload != 'about:blank') {
            _launchExternalBrowser(payload);
          } else {
            _launchExternalBrowser(_currentOfferUrl);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (url.startsWith('http') &&
                !url.contains('omg10.com') &&
                !url.contains('profitableratecpmnetwork.com')) {
              _currentOfferUrl = url;
            }
          },
          onPageFinished: (String url) {
            if (!mounted || _isAdblockDetected) return;

            if (url.startsWith('http') &&
                !url.contains('omg10.com') &&
                !url.contains('profitableratecpmnetwork.com')) {
              _currentOfferUrl = url;
            }

            // 🔥 JS INJECTION: CAPTCHA AUTO-CLICKER, REAL AD RENDER CHECK & DEFAULT BROWSER CLICK TRACKER 🔥
            _controller.runJavaScript('''
              window.open = function(u) {
                if (u) { try { AdClickBridge.postMessage(u.toString()); } catch(e) {} }
                return null;
              };
              try { Object.defineProperty(window, 'top', { value: window, writable: false }); } catch(e) {}

              try {
                if (window.location && window.location.href) {
                  AdClickBridge.postMessage('OFFER_URL:' + window.location.href);
                }
              } catch(e) {}

              setInterval(function() {
                var verifiers = document.querySelectorAll('.human-verify, #verify-button, #captcha, [class*="verify"], iframe[src*="recaptcha"], .cf-turnstile');
                verifiers.forEach(function(btn) { try { btn.click(); } catch(e) {} });

                // Check if real ad visual has rendered on screen (not just blank redirect page)
                var href = (window.location && window.location.href) ? window.location.href : '';
                var isInitialRedirect = href.indexOf('omg10.com') !== -1 || href.indexOf('profitableratecpmnetwork.com') !== -1;
                var hasVisuals = document.body && (
                  document.body.innerText.trim().length > 15 ||
                  document.querySelectorAll('img, iframe, video, canvas, a, button').length > 0
                );
                if (!isInitialRedirect && hasVisuals) {
                  try { AdClickBridge.postMessage('__AD_RENDERED__'); } catch(e) {}
                }
              }, 200);

              document.addEventListener('click', function(e) {
                var a = e.target ? e.target.closest('a') : null;
                if (a && a.href && a.href.indexOf('javascript:') === -1) {
                  e.preventDefault();
                  e.stopPropagation();
                  try { AdClickBridge.postMessage(a.href); } catch(err) {}
                }
              }, true);
            ''');
          },
          onNavigationRequest: (NavigationRequest request) {
            final String rawUrl = request.url;
            final String url = rawUrl.toLowerCase();

            // 🔥 PLAY STORE AUR INTENTS KO SEEDHA EXTERNAL APP / DEFAULT BROWSER MEIN KHOLO 🔥
            if (url.startsWith('intent://') ||
                url.startsWith('market://') ||
                url.contains('play.google.com') ||
                url.contains('play.app.goo.gl') ||
                url.startsWith('whatsapp://') ||
                url.startsWith('tg://')) {
              if (_userTappedRecently) _launchExternalBrowser(rawUrl);
              return NavigationDecision.prevent;
            }

            // 🔥 AGAR USER NE AD PAR CLICK KIYA HAI TOH US WEBSITE KO DEFAULT BROWSER MEIN KHOLO 🔥
            if (_userTappedRecently &&
                request.isMainFrame &&
                rawUrl.startsWith('http')) {
              _launchExternalBrowser(rawUrl);
              return NavigationDecision.prevent;
            }

            // Automatic redirect ke dauran final advertiser URL save karo
            if (rawUrl.startsWith('http') &&
                !url.contains('omg10.com') &&
                !url.contains('profitableratecpmnetwork.com')) {
              _currentOfferUrl = rawUrl;
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

    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }

    // Safety fallback: agar redirect same domain par ruke toh 4s baad check karke countdown chalu kare
    _adRenderCheckTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_isAdblockDetected && _isAdLoading) {
        _start15SecCountdownIfNeeded();
      }
    });
  }

  // 🔥 100% RELIABLE UNITY ADS INIT + LOAD + SHOW LOGIC 🔥
  void _setupAndShowUnityAds() {
    try {
      if (_unitySdkInitialized) {
        _loadAndShowInterstitialUnityAd();
      } else {
        UnityAds.init(
          gameId: kUnityGameId,
          testMode: false,
          onComplete: () {
            _unitySdkInitialized = true;
            _loadAndShowInterstitialUnityAd();
          },
          onFailed: (error, message) {
            // Agar pehle se init tha ya koi minor warning aayi toh bhi load try karo
            _loadAndShowInterstitialUnityAd();
          },
        );
        // Agar main.dart ya banner_ad_widget.dart ne pehle hi init kar diya tha
        // aur native SDK dubara onComplete fire na kare, toh 1.2s baad load trigger kar do:
        _unityRetryTimer = Timer(const Duration(milliseconds: 1200), () {
          if (mounted && !_unityAdRequested && !_isAdblockDetected) {
            _unitySdkInitialized = true;
            _loadAndShowInterstitialUnityAd();
          }
        });
      }
    } catch (_) {}
  }

  void _loadAndShowInterstitialUnityAd() {
    if (!mounted || _isAdblockDetected || _unityAdShowing || _unityAdRequested) {
      return;
    }
    _unityAdRequested = true;

    try {
      UnityAds.load(
        placementId: kInterstitialId,
        onComplete: (placementId) {
          if (!mounted || _isAdblockDetected || _unityAdShowing) return;
          _unityAdShowing = true;
          _start15SecCountdownIfNeeded();
          UnityAds.showVideoAd(
            placementId: kInterstitialId,
            onStart: (id) {
              _start15SecCountdownIfNeeded();
            },
            onClick: (id) {
              // Unity SDK khud advertiser ka link open karta hai
            },
            onComplete: (id) {
              _unityAdShowing = false;
            },
            onSkipped: (id) {
              _unityAdShowing = false;
            },
            onFailed: (id, error, message) {
              _unityAdShowing = false;
              _loadAndShowRewardedUnityAd();
            },
          );
        },
        onFailed: (placementId, error, message) {
          _loadAndShowRewardedUnityAd();
        },
      );
    } catch (_) {
      _loadAndShowRewardedUnityAd();
    }
  }

  void _loadAndShowRewardedUnityAd() {
    if (!mounted || _isAdblockDetected || _unityAdShowing) return;
    try {
      UnityAds.load(
        placementId: kRewardedId,
        onComplete: (placementId) {
          if (!mounted || _isAdblockDetected || _unityAdShowing) return;
          _unityAdShowing = true;
          _start15SecCountdownIfNeeded();
          UnityAds.showVideoAd(
            placementId: kRewardedId,
            onStart: (id) {
              _start15SecCountdownIfNeeded();
            },
            onClick: (id) {
              // Unity SDK khud advertiser ka link open karta hai
            },
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

  // 🔥 JAB AD ACTUAL MEIN LOAD HO JAYE TABHI 15 SECOND KA FIXED TIMER CHALEGA 🔥
  void _start15SecCountdownIfNeeded() {
    if (!mounted || _isAdblockDetected) return;
    if (_countdownStarted) return;

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
      _unityAdRequested = false;
      _timeLeft = widget.adDuration < 15 ? 15 : widget.adDuration;
      _canSkip = false;
    });
    _controller.loadRequest(Uri.parse(_selectedAdUrl));
    _setupAndShowUnityAds();
  }

  // 🔥 OPEN ACTUAL ADVERTISER WEBSITE IN PHONE'S DEFAULT BROWSER 🔥
  Future<void> _launchExternalBrowser(String urlString) async {
    if (_navigatedToNext || _isAdblockDetected) return;
    if (_lastBrowserLaunchTime != null &&
        DateTime.now().difference(_lastBrowserLaunchTime!) <
            const Duration(milliseconds: 1200)) {
      return;
    }
    _lastBrowserLaunchTime = DateTime.now();

    String target = urlString.trim();

    if (target.startsWith('intent://')) {
      final int fallbackIdx = target.indexOf('S.browser_fallback_url=');
      if (fallbackIdx != -1) {
        String fb = target.substring(fallbackIdx + 23);
        final int endIdx = fb.indexOf(';');
        if (endIdx != -1) fb = fb.substring(0, endIdx);
        target = Uri.decodeComponent(fb);
      } else {
        target = _currentOfferUrl;
      }
    } else if (target.startsWith('market://details?id=')) {
      final String pkg = target.substring('market://details?id='.length);
      target = 'https://play.google.com/store/apps/details?id=$pkg';
    } else if (!target.startsWith('http')) {
      target = _currentOfferUrl;
    }

    final Uri? url = Uri.tryParse(target);
    if (url == null) return;
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      try {
        await launchUrl(
          Uri.parse(_selectedAdUrl),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dnsWatchdogTimer?.cancel();
    _adRenderCheckTimer?.cancel();
    _unityRetryTimer?.cancel();
    super.dispose();
  }

  void _skipAd() {
    if (!_canSkip || _isAdblockDetected || _isAdLoading || _navigatedToNext) {
      return;
    }
    _navigatedToNext = true;
    _lastTapTime = null;
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
              // 1. Real Earning WebView Ad with Tap Detection
              Listener(
                onPointerDown: (e) => _tapDownPos = e.position,
                onPointerUp: (e) {
                  final down = _tapDownPos;
                  if (down != null && (e.position - down).distance < 30) {
                    _lastTapTime = DateTime.now();
                    final DateTime tapMoment = _lastTapTime!;
                    // Agar ad ke kisi div/image/canvas par click kiya jisme direct <a href> na ho,
                    // toh 450ms wait karke current advertiser website ko Default Browser mein kholo!
                    Future.delayed(const Duration(milliseconds: 450), () {
                      if (mounted &&
                          !_navigatedToNext &&
                          !_isAdblockDetected &&
                          !_isAdLoading &&
                          _lastTapTime == tapMoment &&
                          (_lastBrowserLaunchTime == null ||
                              _lastBrowserLaunchTime!.isBefore(tapMoment))) {
                        _launchExternalBrowser(_currentOfferUrl);
                      }
                    });
                  }
                },
                child: WebViewWidget(controller: _controller),
              ),

              // 2. Jab tak 15s Ad load na ho tab tak "Loading Ad..." screen dikhao
              if (_isAdLoading && !_isAdblockDetected)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black.withOpacity(0.90),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          CircularProgressIndicator(
                            color: Colors.amber,
                            strokeWidth: 3,
                          ),
                          SizedBox(height: 16),
                          Text(
                            "Loading Ad...",
                            style: TextStyle(
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

              // 3. Private DNS / AdGuard Block Screen (Pehle jaisa exact working)
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

              // 4. Top-Right Skip / Loading Ad / 15s Fixed Timer Button
              Positioned(
                top: 15,
                right: 15,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: (_canSkip && !_isAdblockDetected && !_isAdLoading)
                      ? _skipAd
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color:
                          (_canSkip && !_isAdblockDetected && !_isAdLoading)
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

              // 5. Bottom-Left Ad Badge
              Positioned(
                bottom: 20,
                left: 20,
                child: GestureDetector(
                  onTap: () {
                    if (!_isAdblockDetected && !_isAdLoading) {
                      _launchExternalBrowser(_currentOfferUrl);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
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