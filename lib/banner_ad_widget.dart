import 'dart:async';
import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'unity_ads_service.dart';

class CustomBannerAd extends StatefulWidget {
  final String htmlBannerCode;

  const CustomBannerAd({Key? key, this.htmlBannerCode = ''}) : super(key: key);

  @override
  State<CustomBannerAd> createState() => _CustomBannerAdState();
}

class _CustomBannerAdState extends State<CustomBannerAd> {
  bool _isInit = false;
  int _reloadKey = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _setupUnityBanner();
  }

  Future<void> _setupUnityBanner() async {
    final bool ok = await UnityAdsService.init();
    if (!mounted) return;
    if (ok) {
      setState(() => _isInit = true);
    } else {
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 3), _setupUnityBanner);
    }
  }

  void _scheduleBannerRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() => _reloadKey++);
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
    return Center(
      child: Container(
        width: 320,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF14141F),
          borderRadius: BorderRadius.circular(8),
        ),
        child: _isInit
            ? SizedBox(
                width: 320,
                height: 50,
                child: UnityBannerAd(
                  key: ValueKey<int>(_reloadKey),
                  placementId: UnityAdsService.bannerPlacement,
                  size: BannerSize.standard,
                  onLoad: (id) => debugPrint('[UnityBanner] Loaded: $id'),
                  onClick: (id) => debugPrint('[UnityBanner] Clicked: $id'),
                  onShown: (id) => debugPrint('[UnityBanner] Shown: $id'),
                  onFailed: (id, error, message) {
                    debugPrint('[UnityBanner] Failed: $id | $error | $message');
                    _scheduleBannerRetry();
                  },
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}