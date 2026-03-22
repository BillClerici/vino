/// Stub for non-web platforms. These should never be called
/// because SecureStorageService uses FlutterSecureStorage on native.

String? read(String key) => null;
void write(String key, String value) {}
void delete(String key) {}
