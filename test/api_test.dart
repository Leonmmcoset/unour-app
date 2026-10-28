import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unour/core/api.dart';

class RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  ResponseBody response = ResponseBody.fromString(
    '{}',
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return response;
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'account cookie survives restart while room Bearer remains separate',
    () async {
      final transport = RecordingAdapter();
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://example.test/api/v1/',
          validateStatus: (_) => true,
        ),
      )..httpClientAdapter = transport;
      final api = Api(const FlutterSecureStorage(), client: dio);
      transport.response = ResponseBody.fromString(
        '{"user":{"id":"a","username":"Alice"}}',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          'set-cookie': [
            'account_session=account-secret; Max-Age=2592000; Path=/; Secure; HttpOnly; SameSite=Lax',
          ],
        },
      );
      await api.post('auth/login', {
        'username': 'Alice',
        'password': '12345678',
      });
      final restored = Api(const FlutterSecureStorage(), client: dio);
      await restored.restore();
      restored.accountId = 'a';
      transport.response = ResponseBody.fromString(
        '{}',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
      await restored.get('rooms/table', token: 'room-secret');
      final headers = transport.requests.last.headers;
      expect(headers['Cookie'], 'account_session=account-secret');
      expect(headers['Authorization'], 'Bearer room-secret');
      expect(headers['X-Account-ID'], 'a');
    },
  );
  test('revoked cookie is removed and never restored', () async {
    final adapter = RecordingAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/',
        validateStatus: (_) => true,
      ),
    )..httpClientAdapter = adapter;
    final api = Api(const FlutterSecureStorage(), client: dio);
    adapter.response = ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        'set-cookie': ['session=secret; Max-Age=2592000; Path=/'],
      },
    );
    await api.post('login');
    adapter.response = ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        'set-cookie': ['session=; Max-Age=0; Path=/'],
      },
    );
    await api.post('logout');
    final restored = Api(const FlutterSecureStorage(), client: dio);
    await restored.restore();
    adapter.response = ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
    await restored.get('account');
    expect(adapter.requests.last.headers.containsKey('Cookie'), false);
  });
  test(
    'structured conflict is exposed and a command is sent exactly once',
    () async {
      final adapter = RecordingAdapter()
        ..response = ResponseBody.fromString(
          '{"error":{"code":"version_conflict","message":"stale"}}',
          409,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://example.test/',
          validateStatus: (_) => true,
        ),
      )..httpClientAdapter = adapter;
      final api = Api(const FlutterSecureStorage(), client: dio);
      await expectLater(
        api.post('rooms/table/play', {'expected_version': 2}),
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'version_conflict'),
        ),
      );
      expect(adapter.requests, hasLength(1));
    },
  );
  test('room deletion accepts an empty 204 response', () async {
    final adapter = RecordingAdapter()
      ..response = ResponseBody.fromString('', 204);
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/',
        validateStatus: (_) => true,
      ),
    )..httpClientAdapter = adapter;
    expect(
      await Api(
        const FlutterSecureStorage(),
        client: dio,
      ).request('rooms/table', method: 'DELETE'),
      null,
    );
  });
}
