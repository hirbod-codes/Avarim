class AppConfig {
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://localhost:3000');

  static const env = String.fromEnvironment('ENV', defaultValue: 'dev');
}
