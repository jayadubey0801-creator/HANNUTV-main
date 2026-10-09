import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
//  🔑 TMDB v3 API KEY (ERROR FIXED: Asli Key Daal Di Hai)
// ─────────────────────────────────────────────────────────────
const String kTmdbApiKey = String.fromEnvironment(
  'TMDB_API_KEY',
  defaultValue: '3d2d9116c9de7209ee277bb8cc9aeed8', // 🔥 TERA ASLI API KEY YAHAN ADD KAR DIYA HAI 🔥
);
bool get tmdbKeyMissing => kTmdbApiKey.startsWith('PASTE_');

const String kImg = 'https://image.tmdb.org/t/p';

// 🔗 Support + update links (apne asli links yaha daalo)
const String kTelegramUrl = 'https://t.me/HANNUTV';
const String kWhatsappChannelUrl = 'https://whatsapp.com/channel/0029VbE2Pb17z4kmfjF04P0v';
const String kUpdateUrlFallback = 'https://hannutv.blogspot.com/';
const String kVersionFallback = '1.3.0';

/// Theme tokens (AniStation reference jaisa dark-navy + purple)
class HC {
  static const Color bg = Color(0xFF07060F);
  static const Color surface = Color(0xFF14122A);
  static const Color card = Color(0xFF1B1838);
  static const Color accent = Color(0xFF7C3AED);
  static const Color accent2 = Color(0xFFA855F7);
  static const Color dim = Color(0xFF9A98C0);
  static const Color gold = Color(0xFFFBBF24);
  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF9B4DFF), Color(0xFF5B21B6)],
  );
}

/// Dashboard + saare popups isi dark theme me chalte hain (host app light ho tab bhi text dikhega).
ThemeData hannuTheme() {
  final ThemeData base = ThemeData.dark();
  return base.copyWith(
    scaffoldBackgroundColor: HC.bg,
    colorScheme: base.colorScheme.copyWith(primary: HC.accent2, surface: HC.surface),
    appBarTheme: const AppBarTheme(
      backgroundColor: HC.bg,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
  );
}

/// Color.withOpacity ka version-safe replacement.
Color alpha(Color c, double o) {
  final double v = o < 0 ? 0 : (o > 1 ? 1 : o);
  return c.withAlpha((v * 255).round());
}

// ─────────────────────────────────────────────────────────────
//  OTT PLATFORMS  (logo = tumhare diye hue links)
//  providers = TMDB watch-provider ids ('|' = OR). regions = pehle IN, phir fallback.
//  ⚠️ Provider ids TMDB kabhi kabhi badalta hai — verify:
//     https://api.themoviedb.org/3/watch/providers/tv?api_key=KEY&watch_region=IN
// ─────────────────────────────────────────────────────────────
class Ott {
  final String id;
  final String name;
  final String logoUrl;
  final String providers;
  final List<String> regions;
  final Color tileBg;
  final BoxFit fit;
  const Ott({
    required this.id,
    required this.name,
    required this.logoUrl,
    required this.providers,
    this.regions = const <String>['IN'],
    this.tileBg = Colors.white,
    this.fit = BoxFit.contain,
  });
}

const List<Ott> kOtts = <Ott>[
  Ott(
    id: 'netflix',
    name: 'Netflix',
    logoUrl:
        'https://static.vecteezy.com/system/resources/previews/020/190/493/non_2x/netflix-logo-netflix-icon-free-free-vector.jpg',
    providers: '8',
  ),
  Ott(
    id: 'prime',
    name: 'Amazon Prime Video',
    logoUrl:
        'https://television-b26f.kxcdn.com/wp-content/uploads/2023/03/Amazon-Prime-Video-Logo-2023.png',
    providers: '119|9',
  ),
  Ott(
    id: 'jio',
    name: 'JioCinema / JioHotstar',
    logoUrl: 'https://miro.medium.com/v2/resize:fit:2000/1*Nehq1KYRgFWTanqsLwWeFQ.png',
    providers: '220|2336|122',
  ),
  Ott(
    id: 'disney',
    name: 'Disney+',
    logoUrl: 'https://logos-world.net/wp-content/uploads/2021/02/Disney-Symbol.png',
    providers: '337',
    regions: <String>['US', 'IN'],
  ),
  Ott(
    id: 'hbo',
    name: 'HBO Max',
    logoUrl:
        'https://sm.ign.com/ign_in/news/m/max-changi/max-changing-its-name-back-to-hbo-max-warner-bros-discovery_5g77.jpg',
    providers: '384|1899',
    regions: <String>['US'],
    tileBg: Colors.black,
    fit: BoxFit.cover,
  ),
  Ott(
    id: 'apple',
    name: 'Apple TV+',
    logoUrl:
        'https://www.apple.com/v/apple-tv/c/images/meta/apple-tv__ft1nltyknfmi_og.png?202609180346',
    providers: '350',
    regions: <String>['IN', 'US'],
    tileBg: Colors.black,
    fit: BoxFit.cover,
  ),
  Ott(
    id: 'hulu',
    name: 'Hulu',
    logoUrl: 'https://www.thisishulu.com/app/uploads/2023/10/logo-gradient-3up.svg',
    providers: '15',
    regions: <String>['US'],
    tileBg: Colors.black,
  ),
];

/// India ke liye "Top 10 in India" me jo OTTs count honge.
const String kIndiaProviders = '8|119|9|122|220|2336|350|232|237';

// ─────────────────────────────────────────────────────────────
//  GENRES
//  movie / tv  = TMDB genre param
//  tvKeyword   = TMDB TV me Romance/Horror/Thriller genre nahi hota → keyword se
//  animeMovie / animeTv = Animation(16) ke saath combine
// ─────────────────────────────────────────────────────────────
class GenreDef {
  final String key;
  final String label;
  final String movie;
  final String? tv;
  final String? tvKeyword;
  final String tvFallback;
  final String animeMovie;
  final String animeTv;
  final bool hasKdrama;
  final Color c1;
  final Color c2;
  final IconData icon;
  const GenreDef({
    required this.key,
    required this.label,
    required this.movie,
    this.tv,
    this.tvKeyword,
    this.tvFallback = '18',
    required this.animeMovie,
    required this.animeTv,
    this.hasKdrama = false,
    required this.c1,
    required this.c2,
    required this.icon,
  });
}

/// Dashboard par jo 7 genre sections dikhte hain
const List<GenreDef> kDashGenres = <GenreDef>[
  GenreDef(
    key: 'action', label: 'Action', movie: '28', tv: '10759',
    animeMovie: '16,28', animeTv: '16,10759',
    c1: Color(0xFFD62828), c2: Color(0xFF3A0A0A), icon: Icons.local_fire_department_rounded,
  ),
  GenreDef(
    key: 'romance', label: 'Romance', movie: '10749', tvKeyword: 'romance', tvFallback: '18',
    animeMovie: '16,10749', animeTv: '16',
    c1: Color(0xFFE0457B), c2: Color(0xFF4A0D2A), icon: Icons.favorite_rounded,
  ),
  GenreDef(
    key: 'horror', label: 'Horror', movie: '27', tvKeyword: 'horror', tvFallback: '9648',
    animeMovie: '16,27', animeTv: '16',
    c1: Color(0xFF6B21A8), c2: Color(0xFF12041F), icon: Icons.nightlight_round,
  ),
  GenreDef(
    key: 'thriller', label: 'Thriller', movie: '53', tvKeyword: 'thriller', tvFallback: '80',
    animeMovie: '16,53', animeTv: '16',
    c1: Color(0xFF1E3A8A), c2: Color(0xFF060B1F), icon: Icons.visibility_rounded,
  ),
  GenreDef(
    key: 'drama', label: 'Drama', movie: '18', tv: '18',
    animeMovie: '16,18', animeTv: '16,18', hasKdrama: true,
    c1: Color(0xFF0F766E), c2: Color(0xFF04201E), icon: Icons.theater_comedy_rounded,
  ),
  GenreDef(
    key: 'mystery', label: 'Mystery & Imagination', movie: '9648|14', tv: '9648|10765',
    animeMovie: '16,9648', animeTv: '16,9648',
    c1: Color(0xFFB45309), c2: Color(0xFF2B1304), icon: Icons.auto_awesome_rounded,
  ),
  GenreDef(
    key: 'scifi', label: 'Sci-Fi / Science Fiction', movie: '878', tv: '10765',
    animeMovie: '16,878', animeTv: '16,10765',
    c1: Color(0xFF0369A1), c2: Color(0xFF031A2B), icon: Icons.rocket_launch_rounded,
  ),
];

/// OTT pages / genre chips ke liye extra genres
const List<GenreDef> kExtraGenres = <GenreDef>[
  GenreDef(
    key: 'comedy', label: 'Comedy', movie: '35', tv: '35',
    animeMovie: '16,35', animeTv: '16,35',
    c1: Color(0xFFEAB308), c2: Color(0xFF3A2D02), icon: Icons.emoji_emotions_rounded,
  ),
  GenreDef(
    key: 'fantasy', label: 'Fantasy', movie: '14', tv: '10765',
    animeMovie: '16,14', animeTv: '16,10765',
    c1: Color(0xFF7C3AED), c2: Color(0xFF1A0B3D), icon: Icons.blur_on_rounded,
  ),
  GenreDef(
    key: 'crime', label: 'Crime', movie: '80', tv: '80',
    animeMovie: '16,80', animeTv: '16,80',
    c1: Color(0xFF475569), c2: Color(0xFF0B1018), icon: Icons.gavel_rounded,
  ),
  GenreDef(
    key: 'family', label: 'Family', movie: '10751', tv: '10751',
    animeMovie: '16,10751', animeTv: '16,10751',
    c1: Color(0xFF16A34A), c2: Color(0xFF05200D), icon: Icons.family_restroom_rounded,
  ),
];

const List<GenreDef> kAllGenres = <GenreDef>[...kDashGenres, ...kExtraGenres];