import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Uses browser sessionStorage so tokens survive hot reloads.

String? read(String key) {
  return web.window.sessionStorage.getItem(key);
}

void write(String key, String value) {
  web.window.sessionStorage.setItem(key, value);
}

void delete(String key) {
  web.window.sessionStorage.removeItem(key);
}
