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
  bool _ready = false;
  int _reloadKey = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _startBanner();
  }

  Future<void> _startBanner() async {
    final ok = await UnityAdsService.init();
    if (!mounted) return;
    if (ok) {
      setState(() => _ready = true);
    } else {
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 3), _startBanner);
    }
  }

  void _onAdFailed() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 5), () {
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
    if (!_ready) {
      return const SizedBox(
        width: 320,
        height: 50,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2),
          ),
        ),
      );
    }

    // 🔥 Exact Unity standard 320x50 size constraint with direct plugin widget
    return SizedBox(
      key: ValueKey(_reloadKey),
      width: 320,
      height: 50,
      child: UnityBannerAd(
        placementId: UnityAdsService.bannerPlacement,
        onLoad: (id) => debugPrint('[UnityBanner] LOADED: $id ✅'),
        onClick: (id) => debugPrint('[UnityBanner] CLICKED: $id'),
        onShown: (id) => debugPrint('[UnityBanner] SHOWN: $id'),
        onFailed: (id, error, message) {
          debugPrint('[UnityBanner] FAILED: $id | $error | $message ❌');
          _onAdFailed();
        },
      ),
    );
  }
}
