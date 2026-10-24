import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

import 'unity_ads_service.dart';

class SkippableAdScreen extends StatefulWidget {
  final Widget nextScreen;
  final int adDuration;

  const SkippableAdScreen({
    Key? key,
    required this.nextScreen,
    this.adDuration = 10,
  }) : super(key: key);

  @override
  State<SkippableAdScreen> createState() => _SkippableAdScreenState();
}

class _SkippableAdScreenState extends State<SkippableAdScreen> {
  late int _timeLeft;
  bool _canSkip = false;
  bool _isAdLoading = true;
  bool _countdownStarted = false;
  Timer? _timer;

  bool _isAdblockDetected = false;
  bool _checking = false;
  Timer? _watchdog;
  bool _adShown = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _timeLeft = widget.adDuration < 10 ? 10 : widget.adDuration;

    _runBlockCheck();
    _watchdog = Timer.periodic(const Duration(seconds: 4), (_) => _runBlockCheck());

    _initAndLoadUnityAd();
  }

  Future<void> _initAndLoadUnityAd() async {
    final ok = await UnityAdsService.init();
    if (!mounted || _isAdblockDetected) return;

    if (!ok) {
      _startCountdownIfNeeded();
      return;
    }

    _loadInterstitialUnityAd();
  }

  void _loadInterstitialUnityAd() {
    if (!mounted || _isAdblockDetected || _adShown) return;

    UnityAds.load(
      placementId: UnityAdsService.interstitialPlacement,
      onComplete: (placementId) {
        if (!mounted || _isAdblockDetected || _adShown) return;
        _adShown = true;
        _startCountdownIfNeeded();
        UnityAds.showVideoAd(
          placementId: UnityAdsService.interstitialPlacement,
          onStart: (id) => _startCountdownIfNeeded(),
          onClick: (id) => debugPrint('[UnityAds] Ad Clicked: $id'),
          onSkipped: (id) => _goNext(),
          onComplete: (id) => _goNext(),
          onFailed: (id, error, message) {
            _adShown = false;
            _loadRewardedUnityAdFallback();
          },
        );
      },
      onFailed: (placementId, error, message) {
        _loadRewardedUnityAdFallback();
      },
    );
  }

  void _loadRewardedUnityAdFallback() {
    if (!mounted || _isAdblockDetected || _adShown) return;

    UnityAds.load(
      placementId: UnityAdsService.rewardedPlacement,
      onComplete: (placementId) {
        if (!mounted || _isAdblockDetected || _adShown) return;
        _adShown = true;
        _startCountdownIfNeeded();
        UnityAds.showVideoAd(
          placementId: UnityAdsService.rewardedPlacement,
          onStart: (id) => _startCountdownIfNeeded(),
          onClick: (id) => debugPrint('[UnityAds] Rewarded Clicked: $id'),
          onSkipped: (id) => _goNext(),
          onComplete: (id) => _goNext(),
          onFailed: (id, error, message) => _startCountdownIfNeeded(),
        );
      },
      onFailed: (placementId, error, message) {
        _startCountdownIfNeeded();
      },
    );
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

  static const List<String> _probeHosts = <String>[
    'unity3d.com',
    'unityads.unity3d.com',
    'config.unityads.unity3d.com',
  ];

  bool _isSinkhole(InternetAddress a) =>
      a.isLoopback || a.address == '0.0.0.0' || a.address == '::';

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
    if (res.contains(1)) return true;
    if (!res.contains(2)) return false;

    try {
      final List<InternetAddress> g =
          await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
      if (g.isEmpty) return false;
    } catch (_) {
      return false;
    }

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
      } else if (!blocked && _isAdblockDetected) {
        _recover();
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
      _timeLeft = widget.adDuration < 10 ? 10 : widget.adDuration;
      _canSkip = false;
      _adShown = false;
    });
    _initAndLoadUnityAd();
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

  void _goNext() {
    if (!mounted || _navigated || _isAdblockDetected) return;
    _navigated = true;
    _timer?.cancel();
    _watchdog?.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => widget.nextScreen),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
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
                Positioned.fill(
                  child: Container(
                    color: Colors.black,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        CircularProgressIndicator(color: Colors.amber, strokeWidth: 3),
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
                  onTap: (_canSkip && !_isAdblockDetected && !_isAdLoading) ? _goNext : null,
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
                        ],
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}