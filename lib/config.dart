class AppConfig {
  static const baseUrl = String.fromEnvironment(
    'ERP_URL',
    defaultValue: 'https://fix.delifru.co.id',
  );

  static bool get isStaging => baseUrl.contains('fix');
}