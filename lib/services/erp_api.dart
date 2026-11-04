import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/daily_report.dart';
import '../models/form_options.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SessionExpiredException extends ApiException {
  SessionExpiredException()
      : super('Sesi Anda telah berakhir. Silakan login kembali.');
}

class ErpApi {
  ErpApi._();
  static final ErpApi instance = ErpApi._();

  static const _m = '/api/method/addons.custom_functions.mobile_api';

  late final Dio _dio;
  late final PersistCookieJar _cookieJar;

  FormOptions? _formOptions;

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

  // ---------- auth ----------

  Future<String> login(String usr, String pwd) async {
    try {
      final res = await _dio.post(
        '/api/method/login',
        data: {'usr': usr, 'pwd': pwd},
      );
      return res.data['full_name'] ?? usr;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw ApiException('Username atau password salah.');
      }
      throw ApiException(_errorMessage(e));
    }
  }

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
      // ignore; clear local session regardless
    } finally {
      _formOptions = null;
      await _cookieJar.deleteAll();
    }
  }

  // ---------- daily report ----------

  Future<TodayReport> getTodayReport() async {
    final data = await _call('GET', '$_m.get_today_report');
    return TodayReport.fromJson(Map<String, dynamic>.from(data));
  }

  Future<TodayReport> addVisit(
      Map<String, dynamic> visit, String photoPath) async {
    final isPng = photoPath.toLowerCase().endsWith('.png');
    final form = FormData.fromMap({
      'visit': jsonEncode(visit),
      'photo': await MultipartFile.fromFile(
        photoPath,
        filename: isPng ? 'kunjungan.png' : 'kunjungan.jpg',
        contentType: DioMediaType('image', isPng ? 'png' : 'jpeg'),
      ),
    });
    final data = await _call('POST', '$_m.add_visit', data: form);
    return TodayReport.fromJson(Map<String, dynamic>.from(data));
  }

    Future<TodayReport> updateVisit(
      String name, Map<String, dynamic> fields) async {
    final data = await _call('POST', '$_m.update_visit', data: {
      'visit': {...fields, 'name': name},
    });
    return TodayReport.fromJson(Map<String, dynamic>.from(data));
  }

  Future<TodayReport> deleteVisit(String name) async {
    final data =
        await _call('POST', '$_m.delete_visit', data: {'visit_name': name});
    return TodayReport.fromJson(Map<String, dynamic>.from(data));
  }

  /// Downloads a (private) file with the session cookie.
  Future<Uint8List> getFileBytes(String fileUrl) async {
    final res = await _dio.get<List<int>>(
      fileUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data!);
  }

  // ---------- form data ----------

  /// Cached for the app session; pass refresh: true to reload.
  Future<FormOptions> getFormOptions({bool refresh = false}) async {
    if (_formOptions != null && !refresh) return _formOptions!;
    final data = await _call('GET', '$_m.get_form_options');
    return _formOptions = FormOptions.fromJson(Map<String, dynamic>.from(data));
  }

  Future<List<PickItem>> searchCustomers(String txt) =>
      _search('search_customers', txt);

  Future<List<PickItem>> searchLeads(String txt) => _search('search_leads', txt);

  Future<List<PickItem>> _search(String method, String txt) async {
    final data = await _call('GET', '$_m.$method', query: {'txt': txt});
    return (data as List)
        .map((e) => PickItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> getCustomerDetails(String customer) async =>
      Map<String, dynamic>.from(await _call(
        'GET',
        '$_m.get_customer_details',
        query: {'customer': customer},
      ));

  Future<Map<String, dynamic>> getLeadDetails(String lead) async =>
      Map<String, dynamic>.from(await _call(
        'GET',
        '$_m.get_lead_details',
        query: {'lead': lead},
      ));

  Future<PickItem> createLead(Map<String, dynamic> lead) async {
    final data = await _call('POST', '$_m.create_lead', data: {'lead': lead});
    final m = Map<String, dynamic>.from(data);
    return PickItem(value: m['value'], label: m['label'] ?? m['value']);
  }

  // ---------- internals ----------

  Future<dynamic> _call(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? data,
  }) async {
    try {
      final res = await _dio.request(
        path,
        queryParameters: query,
        data: data,
        options: Options(method: method),
      );
      return res.data is Map ? res.data['message'] : res.data;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      // 401/403 can mean "session gone" or "not allowed"; ask the server which
      if ((code == 401 || code == 403) && await getLoggedUser() == null) {
        await _cookieJar.deleteAll();
        throw SessionExpiredException();
      }
      throw ApiException(_errorMessage(e));
    }
  }

  String _errorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = _serverMessage(data);
      if (msg != null) return msg;
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'Tidak dapat terhubung ke server. Periksa koneksi internet Anda.';
    }
    return 'Terjadi kesalahan (${e.response?.statusCode ?? e.type.name}).';
  }

  /// Frappe puts user-facing errors in `_server_messages` (a JSON list of JSON strings).
  String? _serverMessage(Map data) {
    final raw = data['_server_messages'];
    if (raw is String) {
      try {
        final msgs = (jsonDecode(raw) as List)
            .map((m) {
              final d = m is String ? jsonDecode(m) : m;
              return d is Map ? d['message']?.toString() : d?.toString();
            })
            .whereType<String>()
            .map(_stripHtml)
            .where((s) => s.isNotEmpty)
            .toList();
        if (msgs.isNotEmpty) return msgs.join('\n');
      } catch (_) {}
    }
    final exc = data['exception'];
    if (exc is String && exc.contains(':')) {
      return _stripHtml(exc.substring(exc.indexOf(':') + 1));
    }
    return null;
  }

  String _stripHtml(String s) => s.replaceAll(RegExp(r'<[^>]*>'), '').trim();
}