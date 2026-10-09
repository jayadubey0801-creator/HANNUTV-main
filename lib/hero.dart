import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import 'config.dart';
import 'stores.dart';
import 'tmdb_service.dart';
import 'widgets.dart';

const double kHeroHeight = 430;

/// Poster ke dominant color ko dark/readable tone me badalta hai.
Color _tone(Color c) {
  final HSLColor h = HSLColor.fromColor(c);
  return h
      .withLightness(h.lightness.clamp(0.22, 0.36).toDouble())
      .withSaturation(h.saturation.clamp(0.45, 0.90).toDouble())
      .toColor();
}

class AmbientColors {
  static final Map<String, Color> _cache = <String, Color>{};

  /// Poster se color nikalo (cache + timeout + fail-safe: kabhi crash nahi).
  static Future<Color> of(TmdbItem it) async {
    final Color? hit = _cache[it.key];
    if (hit != null) return hit;
    Color out = HC.accent;
    try {
      final PaletteGenerator p = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(it.posterUrl('w185')),
        size: const Size(110, 165),
        maximumColorCount: 12,
      ).timeout(const Duration(seconds: 8));
      final Color? base = p.vibrantColor?.color ??
          p.darkVibrantColor?.color ??
          p.dominantColor?.color ??
          p.mutedColor?.color;
      if (base != null) out = _tone(base);
    } catch (_) {
      // fallback: purple
    }
    _cache[it.key] = out;
    return out;
  }
}

class HeroSkeleton extends StatelessWidget {
  const HeroSkeleton({super.key});
  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.fromLTRB(0, 0, 0, 20), child: ShimmerBox(h: kHeroHeight, r: 0));
}

class HeroCarousel extends StatefulWidget {
  const HeroCarousel({super.key, required this.items, required this.onColor});
  final List<TmdbItem> items;
  final ValueChanged<Color> onColor;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  late final PageController _pc;
  Timer? _timer;
  int _i = 0;
  Color _tint = HC.accent;

  int get _n => widget.items.length;

  @override
  void initState() {
    super.initState();
    // Bahut bada initialPage → dono taraf infinite loop (last→first par peeche nahi ghoomta)
    _pc = PageController(initialPage: _n * 500);
    _applyColor(0);
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 6), (Timer _) {
      if (!mounted || !_pc.hasClients) return;
      _pc.nextPage(duration: const Duration(milliseconds: 650), curve: Curves.easeInOutCubic);
    });
  }

  Future<void> _applyColor(int idx) async {
    final TmdbItem it = widget.items[idx];
    final Color c = await AmbientColors.of(it);
    if (!mounted || _i != idx) return;
    setState(() => _tint = c);
    widget.onColor(c);
    // agla poster ka color pehle se ready rakho
    AmbientColors.of(widget.items[(idx + 1) % _n]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kHeroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification n) {
              if (n is ScrollStartNotification && n.dragDetails != null) _timer?.cancel();
              if (n is ScrollEndNotification) _restart();
              return false;
            },
            child: PageView.builder(
              controller: _pc,
              onPageChanged: (int p) {
                final int idx = p % _n;
                setState(() => _i = idx);
                _applyColor(idx);
              },
              itemBuilder: (BuildContext ctx, int p) {
                final int idx = p % _n;
                return _Slide(item: widget.items[idx], rank: idx + 1, tint: _tint);
              },
            ),
          ),
          // dots (top-20)
          Positioned(
            right: 16,
            bottom: 10,
            child: IgnorePointer(
              child: Row(
                children: List<Widget>.generate(_n, (int d) {
                  final bool on = d == _i;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(left: 4),
                    width: on ? 16 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: on ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.item, required this.rank, required this.tint});
  final TmdbItem item;
  final int rank;
  final Color tint;

  Widget _chip(String t, {Color? color, bool filled = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: filled ? alpha(Colors.black, 0.45) : null,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(t,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color ?? Colors.white)),
      );

  @override
  Widget build(BuildContext context) {
    final Color side = Color.lerp(tint, HC.bg, 0.55) ?? HC.bg;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CachedNetworkImage(
          imageUrl: item.backdropUrl('w780'),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          fadeInDuration: const Duration(milliseconds: 250),
          placeholder: (BuildContext _, String __) => Container(color: HC.card),
          errorWidget: (BuildContext _, String __, Object ___) => Container(color: HC.card),
        ),
        // left → right tinted scrim (tint smooth animate hota hai)
        TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: side),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeInOutCubic,
          builder: (BuildContext _, Color? v, Widget? __) {
            final Color c = v ?? side;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[alpha(c, 0.96), alpha(c, 0.55), Colors.transparent],
                  stops: const <double>[0.0, 0.5, 1.0],
                ),
              ),
            );
          },
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Colors.transparent, HC.bg],
              stops: <double>[0.5, 1.0],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  if (item.poster != null)
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                        boxShadow: <BoxShadow>[
                          BoxShadow(color: alpha(Colors.black, 0.5), blurRadius: 14, offset: const Offset(0, 6)),
                        ],
                      ),
                      child: PosterImage(item: item, width: 84, size: 'w185'),
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: HC.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('#$rank Trending',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 7,
                          runSpacing: 6,
                          children: <Widget>[
                            _chip('★ ${item.rating.toStringAsFixed(1)}', color: HC.gold, filled: true),
                            if (item.year.isNotEmpty) _chip(item.year),
                            _chip(item.kind),
                            _chip('HD'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                item.overview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.35),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  GestureDetector(
                    onTap: () => Hooks.open(context, item),
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: HC.primary,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: <BoxShadow>[
                          BoxShadow(color: alpha(HC.accent, 0.5), blurRadius: 16, offset: const Offset(0, 6)),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.play_arrow_rounded, color: Colors.white),
                          SizedBox(width: 6),
                          Text('Watch Now',
                              style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedBuilder(
                    animation: WatchlistStore.I,
                    builder: (BuildContext _, Widget? __) {
                      final bool on = WatchlistStore.I.contains(item);
                      return GestureDetector(
                        onTap: () => WatchlistStore.I.toggle(item),
                        child: Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: alpha(Colors.black, 0.35),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: on ? HC.accent2 : Colors.white30),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(on ? Icons.check_rounded : Icons.add_rounded, color: Colors.white, size: 20),
                              const SizedBox(width: 6),
                              const Text('My List',
                                  style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
