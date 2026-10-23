import 'package:flutter/material.dart';
import 'dart:async';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'unity_ads_service.dart';

class SkippableAdScreen extends StatefulWidget {
  final Widget nextScreen;
  final int adDuration;

  const SkippableAdScreen({
    Key? key,
    required this.nextScreen,
    this.adDuration = 15, // FIXED TO 15 SECONDS FOR MOVIES
  }) : super(key: key);

  @override
  State<SkippableAdScreen> createState() => _SkippableAdScreenState();
}

class _SkippableAdScreenState extends State<SkippableAdScreen> {
  late int _timeLeft;
  bool _canSkip = false;
  bool _isAdLoading = true; // Jab tak ad load na ho tab tak Loading Ad... rahega
  bool _countdownStarted = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timeLeft = widget.adDuration < 15 ? 15 : widget.adDuration;
    _loadUnityAd();
  }

  Future<void> _loadUnityAd() async {
    final ok = await UnityAdsService.init();
    if (!mounted) return;
    if (!ok) {
      _startCountdownIfNeeded();
      return;
    }
    UnityAds.load(
      placementId: UnityAdsService.interstitialPlacement,
      onComplete: (placementId) => _showUnityAd(),
      onFailed: (placementId, error, message) {
        debugPrint('Unity load failed: $error $message');
        _startCountdownIfNeeded();
      },
    );
  }

  void _showUnityAd() {
    if (!mounted) return;
    _startCountdownIfNeeded();
    UnityAds.showVideoAd(
      placementId: UnityAdsService.interstitialPlacement,
      onStart: (id) {},
      onClick: (id) {},
      onSkipped: (id) {
        if (mounted) setState(() => _canSkip = true);
      },
      onComplete: (id) {
        if (mounted) setState(() => _canSkip = true);
      },
      onFailed: (id, error, message) {
        debugPrint('Unity show failed: $error $message');
      },
    );
  }

  void _startCountdownIfNeeded() {
    if (!mounted) return;
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
      if (_timeLeft > 0) {
        if (mounted) setState(() => _timeLeft--);
      } else {
        if (mounted) setState(() => _canSkip = true);
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _skipAd() {
    if (!_canSkip || _isAdLoading) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => widget.nextScreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool active = _canSkip && !_isAdLoading;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              if (_isAdLoading)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black.withOpacity(0.90),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          CircularProgressIndicator(color: Colors.amber, strokeWidth: 3),
                          SizedBox(height: 16),
                          Text(
                            "Loading Ad...",
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 15,
                right: 15,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: active ? _skipAd : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: active ? Colors.white : Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: active ? Colors.white : Colors.grey),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isAdLoading) ...[
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          _isAdLoading ? "Loading Ad..." : (_canSkip ? "Skip Ad" : "Skip in $_timeLeft"),
                          style: TextStyle(
                            color: active ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (active) ...[
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
