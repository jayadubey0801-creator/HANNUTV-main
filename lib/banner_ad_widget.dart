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
  bool _hasError = false;
  int _reloadKey = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    if (UnityAdsService.isInitialized) {
      if (mounted) setState(() => _isInit = true);
      return;
    }

    final bool ok = await UnityAdsService.init();
    if (!mounted) return;
    if (ok) {
      setState(() => _isInit = true);
    } else {
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 4), _initAndLoad);
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() {
          _hasError = false;
          _reloadKey++;
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
    if (!_isInit) {
      return const SizedBox(
        height: 50,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2),
          ),
        ),
      );
    }

    return SizedBox(
      width: 320,
      height: 50,
      child: UnityBannerAd(
        key: ValueKey(_reloadKey),
        placementId: UnityAdsService.bannerPlacement,
        onLoad: (id) {
          debugPrint('[UnityBanner] LOAD SUCCESS: $id ✅');
          if (mounted && _hasError) setState(() => _hasError = false);
        },
        onClick: (id) => debugPrint('[UnityBanner] CLICKED: $id'),
        onShown: (id) => debugPrint('[UnityBanner] SHOWN ON SCREEN: $id'),
        onFailed: (id, error, message) {
          debugPrint('[UnityBanner] LOAD FAILED: $id | Error: $error | Msg: $message ❌');
          if (mounted) setState(() => _hasError = true);
          _scheduleRetry();
        },
      ),
    );
  }
}
