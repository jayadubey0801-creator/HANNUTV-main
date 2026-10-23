import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'unity_ads_service.dart';

class CustomBannerAd extends StatefulWidget {
  // Purane code se compatible rakha hai (widgets.dart me htmlBannerCode pass hota hai), ab use nahi hota
  final String htmlBannerCode;

  const CustomBannerAd({Key? key, this.htmlBannerCode = ''}) : super(key: key);

  @override
  State<CustomBannerAd> createState() => _CustomBannerAdState();
}

class _CustomBannerAdState extends State<CustomBannerAd> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    UnityAdsService.init().then((ok) {
      if (mounted && ok) setState(() => _ready = true);
    });
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
        child: _ready
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
            : const SizedBox.shrink(),
      ),
    );
  }
}
