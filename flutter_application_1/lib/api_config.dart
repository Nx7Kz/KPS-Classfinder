class ApiConfig {
  const ApiConfig._();

  // Override this for a device/emulator with --dart-define=API_BASE_URL=...
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  static Uri endpoint(String path) => Uri.parse(baseUrl).resolve(path);
}
