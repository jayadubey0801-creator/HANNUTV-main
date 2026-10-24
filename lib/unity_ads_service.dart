import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

class UnityAdsService {
  UnityAdsService._();

  static const String gameId = '800405137';
  static const bool testMode = false;

  static const String bannerPlacement = 'BP_Banner_Android';
  static const String interstitialPlacement = 'BP_Interstitial_Android';
  static const String rewardedPlacement = 'BP_Rewarded_Android';

  static bool isInitialized = false;
  static Future<bool>? _initFuture;

  static Future<bool> init() async {
    if (isInitialized) return true;
    final bool ok = await (_initFuture ??= _doInit());
    if (!ok) {
      _initFuture = null;
    }
    return ok;
  }

  static Future<bool> _doInit() {
    final Completer<bool> c = Completer<bool>();
    try {
      UnityAds.init(
        gameId: gameId,
        testMode: testMode,
        onComplete: () {
          debugPrint('[UnityAds] SDK Init Complete');
          isInitialized = true;
          if (!c.isCompleted) c.complete(true);
        },
        onFailed: (error, message) {
          debugPrint('[UnityAds] SDK Init Failed: $error | $message');
          if (!c.isCompleted) c.complete(false);
        },
      );
    } catch (e) {
      debugPrint('[UnityAds] Init Exception: $e');
      if (!c.isCompleted) c.complete(false);
    }
    return c.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => isInitialized,
    );
  }
}