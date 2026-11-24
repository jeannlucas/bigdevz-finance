import 'package:flutter/services.dart';

Future<void> openCompanySite(String url) =>
    Clipboard.setData(ClipboardData(text: url));
