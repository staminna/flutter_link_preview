import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:collection/collection.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'isolate_runner_stub.dart' if (dart.library.io) 'isolate_runner_io.dart';
import 'web_info.dart';

class _CacheEntry {
  final InfoBase info;
  final DateTime expiry;

  _CacheEntry(this.info, this.expiry);
}

class _FetchResult {
  final http.Response response;
  final String finalUrl;

  _FetchResult(this.response, {required this.finalUrl});
}

/// Web analyzer
class WebAnalyzer {
  static final Map<String, _CacheEntry> _cache = {};
  static final RegExp _bodyReg =
      RegExp(r"<body[^>]*>([\s\S]*?)<\/body>", caseSensitive: false);
  static final RegExp _metaReg = RegExp(
      r"<(meta|link)(.*?)\/?>|<title(.*?)</title>",
      caseSensitive: false,
      dotAll: true);
  static final RegExp _titleReg =
      RegExp("(title|icon|description|image|video)", caseSensitive: false);
  static final RegExp _lineReg = RegExp(r"[\n\r]|&nbsp;|&gt;");
  static final RegExp _spaceReg = RegExp(r"\s+");
  static final RegExp _charsetReg =
      RegExp('charset=["\']?([\\w-]+)', caseSensitive: false);

  /// User-Agent header sent with requests.
  ///
  /// Browsers ignore this on Flutter Web (User-Agent is a forbidden header).
  /// Note: when [getInfo] runs with `useMultithread: true`, the value is
  /// captured at call time and passed to the isolate.
  static String userAgent =
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

  /// Optional diagnostics hook; null (default) = silent.
  ///
  /// Not called from the spawned isolate when `useMultithread` is true.
  static void Function(String message)? logger;

  /// Overrides the HTTP client used by [getInfo]; test seam only.
  ///
  /// Does not cross isolate boundaries, so tests must use
  /// `useMultithread: false`.
  @visibleForTesting
  static http.Client Function()? clientFactoryOverride;

  /// Is it a non-empty string
  static bool isNotEmpty(String? str) {
    return str != null && str.isNotEmpty;
  }

  /// Get web information from the cache.
  ///
  /// Returns null when the entry is missing or expired.
  static InfoBase? getInfoFromCache(String url) {
    final entry = _cache[url];
    if (entry == null) return null;
    if (!entry.expiry.isAfter(DateTime.now())) {
      _cache.remove(url);
      return null;
    }
    return entry.info;
  }

  @visibleForTesting
  static void clearCache() => _cache.clear();

  /// Get web information.
  ///
  /// Results are cached for [cache]; pass [Duration.zero] to disable caching.
  /// Returns null when the URL cannot be fetched or parsed.
  static Future<InfoBase?> getInfo(
    String url, {
    Duration cache = const Duration(hours: 24),
    bool multimedia = true,
    bool useMultithread = false,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final cached = getInfoFromCache(url);
    if (cached != null) return cached;

    InfoBase? info;
    try {
      // The isolate closure captures only sendable values (String/bool/
      // Duration); statics like the cache do not cross the boundary, so the
      // cache write below always happens on the calling isolate.
      final agent = userAgent;
      Future<InfoBase?> fetch() =>
          _fetchInfo(url, multimedia: multimedia, timeout: timeout, userAgent: agent);
      info = useMultithread ? await runIsolated(fetch) : await fetch();

      if (info != null && cache > Duration.zero) {
        _cache[url] = _CacheEntry(info, DateTime.now().add(cache));
      }
    } catch (e) {
      logger?.call("flutter_link_preview: failed to get info for $url: $e");
    }

    return info;
  }

  static Future<InfoBase?> _fetchInfo(
    String url, {
    required bool multimedia,
    required Duration timeout,
    required String userAgent,
  }) async {
    final result = await _requestUrl(url, timeout: timeout, userAgent: userAgent);
    if (result == null) return null;

    final contentType = result.response.headers["content-type"];
    if (multimedia && contentType != null) {
      if (contentType.contains("image/")) {
        return WebImageInfo(image: url);
      } else if (contentType.contains("video/")) {
        return WebVideoInfo(image: url);
      }
    }

    return _parseWebInfo(
        result.response.bodyBytes, contentType, result.finalUrl, multimedia);
  }

  static Future<_FetchResult?> _requestUrl(
    String url, {
    required Duration timeout,
    required String userAgent,
  }) async {
    final client = (clientFactoryOverride ?? http.Client.new)();
    try {
      var currentUrl = url;
      String? cookie;
      for (var redirects = 0; redirects <= 6; redirects++) {
        final request = http.Request("GET", Uri.parse(currentUrl))
          ..followRedirects = false
          ..headers["User-Agent"] = userAgent
          ..headers["cache-control"] = "no-cache"
          ..headers["accept"] = "*/*";
        if (cookie != null) request.headers["Cookie"] = cookie;

        final streamed = await client.send(request).timeout(timeout);

        // On the web the browser follows redirects transparently, so this
        // branch only runs on io platforms.
        if (const {301, 302, 303, 307, 308}.contains(streamed.statusCode)) {
          final location = streamed.headers["location"];
          if (location == null) return null;
          currentUrl = Uri.parse(currentUrl).resolve(location).toString();
          cookie = streamed.headers["set-cookie"] ?? cookie;
          continue;
        }

        if (streamed.statusCode == 200) {
          final response = await http.Response.fromStream(streamed);
          return _FetchResult(response, finalUrl: currentUrl);
        }

        logger?.call(
            "flutter_link_preview: HTTP ${streamed.statusCode} for $currentUrl");
        return null;
      }
      logger?.call("flutter_link_preview: too many redirects for $url");
      return null;
    } on Exception catch (e) {
      logger?.call("flutter_link_preview: request failed for $url: $e");
      return null;
    } finally {
      client.close();
    }
  }

  static InfoBase? _parseWebInfo(Uint8List bodyBytes, String? contentType,
      String finalUrl, bool multimedia) {
    final html = _decodeBody(bodyBytes, contentType);

    final headHtml = _getHeadHtml(html);
    final document = parser.parse(headHtml);
    final uri = Uri.parse(finalUrl);

    // get image or video defined in the Open Graph tags
    if (multimedia) {
      final gif = _analyzeGif(document, uri);
      if (gif != null) return gif;

      final video = _analyzeVideo(document, uri);
      if (video != null) return video;
    }

    String? title = _analyzeTitle(document);
    String? description =
        _analyzeDescription(document, html)?.replaceAll(r"\x0a", " ");
    if (!isNotEmpty(title)) {
      title = description;
      description = null;
    }

    return WebInfo(
      title: title,
      icon: _analyzeIcon(document, uri),
      description: description,
      image: _analyzeImage(document, uri),
      redirectUrl: finalUrl,
    );
  }

  /// Decodes [bytes] honoring the charset from the Content-Type header or a
  /// sniffed `<meta charset>`; falls back utf8 → gbk → lenient utf8, so it
  /// always returns a string.
  static String _decodeBody(Uint8List bytes, String? contentTypeHeader) {
    final charsetName =
        _charsetReg.firstMatch(contentTypeHeader ?? "")?.group(1)?.toLowerCase() ??
            _sniffMetaCharset(bytes);
    switch (charsetName) {
      case "gbk" || "gb2312" || "gb18030":
        try {
          return gbk.decode(bytes);
        } catch (_) {
          break;
        }
      case "iso-8859-1" || "latin1":
        return latin1.decode(bytes);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      // fall through
    }
    try {
      return gbk.decode(bytes);
    } catch (_) {
      // fall through
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String? _sniffMetaCharset(Uint8List bytes) {
    final prefix =
        latin1.decode(Uint8List.sublistView(bytes, 0, bytes.length.clamp(0, 1024)));
    return _charsetReg.firstMatch(prefix)?.group(1)?.toLowerCase();
  }

  // Reduces the parsed surface to the meta/link/title tags for performance.
  static String _getHeadHtml(String html) {
    html = html.replaceFirst(_bodyReg, "<body></body>");
    final matches = _metaReg.allMatches(html);
    final head = StringBuffer("<html><head>");
    for (final match in matches) {
      final str = match.group(0)!;
      if (str.contains(_titleReg)) head.writeln(str);
    }
    head.writeln("</head></html>");
    return head.toString();
  }

  static InfoBase? _analyzeGif(Document document, Uri uri) {
    if (_getMetaContent(document, "property", "og:image:type") == "image/gif") {
      final gif = _getMetaContent(document, "property", "og:image");
      if (gif != null) {
        final image = _handleUrl(uri, gif);
        if (image != null) return WebImageInfo(image: image);
      }
    }
    return null;
  }

  static InfoBase? _analyzeVideo(Document document, Uri uri) {
    final video = _getMetaContent(document, "property", "og:video");
    if (video != null) {
      final image = _handleUrl(uri, video);
      if (image != null) return WebVideoInfo(image: image);
    }
    return null;
  }

  static String? _getMetaContent(
      Document document, String property, String propertyValue) {
    final meta = document.head?.getElementsByTagName("meta") ?? const <Element>[];
    final ele =
        meta.firstWhereOrNull((e) => e.attributes[property] == propertyValue);
    return ele?.attributes["content"]?.trim();
  }

  static String? _analyzeTitle(Document document) {
    final title = _getMetaContent(document, "property", "og:title");
    if (title != null) return title;
    final list = document.head?.getElementsByTagName("title") ?? const <Element>[];
    if (list.isNotEmpty) {
      return list.first.text.trim();
    }
    return null;
  }

  static String? _analyzeDescription(Document document, String html) {
    final desc = _getMetaContent(document, "property", "og:description") ??
        _getMetaContent(document, "name", "twitter:description") ??
        _getMetaContent(document, "name", "description") ??
        _getMetaContent(document, "name", "Description");
    if (isNotEmpty(desc)) return desc;
    return _firstProse(html);
  }

  /// The first paragraph on the page that reads like prose, or null.
  ///
  /// This replaces a fallback that stripped every tag from the whole document
  /// and returned the first 300 characters. On a page without a description
  /// meta tag that is the navigation rather than the content: Wikipedia
  /// previewed as "Jump to content Main menu Main menu move to sidebar hide
  /// Navigation Main pageContents…" and Hacker News as its own header and
  /// login links. A preview showing a site's menu is worse than one showing no
  /// description at all, so when nothing here reads like a sentence the answer
  /// is null and the widget simply renders the title.
  ///
  /// Only runs when the meta tags are missing, which is what makes parsing the
  /// whole document affordable — the common path still parses the head alone.
  static String? _firstProse(String html) {
    final Document document;
    try {
      document = parser.parse(html);
    } catch (_) {
      return null;
    }
    // Chrome, not content. Removed wholesale so that a paragraph nested inside
    // a banner cannot win over the article's own opening line.
    for (final tag in const [
      "script",
      "style",
      "nav",
      "header",
      "footer",
      "aside",
      "form",
      "noscript",
    ]) {
      for (final element in document.getElementsByTagName(tag).toList()) {
        element.remove();
      }
    }
    for (final paragraph in document.getElementsByTagName("p")) {
      final text = paragraph.text
          .replaceAll(_lineReg, " ")
          .replaceAll(_spaceReg, " ")
          .trim();
      // Long enough to be a sentence rather than a label, a byline, or a
      // cookie banner's "OK".
      if (text.length < 60) continue;
      return text.length > 300 ? text.substring(0, 300) : text;
    }
    return null;
  }

  static String? _analyzeIcon(Document document, Uri uri) {
    final links = document.head?.getElementsByTagName("link") ?? const <Element>[];

    bool isUsableIcon(Element e, String rel) {
      if ((e.attributes["rel"] ?? "").toLowerCase() != rel) return false;
      final href = e.attributes["href"];
      return href != null && !href.toLowerCase().contains(".svg");
    }

    final icon = links.firstWhereOrNull((e) => isUsableIcon(e, "icon")) ??
        links.firstWhereOrNull((e) => isUsableIcon(e, "shortcut icon"));

    final href = icon?.attributes["href"];
    if (href == null) return "${uri.origin}/favicon.ico";
    return _handleUrl(uri, href);
  }

  static String? _analyzeImage(Document document, Uri uri) {
    final image = _getMetaContent(document, "property", "og:image");
    return _handleUrl(uri, image);
  }

  static String? _handleUrl(Uri uri, String? source) {
    if (!isNotEmpty(source)) return source;
    try {
      return uri.resolve(source!).toString();
    } on FormatException {
      return source;
    }
  }
}
