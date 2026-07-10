import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_exception.dart';

/// Every screen in the app should go through this client rather than calling
/// `package:http` directly — it's what turns raw network failures into the
/// friendly [ApiException] messages the UI shows in toasts/banners.
///
/// Add to pubspec.yaml:
///   http: ^1.2.0
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const Duration _timeout = Duration(seconds: 20);
  static const Map<String, String> _headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final cleanQuery = <String, String>{};
    query?.forEach((k, v) {
      if (v == null) return;
      cleanQuery[k] = v.toString();
    });
    return Uri.parse('${ApiConfig.baseUrl}${ApiConfig.apiVersion}$path')
        .replace(queryParameters: cleanQuery.isEmpty ? null : cleanQuery);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) {
    final uri = _uri(path, query);
    return _send(() => http.get(uri, headers: _headers), method: 'GET', uri: uri);
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) {
    final uri = _uri(path);
    return _send(
      () => http.post(uri, headers: _headers, body: jsonEncode(body ?? const {})),
      method: 'POST',
      uri: uri,
      body: body,
    );
  }

  Future<dynamic> _send(Future<http.Response> Function() request, {required String method, required Uri uri, Object? body}) async {
    debugPrint('*** Request ***');
    debugPrint('uri: $uri');
    debugPrint('method: $method');
    if (body != null) debugPrint('data: $body');

    http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on TimeoutException {
      debugPrint('*** Error *** timeout: $uri');
      throw ApiException.timeout();
    } on SocketException {
      debugPrint('*** Error *** socket/network: $uri');
      throw ApiException.network();
    } on HttpException {
      debugPrint('*** Error *** http: $uri');
      throw ApiException.network();
    } on FormatException {
      debugPrint('*** Error *** malformed response: $uri');
      throw ApiException.parse();
    } catch (e) {
      // Covers HandshakeException and any other low-level transport error.
      debugPrint('*** Error *** transport: $uri — $e');
      throw ApiException.network();
    }

    debugPrint('*** Response ***');
    debugPrint('uri: $uri');
    debugPrint('statusCode: ${response.statusCode}');
    debugPrint('Response Text: ${response.body}');

    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      throw ApiException.parse();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final serverMsg = (decoded is Map) ? decoded['msg'] ?? decoded['message'] : null;
      throw ApiException.server(response.statusCode, serverMessage: serverMsg?.toString());
    }

    // Some endpoints (e.g. place order, addresses) return { ok:false, msg }
    // with a 200 status — treat that as a business-logic failure too.
    if (decoded is Map && decoded['ok'] == false) {
      final serverMsg = decoded['msg'];
      throw ApiException.business(
        (serverMsg ?? 'Request failed.').toString(),
        isGenericFailure: serverMsg == null || serverMsg.toString().trim().isEmpty,
      );
    }

    return decoded;
  }
}
