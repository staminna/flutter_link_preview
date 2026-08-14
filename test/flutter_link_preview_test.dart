import 'package:flutter/material.dart';
import 'package:flutter_link_preview_update/flutter_link_preview_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const fixture = '''
<html>
<head>
<meta property="og:title" content="Widget Title" />
<meta property="og:description" content="Widget Description" />
</head>
<body></body>
</html>
''';

void main() {
  setUp(() {
    WebAnalyzer.clientFactoryOverride = () => MockClient((request) async {
          if (request.url.toString() == 'https://example.com/') {
            return http.Response(fixture, 200,
                headers: {'content-type': 'text/html'});
          }
          return http.Response('not found', 404);
        });
  });

  tearDown(() {
    WebAnalyzer.clientFactoryOverride = null;
    WebAnalyzer.clearCache();
  });

  testWidgets('default builder renders title and description', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FlutterLinkPreview(url: 'https://example.com/'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Widget Title'), findsOneWidget);
    expect(find.text('Widget Description'), findsOneWidget);
    // The fixture has no icon; the favicon.ico fallback 404s in the test
    // environment, so the errorBuilder icon renders.
    expect(find.byIcon(Icons.link), findsOneWidget);
  });

  testWidgets('custom builder receives null first, then WebInfo',
      (tester) async {
    final received = <InfoBase?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlutterLinkPreview(
            url: 'https://example.com/',
            builder: (info) {
              received.add(info);
              return Text(info == null ? 'loading' : 'done');
            },
          ),
        ),
      ),
    );

    expect(find.text('loading'), findsOneWidget);
    expect(received, [null]);

    await tester.pumpAndSettle();

    expect(find.text('done'), findsOneWidget);
    expect(received.last, isA<WebInfo>());
  });

  testWidgets('non-http URL renders nothing and does not crash',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FlutterLinkPreview(url: 'abc'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SizedBox), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
