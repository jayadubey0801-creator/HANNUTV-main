import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

class TmdbItem {
  final int id;
  final bool isTv;
  final String title;
  final String overview;
  final String year;
  final String lang;
  final String? poster;
  final String? backdrop;
  final double rating;
  final double popularity;
  final List<int> genreIds;

  const TmdbItem({
    required this.id,
    required this.isTv,
    required this.title,
    required this.overview,
    required this.year,
    required this.lang,
    required this.poster,
    required this.backdrop,
    required this.rating,
    required this.popularity,
    required this.genreIds,
  });

  String get key => '${isTv ? 'tv' : 'movie'}_$id';
  String get kind => isTv ? 'Series' : 'Movie';
  String posterUrl([String size = 'w342']) => '$kImg/$size$poster';
  String backdropUrl([String size = 'w780']) => '$kImg/$size$backdrop';

  factory TmdbItem.fromJson(Map<String, dynamic> j, {required bool isTv}) {
    final String date = (j['release_date'] ?? j['first_air_date'] ?? '').toString();
    final List<dynamic> g = (j['genre_ids'] as List<dynamic>?) ?? const <dynamic>[];
    return TmdbItem(
      id: (j['id'] as num).toInt(),
      isTv: isTv,
      title: (j['title'] ?? j['name'] ?? '').toString(),
      overview: (j['overview'] ?? '').toString(),
      year: date.length >= 4 ? date.substring(0, 4) : '',
      lang: (j['original_language'] ?? '').toString(),
      poster: j['poster_path'] as String?,
      backdrop: j['backdrop_path'] as String?,
      rating: (j['vote_average'] as num?)?.toDouble() ?? 0.0,
      popularity: (j['popularity'] as num?)?.toDouble() ?? 0.0,
      genreIds: g.whereType<num>().map((e) => e.toInt()).toList(),
    );
  }

  factory TmdbItem.fromStored(Map<String, dynamic> j) =>
      TmdbItem.fromJson(j, isTv: j['is_tv'] == true);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'is_tv': isTv,
        'title': title,
        'overview': overview,
        'release_date': year,
        'original_language': lang,
        'poster_path': poster,
        'backdrop_path': backdrop,
        'vote_average': rating,
        'popularity': popularity,
        'genre_ids': genreIds,
      };
}

enum RowKind { movie, series, anime, kdrama }

class Tmdb {
  Tmdb._();
  static final Tmdb I = Tmdb._();

  final http.Client _client = http.Client();
  final Map<String, Future<List<TmdbItem>>> _cache = <String, Future<List<TmdbItem>>>{};
  final Map<String, Future<List<int>>> _kw = <String, Future<List<int>>>{};

  void clearCache() {
    _cache.clear();
    _kw.clear();
  }

  Uri _uri(String path, Map<String, String> q) => Uri.https(
        'api.themoviedb.org',
        '/3$path',
        <String, String>{'api_key': kTmdbApiKey, 'language': 'en-US', ...q},
      );

  /// Retry + 429 backoff ke saath safe GET. Fail hone par null (kabhi throw nahi).
  Future<Map<String, dynamic>?> _get(String path, Map<String, String> q) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final http.Response r =
            await _client.get(_uri(path, q)).timeout(const Duration(seconds: 15));
        if (r.statusCode == 200) {
          final dynamic d = json.decode(r.body);
          if (d is Map<String, dynamic>) return d;
          return null;
        }
        if (r.statusCode == 401) return null; // galat API key — retry bekaar
        if (r.statusCode == 429 || r.statusCode >= 500) {
          await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
          continue;
        }
        return null;
      } catch (_) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    return null;
  }

  /// Generic paged list (20 per page). `tv` null ho to media_type se detect hota hai.
  Future<List<TmdbItem>> list(String path, Map<String, String> q,
      {int count = 20, bool? tv}) {
    final String key = '$path|${(q.entries.map((e) => '${e.key}=${e.value}').toList()..sort()).join('&')}|$count|$tv';
    final Future<List<TmdbItem>>? hit = _cache[key];
    if (hit != null) return hit;
    final Future<List<TmdbItem>> f = _fetchPages(path, q, count, tv).then((List<TmdbItem> r) {
      if (r.isEmpty) _cache.remove(key); // fail/empty cache nahi karte → retry chalega
      return r;
    });
    _cache[key] = f;
    return f;
  }

  Future<List<TmdbItem>> _fetchPages(
      String path, Map<String, String> q, int count, bool? tv) async {
    final int pages = (count / 20).ceil();
    final List<Map<String, dynamic>?> res = await Future.wait(
      List<Future<Map<String, dynamic>?>>.generate(
        pages,
        (int i) => _get(path, <String, String>{...q, 'page': '${i + 1}'}),
      ),
    );
    final List<TmdbItem> out = <TmdbItem>[];
    final Set<String> seen = <String>{};
    for (final Map<String, dynamic>? m in res) {
      final List<dynamic> results = (m?['results'] as List<dynamic>?) ?? const <dynamic>[];
      for (final dynamic r in results) {
        if (r is! Map<String, dynamic>) continue;
        final dynamic mt = r['media_type'];
        if (mt == 'person') continue;
        final bool isTv = tv ?? (mt == 'tv');
        final TmdbItem it = TmdbItem.fromJson(r, isTv: isTv);
        if (it.poster == null || it.title.isEmpty) continue;
        if (seen.add(it.key)) out.add(it);
      }
    }
    return out.take(count).toList();
  }

  // ───────────────────────── discover ─────────────────────────
  Future<List<TmdbItem>> discover({
    required bool tv,
    String? genres,
    String? keywords,
    String? lang,
    String? providers,
    String? region,
    String sort = 'popularity.desc',
    int count = 20,
    Map<String, String>? extra,
  }) {
    final Map<String, String> q = <String, String>{
      'sort_by': sort,
      'include_adult': 'false',
      'vote_count.gte': sort.startsWith('vote_average') ? '300' : '20',
    };
    if (genres != null && genres.isNotEmpty) q['with_genres'] = genres;
    if (keywords != null && keywords.isNotEmpty) q['with_keywords'] = keywords;
    if (lang != null) q['with_original_language'] = lang;
    if (providers != null) {
      q['with_watch_providers'] = providers;
      q['watch_region'] = region ?? 'IN';
      q['with_watch_monetization_types'] = 'flatrate|free|ads';
    }
    if (extra != null) q.addAll(extra);
    return list(tv ? '/discover/tv' : '/discover/movie', q, count: count, tv: tv);
  }

  /// '/search/keyword' se keyword id(s) nikalta hai (cache ke saath).
  Future<String?> keywordIds(String name) async {
    final String k = name.toLowerCase();
    final Future<List<int>> f = _kw[k] ?? (_kw[k] = _loadKeyword(name, k));
    final List<int> ids = await f;
    if (ids.isEmpty) {
      _kw.remove(k);
      return null;
    }
    return ids.take(3).join('|');
  }

  Future<List<int>> _loadKeyword(String name, String lowerName) async {
    final Map<String, dynamic>? m =
        await _get('/search/keyword', <String, String>{'query': name});
    final List<dynamic> res = (m?['results'] as List<dynamic>?) ?? const <dynamic>[];
    final List<int> ids = <int>[];
    for (final dynamic r in res) {
      if (r is Map<String, dynamic> && r['name']?.toString().toLowerCase() == lowerName) {
        ids.add((r['id'] as num).toInt());
      }
    }
    if (ids.isEmpty && res.isNotEmpty && res.first is Map<String, dynamic>) {
      ids.add(((res.first as Map<String, dynamic>)['id'] as num).toInt());
    }
    return ids;
  }

  List<TmdbItem> _merge(List<TmdbItem> a, List<TmdbItem> b, int count) {
    final List<TmdbItem> all = <TmdbItem>[...a, ...b]
      ..sort((TmdbItem x, TmdbItem y) => y.popularity.compareTo(x.popularity));
    return all.take(count).toList();
  }

  // ───────────────────────── dashboard lists ─────────────────────────

  /// Hero: TMDB trending (aaj + is hafte) ke top 20, backdrop wale.
  Future<List<TmdbItem>> heroItems() async {
    final List<List<TmdbItem>> r = await Future.wait(<Future<List<TmdbItem>>>[
      list('/trending/all/day', <String, String>{}, count: 20),
      list('/trending/all/week', <String, String>{}, count: 20),
    ]);
    final Set<String> seen = <String>{};
    final List<TmdbItem> out = <TmdbItem>[];
    for (final TmdbItem it in <TmdbItem>[...r[0], ...r[1]]) {
      if (it.backdrop == null) continue;
      if (seen.add(it.key)) out.add(it);
      if (out.length == 20) break;
    }
    return out;
  }

  /// India me OTTs par sabse popular (movie + series mix).
  Future<List<TmdbItem>> topIndia({int count = 10}) async {
    final List<List<TmdbItem>> r = await Future.wait(<Future<List<TmdbItem>>>[
      discover(tv: false, providers: kIndiaProviders, region: 'IN', count: count),
      discover(tv: true, providers: kIndiaProviders, region: 'IN', count: count),
    ]);
    return _merge(r[0], r[1], count);
  }

  /// Worldwide trending top 10 (movie + series).
  Future<List<TmdbItem>> topWorld({int count = 10}) =>
      list('/trending/all/week', <String, String>{}, count: count);

  // ───────────────────────── genre rows ─────────────────────────
  Future<List<TmdbItem>> genreRow(GenreDef g, RowKind kind,
      {int count = 50, String? providers, String? region}) async {
    switch (kind) {
      case RowKind.movie:
        return discover(tv: false, genres: g.movie, providers: providers, region: region, count: count);
      case RowKind.series:
        return _tvForGenre(g, count: count, providers: providers, region: region);
      case RowKind.anime:
        {
          final List<List<TmdbItem>> r = await Future.wait(<Future<List<TmdbItem>>>[
            _tvForGenre(g, anime: true, lang: 'ja', count: count, providers: providers, region: region),
            discover(
              tv: false,
              genres: g.animeMovie,
              lang: 'ja',
              providers: providers,
              region: region,
              count: (count / 2).ceil(),
            ),
          ]);
          return _merge(r[0], r[1], count);
        }
      case RowKind.kdrama:
        return discover(tv: true, genres: '18', lang: 'ko', providers: providers, region: region, count: count);
    }
  }

  Future<List<TmdbItem>> _tvForGenre(GenreDef g,
      {bool anime = false, String? lang, int count = 50, String? providers, String? region}) async {
    String? genres = anime ? g.animeTv : g.tv;
    String? kw;
    if (g.tvKeyword != null) {
      kw = await keywordIds(g.tvKeyword!);
      if (kw == null && !anime) genres = g.tvFallback;
    }
    return discover(
      tv: true,
      genres: genres,
      keywords: kw,
      lang: lang,
      providers: providers,
      region: region,
      count: count,
    );
  }

  // ───────────────────────── OTT rows ─────────────────────────
  /// Ek OTT ke andar kisi bhi category ka row. Region IN me kam mile to US try karta hai.
  Future<List<TmdbItem>> ottRow(
    Ott o, {
    GenreDef? genre,
    String? lang,
    bool animeOnly = false,
    bool tvOnly = false,
    bool movieOnly = false,
    bool kdrama = false,
    bool mature = false,
    int count = 20,
  }) async {
    List<TmdbItem> best = const <TmdbItem>[];
    for (final String region in o.regions) {
      final List<TmdbItem> r = await _ottOnce(
        o, region,
        genre: genre, lang: lang, animeOnly: animeOnly, tvOnly: tvOnly,
        movieOnly: movieOnly, kdrama: kdrama, mature: mature, count: count,
      );
      if (r.length >= 8 || r.length >= count) return r;
      if (r.length > best.length) best = r;
    }
    return best;
  }

  Future<List<TmdbItem>> _ottOnce(
    Ott o,
    String region, {
    GenreDef? genre,
    String? lang,
    required bool animeOnly,
    required bool tvOnly,
    required bool movieOnly,
    required bool kdrama,
    required bool mature,
    required int count,
  }) async {
    final GenreDef? g = genre;
    String? mg;
    String? tg;
    String? kw;
    String? l = lang;
    if (animeOnly) {
      l = 'ja';
      mg = g?.animeMovie ?? '16';
      tg = g?.animeTv ?? '16';
    } else if (g != null) {
      mg = g.movie;
      tg = g.tv;
    }
    if (g != null && g.tvKeyword != null) {
      kw = await keywordIds(g.tvKeyword!);
      if (kw == null && !animeOnly) tg = g.tvFallback;
    }
    if (kdrama) {
      l = 'ko';
      tg = '18';
    }

    final List<Future<List<TmdbItem>>> futs = <Future<List<TmdbItem>>>[];
    if (!tvOnly && !kdrama) {
      futs.add(discover(
        tv: false,
        genres: mg,
        lang: l,
        providers: o.providers,
        region: region,
        count: count,
        extra: mature
            ? <String, String>{'certification_country': 'US', 'certification.gte': 'R'}
            : null,
      ));
    }
    if (!mature && !movieOnly) {
      futs.add(discover(
        tv: true,
        genres: tg,
        keywords: kw,
        lang: l,
        providers: o.providers,
        region: region,
        count: count,
      ));
    }
    if (futs.isEmpty) return const <TmdbItem>[];
    final List<List<TmdbItem>> res = await Future.wait(futs);
    return res.length == 1 ? res.first : _merge(res[0], res[1], count);
  }

  // ───────────────────────── search ─────────────────────────
  Future<List<TmdbItem>> search(String query) async {
    final Map<String, dynamic>? m = await _get(
      '/search/multi',
      <String, String>{'query': query, 'include_adult': 'false'},
    );
    final List<dynamic> res = (m?['results'] as List<dynamic>?) ?? const <dynamic>[];
    final List<TmdbItem> out = <TmdbItem>[];
    for (final dynamic r in res) {
      if (r is! Map<String, dynamic>) continue;
      final dynamic mt = r['media_type'];
      if (mt != 'movie' && mt != 'tv') continue;
      final TmdbItem it = TmdbItem.fromJson(r, isTv: mt == 'tv');
      if (it.poster != null) out.add(it);
    }
    return out;
  }
}
