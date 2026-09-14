import 'dart:convert';
import 'dart:io';

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
  static const String baseUrl = 'http://192.168.3.4/cupon_app/api/public/api';

  String? _token;

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
    final res = await http.post(
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
    final res = await http.post(
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
      await http.post(Uri.parse('$baseUrl/logout'), headers: _headers);
    } finally {
      _token = null;
    }
  }

  // ── Cupones (usuario final) ─────────────────────────────────

  /// GET /coupons. Todos los parámetros son opcionales: sin ellos
  /// trae todos los cupones; con latitude/longitude el backend puede
  /// ordenar/filtrar por cercanía, y con category filtra por
  /// categoría exacta.
  /// NOTA: no tengo tu api_service.dart original — reconstruí este
  /// método a partir de cómo lo llama tu home_screen.dart. Si tu
  /// backend espera otros nombres de query params, ajústalos aquí.
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
    final uri = Uri.parse('$baseUrl/coupons').replace(
      queryParameters: query.isEmpty ? null : query,
    );
    final res = await http.get(uri, headers: _headers);
    return jsonDecode(res.body) as List<dynamic>;
  }

  /// GET /coupons/mine — cupones que el usuario ya capturó.
  /// Mismo aviso: ruta inferida, ajústala si tu backend usa otra.
  Future<List<dynamic>> getMyCoupons() async {
    final res = await http.get(
      Uri.parse('$baseUrl/coupons/mine'),
      headers: _headers,
    );
    return jsonDecode(res.body) as List<dynamic>;
  }

  /// POST /coupons/capture — sube la foto tomada en la pantalla de
  /// captura (modo RA) junto con la ubicación del usuario, para que
  /// el backend valide y registre la captura de ese cupón.
  /// Mismo aviso: ruta y nombres de campos inferidos.
  Future<Map<String, dynamic>> captureCoupon({
    required String tokenId,
    required File photo,
    required double latitude,
    required double longitude,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/coupons/capture'),
    )
      ..headers.addAll(_multipartHeaders)
      ..fields.addAll({
        'token_id': tokenId,
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
      });

    request.files.add(await http.MultipartFile.fromPath('photo', photo.path));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return _handle(res);
  }

  Future<Map<String, dynamic>> redeemCoupon(String code) async {
    final res = await http.post(
      Uri.parse('$baseUrl/coupons/redeem'),
      headers: _headers,
      body: jsonEncode({'code': code}),
    );
    return _handle(res);
  }

  // ── Cupones (administrador) ─────────────────────────────────

  Future<List<dynamic>> getAdminCoupons() async {
    final res = await http.get(
      Uri.parse('$baseUrl/admin/coupons'),
      headers: _headers,
    );
    return jsonDecode(res.body) as List<dynamic>;
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
    // (admin_screen.dart). Es opcional: si el backend no lo espera,
    // simplemente no lo mandes o ignóralo del lado de Laravel.
    String? tokenId,
    // Cuántas veces se puede capturar este cupón en total.
    int? maxCaptures,
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
          });

    if (photo != null) {
      request.files.add(await http.MultipartFile.fromPath('photo', photo.path));
    }

    final streamed = await request.send();
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
          });

    if (photo != null) {
      request.files.add(await http.MultipartFile.fromPath('photo', photo.path));
    }

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return _handle(res);
  }

  Future<Map<String, dynamic>> toggleCouponStatus(String numericId) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/admin/coupons/$numericId/status'),
      headers: _headers,
    );
    return _handle(res);
  }

  Future<void> deleteCoupon(String numericId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/admin/coupons/$numericId'),
      headers: _headers,
    );
    _handle(res);
  }

  // ── Súper administrador ──────────────────────────────────────

  Future<Map<String, dynamic>> getSuperAdminStats() async {
    final res = await http.get(
      Uri.parse('$baseUrl/super-admin/stats'),
      headers: _headers,
    );
    return _handle(res);
  }

  Future<List<dynamic>> getAdmins() async {
    final res = await http.get(
      Uri.parse('$baseUrl/super-admin/admins'),
      headers: _headers,
    );
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> createAdmin({
    required String name,
    required String email,
    required String password,
  }) async {
    final res = await http.post(
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
    final res = await http.put(
      Uri.parse('$baseUrl/super-admin/admins/$id'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _handle(res);
  }

  Future<Map<String, dynamic>> toggleAdminStatus(String id) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/super-admin/admins/$id/status'),
      headers: _headers,
    );
    return _handle(res);
  }

  Future<void> deleteAdmin(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/super-admin/admins/$id'),
      headers: _headers,
    );
    _handle(res);
  }

  Future<List<dynamic>> getUsers() async {
    final res = await http.get(
      Uri.parse('$baseUrl/super-admin/users'),
      headers: _headers,
    );
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> createUser({
    required String name,
    required String email,
    required String password,
  }) async {
    final res = await http.post(
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
    final res = await http.put(
      Uri.parse('$baseUrl/super-admin/users/$id'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _handle(res);
  }

  Future<Map<String, dynamic>> toggleUserStatus(String id) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/super-admin/users/$id/status'),
      headers: _headers,
    );
    return _handle(res);
  }

  Future<void> deleteUser(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/super-admin/users/$id'),
      headers: _headers,
    );
    _handle(res);
  }

  // ── Negocios (súper administrador) ────────────────────────────

  Future<List<dynamic>> getBusinesses() async {
    final res = await http.get(
      Uri.parse('$baseUrl/super-admin/businesses'),
      headers: _headers,
    );
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> createBusiness(String name) async {
    final res = await http.post(
      Uri.parse('$baseUrl/super-admin/businesses'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    return _handle(res);
  }

  Future<Map<String, dynamic>> updateBusiness(String id, String name) async {
    final res = await http.put(
      Uri.parse('$baseUrl/super-admin/businesses/$id'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    return _handle(res);
  }

  Future<Map<String, dynamic>> toggleBusinessStatus(String id) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/super-admin/businesses/$id/status'),
      headers: _headers,
    );
    return _handle(res);
  }

  Future<void> deleteBusiness(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/super-admin/businesses/$id'),
      headers: _headers,
    );
    _handle(res);
  }

  Map<String, dynamic> _handle(http.Response res) {
    final body = res.body.isEmpty ? {} : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body as Map<String, dynamic>;
    }
    throw ApiException(
      (body is Map && body['message'] != null)
          ? body['message'] as String
          : 'Error de servidor',
      res.statusCode,
    );
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