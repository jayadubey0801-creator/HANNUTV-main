import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'unity_ads_service.dart';

class CustomBannerAd extends StatefulWidget {
  final String htmlBannerCode;

  const CustomBannerAd({Key? key, required this.htmlBannerCode}) : super(key: key);

  @override
  State<CustomBannerAd> createState() => _CustomBannerAdState();
}

class _CustomBannerAdState extends State<CustomBannerAd> {
  bool _isAdblockDetected = false;
  Timer? _watchdog;
  bool _isUnityReady = false;

  @override
  void initState() {
    super.initState();
    _checkDeepBannerAdblock();
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) => _checkDeepBannerAdblock());

    UnityAdsService.init().then((ok) {
      if (mounted && ok) {
        setState(() => _isUnityReady = true);
      }
    });
  }

  void _checkDeepBannerAdblock() async {
    bool isBlocked = false;
    try {
      final addresses = await InternetAddress.lookup('unity3d.com').timeout(const Duration(seconds: 1));
      for (var addr in addresses) {
        if (addr.address == '0.0.0.0' || addr.address == '127.0.0.1' || addr.address == '::1' || addr.address == '::') {
          isBlocked = true;
          break;
        }
      }
    } catch (e) {
      try {
        final googleCheck = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 1));
        if (googleCheck.isNotEmpty) {
          isBlocked = true;
        }
      } catch (e2) {}
    }

    if (mounted && isBlocked != _isAdblockDetected) {
      setState(() {
        _isAdblockDetected = isBlocked;
      });
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 60,
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _isAdblockDetected
            ? Container(
                color: Colors.grey[900],
                child: const Center(
                  child: Text(
                    "Please off pvtdns / adguard",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            : (_isUnityReady
                ? Center(
                    child: UnityBannerAd(
                      placementId: UnityAdsService.bannerPlacement,
                      size: BannerSize.standard,
                      onLoad: (id) => debugPrint('Banner loaded: $id'),
                      onClick: (id) => debugPrint('Banner clicked: $id'),
                      onShown: (id) => debugPrint('Banner shown: $id'),
                      onFailed: (id, error, message) =>
                          debugPrint('Banner failed: $id $error $message'),
                    ),
                  )
                : const SizedBox.shrink()),
      ),
    );
  }
}
