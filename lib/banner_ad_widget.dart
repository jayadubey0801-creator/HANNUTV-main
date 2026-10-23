import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

// ═══════════════════════════════════════════════════════════════════
// 🔥 UNITY ADS HELPER (ONLY SKIPPABLE INTERSTITIAL + BANNER) 🔥
// ═══════════════════════════════════════════════════════════════════
class UnityAdsHelper {
  UnityAdsHelper._();

  static const String gameId = '800405137';
  static const String bannerId = 'BP_Banner_Android';
  static const String interstitialId = 'BP_Interstitial_Android';

  static final ValueNotifier<bool> isInitialized = ValueNotifier<bool>(false);

  static bool _initInProgress = false;
  static bool _interstitialReady = false;
  static bool _loadingInterstitial = false;
  static VoidCallback? _onAdReadyListener;

  static Future<void> init() async {
    if (isInitialized.value || _initInProgress) return;
    _initInProgress = true;

    try {
      await UnityAds.init(
        gameId: gameId,
        testMode: false,
        onComplete: () {
          debugPrint('✅ Unity Ads Init Complete');
          _initInProgress = false;
          isInitialized.value = true;
          preloadInterstitial();
        },
        onFailed: (error, message) {
          debugPrint('❌ Unity Ads Init Failed: $error - $message');
          _initInProgress = false;
          Future<void>.delayed(const Duration(seconds: 8), init);
        },
      );
    } catch (e) {
      _initInProgress = false;
      debugPrint('Unity Ads Init Exception: $e');
    }
  }

  static void preloadInterstitial() {
    if (!isInitialized.value) {
      init();
      return;
    }
    if (_interstitialReady || _loadingInterstitial) return;
    _loadingInterstitial = true;

    UnityAds.load(
      placementId: interstitialId,
      onComplete: (placementId) {
        debugPrint('✅ Unity Skippable Interstitial Loaded: $placementId');
        _loadingInterstitial = false;
        _interstitialReady = true;
        if (_onAdReadyListener != null) {
          final VoidCallback cb = _onAdReadyListener!;
          _onAdReadyListener = null;
          cb();
        }
      },
      onFailed: (placementId, error, message) {
        debugPrint('⚠️ Interstitial Load Failed ($error): $message');
        _loadingInterstitial = false;
        _interstitialReady = false;
        Future<void>.delayed(const Duration(seconds: 10), () {
          if (isInitialized.value && !_interstitialReady) {
            preloadInterstitial();
          }
        });
      },
    );
  }

  static bool get isInterstitialReady => _interstitialReady;

  static void setOnAdReadyListener(VoidCallback? listener) {
    _onAdReadyListener = listener;
  }

  /// Sirf Skippable Interstitial Ad dikhayega
  static void showInterstitialAd({
    required VoidCallback onStart,
    required VoidCallback onClosed,
    required VoidCallback onFailedToShow,
  }) {
    if (!isInitialized.value) {
      init();
      onFailedToShow();
      return;
    }

    _interstitialReady = false;

    UnityAds.showVideoAd(
      placementId: interstitialId,
      onStart: (placementId) {
        debugPrint('🎬 Unity Interstitial Started: $placementId');
        onStart();
      },
      onClick: (placementId) {
        debugPrint('👉 Unity Interstitial Clicked: $placementId');
      },
      onSkipped: (placementId) {
        debugPrint('⏭️ Unity Interstitial Skipped: $placementId');
        preloadInterstitial();
        onClosed();
      },
      onComplete: (placementId) {
        debugPrint('✅ Unity Interstitial Completed: $placementId');
        preloadInterstitial();
        onClosed();
      },
      onFailed: (placementId, error, message) {
        debugPrint('❌ Unity Interstitial Failed: $error - $message');
        preloadInterstitial();
        onFailedToShow();
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 🔥 PUBLIC BANNER SLOT MANAGER (NO UNDERSCORE SCOPE ERROR) 🔥
// ═══════════════════════════════════════════════════════════════════
class BannerSlotManager {
  BannerSlotManager._();

  static final List<_CustomBannerAdState> _slots = <_CustomBannerAdState>[];
  static _CustomBannerAdState? _activeOwner;
  static Timer? _scanTimer;
  static bool _pausedForFullscreenAd = false;

  static void pauseBanners(bool paused) {
    _pausedForFullscreenAd = paused;
    if (paused) {
      _setOwner(null);
    } else {
      _evaluate();
    }
  }

  static void register(_CustomBannerAdState slot) {
    if (!_slots.contains(slot)) {
      _slots.add(slot);
    }
    _startScannerIfNeeded();
    _evaluate();
  }

  static void unregister(_CustomBannerAdState slot) {
    _slots.remove(slot);
    if (_activeOwner == slot) {
      _activeOwner = null;
    }
    if (_slots.isEmpty) {
      _scanTimer?.cancel();
      _scanTimer = null;
    } else {
      _evaluate();
    }
  }

  static void _startScannerIfNeeded() {
    _scanTimer ??= Timer.periodic(const Duration(milliseconds: 700), (_) {
      _evaluate();
    });
  }

  static void _setOwner(_CustomBannerAdState? newOwner) {
    if (_activeOwner == newOwner) return;
    final _CustomBannerAdState? oldOwner = _activeOwner;
    _activeOwner = newOwner;
    oldOwner?._onOwnershipChanged();
    newOwner?._onOwnershipChanged();
  }

  static void _evaluate() {
    if (_pausedForFullscreenAd || !UnityAdsHelper.isInitialized.value) {
      _setOwner(null);
      return;
    }

    _CustomBannerAdState? bestCandidate;
    double bestScore = double.infinity;

    for (final _CustomBannerAdState s in List<_CustomBannerAdState>.from(_slots)) {
      if (!s.mounted || !s._isReadyForPlatformView) continue;
      final BuildContext ctx = s.context;

      final ModalRoute<dynamic>? route = ModalRoute.of(ctx);
      if (route != null && !route.isCurrent) continue;

      final RenderObject? ro = ctx.findRenderObject();
      if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;

      final Offset pos = ro.localToGlobal(Offset.zero);
      final double screenH = MediaQuery.of(ctx).size.height;

      final bool inViewport = pos.dy >= -10 && (pos.dy + ro.size.height) <= (screenH + 20);
      if (inViewport && pos.dy < bestScore) {
        bestScore = pos.dy;
        bestCandidate = s;
      }
    }

    if (_activeOwner != null &&
        _activeOwner!.mounted &&
        _activeOwner!._isReadyForPlatformView &&
        bestCandidate == _activeOwner) {
      return;
    }

    _setOwner(bestCandidate);
  }
}

// ═══════════════════════════════════════════════════════════════════
// 🔥 CUSTOM BANNER AD WIDGET (EXACT 320x50, NO CLIPRRECT BUG) 🔥
// ═══════════════════════════════════════════════════════════════════
class CustomBannerAd extends StatefulWidget {
  final String? htmlBannerCode;

  const CustomBannerAd({Key? key, this.htmlBannerCode}) : super(key: key);

  @override
  State<CustomBannerAd> createState() => _CustomBannerAdState();
}

class _CustomBannerAdState extends State<CustomBannerAd> {
  bool _isReadyForPlatformView = false;
  Timer? _mountDelayTimer;
  Timer? _retryTimer;
  int _reloadKey = 0;

  bool get _isOwner => BannerSlotManager._activeOwner == this;

  @override
  void initState() {
    super.initState();
    UnityAdsHelper.init();

    // Video Player ke WebView ko pehle load hone do taaki surface swap na ho
    _mountDelayTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() {
        _isReadyForPlatformView = true;
      });
      BannerSlotManager.register(this);
    });
  }

  void _onOwnershipChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _isOwner) {
        setState(() {
          _reloadKey++;
        });
      }
    });
  }

  @override
  void dispose() {
    _mountDelayTimer?.cancel();
    _retryTimer?.cancel();
    BannerSlotManager.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: UnityAdsHelper.isInitialized,
      builder: (context, initialized, _) {
        final bool showUnityBanner = initialized && _isReadyForPlatformView && _isOwner;

        return Container(
          width: double.infinity,
          height: 52,
          alignment: Alignment.center,
          color: Colors.transparent,
          child: showUnityBanner
              ? SizedBox(
                  width: 320,
                  height: 50,
                  child: UnityBannerAd(
                    key: ValueKey<String>('hannu_unity_banner_$_reloadKey'),
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
                  ),
                )
              : Container(
                  width: 320,
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Text(
                    "Sponsored Ad",
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        );
      },
    );
  }
}