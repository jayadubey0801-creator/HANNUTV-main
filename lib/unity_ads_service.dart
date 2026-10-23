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

  static Future<bool>? _initFuture;

  static Future<bool> init() {
    return _initFuture ??= _doInit();
  }

  static Future<bool> _doInit() {
    final c = Completer<bool>();
    UnityAds.init(
      gameId: gameId,
      testMode: testMode,
      onComplete: () {
        debugPrint('[UnityAds] Initialized successfully');
        if (!c.isCompleted) c.complete(true);
      },
      onFailed: (error, message) {
        debugPrint('[UnityAds] Init failed: $error $message');
        if (!c.isCompleted) c.complete(false);
      },
    );
    return c.future.timeout(const Duration(seconds: 10), onTimeout: () => false);
  }
}
