import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

class CustomBannerAd extends StatefulWidget {
  final String htmlBannerCode; // Purane references break na hon isliye rakha hai

  const CustomBannerAd({Key? key, required this.htmlBannerCode}) : super(key: key);

  @override
  State<CustomBannerAd> createState() => _CustomBannerAdState();
}

class _CustomBannerAdState extends State<CustomBannerAd> {
  bool _isAdblockDetected = false;
  Timer? _watchdog;

  static const List<String> _adDomains = [
    'unityads.unity3d.com',
    'config.unityads.unity3d.com',
  ];

  @override
  void initState() {
    super.initState();
    _checkDeepBannerAdblock();
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) => _checkDeepBannerAdblock());
  }

  Future<void> _checkDeepBannerAdblock() async {
    bool isBlocked = false;
    for (final host in _adDomains) {
      try {
        final addresses = await InternetAddress.lookup(host).timeout(const Duration(milliseconds: 900));
        for (var addr in addresses) {
          if (addr.isLoopback ||
              addr.address == '0.0.0.0' ||
              addr.address == '127.0.0.1' ||
              addr.address == '::1' ||
              addr.address == '::') {
            isBlocked = true;
            break;
          }
        }
        if (isBlocked) break;
      } catch (e) {
        try {
          final googleCheck = await InternetAddress.lookup('google.com').timeout(const Duration(milliseconds: 900));
          if (googleCheck.isNotEmpty) {
            isBlocked = true;
            break;
          }
        } catch (_) {}
      }
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
      height: 55,
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
                    "AdBlocker / Private DNS kindly off then enjoy",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            : Center(
                // 🔥 ONLY UNITY BANNER HERE 🔥
                child: UnityBannerAd(
                  placementId: 'Banner_Android',
                  onLoad: (placementId) => debugPrint('Banner loaded: $placementId'),
                  onClick: (placementId) => debugPrint('Banner clicked: $placementId'),
                  onFailed: (placementId, error, message) {
                    debugPrint('Banner Ad failed: $error $message');
                    _checkDeepBannerAdblock();
                  },
                ),
              ),
      ),
    );
  }
}