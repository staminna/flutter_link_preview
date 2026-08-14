import 'package:charset/charset.dart';
import 'package:flutter_link_preview/flutter_link_preview.dart';
import 'package:flutter_link_preview/src/isolate_runner_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const ogFixture = '''
<html>
<head>
<title>Tag Title</title>
<meta property="og:title" content="OG Title" />
<meta property="og:description" content="OG Description" />
<meta property="og:image" content="https://cdn.example.com/img.png" />
<link rel="icon" href="https://example.com/favicon.png" />
</head>
<body><p>Hello body</p></body>
</html>
''';

const fallbackFixture = '''
<html>
<head>
<title>Plain Title</title>
<meta name="description" content="Plain description" />
</head>
<body><p>Hello body</p></body>
</html>
''';

/// Installs a MockClient serving [responses] keyed by full URL and returns a
/// per-URL request counter.
///
/// All tests use `useMultithread: false`: the client override is a static and
/// does not cross into a spawned isolate.
Map<String, int> serve(Map<String, http.Response> responses) {
  final counts = <String, int>{};
  WebAnalyzer.clientFactoryOverride = () => MockClient((request) async {
        final url = request.url.toString();
        counts[url] = (counts[url] ?? 0) + 1;
        final response = responses[url];
        if (response == null) return http.Response('not found', 404);
        return response;
      });
  return counts;
}

http.Response htmlResponse(String body, {String contentType = 'text/html'}) =>
    http.Response(body, 200, headers: {'content-type': contentType});

void main() {
  _descriptionFallbackTests();

  tearDown(() {
    WebAnalyzer.clientFactoryOverride = null;
    WebAnalyzer.logger = null;
    WebAnalyzer.clearCache();
  });

  group('WebAnalyzer.getInfo parsing', () {
    test('extracts OpenGraph title, description, image and icon', () async {
      serve({'https://example.com/': htmlResponse(ogFixture)});

      final info = await WebAnalyzer.getInfo('https://example.com/');

      expect(info, isA<WebInfo>());
      final webInfo = info! as WebInfo;
      expect(webInfo.title, 'OG Title');
      expect(webInfo.description, 'OG Description');
      expect(webInfo.image, 'https://cdn.example.com/img.png');
      expect(webInfo.icon, 'https://example.com/favicon.png');
      expect(webInfo.redirectUrl, 'https://example.com/');
    });

    test('falls back to title tag and meta description', () async {
      serve({'https://example.com/': htmlResponse(fallbackFixture)});

      final info =
          await WebAnalyzer.getInfo('https://example.com/') as WebInfo?;

      expect(info!.title, 'Plain Title');
      expect(info.description, 'Plain description');
    });

    test('promotes description to title when no title exists', () async {
      serve({
        'https://example.com/': htmlResponse('''
<html><head><meta name="description" content="Only description" /></head>
<body></body></html>
''')
      });

      final info =
          await WebAnalyzer.getInfo('https://example.com/') as WebInfo?;

      expect(info!.title, 'Only description');
      expect(info.description, isNull);
    });

    test('resolves relative icon and image URLs against the page', () async {
      serve({
        'https://example.com/blog/post': htmlResponse('''
<html><head>
<title>T</title>
<meta property="og:image" content="//cdn.example.com/x.jpg" />
<link rel="icon" href="/assets/favicon.png" />
</head><body></body></html>
''')
      });

      final info =
          await WebAnalyzer.getInfo('https://example.com/blog/post') as WebInfo?;

      expect(info!.icon, 'https://example.com/assets/favicon.png');
      expect(info.image, 'https://cdn.example.com/x.jpg');
    });

    test('falls back to /favicon.ico when the page declares no icon',
        () async {
      serve({
        'https://example.com/page':
            htmlResponse('<html><head><title>T</title></head><body></body></html>')
      });

      final info =
          await WebAnalyzer.getInfo('https://example.com/page') as WebInfo?;

      expect(info!.icon, 'https://example.com/favicon.ico');
    });
  });

  group('multimedia', () {
    test('image and video content types short-circuit to media info',
        () async {
      serve({
        'https://example.com/a.png':
            htmlResponse('bytes', contentType: 'image/png'),
        'https://example.com/a.mp4':
            htmlResponse('bytes', contentType: 'video/mp4'),
      });

      final image = await WebAnalyzer.getInfo('https://example.com/a.png');
      final video = await WebAnalyzer.getInfo('https://example.com/a.mp4');

      expect(image, isA<WebImageInfo>());
      expect((image! as WebImageInfo).image, 'https://example.com/a.png');
      expect(video, isA<WebVideoInfo>());
    });

    test('multimedia: false skips the content-type short-circuit', () async {
      serve({
        'https://example.com/a.png':
            htmlResponse(ogFixture, contentType: 'image/png'),
      });

      final info = await WebAnalyzer.getInfo('https://example.com/a.png',
          multimedia: false);

      expect(info, isA<WebInfo>());
    });

    test('og:image:type image/gif yields WebImageInfo, og:video yields '
        'WebVideoInfo', () async {
      serve({
        'https://example.com/gif': htmlResponse('''
<html><head>
<meta property="og:image:type" content="image/gif" />
<meta property="og:image" content="/anim.gif" />
</head><body></body></html>
'''),
        'https://example.com/video': htmlResponse('''
<html><head>
<meta property="og:video" content="https://example.com/v.mp4" />
</head><body></body></html>
'''),
      });

      final gif = await WebAnalyzer.getInfo('https://example.com/gif');
      final video = await WebAnalyzer.getInfo('https://example.com/video');

      expect(gif, isA<WebImageInfo>());
      expect((gif! as WebImageInfo).image, 'https://example.com/anim.gif');
      expect(video, isA<WebVideoInfo>());
      expect((video! as WebVideoInfo).image, 'https://example.com/v.mp4');
    });
  });

  group('charset handling', () {
    const chineseHtml =
        '<html><head><title>中文标题测试</title></head><body></body></html>';

    test('decodes GBK from the Content-Type header charset', () async {
      WebAnalyzer.clientFactoryOverride = () => MockClient((request) async =>
          http.Response.bytes(gbk.encode(chineseHtml), 200,
              headers: {'content-type': 'text/html; charset=gbk'}));

      final info =
          await WebAnalyzer.getInfo('https://example.com/gbk') as WebInfo?;

      expect(info!.title, '中文标题测试');
    });

    test('decodes GBK sniffed from a meta charset tag', () async {
      const metaHtml = '<html><head><meta charset="gbk">'
          '<title>中文标题测试</title></head><body></body></html>';
      WebAnalyzer.clientFactoryOverride = () => MockClient((request) async =>
          http.Response.bytes(gbk.encode(metaHtml), 200,
              headers: {'content-type': 'text/html'}));

      final info =
          await WebAnalyzer.getInfo('https://example.com/gbk-meta') as WebInfo?;

      expect(info!.title, '中文标题测试');
    });

    test('falls back utf8 -> gbk when no charset is declared', () async {
      WebAnalyzer.clientFactoryOverride = () => MockClient((request) async =>
          http.Response.bytes(gbk.encode(chineseHtml), 200,
              headers: {'content-type': 'text/html'}));

      final info = await WebAnalyzer.getInfo('https://example.com/gbk-sniff')
          as WebInfo?;

      expect(info!.title, '中文标题测试');
    });
  });

  group('redirects', () {
    test('follows redirects and reports the final URL', () async {
      WebAnalyzer.clientFactoryOverride = () => MockClient((request) async {
            if (request.url.toString() == 'https://short.example/a') {
              return http.Response('', 302,
                  headers: {'location': 'https://real.example/page'});
            }
            return htmlResponse(ogFixture);
          });

      final info =
          await WebAnalyzer.getInfo('https://short.example/a') as WebInfo?;

      expect(info!.redirectUrl, 'https://real.example/page');
      expect(info.title, 'OG Title');
    });
  });

  group('caching', () {
    test('second lookup is served from the cache', () async {
      final counts = serve({'https://example.com/': htmlResponse(ogFixture)});

      await WebAnalyzer.getInfo('https://example.com/');
      await WebAnalyzer.getInfo('https://example.com/');

      expect(counts['https://example.com/'], 1);
      expect(WebAnalyzer.getInfoFromCache('https://example.com/'), isNotNull);
    });

    test('expired entries are evicted, not returned', () async {
      final counts = serve({'https://example.com/': htmlResponse(ogFixture)});

      await WebAnalyzer.getInfo('https://example.com/',
          cache: const Duration(milliseconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(WebAnalyzer.getInfoFromCache('https://example.com/'), isNull);

      await WebAnalyzer.getInfo('https://example.com/',
          cache: const Duration(milliseconds: 1));
      expect(counts['https://example.com/'], 2);
    });

    test('Duration.zero disables caching', () async {
      final counts = serve({'https://example.com/': htmlResponse(ogFixture)});

      await WebAnalyzer.getInfo('https://example.com/', cache: Duration.zero);
      await WebAnalyzer.getInfo('https://example.com/', cache: Duration.zero);

      expect(counts['https://example.com/'], 2);
    });
  });

  group('errors', () {
    test('non-200 responses yield null', () async {
      serve({}); // everything 404s

      final info = await WebAnalyzer.getInfo('https://example.com/missing');

      expect(info, isNull);
    });

    test('a throwing client yields null instead of throwing', () async {
      WebAnalyzer.clientFactoryOverride = () => MockClient(
          (request) async => throw http.ClientException('boom', request.url));
      final messages = <String>[];
      WebAnalyzer.logger = messages.add;

      final info = await WebAnalyzer.getInfo('https://example.com/');

      expect(info, isNull);
      expect(messages, isNotEmpty);
    });
  });

  test('isNotEmpty', () {
    expect(WebAnalyzer.isNotEmpty(null), isFalse);
    expect(WebAnalyzer.isNotEmpty(''), isFalse);
    expect(WebAnalyzer.isNotEmpty('x'), isTrue);
  });

  test('runIsolated executes the computation on an isolate', () async {
    final result = await runIsolated(() async => 21 * 2);
    expect(result, 42);
  });
}

/// A page shaped like the ones that exposed the bug: no description meta tag
/// anywhere, a navigation bar full of words, and the real content further down.
const noMetaDescriptionFixture = '''
<html>
<head><title>Encyclopedia</title></head>
<body>
  <nav>Jump to content Main menu move to sidebar hide Navigation Main page Contents Current events Random article About Contact us Contribute Help Learn to edit</nav>
  <header>Search Appearance Donate Create account Log in Personal tools</header>
  <p>Short label</p>
  <p>Flutter is an open-source UI software development kit created by Google, used to build cross-platform applications from a single codebase.</p>
</body>
</html>
''';

/// Navigation only — nothing on the page reads like a sentence.
const chromeOnlyFixture = '''
<html>
<head><title>Link Aggregator</title></head>
<body>
  <nav>new | past | comments | ask | show | jobs | submit | login</nav>
  <p>1.</p>
  <p>2.</p>
</body>
</html>
''';

void _descriptionFallbackTests() {
  group('description without a meta tag', () {
    tearDown(() {
      WebAnalyzer.clientFactoryOverride = null;
      WebAnalyzer.clearCache();
    });

    test('takes the first real paragraph, never the navigation', () async {
      serve({'https://wiki.example/': htmlResponse(noMetaDescriptionFixture)});
      final info = await WebAnalyzer.getInfo('https://wiki.example/',
          cache: Duration.zero) as WebInfo;

      expect(info.description, startsWith('Flutter is an open-source UI'));
      expect(info.description, isNot(contains('Main menu')));
      expect(info.description, isNot(contains('Log in')));
      // "Short label" is a paragraph too, and too short to be a description.
      expect(info.description, isNot(contains('Short label')));
    });

    test('leaves it null when the page is only chrome', () async {
      serve({'https://news.example/': htmlResponse(chromeOnlyFixture)});
      final info = await WebAnalyzer.getInfo('https://news.example/',
          cache: Duration.zero) as WebInfo;

      // A title with no description beats a title followed by a menu.
      expect(info.title, 'Link Aggregator');
      expect(info.description, isNull);
    });

    test('twitter:description is read when OpenGraph is absent', () async {
      serve({
        'https://tw.example/': htmlResponse('''
<html><head><title>T</title>
<meta name="twitter:description" content="From the Twitter card" />
</head><body><p>${'body text that is comfortably longer than sixty characters'}</p></body></html>
'''),
      });
      final info = await WebAnalyzer.getInfo('https://tw.example/',
          cache: Duration.zero) as WebInfo;

      expect(info.description, 'From the Twitter card');
    });
  });
}
