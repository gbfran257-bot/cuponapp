import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/coupon.dart' show kCouponCategories;
import 'contract_screen.dart';

/// ─────────────────────────────────────────────────────────────
/// Tipos de cupón (los mismos que usa el súper administrador para
/// calcular las comisiones).
/// ─────────────────────────────────────────────────────────────
const Map<String, String> kCouponTypeLabels = {
  'producto': 'Cupón por producto',
  'porcentaje': 'Descuento en porcentaje (%)',
  'dinero': 'Descuento en dinero (\$)',
};

/// Promociones predefinidas para cupones "por producto".
const List<String> kProductPromos = [
  '2x1',
  '3x2',
  '2do producto al 50%',
  'Producto gratis',
  'Bebida gratis',
  'Postre gratis',
  'Envío gratis',
];

/// Opción para escribir una promoción distinta a las predefinidas.
const String kOtherPromo = 'Otro (escribir)';

/// Deja solo el número del descuento ("20%" -> "20", "\$50" -> "50").
/// Para cupones por producto el texto se conserva tal cual.
String _plainDiscount(String type, String discount) {
  if (type == 'producto') return discount;
  return discount.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
}

/// Texto final que se guarda/mostrará: "20%", "\$50" o el producto.
String _formatDiscount(String type, String raw) {
  final t = raw.trim();
  switch (type) {
    case 'porcentaje':
      return '${_plainDiscount(type, t)}%';
    case 'dinero':
      return '\$${_plainDiscount(type, t)}';
    default:
      return t;
  }
}

/// ─────────────────────────────────────────────────────────────
/// Modelo local de cupón para el panel de administrador, ahora
/// poblado con datos reales del backend (CouponController.php).
/// ─────────────────────────────────────────────────────────────
class AdminCoupon {
  final String id; // "C-001" (formateado, solo para mostrar)
  final String numericId; // id real en la base de datos, usado en la API
  final String tokenId;
  String name;
  String business;
  String discount;
  // 'producto' | 'porcentaje' | 'dinero'
  String couponType;
  String expiresAt; // dd/mm/aaaa, para mostrar en la lista/formulario
  String category;
  // Cuántas veces se puede capturar este cupón en total.
  int maxCaptures;
  // Cuántas veces ya se capturó (usuarios finales) y cuántas quedan.
  int capturesCount;
  int remainingCaptures;
  // Cuántas veces se ha canjeado (cobrado) este cupón.
  int redeemedCount;
  // Si ya pasó su fecha de vencimiento (lo calcula el servidor).
  bool isExpired;
  // Ruta local de una foto recién elegida (aún no subida).
  String? photoPath;
  // URL ya subida en el servidor (si el cupón ya tenía foto).
  String? photoUrl;
  double? latitude;
  double? longitude;
  bool active;

  AdminCoupon({
    required this.id,
    required this.numericId,
    required this.tokenId,
    required this.name,
    required this.business,
    required this.discount,
    this.couponType = 'porcentaje',
    required this.expiresAt,
    required this.category,
    this.maxCaptures = 1,
    this.capturesCount = 0,
    this.remainingCaptures = 1,
    this.redeemedCount = 0,
    this.isExpired = false,
    this.photoPath,
    this.photoUrl,
    this.latitude,
    this.longitude,
    this.active = true,
  });

  /// Estado visible para el resumen y los filtros del panel.
  /// Prioridad: dado de baja > vencido > agotado > activo.
  CouponStatus get status {
    if (!active) return CouponStatus.inactive;
    if (isExpired) return CouponStatus.expired;
    if (remainingCaptures <= 0) return CouponStatus.soldOut;
    return CouponStatus.active;
  }

  factory AdminCoupon.fromJson(Map<String, dynamic> json) => AdminCoupon(
        id: json['id'] as String,
        numericId: json['numericId'] as String,
        tokenId: json['tokenId'] as String,
        name: json['name'] as String,
        business: json['business'] as String,
        discount: json['discount'] as String,
        couponType: json['couponType'] as String? ?? 'porcentaje',
        expiresAt: json['expiresAt'] as String? ?? '',
        category: json['category'] as String? ?? 'Otro',
        maxCaptures: (json['maxCaptures'] as num?)?.toInt() ?? 1,
        capturesCount: (json['capturesCount'] as num?)?.toInt() ?? 0,
        remainingCaptures: (json['remainingCaptures'] as num?)?.toInt() ?? 1,
        redeemedCount: (json['redeemedCount'] as num?)?.toInt() ?? 0,
        isExpired: json['isExpired'] as bool? ?? false,
        photoUrl: json['photoUrl'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        active: json['active'] as bool? ?? true,
      );
}

/// Estado de un cupón, usado para el resumen y los filtros.
enum CouponStatus { active, inactive, expired, soldOut }

const Map<CouponStatus, String> kCouponStatusLabels = {
  CouponStatus.active: 'Activos',
  CouponStatus.inactive: 'Dados de baja',
  CouponStatus.expired: 'Vencidos',
  CouponStatus.soldOut: 'Agotados',
};

/// Convierte "dd/mm/aaaa" -> "aaaa-mm-dd" (lo que espera el backend).
/// Devuelve null si el formato no es válido.
String? _ddmmyyyyToIso(String value) {
  final parts = value.trim().split('/');
  if (parts.length != 3) return null;
  final d = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final y = int.tryParse(parts[2]);
  if (d == null || m == null || y == null) return null;
  if (d < 1 || d > 31 || m < 1 || m > 12 || y < 2000) return null;
  return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
}

/// Genera un token-id de vista previa con el formato "TKN-XXXXXX"
/// para mostrarlo en el formulario de alta antes de guardar.
String _generateTokenId() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final rnd = Random();
  final code = List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  return 'TKN-$code';
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  String? _loadError;
  List<AdminCoupon> _coupons = [];
  // Nombres de los negocios asignados a este administrador.
  List<String> _myBusinesses = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCoupons();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCoupons() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final data = await apiService.getAdminCoupons();
      final businessesData = await apiService.getMyBusinesses();
      setState(() {
        _coupons = data
            .map((c) => AdminCoupon.fromJson(c as Map<String, dynamic>))
            .toList();
        _myBusinesses = businessesData
            .map((b) => (b as Map<String, dynamic>)['name'] as String)
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('Error en _loadCoupons: $e\n$st');
      setState(() {
        _loadError = 'Error al cargar los datos: $e';
        _loading = false;
      });
    }
  }

  void _logout() {
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de administrador'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Colors.black,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Canjear'),
            Tab(
              icon: Icon(Icons.confirmation_number_outlined),
              text: 'Cupones',
            ),
            Tab(
              icon: Icon(Icons.description_outlined),
              text: 'Contratos',
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadCoupons,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _RedeemTab(onRedeem: _redeemByCode),
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_loadError!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadCoupons,
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _CouponsTab(
                      coupons: _coupons,
                      onCreate: _createCoupon,
                      onEdit: _editCoupon,
                      onToggleActive: _toggleActive,
                      onDelete: _deleteCoupon,
                    ),
          const ContractsScreen(),
        ],
      ),
    );
  }

  // ── Canjeo ──────────────────────────────────────────────────

  Future<void> _redeemByCode(String code) async {
    if (code.trim().isEmpty) return;
    try {
      final data = await apiService.redeemCoupon(code.trim());
      if (!mounted) return;
      final couponName = (data['coupon'] as Map?)?['name'] as String? ?? code;
      _showMsg('Cupón "$couponName" canjeado ✅');
      // Recarga la lista para que el contador "Canjeados" y el filtro
      // reflejen el canje de inmediato.
      await _loadCoupons();
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  // ── CRUD ────────────────────────────────────────────────────

  Future<void> _createCoupon() async {
    if (_myBusinesses.isEmpty) {
      _showMsg(
        'No tienes negocios asignados. Pide al súper administrador que te asigne uno.',
        error: true,
      );
      return;
    }

    final result = await _showCouponForm(context);
    if (result == null) return;

    final iso = _ddmmyyyyToIso(result.expiresAt);
    if (iso == null) {
      _showMsg('Fecha inválida, usa el formato dd/mm/aaaa', error: true);
      return;
    }

    try {
      await apiService.createCoupon(
        name: result.name,
        business: result.business,
        discount: result.discount,
        expiresAtIso: iso,
        category: result.category,
        latitude: result.latitude,
        longitude: result.longitude,
        photo: result.photoPath != null ? File(result.photoPath!) : null,
        tokenId: result.tokenId,
        maxCaptures: result.maxCaptures,
        couponType: result.couponType,
      );
      await _loadCoupons();
      _showMsg('Cupón dado de alta ✅');
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  Future<void> _editCoupon(AdminCoupon coupon) async {
    final result = await _showCouponForm(context, initial: coupon);
    if (result == null) return;

    final iso = _ddmmyyyyToIso(result.expiresAt);
    if (iso == null) {
      _showMsg('Fecha inválida, usa el formato dd/mm/aaaa', error: true);
      return;
    }

    try {
      await apiService.updateCoupon(
        numericId: coupon.numericId,
        name: result.name,
        business: result.business,
        discount: result.discount,
        expiresAtIso: iso,
        category: result.category,
        latitude: result.latitude,
        longitude: result.longitude,
        // Solo se manda si el usuario eligió una foto nueva; si no,
        // el backend conserva la que ya tenía.
        photo: result.photoPath != null ? File(result.photoPath!) : null,
        maxCaptures: result.maxCaptures,
        couponType: result.couponType,
      );
      await _loadCoupons();
      _showMsg('Cupón actualizado ✅');
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  Future<void> _toggleActive(AdminCoupon coupon) async {
    try {
      await apiService.toggleCouponStatus(coupon.numericId);
      await _loadCoupons();
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  Future<void> _deleteCoupon(AdminCoupon coupon) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cupón'),
        content: Text(
          '¿Eliminar "${coupon.name}"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: AppColors.stampCoral),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await apiService.deleteCoupon(coupon.numericId);
      await _loadCoupons();
      _showMsg('Cupón eliminado');
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  Future<_CouponFormResult?> _showCouponForm(
    BuildContext context, {
    AdminCoupon? initial,
  }) {
    return showDialog<_CouponFormResult>(
      context: context,
      builder: (context) => _CouponFormDialog(
        initial: initial,
        businesses: _myBusinesses,
      ),
    );
  }

  void _showMsg(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.stampCoral : null,
      ),
    );
  }
}

/// ───────────────────────── TAB: CANJEAR ─────────────────────────

class _RedeemTab extends StatefulWidget {
  final Future<void> Function(String code) onRedeem;
  const _RedeemTab({required this.onRedeem});

  @override
  State<_RedeemTab> createState() => _RedeemTabState();
}

class _RedeemTabState extends State<_RedeemTab> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScannerScreen()),
    );
    if (code == null || !mounted) return;
    _codeCtrl.text = code;
    await _submit();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    await widget.onRedeem(_codeCtrl.text);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Canjear cupón',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Escanea el código QR o de barras del cupón, o ingresa el token-id manualmente.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loading ? null : _scanQr,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('ESCANEAR CÓDIGO (QR o barras)'),
          ),
          const SizedBox(height: 20),
          Row(
            children: const [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('o'),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _codeCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Token-id / ID del cupón',
              prefixIcon: Icon(Icons.confirmation_number_outlined),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Text('CANJEAR CON TOKEN'),
          ),
        ],
      ),
    );
  }
}

class _QrScannerScreen extends StatefulWidget {
  const _QrScannerScreen();

  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  // Evita que varias detecciones seguidas hagan varios Navigator.pop
  // (los pops extra cerraban también la pantalla de atrás y dejaban la
  // app en negro).
  bool _handled = false;

  // Sin `formats` mobile_scanner ya detecta QR y la mayoría de códigos
  // de barras por defecto, pero los listamos explícitamente para
  // asegurar que estos formatos comunes (QR, barras 1D típicas de
  // productos/cupones) siempre estén activos.
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.qrCode,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.codabar,
      BarcodeFormat.ean8,
      BarcodeFormat.ean13,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.itf,
      BarcodeFormat.pdf417,
      BarcodeFormat.aztec,
      BarcodeFormat.dataMatrix,
    ],
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;

    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.trim().isEmpty) return;

    _handled = true;

    // Detiene la cámara antes de cerrar para que no lleguen más eventos.
    try {
      await _controller.stop();
    } catch (_) {}

    if (!mounted) return;
    Navigator.pop(context, value.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear código')),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
      ),
    );
  }
}

/// ───────────────────────── TAB: CUPONES (CRUD) ─────────────────────────

/// Filtro de la lista. "all" no filtra nada.
enum _CouponFilter { all, active, inactive, expired, soldOut, redeemed }

const Map<_CouponFilter, String> _filterLabels = {
  _CouponFilter.all: 'Todos',
  _CouponFilter.active: 'Activos',
  _CouponFilter.inactive: 'Dados de baja',
  _CouponFilter.expired: 'Vencidos',
  _CouponFilter.soldOut: 'Agotados',
  _CouponFilter.redeemed: 'Canjeados',
};

bool _matchesFilter(AdminCoupon c, _CouponFilter f) {
  switch (f) {
    case _CouponFilter.all:
      return true;
    case _CouponFilter.active:
      return c.status == CouponStatus.active;
    case _CouponFilter.inactive:
      return c.status == CouponStatus.inactive;
    case _CouponFilter.expired:
      return c.status == CouponStatus.expired;
    case _CouponFilter.soldOut:
      return c.status == CouponStatus.soldOut;
    case _CouponFilter.redeemed:
      // Un cupón puede estar activo Y canjeado a la vez, por eso este
      // filtro va por el contador y no por `status`.
      return c.redeemedCount > 0;
  }
}

class _CouponsTab extends StatefulWidget {
  final List<AdminCoupon> coupons;
  final VoidCallback onCreate;
  final void Function(AdminCoupon) onEdit;
  final void Function(AdminCoupon) onToggleActive;
  final void Function(AdminCoupon) onDelete;

  const _CouponsTab({
    required this.coupons,
    required this.onCreate,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  @override
  State<_CouponsTab> createState() => _CouponsTabState();
}

class _CouponsTabState extends State<_CouponsTab> {
  _CouponFilter _filter = _CouponFilter.all;

  @override
  Widget build(BuildContext context) {
    final all = widget.coupons;
    final active = all.where((c) => c.status == CouponStatus.active).length;
    final inactive =
        all.where((c) => c.status == CouponStatus.inactive).length;
    final expired = all.where((c) => c.status == CouponStatus.expired).length;
    final soldOut = all.where((c) => c.status == CouponStatus.soldOut).length;
    final redeemed =
        all.fold<int>(0, (sum, c) => sum + c.redeemedCount);
    final availableSlots = all
        .where((c) => c.status == CouponStatus.active)
        .fold<int>(0, (sum, c) => sum + c.remainingCaptures);

    final visible =
        all.where((c) => _matchesFilter(c, _filter)).toList(growable: false);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onCreate,
        icon: const Icon(Icons.add),
        label: const Text('Dar de alta'),
      ),
      body: Column(
        children: [
          _CouponStatsRow(
            total: all.length,
            active: active,
            inactive: inactive,
            expired: expired,
            soldOut: soldOut,
            redeemed: redeemed,
            availableSlots: availableSlots,
            selected: _filter,
            onSelect: (f) => setState(() => _filter = f),
          ),
          const Divider(height: 1),
          Expanded(
            child: all.isEmpty
                ? const Center(child: Text('Aún no hay cupones.'))
                : visible.isEmpty
                    ? Center(
                        child: Text(
                          'No hay cupones en "${_filterLabels[_filter]}".',
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.vertical,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final c = visible[i];
                          return Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              leading: _CouponThumbnail(coupon: c),
                              title: Text(
                                '${c.name}  •  ${c.discount}',
                                style:
                                    const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                '${c.business}\n'
                                'Tipo: ${kCouponTypeLabels[c.couponType] ?? c.couponType}\n'
                                'Categoría: ${c.category}\n'
                                'ID: ${c.id}  ·  Token-id: ${c.tokenId}\n'
                                'Vence: ${c.expiresAt}'
                                '${c.isExpired ? ' (vencido)' : ''}\n'
                                'Capturas: ${c.capturesCount}/${c.maxCaptures}'
                                '  ·  Canjeado: ${c.redeemedCount} '
                                '${c.redeemedCount == 1 ? 'vez' : 'veces'}'
                                '${c.latitude != null && c.longitude != null ? '\nUbicación: ${c.latitude!.toStringAsFixed(5)}, ${c.longitude!.toStringAsFixed(5)}' : ''}',
                              ),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                onSelected: (action) {
                                  switch (action) {
                                    case 'edit':
                                      widget.onEdit(c);
                                      break;
                                    case 'toggle':
                                      widget.onToggleActive(c);
                                      break;
                                    case 'delete':
                                      widget.onDelete(c);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Editar'),
                                  ),
                                  PopupMenuItem(
                                    value: 'toggle',
                                    child: Text(
                                      c.active ? 'Dar de baja' : 'Dar de alta',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text(
                                      'Eliminar',
                                      style:
                                          TextStyle(color: AppColors.stampCoral),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// Fila de tarjetas con el resumen de cupones. Tocar una tarjeta filtra
/// la lista de abajo; tocar la ya seleccionada quita el filtro.
class _CouponStatsRow extends StatelessWidget {
  final int total;
  final int active;
  final int inactive;
  final int expired;
  final int soldOut;
  final int redeemed;
  final int availableSlots;
  final _CouponFilter selected;
  final void Function(_CouponFilter) onSelect;

  const _CouponStatsRow({
    required this.total,
    required this.active,
    required this.inactive,
    required this.expired,
    required this.soldOut,
    required this.redeemed,
    required this.availableSlots,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cards = <_StatCardData>[
      _StatCardData('$total', 'Total', 'Ver todos', _CouponFilter.all),
      _StatCardData(
        '$active',
        'Activos',
        '$availableSlots cupos disponibles',
        _CouponFilter.active,
      ),
      _StatCardData(
        '$redeemed',
        'Canjeados',
        redeemed == 1 ? '1 vez' : '$redeemed veces',
        _CouponFilter.redeemed,
      ),
      _StatCardData(
        '$soldOut',
        'Agotados',
        'Sin cupos',
        _CouponFilter.soldOut,
      ),
      _StatCardData(
        '$expired',
        'Vencidos',
        'Fecha pasada',
        _CouponFilter.expired,
      ),
      _StatCardData(
        '$inactive',
        'Dados de baja',
        'Desactivados a mano',
        _CouponFilter.inactive,
      ),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SizedBox(
        height: 78,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: cards.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final d = cards[i];
            final isSelected = d.filter != null && d.filter == selected;
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: d.filter == null
                  ? null
                  : () => onSelect(isSelected ? _CouponFilter.all : d.filter!),
              child: Container(
                width: 118,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.inkTeal.withOpacity(0.08)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.inkTeal
                        : Colors.grey.shade300,
                    width: isSelected ? 1.6 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      d.value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: AppColors.inkTeal,
                      ),
                    ),
                    Text(
                      d.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      d.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatCardData {
  final String value;
  final String label;
  final String subtitle;
  final _CouponFilter? filter;
  const _StatCardData(this.value, this.label, this.subtitle, this.filter);
}

/// Miniatura del cupón: foto local recién elegida > foto ya subida en
/// el servidor > ícono de respaldo con el estado.
class _CouponThumbnail extends StatelessWidget {
  final AdminCoupon coupon;
  const _CouponThumbnail({required this.coupon});

  @override
  Widget build(BuildContext context) {
    if (coupon.photoPath != null) {
      return CircleAvatar(
        backgroundImage: FileImage(File(coupon.photoPath!)),
      );
    }
    if (coupon.photoUrl != null) {
      return CircleAvatar(
        backgroundImage: NetworkImage(coupon.photoUrl!),
      );
    }
    return CircleAvatar(
      backgroundColor:
          coupon.active ? AppColors.inkTeal : Colors.grey.shade400,
      child: Icon(
        coupon.active ? Icons.check : Icons.pause,
        color: Colors.white,
        size: 18,
      ),
    );
  }
}

class _CouponFormResult {
  final String name;
  final String business;
  final String discount;
  final String couponType;
  final String expiresAt;
  final String category;
  final String? photoPath;
  final double latitude;
  final double longitude;
  final String tokenId;
  final int maxCaptures;
  _CouponFormResult(
    this.name,
    this.business,
    this.discount,
    this.couponType,
    this.expiresAt,
    this.category,
    this.photoPath,
    this.latitude,
    this.longitude,
    this.tokenId,
    this.maxCaptures,
  );
}

class _CouponFormDialog extends StatefulWidget {
  final AdminCoupon? initial;
  // Negocios asignados al administrador (nombres).
  final List<String> businesses;
  const _CouponFormDialog({this.initial, required this.businesses});

  @override
  State<_CouponFormDialog> createState() => _CouponFormDialogState();
}

class _CouponFormDialogState extends State<_CouponFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  // Al editar se muestra solo el número ("20", "50") para porcentaje/dinero;
  // para cupón por producto, el texto tal cual.
  late final _discountCtrl = TextEditingController(
    text: _initialDiscountText(),
  );
  late final _expiresCtrl = TextEditingController(
    text: widget.initial?.expiresAt ?? '',
  );
  // Token-id: si es edición, se muestra el que ya tiene el cupón (no se
  // puede editar). Si es alta nueva, se genera uno de vista previa que se
  // puede regenerar con el botón de refrescar.
  late final _tokenCtrl = TextEditingController(
    text: widget.initial?.tokenId ?? _generateTokenId(),
  );

  late String? _business = widget.initial?.business;
  late String _couponType = widget.initial?.couponType ?? 'porcentaje';
  // Promoción elegida cuando el tipo es "producto" (2x1, 3x2, ...).
  late String? _promo = _initialPromo();
  late String _category =
      widget.initial?.category ?? kCouponCategories.first;
  late int _maxCaptures = widget.initial?.maxCaptures ?? 1;
  late String? _photoPath;
  late String? _existingPhotoUrl = widget.initial?.photoUrl;

  late LatLng? _location = (widget.initial?.latitude != null &&
          widget.initial?.longitude != null)
      ? LatLng(widget.initial!.latitude!, widget.initial!.longitude!)
      : null;

  bool get _isEdit => widget.initial != null;

  // Al editar un cupón cuyo negocio ya no está asignado a este admin,
  // hay que elegir otro de la lista.
  bool get _businessNoLongerAssigned =>
      _isEdit && !widget.businesses.contains(widget.initial!.business);

  String get _discountLabel {
    switch (_couponType) {
      case 'producto':
        return 'Producto o promoción (ej. 2x1 en café)';
      case 'dinero':
        return 'Descuento en pesos (ej. 50)';
      default:
        return 'Descuento en % (ej. 20)';
    }
  }

  String? _initialPromo() {
    final i = widget.initial;
    if (i == null || i.couponType != 'producto') return null;
    return kProductPromos.contains(i.discount) ? i.discount : kOtherPromo;
  }

  String _initialDiscountText() {
    final i = widget.initial;
    if (i == null) return '';
    if (i.couponType == 'producto') {
      return kProductPromos.contains(i.discount) ? '' : i.discount;
    }
    return _plainDiscount(i.couponType, i.discount);
  }

  /// Texto final del descuento que se guarda en el cupón.
  String _finalDiscount() {
    if (_couponType == 'producto') {
      return _promo == kOtherPromo ? _discountCtrl.text.trim() : (_promo ?? '');
    }
    return _formatDiscount(_couponType, _discountCtrl.text);
  }

  @override
  void initState() {
    super.initState();
    _photoPath = null;
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1280,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() {
      _photoPath = picked.path;
      _existingPhotoUrl = null;
    });
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    var initialDate = now;
    final iso = _ddmmyyyyToIso(_expiresCtrl.text);
    if (iso != null) {
      final parsed = DateTime.tryParse(iso);
      if (parsed != null && !parsed.isBefore(now)) {
        initialDate = parsed;
      }
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      helpText: 'Selecciona la fecha de vencimiento',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (picked == null) return;
    setState(() {
      _expiresCtrl.text = '${picked.day.toString().padLeft(2, '0')}/'
          '${picked.month.toString().padLeft(2, '0')}/'
          '${picked.year}';
    });
  }

  void _decrementMaxCaptures() {
    if (_maxCaptures <= 1) return;
    setState(() => _maxCaptures--);
  }

  void _incrementMaxCaptures() {
    setState(() => _maxCaptures++);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _discountCtrl.dispose();
    _expiresCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Editar cupón' : 'Dar de alta cupón'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isEdit)
                TextFormField(
                  initialValue: widget.initial!.id,
                  enabled: false,
                  decoration: const InputDecoration(labelText: 'ID'),
                ),
              TextFormField(
                controller: _tokenCtrl,
                // OJO: usamos `readOnly` (no `enabled: false`). Con
                // `enabled: false` Flutter envuelve TODO el campo —
                // incluido el botón del suffixIcon — en un IgnorePointer,
                // así que el botón de refrescar se veía pero no
                // respondía al toque. Con `readOnly: true` el texto
                // sigue sin poder editarse a mano, pero el botón sí
                // funciona.
                readOnly: true,
                showCursor: false,
                style: TextStyle(color: Theme.of(context).disabledColor),
                decoration: InputDecoration(
                  labelText: 'Token-id',
                  suffixIcon: _isEdit
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Generar otro token',
                          onPressed: () => setState(() {
                            _tokenCtrl.text = _generateTokenId();
                          }),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              _PhotoPicker(
                photoPath: _photoPath,
                existingPhotoUrl: _existingPhotoUrl,
                onPick: _pickPhoto,
                onRemove: (_photoPath == null && _existingPhotoUrl == null)
                    ? null
                    : () => setState(() {
                          _photoPath = null;
                          _existingPhotoUrl = null;
                        }),
              ),
              const SizedBox(height: 12),
              _LocationPicker(
                initial: _location,
                onChanged: (loc) => setState(() => _location = loc),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.black),
                decoration: const InputDecoration(
                  labelText: 'Nombre del cupón',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              // ── Negocio: solo los asignados a este administrador ──
              DropdownButtonFormField<String>(
                initialValue:
                    widget.businesses.contains(_business) ? _business : null,
                isExpanded: true,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  labelText: 'Negocio',
                  helperText: _businessNoLongerAssigned
                      ? '"${widget.initial!.business}" ya no está en tus '
                          'negocios. Elige otro.'
                      : null,
                  helperMaxLines: 2,
                ),
                items: widget.businesses
                    .map(
                      (name) => DropdownMenuItem(
                        value: name,
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.black),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _business = value),
                validator: (v) => v == null ? 'Selecciona un negocio' : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _category,
                style: const TextStyle(color: Colors.black),
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: kCouponCategories
                    .map(
                      (cat) => DropdownMenuItem(
                        value: cat,
                        child: Text(
                          cat,
                          style: const TextStyle(color: Colors.black),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              // ── Tipo de cupón: producto / porcentaje / dinero ──
              DropdownButtonFormField<String>(
                initialValue: _couponType,
                isExpanded: true,
                style: const TextStyle(color: Colors.black),
                decoration: const InputDecoration(labelText: 'Tipo de cupón'),
                items: kCouponTypeLabels.entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(
                          e.value,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.black),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null || value == _couponType) return;
                  setState(() {
                    _couponType = value;
                    // El valor anterior ya no aplica al nuevo tipo.
                    _discountCtrl.clear();
                    _promo = null;
                  });
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.repeat, size: 18, color: Colors.grey),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Veces que se puede capturar',
                      style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black),
                    ),
                  ),
                  IconButton(
                    onPressed: _decrementMaxCaptures,
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Menos capturas',
                  ),
                  Text(
                    '$_maxCaptures',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.black),
                  ),
                  IconButton(
                    onPressed: _incrementMaxCaptures,
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Más capturas',
                  ),
                ],
              ),
              // ── Descuento: depende del tipo de cupón ──
              if (_couponType == 'producto') ...[
                DropdownButtonFormField<String>(
                  key: const ValueKey('promo-dropdown'),
                  initialValue: _promo,
                  isExpanded: true,
                  style: const TextStyle(color: Colors.black),
                  decoration: const InputDecoration(labelText: 'Promoción'),
                  items: [...kProductPromos, kOtherPromo]
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            p,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _promo = value),
                  validator: (v) =>
                      v == null ? 'Selecciona una promoción' : null,
                ),
                if (_promo == kOtherPromo)
                  TextFormField(
                    controller: _discountCtrl,
                    style: const TextStyle(color: Colors.black),
                    decoration: const InputDecoration(
                      labelText: 'Describe la promoción (máx. 30)',
                    ),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Requerido';
                      if (t.length > 30) return 'Máximo 30 caracteres';
                      return null;
                    },
                  ),
              ] else
                TextFormField(
                  controller: _discountCtrl,
                  style: const TextStyle(color: Colors.black),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _discountLabel,
                    prefixText: _couponType == 'dinero' ? '\$ ' : null,
                    suffixText: _couponType == 'porcentaje' ? '%' : null,
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'Requerido';
                    final n = double.tryParse(t.replaceAll(',', '.'));
                    if (n == null || n <= 0) {
                      return 'Ingresa un número mayor a 0';
                    }
                    if (_couponType == 'porcentaje' && n > 100) {
                      return 'Máximo 100%';
                    }
                    return null;
                  },
                ),
              TextFormField(
                controller: _expiresCtrl,
                readOnly: true,
                style: const TextStyle(color: Colors.black),
                decoration: const InputDecoration(
                  labelText: 'Vence (dd/mm/aaaa)',
                  suffixIcon: Icon(Icons.calendar_month_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requerido';
                  if (_ddmmyyyyToIso(v) == null) {
                    return 'Formato inválido, usa dd/mm/aaaa';
                  }
                  return null;
                },
                onTap: _pickExpiryDate,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            if (_location == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Marca la ubicación del cupón (mapa o coordenadas)',
                  ),
                ),
              );
              return;
            }
            Navigator.pop(
              context,
              _CouponFormResult(
                _nameCtrl.text.trim(),
                _business!,
                _finalDiscount(),
                _couponType,
                _expiresCtrl.text.trim(),
                _category,
                _photoPath,
                _location!.latitude,
                _location!.longitude,
                _tokenCtrl.text.trim(),
                _maxCaptures,
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Selector de foto: muestra la foto recién elegida, o la que ya
/// estaba subida en el servidor, o un placeholder.
class _PhotoPicker extends StatelessWidget {
  final String? photoPath;
  final String? existingPhotoUrl;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  const _PhotoPicker({
    required this.photoPath,
    required this.existingPhotoUrl,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoPath != null || existingPhotoUrl != null;
    return Row(
      children: [
        GestureDetector(
          onTap: onPick,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.grey.shade200,
              image: photoPath != null
                  ? DecorationImage(
                      image: FileImage(File(photoPath!)),
                      fit: BoxFit.cover,
                    )
                  : existingPhotoUrl != null
                      ? DecorationImage(
                          image: NetworkImage(existingPhotoUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
            ),
            child: !hasPhoto
                ? const Icon(Icons.add_a_photo_outlined, color: Colors.grey)
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: onPick,
                child: Text(hasPhoto ? 'Cambiar foto' : 'Agregar foto'),
              ),
              if (onRemove != null)
                TextButton(
                  onPressed: onRemove,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.stampCoral,
                  ),
                  child: const Text('Quitar foto'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Selector de ubicación DENTRO del formulario/diálogo: solo texto y
/// botones. El mapa vive en `_MapPickerScreen`.
class _LocationPicker extends StatefulWidget {
  final LatLng? initial;
  final ValueChanged<LatLng?> onChanged;

  const _LocationPicker({required this.initial, required this.onChanged});

  @override
  State<_LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<_LocationPicker> {
  late final TextEditingController _latCtrl = TextEditingController(
    text: widget.initial?.latitude.toStringAsFixed(6) ?? '',
  );
  late final TextEditingController _lngCtrl = TextEditingController(
    text: widget.initial?.longitude.toStringAsFixed(6) ?? '',
  );

  LatLng? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  void _setSelected(LatLng? point) {
    setState(() {
      _selected = point;
      _latCtrl.text = point?.latitude.toStringAsFixed(6) ?? '';
      _lngCtrl.text = point?.longitude.toStringAsFixed(6) ?? '';
    });
    widget.onChanged(point);
  }

  void _applyTextCoords() {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat == null || lng == null) {
      _showMsg('Coordenadas inválidas');
      return;
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      _showMsg('Coordenadas fuera de rango');
      return;
    }
    _setSelected(LatLng(lat, lng));
  }

  Future<void> _abrirMapa() async {
    final result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (_) => _MapPickerScreen(initial: _selected)),
    );
    if (result != null) _setSelected(result);
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.place_outlined, size: 18, color: Colors.grey),
            const SizedBox(width: 6),
            Text(
              'Ubicación del cupón',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _selected != null
              ? 'Seleccionado: ${_selected!.latitude.toStringAsFixed(6)}, '
                  '${_selected!.longitude.toStringAsFixed(6)}'
              : 'Aún no has marcado una ubicación.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _latCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: 'Latitud'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _lngCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: 'Longitud'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _applyTextCoords,
                icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                label: const Text('Usar coordenadas'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _abrirMapa,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Marcar en mapa'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Pantalla completa para marcar la ubicación del cupón en un mapa,
/// con buscador de direcciones (geocodificación vía Nominatim, el
/// servicio gratuito de OpenStreetMap — no requiere API key).
class _MapPickerScreen extends StatefulWidget {
  final LatLng? initial;
  const _MapPickerScreen({this.initial});

  @override
  State<_MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<_MapPickerScreen> {
  static const _defaultCenter = LatLng(18.6560, -99.1953);

  final MapController _mapController = MapController();
  final TextEditingController _searchCtrl = TextEditingController();

  LatLng? _selected;
  bool _loadingLocation = false;
  bool _searching = false;
  List<Map<String, dynamic>> _searchResults = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    // Búsqueda "en vivo": espera a que el usuario deje de escribir
    // (debounce) y solo entonces consulta Nominatim, además de
    // refrescar el ícono de "limpiar" del campo de texto.
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {}); // refresca el botón de limpiar/mostrar spinner
    _debounce?.cancel();
    final query = _searchCtrl.text.trim();
    if (query.length < 3) {
      setState(() => _searchResults = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), _searchAddress);
  }

  void _setSelected(LatLng point, {bool moveMap = false}) {
    setState(() => _selected = point);
    if (moveMap) _mapController.move(point, 16);
  }

  Future<void> _usarUbicacionActual() async {
    setState(() => _loadingLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMsg('Activa el GPS/ubicación del dispositivo.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showMsg('Necesitamos permiso de ubicación para continuar.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showMsg('Permiso denegado permanentemente. Actívalo en Ajustes.');
        return;
      }
      // bestForNavigation exige al GPS la lectura más precisa posible
      // (en vez de conformarse con la triangulación por Wi-Fi/red,
      // que es lo que suele dar una ubicación "aproximada").
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      );
      _setSelected(LatLng(position.latitude, position.longitude), moveMap: true);
      // position.accuracy es el radio de error en metros que reporta
      // el propio GPS del teléfono: si sale muy alto (>50m), el
      // problema es la señal/el modo de ubicación del dispositivo,
      // no la app.
      if (position.accuracy > 50) {
        _showMsg(
          'Ubicación con poca precisión (±${position.accuracy.round()} m). '
          'Sal a espacio abierto o activa "Alta precisión" en Ubicación '
          'del teléfono.',
        );
      }
    } catch (e) {
      _showMsg('No se pudo obtener la ubicación: $e');
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  // Palabras que suelen estorbar la búsqueda de POIs (no aportan nada
  // que Nominatim pueda emparejar, y a veces sobran del todo).
  static const _searchStopwords = {
    'centro',
    'méxico',
    'mexico',
    'mx',
    'cerca',
    'de',
    'en',
    'la',
    'el',
  };

  /// Quita comas, el estado/país (ya cubiertos por countrycodes=mx) y
  /// palabras de relleno, dejando solo lo que de verdad ayuda a
  /// encontrar el lugar (ej. la marca y la localidad).
  String _simplifyQuery(String query) {
    final words = query
        .replaceAll(',', ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .where((w) => !_searchStopwords.contains(w.toLowerCase()))
        .toList();
    return words.join(' ');
  }

  Future<List<Map<String, dynamic>>> _fetchNominatim(String query) async {
    // Sesga la búsqueda a un cuadro alrededor de donde está el mapa
    // ahora mismo (viewbox), sin excluir resultados fuera de él
    // (bounded=0): así "BBVA en Jojutla" encuentra primero las
    // sucursales cercanas al punto donde ya estás viendo el mapa,
    // en vez de devolver la primera coincidencia en cualquier parte
    // del mundo.
    final center = _selected ?? _defaultCenter;
    const delta = 0.6; // ~60 km de margen alrededor del centro
    final viewbox = '${center.longitude - delta},${center.latitude + delta},'
        '${center.longitude + delta},${center.latitude - delta}';

    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?format=json&limit=8&addressdetails=1'
      '&accept-language=es&countrycodes=mx'
      '&viewbox=$viewbox&bounded=0'
      '&q=${Uri.encodeQueryComponent(query)}',
    );
    final res = await http
        .get(
          uri,
          // Nominatim pide identificar la app en el User-Agent, pero en
          // Flutter Web el navegador PROHÍBE fijar ese header a mano
          // (lo ignora o lanza error) — por eso solo se envía fuera de
          // la web. En web, Nominatim igualmente acepta la petición
          // usando el User-Agent real del navegador.
          headers: kIsWeb
              ? null
              // Los headers HTTP solo aceptan caracteres ASCII: nada
              // de acentos ni "ñ" aquí, o Dart lanza una
              // FormatException ("Invalid HTTP header field value").
              : {'User-Agent': 'com.cuponapp.app (CuponApp)'},
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw HttpException('código ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> _searchAddress() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _searchResults = [];
    });
    try {
      var results = await _fetchNominatim(query);

      // Si la búsqueda tal cual no encontró nada, reintenta una vez
      // con una versión más simple (sin comas ni palabras de relleno
      // como "centro" o "méxico"), que suele funcionar mejor con
      // nombres de comercios.
      final simplified = _simplifyQuery(query);
      if (results.isEmpty && simplified.isNotEmpty && simplified != query) {
        results = await _fetchNominatim(simplified);
      }

      if (!mounted) return;
      setState(() => _searchResults = results);
      if (_searchResults.isEmpty) {
        _showMsg(
          'No se encontraron resultados para "$query". Prueba solo con '
          'la marca y la localidad (ej. "BBVA Axochiapan"), o marca el '
          'punto directamente en el mapa.',
        );
      }
    } on TimeoutException {
      _showMsg('La búsqueda tardó demasiado. Intenta de nuevo.');
    } catch (e) {
      _showMsg('No se pudo buscar la dirección. Revisa tu conexión. ($e)');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectSearchResult(Map<String, dynamic> result) {
    final lat = double.tryParse(result['lat'].toString());
    final lon = double.tryParse(result['lon'].toString());
    if (lat == null || lon == null) return;
    _setSelected(LatLng(lat, lon), moveMap: true);
    _searchCtrl.removeListener(_onSearchChanged);
    setState(() {
      _searchResults = [];
      _searchCtrl.text = (result['display_name'] as String?) ?? '';
    });
    _searchCtrl.addListener(_onSearchChanged);
    FocusScope.of(context).unfocus();
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final center = _selected ?? _defaultCenter;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marca la ubicación del cupón'),
        actions: [
          IconButton(
            onPressed: _loadingLocation ? null : _usarUbicacionActual,
            icon: _loadingLocation
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Icon(Icons.my_location),
            tooltip: 'Usar mi ubicación actual',
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: _selected != null ? 16 : 13,
              onTap: (tapPosition, point) {
                _setSelected(point);
                setState(() => _searchResults = []);
                FocusScope.of(context).unfocus();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.cuponapp.app',
              ),
              if (_selected != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selected!,
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.location_on,
                        color: AppColors.stampCoral,
                        size: 44,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          // ── Buscador de direcciones, arriba del mapa ──
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) {
                      _debounce?.cancel();
                      _searchAddress();
                    },
                    decoration: InputDecoration(
                      hintText: 'Buscar una dirección…',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : (_searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    _debounce?.cancel();
                                    _searchCtrl.clear();
                                    setState(() => _searchResults = []);
                                  },
                                )
                              : IconButton(
                                  icon: const Icon(Icons.arrow_forward),
                                  onPressed: () {
                                    _debounce?.cancel();
                                    _searchAddress();
                                  },
                                )),
                    ),
                  ),
                ),
                if (_searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    constraints: const BoxConstraints(maxHeight: 240),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 6),
                      ],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _searchResults.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final r = _searchResults[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined),
                          title: Text(
                            (r['display_name'] as String?) ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectSearchResult(r),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selected != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 6),
                      ],
                    ),
                    child: Text(
                      '${_selected!.latitude.toStringAsFixed(6)}, '
                      '${_selected!.longitude.toStringAsFixed(6)}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ElevatedButton(
                  onPressed: _selected == null
                      ? null
                      : () => Navigator.pop(context, _selected),
                  child: const Text('CONFIRMAR UBICACIÓN'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}