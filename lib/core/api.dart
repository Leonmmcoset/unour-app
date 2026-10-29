import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

class ApiFailure implements Exception {
  final String code, message;
  final int? status;
  const ApiFailure(this.code, this.message, [this.status]);
  bool get uncertain => status == null;
  @override
  String toString() => message;
}

class Api {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://csac.chat/',
  );
  final Dio dio;
  final FlutterSecureStorage storage;
  String? accountId;
  final Map<String, String> _cookies = {};
  Api(this.storage, {Dio? client})
    : dio =
          client ??
          Dio(
            BaseOptions(
              baseUrl: '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1/',
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 18),
              sendTimeout: const Duration(seconds: 18),
              followRedirects: false,
              validateStatus: (_) => true,
            ),
          );

  Future<void> restore() async {
    final value = await storage.read(key: 'account_cookies');
    if (value != null) {
      try {
        final saved = object(jsonDecode(value));
        for (final entry in saved.entries) {
          final c = object(entry.value);
          final expiry = DateTime.tryParse('${c['expires']}');
          if (expiry != null && expiry.isAfter(DateTime.now())) {
            _cookies[entry.key] = '${c['value']}';
          }
        }
      } catch (_) {
        await clearCookies();
      }
    }
  }

  final Map<String, dynamic> _savedCookies = {};
  Future<void> _saveCookies(List<String> headers) async {
    // Preserve expiry information when a response rotates only one cookie.
    if (_savedCookies.isEmpty) {
      final previous = await storage.read(key: 'account_cookies');
      if (previous != null) {
        try {
          _savedCookies.addAll(object(jsonDecode(previous)));
        } catch (_) {}
      }
    }
    for (final header in headers) {
      final cookie = Cookie.fromSetCookieValue(header);
      if (cookie.maxAge == 0 ||
          (cookie.expires?.isBefore(DateTime.now().toUtc()) ?? false)) {
        _cookies.remove(cookie.name);
        _savedCookies.remove(cookie.name);
      } else {
        _cookies[cookie.name] = cookie.value;
        _savedCookies[cookie.name] = {
          'value': cookie.value,
          'expires':
              (cookie.maxAge != null
                      ? DateTime.now().toUtc().add(
                          Duration(seconds: cookie.maxAge!),
                        )
                      : cookie.expires ??
                            DateTime.now().toUtc().add(
                              const Duration(days: 30),
                            ))
                  .toIso8601String(),
        };
      }
    }
    await storage.write(
      key: 'account_cookies',
      value: jsonEncode(_savedCookies),
    );
  }

  Future<void> clearCookies() async {
    _cookies.clear();
    _savedCookies.clear();
    accountId = null;
    await storage.delete(key: 'account_cookies');
  }

  // Passed only to the app's native, in-memory background reader.
  Json liveTableConnection(RoomSession session) => {
    'url': Uri.parse(
      dio.options.baseUrl,
    ).resolve('rooms/${Uri.encodeComponent(session.id)}').toString(),
    'accountId': accountId,
    'token': session.token,
    'cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
  };

  Future<void> acceptBackgroundCookies(List<String> headers) =>
      headers.isEmpty ? Future.value() : _saveCookies(headers);

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    dynamic data,
    String? token,
    String? contentType,
  }) async {
    try {
      final response = await dio.request<dynamic>(
        path,
        data: data,
        options: Options(
          method: method,
          contentType: contentType ?? Headers.jsonContentType,
          headers: {
            if (_cookies.isNotEmpty)
              'Cookie': _cookies.entries
                  .map((e) => '${e.key}=${e.value}')
                  .join('; '),
            if (accountId != null) 'X-Account-ID': accountId,
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );
      final cookies = response.headers['set-cookie'];
      if (cookies != null) await _saveCookies(cookies);
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        final error = object(object(response.data)['error']);
        throw ApiFailure(
          '${error['code'] ?? 'http_$status'}',
          '${error['message'] ?? '服务暂时不可用，请稍后重试'}',
          status,
        );
      }
      if (status == 204) return null;
      if (response.data is! Map) {
        throw const ApiFailure('invalid_response', '服务返回了无法识别的数据');
      }
      return response.data;
    } on DioException catch (_) {
      throw const ApiFailure('network', '网络未连接，或响应超时。请刷新后再操作');
    }
  }

  Future<Json> get(String path, {String? token}) async =>
      object(await request(path, token: token));
  Future<Json> post(String path, [Json data = const {}, String? token]) async =>
      object(await request(path, method: 'POST', data: data, token: token));
  Future<Account> uploadAvatar(Uint8List bytes, String type) async =>
      Account.fromJson(
        object(
          object(
            await request(
              'account/avatar',
              method: 'PUT',
              data: Stream.value(bytes),
              contentType: type,
            ),
          )['user'],
        ),
      );
}
