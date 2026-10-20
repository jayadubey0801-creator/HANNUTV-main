import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

class SkippableAdScreen extends StatefulWidget {
  final Widget nextScreen;
  final int adDuration;

  const SkippableAdScreen({
    Key? key,
    required this.nextScreen,
    this.adDuration = 30, // 30 second ka ad
  }) : super(key: key);

  @override
  State<SkippableAdScreen> createState() => _SkippableAdScreenState();
}

class _SkippableAdScreenState extends State<SkippableAdScreen> {
  late int _timeLeft;
  int _skipTimeLeft = 15; // 15 second tak skip hide rahega
  bool _canSkip = false;
  bool _isAdblockDetected = false;
  bool _checking = false;
  bool _unityAdShowing = false;
  bool _navigated = false;

  Timer? _timer;
  Timer? _watchdog;

  final String adUnitId = 'Interstitial_Android';

  static const List<String> _adDomains = [
    'unityads.unity3d.com',
    'config.unityads.unity3d.com',
    'webview.unityads.unity3d.com',
  ];

  @override
  void initState() {
    super.initState();
    _timeLeft = widget.adDuration;

    _runBlockCheck();
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _runBlockCheck());

    _startCountdown();
    _loadUnityAd();
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isAdblockDetected) return; 

      if (_skipTimeLeft > 0) {
        if (mounted) setState(() => _skipTimeLeft--);
      } else if (!_canSkip) {
         if (mounted) setState(() => _canSkip = true);
      }

      if (_timeLeft > 0) {
        if (mounted) setState(() => _timeLeft--);
      } else {
        _skipToNext();
      }
    });
  }

  void _loadUnityAd() {
    if (_isAdblockDetected) return;

    UnityAds.load(
      placementId: adUnitId,
      onComplete: (placementId) {
        if (!mounted || _isAdblockDetected || _unityAdShowing) return;
        _unityAdShowing = true;
        UnityAds.showVideoAd(
          placementId: adUnitId,
          onComplete: (placementId) => _skipToNext(),
          onSkipped: (placementId) => _skipToNext(),
          onFailed: (placementId, error, message) {
            _unityAdShowing = false;
            _runBlockCheck();
          },
        );
      },
      onFailed: (placementId, error, message) async {
        final bool blocked = await _isDnsBlocked();
        if (blocked && mounted) {
          _triggerBlock();
        } else {
            _skipToNext(); // Agar Unity fail ho aur DNS theek ho, toh direct movie play
        }
      },
    );
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
          if (google.isNotEmpty) {
            return true; 
          }
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
      _timeLeft = widget.adDuration;
      _skipTimeLeft = 15;
      _canSkip = false;
    });
    _startCountdown();
    _loadUnityAd();
  }

  void _skipToNext() {
    if (_isAdblockDetected || _navigated || !mounted) return;
    _navigated = true;
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
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      CircularProgressIndicator(color: Colors.redAccent),
                      SizedBox(height: 20),
                      Text(
                        "Loading Advertisement...",
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
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
                  onTap: (_canSkip && !_isAdblockDetected) ? _skipToNext : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: (_canSkip && !_isAdblockDetected) ? Colors.white : Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: (_canSkip && !_isAdblockDetected) ? Colors.white : Colors.grey,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isAdblockDetected) ...[
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
                              : (_canSkip ? "Skip Ad" : "Skip in $_skipTimeLeft"),
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
                bottom: 20,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    "Ad closes in $_timeLeft",
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
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