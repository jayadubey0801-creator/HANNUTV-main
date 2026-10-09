import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import 'banner_ad_widget.dart';
import 'config.dart';
import 'stores.dart';
import 'tmdb_service.dart';

// ───────────────────────── hooks (apne app se jodne ke liye) ─────────────────────────
class DashboardHooks {
  /// Poster/Watch Now par tap → apni details/player screen kholo.
  final void Function(BuildContext context, TmdbItem item)? onOpenTitle;
  final VoidCallback? onOpenLiveTv;
  final VoidCallback? onOpenSearch;
  const DashboardHooks({this.onOpenTitle, this.onOpenLiveTv, this.onOpenSearch});
}

class Hooks {
  static DashboardHooks cfg = const DashboardHooks();
  static void open(BuildContext c, TmdbItem i) {
    final void Function(BuildContext, TmdbItem)? f = cfg.onOpenTitle;
    if (f != null) {
      f(c, i);
    } else {
      showTitleSheet(c, i);
    }
  }
}

Future<void> openUrl(String url) async {
  final Uri? u = Uri.tryParse(url);
  if (u == null) return;
  try {
    await launchUrl(u, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

// ───────────────────────── primitives ─────────────────────────
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({super.key, this.w, this.h, this.r = 12});
  final double? w;
  final double? h;
  final double r;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: HC.card,
      highlightColor: const Color(0xFF2B2752),
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(color: HC.card, borderRadius: BorderRadius.circular(r)),
      ),
    );
  }
}

class PosterImage extends StatelessWidget {
  const PosterImage({super.key, required this.item, required this.width, this.size = 'w342'});
  final TmdbItem item;
  final double width;
  final String size;

  @override
  Widget build(BuildContext context) {
    final Widget empty = Container(
      width: width,
      height: width * 1.5,
      color: HC.card,
      child: const Icon(Icons.movie_outlined, color: HC.dim),
    );
    if (item.poster == null) return ClipRRect(borderRadius: BorderRadius.circular(12), child: empty);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: item.posterUrl(size),
        width: width,
        height: width * 1.5,
        fit: BoxFit.cover,
        memCacheWidth: (width * 3).round(),
        fadeInDuration: const Duration(milliseconds: 180),
        placeholder: (BuildContext _, String __) => ShimmerBox(w: width, h: width * 1.5),
        errorWidget: (BuildContext _, String __, Object ___) => empty,
      ),
    );
  }
}

/// Poster ke upar lagne wala bada 3D number (Top 10 ke liye).
class RankNumber extends StatelessWidget {
  const RankNumber(this.n, {super.key, this.size = 56});
  final int n;
  final double size;

  @override
  Widget build(BuildContext context) {
    final TextStyle base = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      fontStyle: FontStyle.italic,
      height: 1.0,
      letterSpacing: -2,
    );
    return Stack(
      children: <Widget>[
        Text(
          '$n',
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5
              ..strokeJoin = StrokeJoin.round
              ..color = Colors.black,
            shadows: <Shadow>[
              Shadow(color: alpha(HC.accent, 0.95), offset: const Offset(3, 4), blurRadius: 0),
            ],
          ),
        ),
        Text(
          '$n',
          style: base.copyWith(
            foreground: Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Colors.white, Color(0xFFC9A8FF)],
              ).createShader(Rect.fromLTWH(0, 0, size, size)),
          ),
        ),
      ],
    );
  }
}

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    this.width = 112,
    this.rank,
    this.progress,
    this.badge,
    this.onTap,
    this.onLongPress,
  });

  final TmdbItem item;
  final double width;
  final int? rank;
  final double? progress;
  final String? badge;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap ?? () => Hooks.open(context, item),
      onLongPress: onLongPress,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: width,
              height: width * 1.5,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  PosterImage(item: item, width: width),
                  if (rank != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: width * 0.75,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[Colors.transparent, alpha(Colors.black, 0.85)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (rank != null)
                    Positioned(left: 8, bottom: 4, child: RankNumber(rank!, size: width * 0.5)),
                  if (badge != null)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: alpha(Colors.black, 0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(badge!,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  if (progress != null)
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(HC.accent2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
            Text(
              item.rating > 0 ? '★ ${item.rating.toStringAsFixed(1)}   ${item.year}' : item.year,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: HC.dim),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle, this.leading, this.onMore, this.size = 18});
  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback? onMore;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 10),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[leading!, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: Colors.white)),
                if (subtitle != null)
                  Text(subtitle!, style: const TextStyle(fontSize: 12, color: HC.dim)),
              ],
            ),
          ),
          if (onMore != null)
            GestureDetector(
              onTap: onMore,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Text('See all', style: TextStyle(color: HC.accent2, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

const double kRowExtra = 52; // poster ke neeche title+rating ki jagah

/// Lazy poster row: tabhi load hota hai jab screen ke paas aata hai.
class PosterRow extends StatefulWidget {
  const PosterRow({
    super.key,
    required this.title,
    required this.loader,
    this.subtitle,
    this.leading,
    this.ranked = false,
    this.width = 112,
    this.hideIfEmpty = true,
    this.titleSize = 18,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Future<List<TmdbItem>> Function() loader;
  final bool ranked;
  final double width;
  final bool hideIfEmpty;
  final double titleSize;

  @override
  State<PosterRow> createState() => _PosterRowState();
}

class _PosterRowState extends State<PosterRow> {
  late Future<List<TmdbItem>> _f;

  @override
  void initState() {
    super.initState();
    _f = widget.loader();
  }

  void _retry() => setState(() => _f = widget.loader());

  @override
  Widget build(BuildContext context) {
    final double h = widget.width * 1.5 + kRowExtra;
    return FutureBuilder<List<TmdbItem>>(
      future: _f,
      builder: (BuildContext ctx, AsyncSnapshot<List<TmdbItem>> snap) {
        final bool loading = snap.connectionState != ConnectionState.done;
        final List<TmdbItem> items = snap.data ?? const <TmdbItem>[];
        if (!loading && items.isEmpty) {
          if (widget.hideIfEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: GestureDetector(
              onTap: _retry,
              child: Container(
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: HC.surface, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  tmdbKeyMissing
                      ? 'TMDB API key paste karo (config.dart)'
                      : '${widget.title} load nahi hua — tap karke retry karo',
                  style: const TextStyle(color: HC.dim, fontSize: 13),
                ),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionTitle(widget.title,
                subtitle: widget.subtitle, leading: widget.leading, size: widget.titleSize),
            SizedBox(
              height: h,
              child: loading
                  ? ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: 6,
                      separatorBuilder: (BuildContext _, int __) => const SizedBox(width: 12),
                      itemBuilder: (BuildContext _, int __) =>
                          ShimmerBox(w: widget.width, h: widget.width * 1.5),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: items.length,
                      separatorBuilder: (BuildContext _, int __) => const SizedBox(width: 12),
                      itemBuilder: (BuildContext _, int i) => PosterCard(
                        item: items[i],
                        width: widget.width,
                        rank: widget.ranked ? i + 1 : null,
                      ),
                    ),
            ),
            const SizedBox(height: 14),
          ],
        );
      },
    );
  }
}

class ContinueWatchingRow extends StatelessWidget {
  const ContinueWatchingRow({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ContinueWatchingStore.I,
      builder: (BuildContext ctx, Widget? _) {
        final List<CwEntry> list = ContinueWatchingStore.I.entries;
        if (list.isEmpty) return const SizedBox.shrink();
        const double w = 128;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionTitle('Continue Watching', subtitle: 'Long-press se hatao'),
            SizedBox(
              height: w * 1.5 + kRowExtra,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: list.length,
                separatorBuilder: (BuildContext _, int __) => const SizedBox(width: 12),
                itemBuilder: (BuildContext _, int i) {
                  final CwEntry e = list[i];
                  return PosterCard(
                    item: e.item,
                    width: w,
                    progress: e.progress,
                    badge: e.label,
                    onLongPress: () => ContinueWatchingStore.I.remove(e.item),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
          ],
        );
      },
    );
  }
}

// ───────────────────────── OTT logo ─────────────────────────
class OttLogo extends StatelessWidget {
  const OttLogo(this.ott, {super.key, this.w = 84, this.h = 54, this.radius = 14});
  final Ott ott;
  final double w;
  final double h;
  final double radius;

  Widget _fallback() => Center(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            ott.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: ott.tileBg == Colors.white ? Colors.black87 : Colors.white,
            ),
          ),
        ),
      );

  Widget _spinner() => const Center(
        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );

  @override
  Widget build(BuildContext context) {
    final bool isSvg = ott.logoUrl.toLowerCase().contains('.svg');
    final Widget img = isSvg
        ? SvgPicture.network(
            ott.logoUrl,
            fit: ott.fit,
            placeholderBuilder: (BuildContext _) => _spinner(),
          )
        : CachedNetworkImage(
            imageUrl: ott.logoUrl,
            fit: ott.fit,
            memCacheWidth: 420,
            fadeInDuration: const Duration(milliseconds: 200),
            placeholder: (BuildContext _, String __) => _spinner(),
            errorWidget: (BuildContext _, String __, Object ___) => _fallback(),
          );
    return Container(
      width: w,
      height: h,
      clipBehavior: Clip.antiAlias,
      padding: ott.fit == BoxFit.contain ? const EdgeInsets.all(8) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: ott.tileBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white12),
      ),
      child: img,
    );
  }
}

// Dashboard ke AdSlot me jo asli banner chalta hai (Adsterra 320x50) — player wale snippet jaisa hi.
const String kDashAdsterraSnippet = '''
<script type="text/javascript">
  atOptions = { 'key' : 'a39df283f6ad10c34e229e5715bceff5', 'format' : 'iframe', 'height' : 50, 'width' : 320, 'params' : {} };
</script>
<script type="text/javascript" src="https://www.highrevenueformat.com/a39df283f6ad10c34e229e5715bceff5/invoke.js"></script>
''';

// ───────────────────────── ad slot ─────────────────────────
class AdSlot extends StatelessWidget {
  const AdSlot({super.key});

  /// AdMob jodna ho to:  AdSlot.builder = (ctx) => AdWidget(ad: myBannerAd);
  static Widget Function(BuildContext)? builder;

  @override
  Widget build(BuildContext context) {
    final Widget Function(BuildContext)? b = builder;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: Container(
        height: 62,
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: HC.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: b != null
            ? b(context)
            : const CustomBannerAd(htmlBannerCode: kDashAdsterraSnippet),
      ),
    );
  }
}

// ───────────────────────── genre block (dashboard + popup dono me) ─────────────────────────
class GenreBlock extends StatelessWidget {
  const GenreBlock({super.key, required this.g, this.onSeeAll});
  final GenreDef g;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: GestureDetector(
            onTap: onSeeAll,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(colors: <Color>[g.c1, g.c2]),
              ),
              child: Row(
                children: <Widget>[
                  Icon(g.icon, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(g.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                  if (onSeeAll != null) const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                ],
              ),
            ),
          ),
        ),
        PosterRow(
          title: 'Movies',
          subtitle: 'Top 50 ${g.label} movies',
          titleSize: 16,
          loader: () => Tmdb.I.genreRow(g, RowKind.movie),
        ),
        PosterRow(
          title: 'Web Series',
          subtitle: 'Top 50 ${g.label} series',
          titleSize: 16,
          loader: () => Tmdb.I.genreRow(g, RowKind.series),
        ),
        PosterRow(
          title: 'Anime',
          subtitle: 'Top 50 ${g.label} anime',
          titleSize: 16,
          loader: () => Tmdb.I.genreRow(g, RowKind.anime),
        ),
        if (g.hasKdrama)
          PosterRow(
            title: 'K-Drama',
            subtitle: 'Top 50 Korean dramas',
            titleSize: 16,
            loader: () => Tmdb.I.genreRow(g, RowKind.kdrama),
          ),
      ],
    );
  }
}

// ───────────────────────── default title sheet ─────────────────────────
void showTitleSheet(BuildContext context, TmdbItem item) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetCtx) => _TitleSheet(item: item, outer: context),
  );
}

class _TitleSheet extends StatelessWidget {
  const _TitleSheet({required this.item, required this.outer});
  final TmdbItem item;
  final BuildContext outer;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
        color: HC.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (item.backdrop != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      CachedNetworkImage(imageUrl: item.backdropUrl('w780'), fit: BoxFit.cover),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[Colors.transparent, HC.surface],
                            stops: const <double>[0.5, 1],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(item.title,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(
                    '★ ${item.rating.toStringAsFixed(1)}   ${item.year}   ${item.kind}',
                    style: const TextStyle(color: HC.dim),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.overview.isEmpty ? 'Description available nahi.' : item.overview,
                    style: const TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(outer).showSnackBar(const SnackBar(
                              content: Text('Player connect nahi hai — DashboardHooks.onOpenTitle me apna player do.'),
                            ));
                          },
                          child: Container(
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: HC.primary,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(Icons.play_arrow_rounded, color: Colors.white),
                                SizedBox(width: 6),
                                Text('Watch Now',
                                    style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      AnimatedBuilder(
                        animation: WatchlistStore.I,
                        builder: (BuildContext _, Widget? __) {
                          final bool on = WatchlistStore.I.contains(item);
                          return GestureDetector(
                            onTap: () => WatchlistStore.I.toggle(item),
                            child: Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: on ? HC.accent2 : Colors.white24),
                              ),
                              child: Row(
                                children: <Widget>[
                                  Icon(on ? Icons.check_rounded : Icons.add_rounded, color: Colors.white),
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
        ),
      ),
    );
  }
}
