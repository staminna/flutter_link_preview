import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_link_preview/flutter_link_preview.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Flutter Demo',
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _controller = TextEditingController(
    text: "https://github.com/flutter/flutter",
  );
  int _index = -1;
  final List<String> _urls = [
    "https://github.com/flutter/flutter",
    "https://en.wikipedia.org/wiki/Flutter_(software)",
    "https://www.youtube.com/watch?v=b_sQ9bMltGU",
    "https://pub.dev/packages/http",
    "https://news.sina.com.cn/",
    "https://www.zhihu.com/",
    "https://www.bilibili.com/",
    "https://raw.githubusercontent.com/flutter/website/main/src/_assets/image/flutter-lockup-bg.jpg",
    "https://media.giphy.com/media/3o7aCTfyhYawdOXcFW/giphy.gif",
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(controller: _controller),
              Row(
                children: <Widget>[
                  ElevatedButton(
                    onPressed: () {
                      setState(() {});
                    },
                    child: const Text("get"),
                  ),
                  const SizedBox(width: 15),
                  ElevatedButton(
                    onPressed: () {
                      _index++;
                      if (_index >= _urls.length) _index = 0;
                      _controller.text = _urls[_index];
                      setState(() {});
                    },
                    child: const Text("next"),
                  ),
                  const SizedBox(width: 15),
                  ElevatedButton(
                    onPressed: () {
                      _controller.clear();
                    },
                    child: const Text("clear"),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              FlutterLinkPreview(
                key: ValueKey(_controller.value.text),
                url: _controller.value.text,
                titleStyle: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 50),
              const Text("Custom Builder", style: TextStyle(fontSize: 20)),
              const Divider(),
              _buildCustomLinkPreview(context),
            ],
          ),
        ),
      ),
    );
  }

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
        if (!WebAnalyzer.isNotEmpty(info.title)) return const SizedBox();
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
                    imageUrl: info.icon ?? "",
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.link),
                    imageBuilder: (context, imageProvider) {
                      return Image(
                        image: imageProvider,
                        fit: BoxFit.contain,
                        width: 30,
                        height: 30,
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      info.title ?? "",
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (WebAnalyzer.isNotEmpty(info.description)) ...[
                const SizedBox(height: 8),
                Text(
                  info.description ?? "",
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (WebAnalyzer.isNotEmpty(info.image)) ...[
                const SizedBox(height: 8),
                CachedNetworkImage(
                  imageUrl: info.image ?? "",
                  fit: BoxFit.contain,
                ),
              ]
            ],
          ),
        );
      },
    );
  }
}
