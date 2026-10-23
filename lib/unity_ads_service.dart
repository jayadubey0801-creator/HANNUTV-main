import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

class UnityAdsHelper {
  UnityAdsHelper._();

  // 🔥 Teri Unity Dashboard ki Exact IDs 🔥
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

  /// App start hote hi Unity Ads ko initialize aur preload karega
  static Future<void> init() async {
    if (isInitialized.value || _initInProgress) return;
    _initInProgress = true;

    try {
      await UnityAds.init(
        gameId: gameId,
        testMode: false, // 🔥 Real Earning ke liye hamesha FALSE rahega
        onComplete: () {
          debugPrint('✅ Unity Ads Init Complete');
          _initInProgress = false;
          isInitialized.value = true;
          preloadAds();
        },
        onFailed: (error, message) {
          debugPrint('❌ Unity Ads Init Failed: $error - $message');
          _initInProgress = false;
          // 10 second baad wapas init try karega agar net slow tha
          Future<void>.delayed(const Duration(seconds: 10), init);
        },
      );
    } catch (e) {
      _initInProgress = false;
      debugPrint('Unity Ads Init Exception: $e');
    }
  }

  /// Interstitial aur Rewarded dono ko pehle se load karke ready rakhega
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
        // 12 sec baad auto-retry
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
        // 15 sec baad auto-retry
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

  /// Agar SkippableAdScreen khulte waqt ad load ho raha hai, toh load hote hi notify karega
  static void setOnAdReadyListener(VoidCallback? listener) {
    _onAdReadyListener = listener;
  }

  /// Smart Show: Pehle Interstitial dikhayega, agar wo ready nahi hai toh Rewarded dikhayega
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

    String? targetPlacement;
    if (_interstitialReady) {
      targetPlacement = interstitialId;
      _interstitialReady = false;
    } else if (_rewardedReady) {
      targetPlacement = rewardedId;
      _rewardedReady = false;
    } else {
      // Agar preloaded flag false bhi hai, tab bhi Interstitial try karenge aur preload trigger karenge
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
        debugPrint('👉 Unity Ad Clicked (Redirecting to PlayStore/Browser): $placementId');
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
        // Agar Interstitial fail hua aur Rewarded ready hai, toh turant Rewarded chala do
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