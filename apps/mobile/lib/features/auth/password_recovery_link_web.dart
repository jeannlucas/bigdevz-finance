import 'dart:js_interop';

@JS('history.replaceState')
external void _replaceState(JSAny? state, String unused, String url);

({String email, String token})? takePasswordRecoveryLink() {
  const prefix = 'redefinir-senha?';
  final url = Uri.base;
  final fragment = url.fragment;
  if (!fragment.startsWith(prefix)) return null;

  _replaceState(null, '', url.removeFragment().toString());
  try {
    final params = Uri.splitQueryString(fragment.substring(prefix.length));
    return (email: params['email'] ?? '', token: params['token'] ?? '');
  } on FormatException {
    return (email: '', token: '');
  } on ArgumentError {
    return (email: '', token: '');
  }
}
