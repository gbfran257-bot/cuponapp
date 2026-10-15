import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:http/http.dart' as http;

/// Cliente HTTP central para hablar con el backend de Laravel.
///
/// IMPORTANTE — ajusta [baseUrl] según dónde estés probando:
/// - Emulador Android: usa 10.0.2.2 (así el emulador ve el "localhost"
///   de tu PC): http://10.0.2.2/cupon_app/api/public/api
/// - App corriendo en Windows/Web en la misma PC: localhost sí sirve.
/// - Celular físico en la misma red Wi-Fi: usa la IP local de tu PC,
///   ej. http://192.168.1.50/cupon_app/api/public/api
class ApiService {
  ///static const String baseUrl = 'http://192.168.3.4/cupon_app/api/public/api';
  static const String baseUrl = 'https://cupon-app.infinityfreeapp.com/api';

  ///static const String baseUrl = 'https://ccuponapp.rf.gd/api';
  String? _token;

  /// Cliente que resuelve el desafío anti-bot de InfinityFree.
  final http.Client _client = InfinityFreeClient(
    'https://cupon-app.infinityfreeapp.com',
  );

  void setToken(String? token) => _token = token;
  String? get token => _token;

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Map<String, String> get _multipartHeaders => {
    'Accept': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  // ── Autenticación ────────────────────────────────────────────

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/register'),
      headers: _headers,
      body: jsonEncode({'name': name, 'email': email, 'password': password}),
    );
    final data = _handle(res);
    _token = data['token'] as String?;
    return data;
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/login'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = _handle(res);
    _token = data['token'] as String?;
    return data;
  }

  Future<void> logout() async {
    try {
      await _client.post(Uri.parse('$baseUrl/logout'), headers: _headers);
    } finally {
      _token = null;
    }
  }

  // ── Cupones (usuario final) ─────────────────────────────────

  /// GET /coupons. Todos los parámetros son opcionales: sin ellos
  /// trae todos los cupones; con latitude/longitude el backend puede
  /// ordenar/filtrar por cercanía, y con category filtra por
  /// categoría exacta.
  Future<List<dynamic>> getCoupons({
    double? latitude,
    double? longitude,
    String? category,
  }) async {
    final query = <String, String>{
      if (latitude != null) 'latitude': latitude.toString(),
      if (longitude != null) 'longitude': longitude.toString(),
      if (category != null && category.isNotEmpty) 'category': category,
    };
    final uri = Uri.parse('$baseUrl/coupons')
        .replace(queryParameters: query.isEmpty ? null : query);
    final res = await _client.get(uri, headers: _headers);
    return _handleList(res);
  }

  /// GET /coupons/mine — cupones que el usuario ya capturó.
  Future<List<dynamic>> getMyCoupons() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/coupons/mine'),
      headers: _headers,
    );
    return _handleList(res);
  }

  /// POST /coupons/capture — sube la foto tomada en la pantalla de
  /// captura (modo RA) junto con la ubicación del usuario, para que
  /// el backend valide y registre la captura de ese cupón.
  Future<Map<String, dynamic>> captureCoupon({
    required String tokenId,
    required File photo,
    required double latitude,
    required double longitude,
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/coupons/capture'))
          ..headers.addAll(_multipartHeaders)
          ..fields.addAll({
            'token_id': tokenId,
            'latitude': latitude.toString(),
            'longitude': longitude.toString(),
          });

    request.files.add(await http.MultipartFile.fromPath('photo', photo.path));

    final streamed = await _client.send(request);
    final res = await http.Response.fromStream(streamed);
    return _handle(res);
  }

  Future<Map<String, dynamic>> redeemCoupon(String code) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/coupons/redeem'),
      headers: _headers,
      body: jsonEncode({'code': code}),
    );
    return _handle(res);
  }

  // ── Cupones (administrador) ─────────────────────────────────

  Future<List<dynamic>> getAdminCoupons() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/admin/coupons'),
      headers: _headers,
    );
    return _handleList(res);
  }

  /// Negocios activos asignados al administrador (para el dropdown
  /// del formulario de cupones).
  Future<List<dynamic>> getMyBusinesses() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/admin/my-businesses'),
      headers: _headers,
    );
    return _handleList(res);
  }

  Future<Map<String, dynamic>> createCoupon({
    required String name,
    required String business,
    required String discount,
    required String expiresAtIso, // formato yyyy-MM-dd
    required String category,
    required double latitude,
    required double longitude,
    File? photo,
    // Token-id generado como vista previa en el formulario de alta
    // (admin_screen.dart). Es opcional.
    String? tokenId,
    // Cuántas veces se puede capturar este cupón en total.
    int? maxCaptures,
    // 'producto' | 'porcentaje' | 'dinero'
    String? couponType,
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/admin/coupons'))
          ..headers.addAll(_multipartHeaders)
          ..fields.addAll({
            'name': name,
            'business': business,
            'discount': discount,
            'expires_at': expiresAtIso,
            'category': category,
            'latitude': latitude.toString(),
            'longitude': longitude.toString(),
            if (tokenId != null && tokenId.isNotEmpty) 'token_id': tokenId,
            if (maxCaptures != null) 'max_captures': maxCaptures.toString(),
            if (couponType != null) 'coupon_type': couponType,
          });

    if (photo != null) {
      request.files.add(await http.MultipartFile.fromPath('photo', photo.path));
    }

    final streamed = await _client.send(request);
    final res = await http.Response.fromStream(streamed);
    return _handle(res);
  }

  Future<Map<String, dynamic>> updateCoupon({
    required String numericId,
    required String name,
    required String business,
    required String discount,
    required String expiresAtIso,
    required String category,
    required double latitude,
    required double longitude,
    File? photo,
    int? maxCaptures,
    // 'producto' | 'porcentaje' | 'dinero'
    String? couponType,
  }) async {
    final request =
        http.MultipartRequest(
            'POST', // Laravel simula PUT con _method cuando hay multipart
            Uri.parse('$baseUrl/admin/coupons/$numericId'),
          )
          ..headers.addAll(_multipartHeaders)
          ..fields.addAll({
            '_method': 'PUT',
            'name': name,
            'business': business,
            'discount': discount,
            'expires_at': expiresAtIso,
            'category': category,
            'latitude': latitude.toString(),
            'longitude': longitude.toString(),
            if (maxCaptures != null) 'max_captures': maxCaptures.toString(),
            if (couponType != null) 'coupon_type': couponType,
          });

    if (photo != null) {
      request.files.add(await http.MultipartFile.fromPath('photo', photo.path));
    }

    final streamed = await _client.send(request);
    final res = await http.Response.fromStream(streamed);
    return _handle(res);
  }

  Future<Map<String, dynamic>> toggleCouponStatus(String numericId) async {
    final res = await _client.patch(
      Uri.parse('$baseUrl/admin/coupons/$numericId/status'),
      headers: _headers,
    );
    return _handle(res);
  }

  Future<void> deleteCoupon(String numericId) async {
    final res = await _client.delete(
      Uri.parse('$baseUrl/admin/coupons/$numericId'),
      headers: _headers,
    );
    _handle(res);
  }

  // ── Súper administrador ──────────────────────────────────────

  /// Ganancias (comisiones) por canjes: { month: {...}, all: {...} }
  Future<Map<String, dynamic>> getEarnings() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/super-admin/earnings'),
      headers: _headers,
    );
    return _handle(res);
  }

  /// Canjes del mes actual (con comisión y estado de pago).
  Future<List<dynamic>> getMonthRedemptions() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/super-admin/redemptions'),
      headers: _headers,
    );
    return _handleList(res);
  }

  /// Marca un canje como pagado: desde ese momento suma en las ganancias.
  Future<Map<String, dynamic>> markRedemptionPaid(String id) async {
    final res = await _client.patch(
      Uri.parse('$baseUrl/super-admin/redemptions/$id/paid'),
      headers: _headers,
    );
    return _handle(res);
  }

  Future<Map<String, dynamic>> getSuperAdminStats() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/super-admin/stats'),
      headers: _headers,
    );
    return _handle(res);
  }

  Future<List<dynamic>> getAdmins() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/super-admin/admins'),
      headers: _headers,
    );
    return _handleList(res);
  }

  Future<Map<String, dynamic>> createAdmin({
    required String name,
    required String email,
    required String password,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/super-admin/admins'),
      headers: _headers,
      body: jsonEncode({'name': name, 'email': email, 'password': password}),
    );
    return _handle(res);
  }

  Future<Map<String, dynamic>> updateAdmin({
    required String id,
    required String name,
    required String email,
    String? password,
  }) async {
    final body = {'name': name, 'email': email};
    if (password != null && password.isNotEmpty) body['password'] = password;
    final res = await _client.put(
      Uri.parse('$baseUrl/super-admin/admins/$id'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _handle(res);
  }

  Future<Map<String, dynamic>> toggleAdminStatus(String id) async {
    final res = await _client.patch(
      Uri.parse('$baseUrl/super-admin/admins/$id/status'),
      headers: _headers,
    );
    return _handle(res);
  }

  Future<void> deleteAdmin(String id) async {
    final res = await _client.delete(
      Uri.parse('$baseUrl/super-admin/admins/$id'),
      headers: _headers,
    );
    _handle(res);
  }

  Future<List<dynamic>> getUsers() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/super-admin/users'),
      headers: _headers,
    );
    return _handleList(res);
  }

  Future<Map<String, dynamic>> createUser({
    required String name,
    required String email,
    required String password,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/super-admin/users'),
      headers: _headers,
      body: jsonEncode({'name': name, 'email': email, 'password': password}),
    );
    return _handle(res);
  }

  Future<Map<String, dynamic>> updateUser({
    required String id,
    required String name,
    required String email,
    String? password,
  }) async {
    final body = {'name': name, 'email': email};
    if (password != null && password.isNotEmpty) body['password'] = password;
    final res = await _client.put(
      Uri.parse('$baseUrl/super-admin/users/$id'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _handle(res);
  }

  Future<Map<String, dynamic>> toggleUserStatus(String id) async {
    final res = await _client.patch(
      Uri.parse('$baseUrl/super-admin/users/$id/status'),
      headers: _headers,
    );
    return _handle(res);
  }

  Future<void> deleteUser(String id) async {
    final res = await _client.delete(
      Uri.parse('$baseUrl/super-admin/users/$id'),
      headers: _headers,
    );
    _handle(res);
  }

  // ── Negocios (súper administrador) ────────────────────────────

  Future<List<dynamic>> getBusinesses() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/super-admin/businesses'),
      headers: _headers,
    );
    return _handleList(res);
  }

  /// [data] lleva: name, admin_id, address, phone, commission_product,
  /// commission_percent, commission_money, contact_name, contact_email,
  /// rfc, description.
  Future<Map<String, dynamic>> createBusiness(Map<String, dynamic> data) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/super-admin/businesses'),
      headers: _headers,
      body: jsonEncode(data),
    );
    return _handle(res);
  }

  Future<Map<String, dynamic>> updateBusiness(
    String id,
    Map<String, dynamic> data,
  ) async {
    final res = await _client.put(
      Uri.parse('$baseUrl/super-admin/businesses/$id'),
      headers: _headers,
      body: jsonEncode(data),
    );
    return _handle(res);
  }

  Future<Map<String, dynamic>> toggleBusinessStatus(String id) async {
    final res = await _client.patch(
      Uri.parse('$baseUrl/super-admin/businesses/$id/status'),
      headers: _headers,
    );
    return _handle(res);
  }

  Future<void> deleteBusiness(String id) async {
    final res = await _client.delete(
      Uri.parse('$baseUrl/super-admin/businesses/$id'),
      headers: _headers,
    );
    _handle(res);
  }

  // ── Contratos / convenios ─────────────────────────────────────

  /// Contratos visibles para el usuario autenticado.
  /// Súper administrador: todos. Administrador: solo los de sus negocios.
  Future<List<dynamic>> getContracts() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/contracts'),
      headers: _headers,
    );
    return _handleList(res);
  }

  Future<Map<String, dynamic>> getContract(String id) async {
    final res = await _client.get(
      Uri.parse('$baseUrl/contracts/$id'),
      headers: _headers,
    );
    return _handle(res);
  }

  /// Aceptación/firma electrónica dentro de la aplicación.
  /// [signatureBase64] es la firma manual dibujada, en PNG codificado
  /// en base64 (sin el prefijo "data:image/png;base64,").
  Future<Map<String, dynamic>> acceptContract(
    String id,
    String signatureBase64,
  ) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/contracts/$id/accept'),
      headers: _headers,
      body: jsonEncode({'signature': signatureBase64}),
    );
    return _handle(res);
  }

  /// URL del PDF generado por Laravel.
  String contractPdfUrl(String id) => '$baseUrl/contracts/$id/pdf';

  /// Decodifica el body. Si no es JSON (por ejemplo una página HTML de
  /// error de Laravel/Apache), lanza un error legible con el código HTTP.
  dynamic _decode(http.Response res) {
    if (res.body.isEmpty) return null;
    try {
      return jsonDecode(res.body);
    } catch (_) {
      print('BODY RECIBIDO: ${res.body}');
      throw ApiException(
        'Respuesta inválida del servidor (HTTP ${res.statusCode}). '
        'Revisa storage/logs/laravel.log',
        res.statusCode,
      );
    }
  }

  /// Extrae el mejor mensaje de error posible de la respuesta de Laravel.
  ApiException _errorFrom(dynamic body, int status) {
    String message = 'Error de servidor (HTTP $status)';
    if (body is Map) {
      final errors = body['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) {
          message = first.first.toString();
        }
      } else if (body['message'] != null) {
        message = body['message'].toString();
      }
    }
    return ApiException(message, status);
  }

  Map<String, dynamic> _handle(http.Response res) {
    final body = _decode(res) ?? {};
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body as Map<String, dynamic>;
    }
    throw _errorFrom(body, res.statusCode);
  }

  /// Igual que [_handle] pero para endpoints que devuelven una lista.
  /// Antes, si el servidor respondía un error (un Map), el cast a List
  /// fallaba y se veía "No se pudo conectar". Ahora se muestra el error real.
  List<dynamic> _handleList(http.Response res) {
    final body = _decode(res) ?? [];
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body as List<dynamic>;
    }
    throw _errorFrom(body, res.statusCode);
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}

/// Instancia única compartida en toda la app.
final apiService = ApiService();

/// Cliente HTTP que resuelve el desafío anti-bot de InfinityFree
/// y envía la cookie __test en cada petición.
class InfinityFreeClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final String siteUrl;
  String? _cookie;
  DateTime? _cookieTime;

  InfinityFreeClient(this.siteUrl);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await _ensureCookie();
    if (_cookie != null && _cookie!.isNotEmpty) {
      request.headers['Cookie'] = '__test=$_cookie';
    }
    return _inner.send(request);
  }

  Future<void> _ensureCookie() async {
    final fresh =
        _cookieTime != null &&
        DateTime.now().difference(_cookieTime!) < const Duration(hours: 5);
    if (fresh) return;

    final res = await _inner.get(Uri.parse('$siteUrl/'));
    _cookieTime = DateTime.now();

    final nums = RegExp(r'toNumbers\("([0-9a-f]+)"\)')
        .allMatches(res.body)
        .map((m) => m.group(1)!)
        .toList();
    if (nums.length < 3) {
      _cookie = null; // no hubo desafío
      return;
    }

    // a = llave, b = IV, c = texto cifrado
    final key = enc.Key(_fromHex(nums[0]));
    final iv = enc.IV(_fromHex(nums[1]));
    final encrypter = enc.Encrypter(
      enc.AES(key, mode: enc.AESMode.cbc, padding: null),
    );
    final plain = encrypter.decryptBytes(
      enc.Encrypted(_fromHex(nums[2])),
      iv: iv,
    );
    _cookie = _toHex(plain);
  }

  Uint8List _fromHex(String h) => Uint8List.fromList([
    for (var i = 0; i < h.length; i += 2)
      int.parse(h.substring(i, i + 2), radix: 16),
  ]);

  String _toHex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}
