import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'package:url_launcher/url_launcher.dart';

class SkippableAdScreen extends StatefulWidget {
  final Widget nextScreen;
  final int adDuration;

  const SkippableAdScreen({
    Key? key,
    required this.nextScreen,
    this.adDuration = 15,
  }) : super(key: key);

  @override
  State<SkippableAdScreen> createState() => _SkippableAdScreenState();
}

class _SkippableAdScreenState extends State<SkippableAdScreen> {
  bool _isLoadingAd = true;
  int _loadWaitLeft = 10; // 10 second wait to load ad
  int _skipTimeLeft = 15; // 15 second skip timer once ad starts
  bool _canSkip = false;
  bool _isAdblockDetected = false;
  bool _checking = false;
  bool _unityAdShowing = false;
  bool _navigated = false;

  Timer? _loadWaitTimer;
  Timer? _skipTimer;
  Timer? _watchdog;

  static const String kInterstitialId = 'BP_Interstitial_Android';
  static const String kRewardedId = 'BP_Rewarded_Android';

  static const List<String> _adDomains = [
    'unityads.unity3d.com',
    'config.unityads.unity3d.com',
    'webview.unityads.unity3d.com',
  ];

  @override
  void initState() {
    super.initState();
    _runBlockCheck();
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _runBlockCheck());
    _start10SecAdLoadPhase();
  }

  void _start10SecAdLoadPhase() {
    _loadWaitTimer?.cancel();
    _isLoadingAd = true;
    _loadWaitLeft = 10;

    _requestUnityAd();

    _loadWaitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_isAdblockDetected) return;

      if (_loadWaitLeft > 1) {
        setState(() => _loadWaitLeft--);
      } else {
        timer.cancel();
        if (_isLoadingAd) {
          _onAdStartedPlaying();
        }
      }
    });
  }

  void _requestUnityAd() {
    if (_isAdblockDetected) return;

    UnityAds.load(
      placementId: kInterstitialId,
      onComplete: (placementId) {
        if (!mounted || _isAdblockDetected || _unityAdShowing) return;
        _unityAdShowing = true;
        _onAdStartedPlaying();
        UnityAds.showVideoAd(
          placementId: kInterstitialId,
          onComplete: (placementId) => _skipToNext(),
          onSkipped: (placementId) => _skipToNext(),
          onFailed: (placementId, error, message) {
            _unityAdShowing = false;
            _tryFallbackRewardedAd();
          },
        );
      },
      onFailed: (placementId, error, message) async {
        final bool blocked = await _isDnsBlocked();
        if (blocked && mounted) {
          _triggerBlock();
        } else {
          _tryFallbackRewardedAd();
        }
      },
    );
  }

  void _tryFallbackRewardedAd() {
    if (_isAdblockDetected || !mounted) return;
    UnityAds.load(
      placementId: kRewardedId,
      onComplete: (placementId) {
        if (!mounted || _isAdblockDetected || _unityAdShowing) return;
        _unityAdShowing = true;
        _onAdStartedPlaying();
        UnityAds.showVideoAd(
          placementId: kRewardedId,
          onComplete: (placementId) => _skipToNext(),
          onSkipped: (placementId) => _skipToNext(),
          onFailed: (placementId, error, message) {
            _unityAdShowing = false;
          },
        );
      },
      onFailed: (placementId, error, message) {},
    );
  }

  void _onAdStartedPlaying() {
    if (!mounted) return;
    _loadWaitTimer?.cancel();
    setState(() {
      _isLoadingAd = false;
      _skipTimeLeft = 15;
      _canSkip = false;
    });

    _skipTimer?.cancel();
    _skipTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_isAdblockDetected) return;

      if (_skipTimeLeft > 1) {
        setState(() => _skipTimeLeft--);
      } else {
        setState(() {
          _skipTimeLeft = 0;
          _canSkip = true;
        });
        timer.cancel(); // No 30s cutoff! Ad stays active until finished or user clicks Skip Ad
      }
    });
  }

  Future<bool> _isDnsBlocked() async {
    for (final host in _adDomains) {
      try {
        final result = await InternetAddress.lookup(host).timeout(const Duration(milliseconds: 900));
        if (result.isEmpty) return true;
        if (result.any((a) =>
            a.isLoopback ||
            a.address == '0.0.0.0' ||
            a.address == '127.0.0.1' ||
            a.address == '::1' ||
            a.address == '::')) {
          return true;
        }
      } catch (_) {
        try {
          final google = await InternetAddress.lookup('google.com').timeout(const Duration(milliseconds: 900));
          if (google.isNotEmpty) return true;
        } catch (_) {
          return false;
        }
      }
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
      } else if (!blocked && _isAdblockDetected) {
        _recover();
      }
    } catch (_) {
    } finally {
      _checking = false;
    }
  }

  void _triggerBlock() {
    if (!mounted) return;
    setState(() {
      _isAdblockDetected = true;
      _canSkip = false;
    });
  }

  void _recover() {
    if (!mounted) return;
    setState(() {
      _isAdblockDetected = false;
      _canSkip = false;
    });
    _start10SecAdLoadPhase();
  }

  void _skipToNext() {
    if (_isAdblockDetected || _navigated || !mounted) return;
    _navigated = true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => widget.nextScreen),
    );
  }

  Future<void> _openSponsorSite() async {
    final Uri uri = Uri.parse('https://play.google.com/store/apps');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  void dispose() {
    _loadWaitTimer?.cancel();
    _skipTimer?.cancel();
    _watchdog?.cancel();
    super.dispose();
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
              if (!_isAdblockDetected)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Colors.amber, strokeWidth: 3),
                        const SizedBox(height: 20),
                        Text(
                          _isLoadingAd
                              ? "Loading Advertisement (${_loadWaitLeft}s)..."
                              : "Sponsored Video Advertisement Playing",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 18),
                        GestureDetector(
                          onTap: _openSponsorSite,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A26),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.amber.withOpacity(0.6)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.open_in_new_rounded, color: Colors.amber, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  "Visit Advertiser Website / Play Store",
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_isAdblockDetected)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.98),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
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
                          "AdBlocker / Private DNS kindly off\nthen enjoy with your screen.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                top: 15,
                right: 15,
                child: GestureDetector(
                  onTap: (_canSkip && !_isAdblockDetected && !_isLoadingAd) ? _skipToNext : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: (_canSkip && !_isAdblockDetected && !_isLoadingAd)
                          ? Colors.white
                          : Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: (_canSkip && !_isAdblockDetected && !_isLoadingAd) ? Colors.white : Colors.grey,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isAdblockDetected || _isLoadingAd) ...[
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          _isAdblockDetected
                              ? "Loading..."
                              : (_isLoadingAd
                                  ? "Loading Ad..."
                                  : (_canSkip ? "Skip Ad" : "Skip in $_skipTimeLeft")),
                          style: TextStyle(
                            color: (_canSkip && !_isAdblockDetected && !_isLoadingAd) ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (_canSkip && !_isAdblockDetected && !_isLoadingAd) ...[
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
                    "Sponsored Ad",
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
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