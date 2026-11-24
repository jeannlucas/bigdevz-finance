import 'dart:js_interop';

@JS('window.open')
external void _open(JSString url, JSString target, JSString features);

Future<void> openCompanySite(String url) async {
  _open(url.toJS, '_blank'.toJS, 'noopener,noreferrer'.toJS);
}
