import 'dart:async';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

class UnityAdsService {
  UnityAdsService._();

  // Unity Dashboard > Monetization > Apps me jo Game ID dikhe wahi yahan daalna
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
        if (!c.isCompleted) c.complete(true);
      },
      onFailed: (error, message) {
        if (!c.isCompleted) c.complete(false);
      },
    );
    return c.future.timeout(const Duration(seconds: 15), onTimeout: () => false);
  }
}
