# flutter_link_preview

This is a URL preview plugin that previews the content of a URL

Language: [English](README.md) | [中文简体](README-ZH.md)

![Demo](images/web1.png)

## Special feature

-   Null safe, Dart 3 / Flutter 3.22+, works on all platforms including Flutter Web
-   Optional isolate parsing (`useMultithread`) to keep the main isolate free
-   Support for content caching and expiration mechanisms to return results faster
-   Better fault tolerance, multiple ways to find icons, titles, descriptions, image
-   Charset aware: honors Content-Type / meta charset, including GBK — no messy code
-   Optimized for large files with better crawl performance
-   Support gif, video and other content capture
-   Supports custom builder

## Getting Started

```dart
FlutterLinkPreview(
    url: "https://github.com",
    titleStyle: TextStyle(
        color: Colors.blue,
        fontWeight: FontWeight.bold,
    ),
)
```

Result:

![Result Image](images/web2.png)

## Custom Rendering

```dart
Widget _buildCustomLinkPreview(BuildContext context) {
  return FlutterLinkPreview(
    key: ValueKey("${_controller.value.text}211"),
    url: _controller.value.text,
    builder: (info) {
      if (info == null) return const SizedBox();
      if (info is WebImageInfo) {
        return CachedNetworkImage(
          imageUrl: info.image,
          fit: BoxFit.contain,
        );
      }

      if (info is! WebInfo) return const SizedBox();
      final webInfo = info;
      if (!WebAnalyzer.isNotEmpty(webInfo.title)) return const SizedBox();
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: const Color(0xFFF0F1F2),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CachedNetworkImage(
                  imageUrl: webInfo.icon ?? "",
                  imageBuilder: (context, imageProvider) {
                    return Image(
                      image: imageProvider,
                      fit: BoxFit.contain,
                      width: 30,
                      height: 30,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.link);
                      },
                    );
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    webInfo.title ?? "",
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (WebAnalyzer.isNotEmpty(webInfo.description)) ...[
              const SizedBox(height: 8),
              Text(
                webInfo.description ?? "",
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (WebAnalyzer.isNotEmpty(webInfo.image)) ...[
              const SizedBox(height: 8),
              CachedNetworkImage(
                imageUrl: webInfo.image ?? "",
                fit: BoxFit.contain,
              ),
            ]
          ],
        ),
      );
    },
  );
}
```

![Result Image](images/web3.png)

## Flutter Web

The package compiles and runs on Flutter Web, with two browser-imposed caveats:

-   **CORS**: the browser only allows fetching sites that send permissive `Access-Control-Allow-Origin` headers. Most arbitrary sites do not, so previews on web typically require routing requests through your own proxy. When a fetch is blocked, `getInfo` returns `null` and the widget renders nothing.
-   Browsers follow redirects transparently and drop restricted headers (`User-Agent`, `Cookie`), so `WebInfo.redirectUrl` may simply equal the requested URL on web.

`useMultithread` silently degrades to same-isolate execution on web (isolates are unavailable there).

## Migrating to 2.0

Version 2.0.0 is a breaking modernization release (null safety, Dart 3, Flutter Web):

-   Requires Dart >= 3.4 / Flutter >= 3.22.
-   `builder` is now `Widget Function(InfoBase? info)?` — handle `null` and use `is WebInfo` / `is WebImageInfo` checks (implicit downcasts from `InfoBase` no longer compile).
-   `WebInfo.title/description/icon/image` are `String?`; `WebInfo.redirectUrl` is non-null.
-   Disable caching with `cache: Duration.zero` instead of `null`.
-   `WebAnalyzer.userAgent` replaces the old hard-coded user agents; `WebAnalyzer.logger` replaces console prints; `getInfo` accepts a `timeout`.
-   Removed: the accept-all invalid-certificate callback, the hard-coded weibo.com cookie, and other 2020-era site-specific hacks.

## Sample code

[Click here for a detailed example](example/lib/main.dart).

## Credits

This package was originally created by [yungzhu](https://github.com/yungzhu) — all the core scraping and preview design is theirs ([original repository](https://github.com/yungzhu/flutter_link_preview)). Version 2.0.0 is a community modernization (null safety, Dart 3, Flutter Web) building on that work.
