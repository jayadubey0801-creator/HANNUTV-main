import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import 'banner_ad_widget.dart';
import 'config.dart';
import 'stores.dart';
import 'tmdb_service.dart';
import 'video_player_page.dart';

const String _kWidgetBannerSnippet = '''
  <script type="text/javascript">
    atOptions = { 'key' : 'a39df283f6ad10c34e229e5715bceff5', 'format' : 'iframe', 'height' : 50, 'width' : 320, 'params' : {} };
  </script>
  <script type="text/javascript" src="https://www.highrevenueformat.com/a39df283f6ad10c34e229e5715bceff5/invoke.js"></script>
''';

class DashboardHooks {
  final void Function(BuildContext context, TmdbItem item)? onOpenTitle;
  final void Function(BuildContext context)? onOpenLiveTv;
  final void Function(BuildContext context)? onOpenSearch;

  const DashboardHooks({
    this.onOpenTitle,
    this.onOpenLiveTv,
    this.onOpenSearch,
  });

  static DashboardHooks config = const DashboardHooks();

  static void open(BuildContext context, TmdbItem item) =>
      Hooks.open(context, item);
}

class Hooks {
  static DashboardHooks cfg = const DashboardHooks();

  static void open(BuildContext context, TmdbItem item) {
    ContinueStore.I.push(item, progress: 0.18);
    HistoryStore.I.push(item);
    final fn = cfg.onOpenTitle ?? DashboardHooks.config.onOpenTitle;
    if (fn != null) {
      fn(context, item);
      return;
    }

    final DownloadTaskItem? existingTask = DownloadStore.I.findTaskForMedia(
      tmdbId: item.id,
      mediaType: item.isTv ? 'tv' : 'movie',
    );
    final bool readyOffline =
        existingTask != null && existingTask.status == 'completed';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          tmdbId: item.id,
          mediaType: item.isTv ? 'tv' : 'movie',
          movieTitle: item.title,
          overview: item.overview,
          rating: item.rating.toStringAsFixed(1),
          year: item.year,
          isOfflineDownload: readyOffline,
          offlineFilePath: readyOffline ? existingTask.localFilePath : null,
          offlineLanguage: readyOffline ? existingTask.language : null,
          offlineQuality: readyOffline ? existingTask.quality : null,
          offlineServerName: readyOffline ? existingTask.serverName : null,
        ),
      ),
    );
  }

  static void openLiveTv(BuildContext context) {
    final fn = cfg.onOpenLiveTv ?? DashboardHooks.config.onOpenLiveTv;
    if (fn != null) fn(context);
  }

  static void openSearch(BuildContext context) {
    final fn = cfg.onOpenSearch ?? DashboardHooks.config.onOpenSearch;
    if (fn != null) fn(context);
  }
}

Future<void> openUrl(String url) async {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

class ShimmerBox extends StatelessWidget {
  final double? w;
  final double? h;
  final double r;

  const ShimmerBox({
    super.key,
    this.w,
    this.h,
    this.r = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF191924),
      highlightColor: const Color(0xFF29293A),
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: const Color(0xFF191924),
          borderRadius: BorderRadius.circular(r),
        ),
      ),
    );
  }
}

class PosterImage extends StatelessWidget {
  final TmdbItem item;
  final double width;
  final String size;

  const PosterImage({
    super.key,
    required this.item,
    required this.width,
    this.size = 'w342',
  });

  @override
  Widget build(BuildContext context) {
    final String url = item.posterUrl(size);
    if (url.isEmpty) {
      return Container(
        color: const Color(0xFF181822),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: Text(
          item.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      fit: BoxFit.cover,
      placeholder: (BuildContext _, String __) => ShimmerBox(w: width, r: 12),
      errorWidget: (BuildContext _, String __, Object ___) => Container(
        color: const Color(0xFF181822),
        alignment: Alignment.center,
        child: const Icon(Icons.movie_outlined, color: Colors.white30, size: 28),
      ),
    );
  }
}

class RankNumber extends StatelessWidget {
  final int n;
  final double size;

  const RankNumber(this.n, {super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Text(
          '$n',
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w900,
            height: 0.9,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.2
              ..color = Colors.white,
          ),
        ),
        Text(
          '$n',
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w900,
            height: 0.9,
            color: const Color(0xFF0B0B12),
          ),
        ),
      ],
    );
  }
}

class PosterCard extends StatelessWidget {
  final TmdbItem item;
  final double width;
  final int? rank;
  final double? progress;
  final String? badge;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

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

  @override
  Widget build(BuildContext context) {
    final double cardHeight = width * 1.48;
    return GestureDetector(
      onTap: onTap ?? () => Hooks.open(context, item),
      onLongPress: onLongPress ?? () => showTitleSheet(context, item),
      child: SizedBox(
        width: rank != null ? width + 24 : width,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: rank != null ? Alignment.centerRight : Alignment.center,
              child: Container(
                width: width,
                height: cardHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.42),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PosterImage(item: item, width: width),
                      if (badge != null && badge!.isNotEmpty)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE50914),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badge!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      if (item.rating > 0)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded,
                                    color: Colors.amber, size: 11),
                                const SizedBox(width: 2),
                                Text(
                                  item.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (progress != null && progress! > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: progress!.clamp(0.05, 1.0),
                            minHeight: 3.5,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFFE50914)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (rank != null)
              Positioned(
                left: -2,
                bottom: 2,
                child: IgnorePointer(child: RankNumber(rank!, size: 64)),
              ),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback? onMore;
  final double size;

  const SectionTitle(
    this.title, {
    super.key,
    this.subtitle,
    this.leading,
    this.onMore,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (onMore != null)
            GestureDetector(
              onTap: onMore,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  'See all',
                  style: TextStyle(
                    color: Color(0xFFB388FF),
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PosterRow extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Future<List<TmdbItem>> Function() loader;
  final bool ranked;
  final double width;
  final bool hideIfEmpty;
  final double titleSize;
  final VoidCallback? onMore;

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
    this.onMore,
  });

  @override
  State<PosterRow> createState() => _PosterRowState();
}

class _PosterRowState extends State<PosterRow>
    with AutomaticKeepAliveClientMixin {
  List<TmdbItem>? _items;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<TmdbItem> res = await widget.loader();
      if (mounted) setState(() => _items = res);
    } catch (_) {
      if (mounted) setState(() => _items = const <TmdbItem>[]);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final List<TmdbItem>? items = _items;
    if (items != null && items.isEmpty && widget.hideIfEmpty) {
      return const SizedBox.shrink();
    }
    final double rowH = widget.width * 1.48;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          widget.title,
          subtitle: widget.subtitle,
          leading: widget.leading,
          onMore: widget.onMore,
          size: widget.titleSize,
        ),
        SizedBox(
          height: rowH,
          child: items == null
              ? ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: 6,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, __) =>
                      ShimmerBox(w: widget.width, h: rowH, r: 12),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (BuildContext context, int index) {
                    final TmdbItem item = items[index];
                    return PosterCard(
                      item: item,
                      width: widget.width,
                      rank: widget.ranked ? index + 1 : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class GenreBlock extends StatelessWidget {
  final GenreDef g;
  final VoidCallback? onSeeAll;

  const GenreBlock({
    super.key,
    required this.g,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return PosterRow(
      title: g.label,
      subtitle: 'Top trending in ${g.label}',
      leading: Icon(g.icon, color: g.c1, size: 20),
      width: 116,
      onMore: onSeeAll,
      loader: () => Tmdb.I.genreRow(g, RowKind.movie),
    );
  }
}

class ContinueWatchingRow extends StatelessWidget {
  const ContinueWatchingRow({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ContinueStore.I,
      builder: (BuildContext context, _) {
        final List<ContinueEntry> entries = ContinueStore.I.entries;
        if (entries.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(
              'Continue Watching',
              subtitle: 'Pick up right where you left off',
              onMore: () => ContinueStore.I.clear(),
            ),
            SizedBox(
              height: 166,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (BuildContext context, int i) {
                  final ContinueEntry e = entries[i];
                  return Stack(
                    children: [
                      PosterCard(
                        item: e.item,
                        width: 112,
                        progress: e.progress,
                      ),
                      Positioned(
                        top: 4,
                        left: 4,
                        child: GestureDetector(
                          onTap: () => ContinueStore.I.remove(e.item.id),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white70, size: 13),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

void _openOfflinePlayer(BuildContext context, DownloadTaskItem t) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => VideoPlayerPage(
        tmdbId: t.tmdbId,
        mediaType: t.mediaType,
        season: t.season,
        episode: t.episode,
        movieTitle: t.title,
        overview: t.overview, // FIXED: Now fetching correct data
        rating: t.rating,     // FIXED
        year: t.year,         // FIXED
        isOfflineDownload: true,
        offlineFilePath: t.localFilePath,
        offlineLanguage: t.language,
        offlineQuality: t.quality,
        offlineServerName: t.serverName,
      ),
    ),
  );
}

void openMyDownloads(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const MyDownloadsPage()),
  );
}

class MyDownloadsRow extends StatelessWidget {
  const MyDownloadsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: DownloadStore.I,
      builder: (BuildContext context, _) {
        final List<DownloadTaskItem> tasks = DownloadStore.I.tasks;
        if (tasks.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(
              'My Downloads',
              subtitle: 'Real Multi-Audio Offline & Active Downloads',
              onMore: () => openMyDownloads(context),
            ),
            SizedBox(
              height: 118,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: tasks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (BuildContext context, int index) {
                  final DownloadTaskItem t = tasks[index];
                  final bool isDone = t.status == 'completed';
                  final bool isPaused = t.status == 'paused';

                  return GestureDetector(
                    onTap: () {
                      if (isDone) {
                        _openOfflinePlayer(context, t);
                      } else {
                        openMyDownloads(context);
                      }
                    },
                    child: Container(
                      width: 285,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF151522),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDone
                              ? Colors.greenAccent.withOpacity(0.45)
                              : (isPaused
                                  ? Colors.amber.withOpacity(0.45)
                                  : Colors.redAccent.withOpacity(0.45)),
                        ),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: t.posterUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: t.posterUrl,
                                    width: 62,
                                    height: 94,
                                    fit: BoxFit.cover,
                                    errorWidget: (BuildContext _, String __, Object ___) => Container(
                                      width: 62,
                                      height: 94,
                                      color: Colors.grey[900],
                                      child: const Icon(Icons.movie,
                                          color: Colors.white30),
                                    ),
                                  )
                                : Container(
                                    width: 62,
                                    height: 94,
                                    color: Colors.grey[900],
                                    child: const Icon(Icons.movie,
                                        color: Colors.white30),
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${t.language} • ${t.quality}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${DownloadStore.formatBytes(t.downloadedBytes)} / ${DownloadStore.formatBytes(t.totalBytes)}',
                                  style: const TextStyle(
                                      color: Colors.white60, fontSize: 10.5),
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: t.progress.clamp(0.0, 1.0),
                                    minHeight: 5,
                                    backgroundColor: Colors.white12,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isDone
                                          ? const Color(0xFF00E676)
                                          : (isPaused
                                              ? Colors.amber
                                              : Colors.redAccent),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      isDone
                                          ? '100% Ready (Play Now)'
                                          : (isPaused
                                              ? 'Paused (${t.percent}%)'
                                              : 'Downloading ${t.percent}%'),
                                      style: TextStyle(
                                        color: isDone
                                            ? const Color(0xFF00E676)
                                            : (isPaused
                                                ? Colors.amber
                                                : Colors.white70),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (!isDone)
                                      GestureDetector(
                                        onTap: () {
                                          if (isPaused) {
                                            DownloadStore.I
                                                .resumeDownload(t.id);
                                          } else {
                                            DownloadStore.I.pauseDownload(t.id);
                                          }
                                        },
                                        child: Icon(
                                          isPaused
                                              ? Icons.play_circle_fill
                                              : Icons.pause_circle_filled,
                                          color: isPaused
                                              ? Colors.amber
                                              : Colors.white,
                                          size: 20,
                                        ),
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
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class MyDownloadsPage extends StatelessWidget {
  const MyDownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121C),
        foregroundColor: Colors.white,
        title: const Text(
          'My Downloads',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: DownloadStore.I,
            builder: (BuildContext context, _) {
              final List<DownloadTaskItem> tasks = DownloadStore.I.tasks;
              if (tasks.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.cloud_download_outlined,
                          color: Colors.white24, size: 64),
                      SizedBox(height: 12),
                      Text(
                        'No downloads yet',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Download movies in your favorite audio & quality to watch offline!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
                itemCount: tasks.length,
                itemBuilder: (BuildContext context, int index) {
                  final DownloadTaskItem t = tasks[index];
                  final bool isDone = t.status == 'completed';
                  final bool isPaused = t.status == 'paused';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161624),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDone
                            ? Colors.greenAccent.withOpacity(0.4)
                            : (isPaused
                                ? Colors.amber.withOpacity(0.4)
                                : Colors.white12),
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: t.posterUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: t.posterUrl,
                                  width: 64,
                                  height: 92,
                                  fit: BoxFit.cover,
                                  errorWidget: (BuildContext _, String __, Object ___) => Container(
                                    width: 64,
                                    height: 92,
                                    color: Colors.grey[900],
                                    child: const Icon(Icons.movie,
                                        color: Colors.white30),
                                  ),
                                )
                              : Container(
                                  width: 64,
                                  height: 92,
                                  color: Colors.grey[900],
                                  child: const Icon(Icons.movie,
                                      color: Colors.white30),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${t.language} • ${t.quality} • Server: ${t.serverName}',
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${DownloadStore.formatBytes(t.downloadedBytes)} of ${DownloadStore.formatBytes(t.totalBytes)} (${t.percent}%)${isPaused ? " • PAUSED" : ""}',
                                style: TextStyle(
                                  color:
                                      isPaused ? Colors.amber : Colors.white70,
                                  fontSize: 11.5,
                                  fontWeight: isPaused
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: t.progress.clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: Colors.white12,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isDone
                                        ? const Color(0xFF00E676)
                                        : (isPaused
                                            ? Colors.amber
                                            : Colors.redAccent),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!isDone)
                          IconButton(
                            tooltip:
                                isPaused ? 'Resume Download' : 'Pause Download',
                            onPressed: () {
                              if (isPaused) {
                                DownloadStore.I.resumeDownload(t.id);
                              } else {
                                DownloadStore.I.pauseDownload(t.id);
                              }
                            },
                            icon: CircleAvatar(
                              radius: 18,
                              backgroundColor:
                                  isPaused ? Colors.amber : Colors.redAccent,
                              child: Icon(
                                isPaused
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                                color: Colors.black,
                                size: 22,
                              ),
                            ),
                          ),
                        if (isDone)
                          IconButton(
                            tooltip: 'Play Offline (No Ads)',
                            onPressed: () => _openOfflinePlayer(context, t),
                            icon: const CircleAvatar(
                              radius: 18,
                              backgroundColor: Color(0xFF00E676),
                              child: Icon(Icons.play_arrow_rounded,
                                  color: Colors.black, size: 22),
                            ),
                          ),
                        IconButton(
                          tooltip: 'Delete Download',
                          onPressed: () => DownloadStore.I.removeDownload(t.id),
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.redAccent, size: 22),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Center(
              child: CustomBannerAd(htmlBannerCode: _kWidgetBannerSnippet),
            ),
          ),
        ],
      ),
    );
  }
}

class LiveDownloadNotificationBanner extends StatelessWidget {
  const LiveDownloadNotificationBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: DownloadStore.I,
      builder: (BuildContext context, _) {
        final DownloadTaskItem? t = DownloadStore.I.activeBannerTask;
        if (t == null) return const SizedBox.shrink();

        final bool isDone = t.status == 'completed';
        final bool isPaused = t.status == 'paused';

        return SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Material(
                color: Colors.transparent,
                elevation: 14,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF191929), Color(0xFF232338)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDone
                          ? const Color(0xFF00E676)
                          : (isPaused ? Colors.amber : Colors.redAccent),
                      width: 1.3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.55),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: (isDone
                                      ? const Color(0xFF00E676)
                                      : (isPaused
                                          ? Colors.amber
                                          : Colors.redAccent))
                                  .withOpacity(0.18),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isDone
                                  ? Icons.download_done_rounded
                                  : (isPaused
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.downloading_rounded),
                              color: isDone
                                  ? const Color(0xFF00E676)
                                  : (isPaused
                                      ? Colors.amber
                                      : Colors.redAccent),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'HANNUTV DOWNLOADER',
                                      style: TextStyle(
                                        color: Colors.amber,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '• ${t.percent}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${t.language} • ${t.quality} • ${DownloadStore.formatBytes(t.downloadedBytes)} / ${DownloadStore.formatBytes(t.totalBytes)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 10.5),
                                ),
                              ],
                            ),
                          ),
                          if (!isDone)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                backgroundColor: isPaused
                                    ? Colors.amber.withOpacity(0.2)
                                    : Colors.white.withOpacity(0.1),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () {
                                if (isPaused) {
                                  DownloadStore.I.resumeDownload(t.id);
                                } else {
                                  DownloadStore.I.pauseDownload(t.id);
                                }
                              },
                              icon: Icon(
                                isPaused
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                                color: isPaused ? Colors.amber : Colors.white,
                                size: 15,
                              ),
                              label: Text(
                                isPaused ? 'Resume' : 'Pause',
                                style: TextStyle(
                                  color: isPaused ? Colors.amber : Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (isDone)
                            TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: const Color(0xFF00E676),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () {
                                DownloadStore.I.dismissBanner();
                                _openOfflinePlayer(context, t);
                              },
                              child: const Text(
                                'Play Offline',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => DownloadStore.I.dismissBanner(),
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(Icons.close,
                                  color: Colors.white54, size: 18),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: t.progress.clamp(0.0, 1.0),
                          minHeight: 4.5,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDone
                                ? const Color(0xFF00E676)
                                : (isPaused ? Colors.amber : Colors.redAccent),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class OttLogo extends StatelessWidget {
  final Ott ott;
  final double w;
  final double h;
  final double radius;

  const OttLogo(
    this.ott, {
    super.key,
    this.w = 84,
    this.h = 54,
    this.radius = 14,
  });

  String _resolveLogoUrl() {
    try {
      final dynamic d = ott;
      if (d.logo is String && d.logo.isNotEmpty) return d.logo;
    } catch (_) {}
    try {
      final dynamic d = ott;
      if (d.logos is List && d.logos.isNotEmpty) return d.logos.first.toString();
    } catch (_) {}
    return '';
  }

  Color _resolveAccent() {
    try {
      final dynamic d = ott;
      if (d.accent is Color) return d.accent;
      if (d.fg is Color) return d.fg;
      if (d.color is Color) return d.color;
    } catch (_) {}
    return const Color(0xFF7C3AED);
  }

  Color _resolveBg() {
    // 🔥 DEEP BLACK FIX FOR OTT LOGOS 🔥
    return const Color(0xFF000000);
  }

  @override
  Widget build(BuildContext context) {
    final String logoUrl = _resolveLogoUrl();
    final Color accent = _resolveAccent();
    final Color bg = _resolveBg();

    return Container(
      width: w,
      height: h,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: accent.withOpacity(0.45), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.22),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: logoUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: logoUrl,
                fit: BoxFit.contain,
                errorWidget: (BuildContext _, String __, Object ___) => Text(
                  ott.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              )
            : Text(
                ott.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
      ),
    );
  }
}

class AdSlot extends StatelessWidget {
  final double height;
  const AdSlot({super.key, this.height = 55});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: CustomBannerAd(htmlBannerCode: _kWidgetBannerSnippet),
    );
  }
}

void showTitleSheet(BuildContext context, TmdbItem item) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF14141F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (BuildContext sheetCtx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 84,
                      height: 124,
                      child: PosterImage(item: item, width: 84),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (item.year.isNotEmpty) ...[
                              Text(
                                item.year,
                                style: const TextStyle(
                                    color: Colors.white60, fontSize: 12),
                              ),
                              const SizedBox(width: 10),
                            ],
                            const Icon(Icons.star_rounded,
                                color: Colors.amber, size: 15),
                            const SizedBox(width: 3),
                            Text(
                              item.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.isTv ? 'SERIES' : 'MOVIE',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.overview.isEmpty
                              ? 'Watch in Full HD on HANNUTV.'
                              : item.overview,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE50914),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        Hooks.open(context, item);
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text(
                        'Watch Now',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedBuilder(
                    animation: WatchlistStore.I,
                    builder: (BuildContext context, _) {
                      final bool saved = WatchlistStore.I.contains(item);
                      return OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => WatchlistStore.I.toggle(item),
                        icon: Icon(
                          saved ? Icons.check_rounded : Icons.add_rounded,
                          color: saved ? Colors.amber : Colors.white,
                        ),
                        label: Text(saved ? 'Saved' : 'My List'),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}