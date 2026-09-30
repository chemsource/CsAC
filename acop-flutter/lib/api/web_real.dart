/// Web平台实现：从浏览器location推断baseUrl
import 'dart:html' as html show window;

String getWebBaseUrl() {
  final loc = html.window.location;
  return '${loc.protocol}//${loc.host}/acop';
}
