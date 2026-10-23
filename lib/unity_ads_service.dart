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

  static bool _isInitialized = false;
  static Future<bool>? _initFuture;

  static Future<bool> init() async {
    if (_isInitialized) return true;
    final bool ok = await (_initFuture ??= _doInit());
    if (!ok) {
      // Agar network delay se fail hua toh future clear karo taaki next call retry kar sake
      _initFuture = null;
    }
    return ok;
  }

  static Future<bool> _doInit() {
    final c = Completer<bool>();
    try {
      UnityAds.init(
        gameId: gameId,
        testMode: testMode,
        onComplete: () {
          debugPrint('[UnityAds] Initialized successfully');
          _isInitialized = true;
          if (!c.isCompleted) c.complete(true);
        },
        onFailed: (error, message) {
          debugPrint('[UnityAds] Init failed: $error $message');
          if (!c.isCompleted) c.complete(false);
        },
      );
    } catch (e) {
      if (!c.isCompleted) c.complete(false);
    }
    return c.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => _isInitialized,
    );
  }
}