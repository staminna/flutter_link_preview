import 'package:flutter/material.dart';

import 'web_analyzer.dart';
import 'web_info.dart';

/// Link Preview Widget
class FlutterLinkPreview extends StatefulWidget {
  const FlutterLinkPreview({
    super.key,
    required this.url,
    this.cache = const Duration(hours: 24),
    this.builder,
    this.titleStyle,
    this.bodyStyle,
    this.showMultimedia = true,
    this.useMultithread = false,
  });

  /// Web address, HTTP and HTTPS support
  final String url;

  /// Cache result time, default cache 24 hours
  final Duration cache;

  /// Customized rendering methods
  final Widget Function(InfoBase? info)? builder;

  /// Title style
  final TextStyle? titleStyle;

  /// Content style
  final TextStyle? bodyStyle;

  /// Show image or video
  final bool showMultimedia;

  /// Whether to use multi-threaded analysis of web pages
  final bool useMultithread;

  @override
  State<FlutterLinkPreview> createState() => _FlutterLinkPreviewState();
}

class _FlutterLinkPreviewState extends State<FlutterLinkPreview> {
  late String _url;
  InfoBase? _info;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(FlutterLinkPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      _info = null;
      _init();
    }
  }

  void _init() {
    _url = widget.url.trim();
    _info = WebAnalyzer.getInfoFromCache(_url);
    if (_info == null) _getInfo();
  }

  Future<void> _getInfo() async {
    final url = _url;
    if (!url.startsWith("http")) return;
    final info = await WebAnalyzer.getInfo(
      url,
      cache: widget.cache,
      multimedia: widget.showMultimedia,
      useMultithread: widget.useMultithread,
    );
    // Ignore stale results if the widget was rebuilt with a different URL.
    if (mounted && url == _url) {
      setState(() => _info = info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final builder = widget.builder;
    if (builder != null) return builder(_info);

    return switch (_info) {
      null => const SizedBox(),
      final WebImageInfo info => Image.network(info.image, fit: BoxFit.contain),
      final WebInfo info => _buildWebInfo(info),
    };
  }

  Widget _buildWebInfo(WebInfo info) {
    if (!WebAnalyzer.isNotEmpty(info.title)) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: [
            Image.network(
              info.icon ?? "",
              fit: BoxFit.contain,
              width: 30,
              height: 30,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.link, size: 30, color: widget.titleStyle?.color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                info.title ?? "",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: widget.titleStyle,
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
            style: widget.bodyStyle,
          ),
        ],
      ],
    );
  }
}
