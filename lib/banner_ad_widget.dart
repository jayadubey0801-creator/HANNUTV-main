import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

class CustomBannerAd extends StatefulWidget {
  final String htmlBannerCode;

  const CustomBannerAd({Key? key, required this.htmlBannerCode}) : super(key: key);

  @override
  State<CustomBannerAd> createState() => _CustomBannerAdState();
}

class _CustomBannerAdState extends State<CustomBannerAd> {
  bool _isAdblockDetected = false;
  bool _isOffline = false;
  int _retryKey = 0;
  Timer? _watchdog;

  // Exact Unity Placement ID from Dashboard
  static const String kUnityBannerPlacementId = 'BP_Banner_Android';

  static const List<String> _adDomains = [
    'unityads.unity3d.com',
    'config.unityads.unity3d.com',
    'webview.unityads.unity3d.com',
  ];

  @override
  void initState() {
    super.initState();
    _checkDeepBannerAdblock();
    _watchdog = Timer.periodic(const Duration(seconds: 4), (_) => _checkDeepBannerAdblock());
  }

  Future<void> _checkDeepBannerAdblock() async {
    // First check if internet is available at all
    bool netAvailable = false;
    try {
      final g = await InternetAddress.lookup('google.com').timeout(const Duration(milliseconds: 900));
      if (g.isNotEmpty) netAvailable = true;
    } catch (_) {
      netAvailable = false;
    }

    if (!netAvailable) {
      if (mounted && (!_isOffline || _isAdblockDetected)) {
        setState(() {
          _isOffline = true;
          _isAdblockDetected = false;
        });
      }
      return;
    }

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
      } catch (_) {
        isBlocked = true;
        break;
      }
    }

    if (mounted && (isBlocked != _isAdblockDetected || _isOffline)) {
      setState(() {
        _isOffline = false;
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
    if (_isOffline) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      height: 55,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
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
                child: UnityBannerAd(
                  key: ValueKey('unity_banner_$_retryKey'),
                  placementId: kUnityBannerPlacementId,
                  onLoad: (placementId) => debugPrint('Unity Banner loaded: $placementId'),
                  onClick: (placementId) => debugPrint('Unity Banner clicked: $placementId'),
                  onFailed: (placementId, error, message) {
                    debugPrint('Unity Banner failed: $error $message');
                    _checkDeepBannerAdblock();
                    Future.delayed(const Duration(seconds: 6), () {
                      if (mounted && !_isAdblockDetected && !_isOffline) {
                        setState(() => _retryKey++);
                      }
                    });
                  },
                ),
              ),
      ),
    );
  }
}