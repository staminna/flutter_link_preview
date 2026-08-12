/// Base type for the result of analyzing a URL.
///
/// Sealed: exhaustive `switch` over [WebInfo], [WebImageInfo] and
/// [WebVideoInfo] is supported.
sealed class InfoBase {}

/// Web Information
class WebInfo extends InfoBase {
  final String? title;
  final String? icon;
  final String? description;
  final String? image;

  /// The final URL after following redirects; equals the requested URL when
  /// no redirect happened (or on the web, where the browser follows
  /// redirects transparently).
  final String redirectUrl;

  WebInfo({
    this.title,
    this.icon,
    this.description,
    this.image,
    required this.redirectUrl,
  });
}

/// Image Information
class WebImageInfo extends InfoBase {
  final String image;

  WebImageInfo({required this.image});
}

/// Video Information
class WebVideoInfo extends WebImageInfo {
  WebVideoInfo({required super.image});
}
