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

  @override
  void initState() {
    super.initState();
    UnityAdsService.init().then((ok) {
      if (mounted) {
        setState(() => _isInit = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 60,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF14141F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: _isInit
          ? UnityBannerAd(
              placementId: UnityAdsService.bannerPlacement,
              size: BannerSize.standard,
              onLoad: (id) => debugPrint('[UnityBanner] Loaded: $id'),
              onClick: (id) => debugPrint('[UnityBanner] Clicked: $id'),
              onShown: (id) => debugPrint('[UnityBanner] Shown: $id'),
              onFailed: (id, error, message) =>
                  debugPrint('[UnityBanner] Failed: $id | Error: $error | Msg: $message'),
            )
          : const SizedBox.shrink(),
    );
  }
}