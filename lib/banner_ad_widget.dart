import 'dart:async';
import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'unity_ads_helper.dart';

class CustomBannerAd extends StatefulWidget {
  final String? htmlBannerCode; // Purane calls ko break hone se bachane ke liye rakha hai

  const CustomBannerAd({Key? key, this.htmlBannerCode}) : super(key: key);

  @override
  State<CustomBannerAd> createState() => _CustomBannerAdState();
}

class _CustomBannerAdState extends State<CustomBannerAd> {
  Timer? _retryTimer;
  int _reloadAttempt = 0;

  @override
  void initState() {
    super.initState();
    if (!UnityAdsHelper.isInitialized.value) {
      UnityAdsHelper.init();
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) {
        setState(() {
          _reloadAttempt++;
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
    return Container(
      width: double.infinity,
      height: 55,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ValueListenableBuilder<bool>(
          valueListenable: UnityAdsHelper.isInitialized,
          builder: (context, initialized, _) {
            if (!initialized) {
              return const SizedBox(
                height: 50,
                child: Center(
                  child: Text(
                    "Sponsored",
                    style: TextStyle(color: Colors.white24, fontSize: 11),
                  ),
                ),
              );
            }

            return UnityBannerAd(
              key: ValueKey<String>('unity_banner_$_reloadAttempt'),
              placementId: UnityAdsHelper.bannerId,
              size: BannerSize.standard,
              onLoad: (placementId) {
                debugPrint('✅ Unity Banner Loaded: $placementId');
              },
              onClick: (placementId) {
                debugPrint('👉 Unity Banner Clicked (External Redirect): $placementId');
              },
              onFailed: (placementId, error, message) {
                debugPrint('⚠️ Unity Banner Failed ($error): $message');
                _scheduleRetry();
              },
            );
          },
        ),
      ),
    );
  }
}