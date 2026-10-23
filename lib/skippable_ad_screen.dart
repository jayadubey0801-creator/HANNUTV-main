import 'dart:async';
import 'package:flutter/material.dart';
import 'banner_ad_widget.dart';

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
  Timer? _timer;

  bool _isNavigating = false;
  bool _videoAdTriggered = false;

  @override
  void initState() {
    super.initState();
    _timeLeft = widget.adDuration;
    BannerSlotManager.pauseBanners(true);
    _startCountdown();

    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _tryLaunchUnityInterstitial();
    });
  }

  void _tryLaunchUnityInterstitial() {
    if (!mounted || _isNavigating || _videoAdTriggered) return;

    if (UnityAdsHelper.isInterstitialReady) {
      _launchInterstitialNow();
    } else {
      UnityAdsHelper.setOnAdReadyListener(() {
        if (mounted && !_isNavigating && !_videoAdTriggered) {
          _launchInterstitialNow();
        }
      });
      UnityAdsHelper.preloadInterstitial();
    }
  }

  void _launchInterstitialNow() {
    if (!mounted || _isNavigating || _videoAdTriggered) return;
    _videoAdTriggered = true;
    UnityAdsHelper.setOnAdReadyListener(null);

    UnityAdsHelper.showInterstitialAd(
      onStart: () {},
      onClosed: () {
        Future<void>.delayed(const Duration(milliseconds: 350), () {
          _goToNextScreen();
        });
      },
      onFailedToShow: () {},
    );
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_timeLeft > 0) {
        setState(() => _timeLeft--);
      } else {
        setState(() => _canSkip = true);
        timer.cancel();
      }
    });
  }

  void _goToNextScreen() {
    if (_isNavigating) return;
    _isNavigating = true;
    _timer?.cancel();
    UnityAdsHelper.setOnAdReadyListener(null);
    BannerSlotManager.pauseBanners(false);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => widget.nextScreen),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    UnityAdsHelper.setOnAdReadyListener(null);
    BannerSlotManager.pauseBanners(false);
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
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        color: Colors.redAccent,
                        strokeWidth: 2.5,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      "Loading Advertisement...",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              Positioned(
                top: 15,
                right: 15,
                child: GestureDetector(
                  onTap: _canSkip ? _goToNextScreen : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: _canSkip ? Colors.white : Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: _canSkip ? Colors.white : Colors.grey,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _canSkip ? "Skip Ad" : "Skip in $_timeLeft",
                          style: TextStyle(
                            color: _canSkip ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (_canSkip) ...[
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
            ],
          ),
        ),
      ),
    );
  }
}