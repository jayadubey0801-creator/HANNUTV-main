# HANNUTV v1.4.0 — Download system setup

## 1. Files (sab ek hi folder me, jahan main.dart / widgets.dart hain)

| File | Kya hai |
|---|---|
| `download_manager.dart` | NEW — engine: HLS parser, parallel segment downloader (retry / resume / pause), FFmpeg converter, `DownloadStore` |
| `download_sheet.dart` | NEW — server scan (sniffer) + quality / language / size picker sheet |
| `downloads_page.dart` | NEW — Dashboard wala Downloads page + in-app offline player |
| `video_player_page.dart` | PATCHED — fake AI downloader hata kar asli sheet jodi + **white line fix** |
| `dashboard_screen.dart` | PATCHED — header ka download icon ab asli page kholta hai (+ active count badge) |
| `main.dart` | PATCHED — sirf version `1.4.0` |

`hero.dart`, `stores.dart`, `widgets.dart` — **bilkul unchanged** (apni purani file hi rakho).
Firebase, OTT icons, iframe/sticker logic, YouTube slider, proxy — kuch nahi chheda.

## 2. Packages (terminal me, project folder me)

```bash
flutter pub add ffmpeg_kit_flutter_new_min path_provider video_player open_filex gal wakelock_plus
flutter pub get
```

`flutter pub add` khud latest compatible version laga deta hai.
(Already hain: http, shared_preferences, webview_flutter, webview_flutter_android, cached_network_image.)

Note: original `ffmpeg_kit_flutter` officially retired hai aur uske Android binaries Maven se hata diye gaye,
isliye maintained fork `ffmpeg_kit_flutter_new_min` use hua hai (sirf local files jodta hai, isliye smallest build kaafi hai).

## 3. Version

`pubspec.yaml`:

```yaml
version: 1.4.0+14     # +14 ko apne pichle build number se bada rakho
```

(`main.dart` me `currentAppVersion = "1.4.0"` ho chuka hai. Firebase Remote Config me `latest_version`
tab hi 1.4.0 karna jab 1.4.0 APK publish kar do.)

## 4. Android

`android/app/build.gradle(.kts)` — `minSdk` kam se kam **24** ho (webview_flutter ke liye pehle se hoga):

```
minSdk = 24
```

`AndroidManifest.xml` — INTERNET pehle se hogi. Purane Android (9 aur neeche) pe gallery export ke liye ye line na ho to add karo:

```xml
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>
```

Android 10+ pe koi storage permission popup nahi aata (movie app ke apne folder me banti hai,
aur Movies/HANNUTV me MediaStore se jaati hai).

## 5. Kaise kaam karta hai

1. Player me **Download** dabao → sheet khulti hai → chhota hidden browser usi server ka embed page kholta hai
   (e.g. `https://embed.vidrift.in/embed/tv/1416/1/1`) aur asli `.m3u8` / `.mp4` stream link pakadta hai.
2. Stream khol kar dikhata hai: **kaun-kaun si quality, kaun-kaun si language (audio tracks), kitna GB (estimate)**.
3. Tum quality + language chunte ho (ya "Sab audio") → **Download**.
4. Segments parallel download hote hain (6 connections, retry, resume). Phir FFmpeg unhe **ek MP4** me jodta hai
   (video + chuni hui audio tracks, faststart, correct timestamps) → isi se gray / purple screen nahi aati.
   Agar copy-mode fail ho to khud audio AAC me convert karta hai, phir MKV try karta hai.
5. **Dashboard → Download icon (search / watchlist ke bagal me)** → list, progress, speed, pause / resume.
   Tap → in-app **offline player** (net band ho tab bhi). 3-dot menu → **Open with VLC / MX Player**.
6. Phone ke `Movies/HANNUTV` me bhi copy ban jaati hai (sheet me switch se band kar sakte ho).

Agar auto-scan fail ho: sheet me **"Link paste karo"** — embed link ya `.m3u8` / `.mp4` link paste karo.

## 6. White line fix

Video ke upar aur left me 2px ki bright L-shaped line thi. Root cause: code iframe ko `position: fixed; width: 100vw`
karta hai par iframe ka **default 2px inset border** nahi hatata tha. Ab CSS + JS dono me `border: 0`, `outline: 0`,
`frameborder=0`, scrollbar hide add hai (purana nuclear CSS/JS logic waisa hi hai, sirf ye lines jodi).

## 7. Test checklist (pehli baar)

1. `flutter clean && flutter pub get && flutter analyze`
2. Phone par run karo → koi episode kholo → Download → quality + language chuno.
3. Dashboard → Download icon → progress dikhna chahiye → done hone par Play.
4. WiFi + data band karke Downloads se movie chalao.
5. 3-dot → Open with VLC / MX Player.

## 8. Sach me jo limits hain

- Ye code mere paas Flutter SDK na hone se **compile / device par run nahi** ho paaya aur sandbox se `embed.vidrift.in`
  tak network nahi tha. Syntax / bracket check hua hai, par pehla `flutter analyze` + ek real test tumhe chalana hoga.
  Koi error aaye to exact error text bhejo, turant fix kar dunga.
- Sirf **HLS (.m3u8)** aur direct **.mp4** support hai. DRM-protected stream (Widevine / SAMPLE-AES) download nahi hoti
  — app saaf message dikhata hai.
- Size **estimate** hai (bitrate x duration), exact nahi. Languages tabhi alag dikhengi jab server unhe HLS me alag
  audio tracks ke roop me deta ho.
- Download tab tak chalta hai jab tak Android app ko zinda rakhe. Phone app kill kar de to app dobara kholne par
  download wahin se **resume** ho jaata hai (segments disk par safe hain). Foreground-service notification abhi nahi hai.
- Subtitles download nahi hoti.
