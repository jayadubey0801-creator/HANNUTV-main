import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

class UnityAdsService {
  UnityAdsService._();

  // 🔥 UNITY DASHBOARD IDS 🔥
  static const String gameId = '800405137';
  static const bool testMode = false; // Production Live Earning Mode

  static const String bannerPlacement = 'BP_Banner_Android';
  static const String interstitialPlacement = 'BP_Interstitial_Android';
  static const String rewardedPlacement = 'BP_Rewarded_Android';

  static bool _isInitialized = false;
  static Future<bool>? _initFuture;

  static bool get isInitialized => _isInitialized;

  static Future<bool> init() async {
    if (_isInitialized) return true;
    final bool ok = await (_initFuture ??= _doInit());
    if (!ok) {
      _initFuture = null; // Auto-retry on next request if initial network failed
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
          debugPrint('[UnityAds] Initialized successfully ✅');
          _isInitialized = true;
          if (!c.isCompleted) c.complete(true);
        },
        onFailed: (error, message) {
          debugPrint('[UnityAds] Init failed: $error | $message');
          if (!c.isCompleted) c.complete(false);
        },
      );
    } catch (e) {
      debugPrint('[UnityAds] Init exception: $e');
      if (!c.isCompleted) c.complete(false);
    }
    return c.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => _isInitialized,
    );
  }
}
