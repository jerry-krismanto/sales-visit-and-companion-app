import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';

class ErpApi {
  ErpApi._();
  static final ErpApi instance = ErpApi._();

  late final Dio _dio;
  late final PersistCookieJar _cookieJar;

  /// Call once at app startup.
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _cookieJar = PersistCookieJar(
      storage: FileStorage('${dir.path}/.cookies/'),
    );
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ))
      ..interceptors.add(CookieManager(_cookieJar));
  }

  /// Logs in and returns the user's full name.
  Future<String> login(String usr, String pwd) async {
    try {
      final res = await _dio.post(
        '/api/method/login',
        data: {'usr': usr, 'pwd': pwd},
      );
      return res.data['full_name'] ?? usr;
    } on DioException catch (e) {
      throw Exception(_errorMessage(e));
    }
  }

  /// Returns the logged-in user ID, or null if not logged in / session expired.
  Future<String?> getLoggedUser() async {
    try {
      final res = await _dio.get('/api/method/frappe.auth.get_logged_user');
      final user = res.data['message'];
      return (user == null || user == 'Guest') ? null : user;
    } on DioException {
      return null;
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post('/api/method/logout');
    } catch (_) {
      // ignore server errors; clear local session regardless
    } finally {
      await _cookieJar.deleteAll();
    }
  }

  String _errorMessage(DioException e) {
    if (e.response?.statusCode == 401) {
      return 'Username atau password salah.';
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'Tidak dapat terhubung ke server.';
    }
    return 'Terjadi kesalahan (${e.response?.statusCode ?? e.type.name}).';
  }
}