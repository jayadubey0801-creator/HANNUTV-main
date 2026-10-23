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
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    _startInitFlow();
    // 🔥 Watchdog: agar ad load na ho ya fail ho jaye toh har 10s me fresh request karega taaki column gayab na ho
    _watchdog = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && UnityAdsService.isInitialized) {
        setState(() => _reloadKey++);
      }
    });
  }

  Future<void> _startInitFlow() async {
    if (UnityAdsService.isInitialized) {
      if (mounted) setState(() => _isInit = true);
      return;
    }
    final bool ok = await UnityAdsService.init();
    if (!mounted) return;
    if (ok) {
      setState(() => _isInit = true);
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 PERMANENT FIXED SIZE BOX: Chahe ad load ho ya reload ho, height/width kabhi gayab nahi hogi!
    return Container(
      width: 320,
      height: 52,
      alignment: Alignment.center,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF14141F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: _isInit
          ? SizedBox(
              width: 320,
              height: 50,
              child: UnityBannerAd(
                key: ValueKey(_reloadKey),
                placementId: UnityAdsService.bannerPlacement,
                size: BannerSize.standard,
                onLoad: (id) => debugPrint('[UnityBanner] LOAD SUCCESS: $id ✅'),
                onClick: (id) => debugPrint('[UnityBanner] CLICKED: $id'),
                onShown: (id) => debugPrint('[UnityBanner] SHOWN: $id'),
                onFailed: (id, error, message) {
                  debugPrint('[UnityBanner] FAILED: $id | $error | $message ❌');
                },
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text(
                  "Sponsored Ad",
                  style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
    );
  }
}
