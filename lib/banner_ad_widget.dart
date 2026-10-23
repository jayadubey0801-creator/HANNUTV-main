import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

// ═══════════════════════════════════════════════════════════════════
// 🔥 DEEP UNITY ADS HELPER (AUTO-INIT + WATERFALL LOGIC) 🔥
// ═══════════════════════════════════════════════════════════════════
class UnityAdsHelper {
  UnityAdsHelper._();

  // Teri Unity Dashboard ki Exact Placement IDs
  static const String gameId = '800405137';
  static const String bannerId = 'BP_Banner_Android';
  static const String interstitialId = 'BP_Interstitial_Android';
  static const String rewardedId = 'BP_Rewarded_Android';

  static final ValueNotifier<bool> isInitialized = ValueNotifier<bool>(false);

  static bool _initInProgress = false;
  static bool _interstitialReady = false;
  static bool _rewardedReady = false;
  static bool _loadingInterstitial = false;
  static bool _loadingRewarded = false;

  static VoidCallback? _onAdReadyListener;

  /// Unity Ads ko initialize aur preload karega
  static Future<void> init() async {
    if (isInitialized.value || _initInProgress) return;
    _initInProgress = true;

    try {
      await UnityAds.init(
        gameId: gameId,
        testMode: false, // 🔥 Real Earning ke liye FALSE
        onComplete: () {
          debugPrint('✅ Unity Ads Init Complete');
          _initInProgress = false;
          isInitialized.value = true;
          preloadAds();
        },
        onFailed: (error, message) {
          debugPrint('❌ Unity Ads Init Failed: $error - $message');
          _initInProgress = false;
          Future<void>.delayed(const Duration(seconds: 10), init);
        },
      );
    } catch (e) {
      _initInProgress = false;
      debugPrint('Unity Ads Init Exception: $e');
    }
  }

  /// Interstitial aur Rewarded dono ko background me load karke ready rakhega
  static void preloadAds() {
    if (!isInitialized.value) {
      init();
      return;
    }
    _loadInterstitial();
    _loadRewarded();
  }

  static void _loadInterstitial() {
    if (_interstitialReady || _loadingInterstitial) return;
    _loadingInterstitial = true;

    UnityAds.load(
      placementId: interstitialId,
      onComplete: (placementId) {
        debugPrint('✅ Unity Interstitial Loaded: $placementId');
        _loadingInterstitial = false;
        _interstitialReady = true;
        _notifyListenerIfWaiting();
      },
      onFailed: (placementId, error, message) {
        debugPrint('⚠️ Interstitial Load Failed ($error): $message');
        _loadingInterstitial = false;
        _interstitialReady = false;
        Future<void>.delayed(const Duration(seconds: 12), () {
          if (isInitialized.value && !_interstitialReady) _loadInterstitial();
        });
      },
    );
  }

  static void _loadRewarded() {
    if (_rewardedReady || _loadingRewarded) return;
    _loadingRewarded = true;

    UnityAds.load(
      placementId: rewardedId,
      onComplete: (placementId) {
        debugPrint('✅ Unity Rewarded Loaded: $placementId');
        _loadingRewarded = false;
        _rewardedReady = true;
        _notifyListenerIfWaiting();
      },
      onFailed: (placementId, error, message) {
        debugPrint('⚠️ Rewarded Load Failed ($error): $message');
        _loadingRewarded = false;
        _rewardedReady = false;
        Future<void>.delayed(const Duration(seconds: 15), () {
          if (isInitialized.value && !_rewardedReady) _loadRewarded();
        });
      },
    );
  }

  static void _notifyListenerIfWaiting() {
    if (_onAdReadyListener != null) {
      final VoidCallback cb = _onAdReadyListener!;
      _onAdReadyListener = null;
      cb();
    }
  }

  static bool get hasAnyVideoAdReady => _interstitialReady || _rewardedReady;

  static void setOnAdReadyListener(VoidCallback? listener) {
    _onAdReadyListener = listener;
  }

  /// Pehle Interstitial dikhayega, agar wo ready nahi hai toh Rewarded chala dega
  static void showFullScreenAd({
    required VoidCallback onStart,
    required VoidCallback onClosed,
    required VoidCallback onFailedToShow,
  }) {
    if (!isInitialized.value) {
      init();
      onFailedToShow();
      return;
    }

    String targetPlacement;
    if (_interstitialReady) {
      targetPlacement = interstitialId;
      _interstitialReady = false;
    } else if (_rewardedReady) {
      targetPlacement = rewardedId;
      _rewardedReady = false;
    } else {
      targetPlacement = interstitialId;
      preloadAds();
    }

    UnityAds.showVideoAd(
      placementId: targetPlacement,
      onStart: (placementId) {
        debugPrint('🎬 Unity Ad Started: $placementId');
        onStart();
      },
      onClick: (placementId) {
        debugPrint('👉 Unity Ad Clicked (External Browser/PlayStore): $placementId');
      },
      onSkipped: (placementId) {
        debugPrint('⏭️ Unity Ad Skipped: $placementId');
        preloadAds();
        onClosed();
      },
      onComplete: (placementId) {
        debugPrint('✅ Unity Ad Completed: $placementId');
        preloadAds();
        onClosed();
      },
      onFailed: (placementId, error, message) {
        debugPrint('❌ Unity Ad Show Failed ($placementId): $error - $message');
        if (placementId == interstitialId && _rewardedReady) {
          _rewardedReady = false;
          UnityAds.showVideoAd(
            placementId: rewardedId,
            onStart: (_) => onStart(),
            onClick: (_) {},
            onSkipped: (_) {
              preloadAds();
              onClosed();
            },
            onComplete: (_) {
              preloadAds();
              onClosed();
            },
            onFailed: (_, __, ___) {
              preloadAds();
              onFailedToShow();
            },
          );
          return;
        }
        preloadAds();
        onFailedToShow();
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 🔥 CUSTOM UNITY BANNER AD WIDGET 🔥
// ═══════════════════════════════════════════════════════════════════
class CustomBannerAd extends StatefulWidget {
  final String? htmlBannerCode; // Purane calls ko error-free rakhne ke liye

  const CustomBannerAd({Key? key, this.htmlBannerCode}) : super(key: key);

  @override
  State<CustomBannerAd> createState() => _CustomBannerAdState();
}

class _CustomBannerAdState extends State<CustomBannerAd> {
  Timer? _retryTimer;
  int _reloadAttempt = 0;

  @override
  void initState() {
    super.initState();
    if (!UnityAdsHelper.isInitialized.value) {
      UnityAdsHelper.init();
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) {
        setState(() {
          _reloadAttempt++;
        });
      }
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 55,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ValueListenableBuilder<bool>(
          valueListenable: UnityAdsHelper.isInitialized,
          builder: (context, initialized, _) {
            if (!initialized) {
              return const SizedBox(
                height: 50,
                child: Center(
                  child: Text(
                    "Sponsored",
                    style: TextStyle(color: Colors.white24, fontSize: 11),
                  ),
                ),
              );
            }

            return UnityBannerAd(
              key: ValueKey<String>('unity_banner_$_reloadAttempt'),
              placementId: UnityAdsHelper.bannerId,
              size: BannerSize.standard,
              onLoad: (placementId) {
                debugPrint('✅ Unity Banner Loaded: $placementId');
              },
              onClick: (placementId) {
                debugPrint('👉 Unity Banner Clicked: $placementId');
              },
              onFailed: (placementId, error, message) {
                debugPrint('⚠️ Unity Banner Failed ($error): $message');
                _scheduleRetry();
              },
            );
          },
        ),
      ),
    );
  }
}