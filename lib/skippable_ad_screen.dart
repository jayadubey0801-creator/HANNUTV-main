import 'dart:async';
import 'package:flutter/material.dart';
import 'banner_ad_widget.dart';
import 'unity_ads_helper.dart';

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
  bool _isNativeAdShowing = false;

  @override
  void initState() {
    super.initState();
    _timeLeft = widget.adDuration;
    _startCountdown();

    // 🔥 First frame ke baad safely Unity Video Ad trigger karo (No Build Crash) 🔥
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryLaunchUnityVideoAd();
    });
  }

  void _tryLaunchUnityVideoAd() {
    if (!mounted || _isNavigating || _videoAdTriggered) return;

    if (UnityAdsHelper.hasAnyVideoAdReady) {
      _launchVideoAdNow();
    } else {
      // Agar abhi load ho raha hai, toh load complete hote hi turant dikhao
      UnityAdsHelper.preloadAds();
      UnityAdsHelper.setOnAdReadyListener(() {
        if (mounted && !_isNavigating && !_videoAdTriggered) {
          _launchVideoAdNow();
        }
      });
    }
  }

  void _launchVideoAdNow() {
    if (!mounted || _isNavigating || _videoAdTriggered) return;
    _videoAdTriggered = true;
    UnityAdsHelper.setOnAdReadyListener(null);

    UnityAdsHelper.showFullScreenAd(
      onStart: () {
        _isNativeAdShowing = true;
      },
      onClosed: () {
        _isNativeAdShowing = false;
        // Native Unity Ad skip ya complete hote hi sidha movie/nextScreen chalu karo
        _goToNextScreen();
      },
      onFailedToShow: () {
        _isNativeAdShowing = false;
        // Agar video ad fail ho jaye, toh fallback timer aur banner chalte rahenge
      },
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
              // 🔥 Center Unity Ad Area (Koi WebView nahi, sirf Native Unity Ads) 🔥
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.ondemand_video_rounded,
                        color: Colors.redAccent,
                        size: 54,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isNativeAdShowing
                            ? "Playing Sponsored Video Ad..."
                            : (_canSkip
                                ? "Ad Ready to Skip"
                                : "Loading Sponsored Ad... ($_timeLeft s)"),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Click on the ad to visit Play Store / Browser",
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const SizedBox(height: 30),
                      const CustomBannerAd(),
                      const SizedBox(height: 12),
                      const CustomBannerAd(),
                    ],
                  ),
                ),
              ),

              // 🔥 Top-Right Skip Timer / Button 🔥
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

              // 🔥 Bottom-Left Ad Badge 🔥
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