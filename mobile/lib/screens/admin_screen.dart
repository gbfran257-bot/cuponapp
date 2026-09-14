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
  String expiresAt; // dd/mm/aaaa, para mostrar en la lista/formulario
  String category;
  // Cuántas veces se puede capturar este cupón en total.
  int maxCaptures;
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
    required this.expiresAt,
    required this.category,
    this.maxCaptures = 1,
    this.photoPath,
    this.photoUrl,
    this.latitude,
    this.longitude,
    this.active = true,
  });

  factory AdminCoupon.fromJson(Map<String, dynamic> json) => AdminCoupon(
        id: json['id'] as String,
        numericId: json['numericId'] as String,
        tokenId: json['tokenId'] as String,
        name: json['name'] as String,
        business: json['business'] as String,
        discount: json['discount'] as String,
        expiresAt: json['expiresAt'] as String? ?? '',
        category: json['category'] as String? ?? 'Otro',
        maxCaptures: (json['maxCaptures'] as num?)?.toInt() ?? 1,
        photoUrl: json['photoUrl'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        active: json['active'] as bool? ?? true,
      );
}

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
      setState(() {
        _coupons = data
            .map((c) => AdminCoupon.fromJson(c as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = 'No se pudo conectar con el servidor. Revisa tu conexión.';
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
          labelColor: Colors.white,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Canjear'),
            Tab(
              icon: Icon(Icons.confirmation_number_outlined),
              text: 'Cupones',
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
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  // ── CRUD ────────────────────────────────────────────────────

  Future<void> _createCoupon() async {
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
      builder: (context) => _CouponFormDialog(initial: initial),
    );
  }

  void _showMsg(String msg, {bool error = false}) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear código')),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          final barcode = capture.barcodes.firstOrNull;
          final value = barcode?.rawValue;
          if (value != null) {
            Navigator.pop(context, value);
          }
        },
      ),
    );
  }
}

/// ───────────────────────── TAB: CUPONES (CRUD) ─────────────────────────

class _CouponsTab extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onCreate,
        icon: const Icon(Icons.add),
        label: const Text('Dar de alta'),
      ),
      body: coupons.isEmpty
          ? const Center(child: Text('Aún no hay cupones.'))
          : ListView.separated(
              scrollDirection: Axis.vertical,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: coupons.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final c = coupons[i];
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: _CouponThumbnail(coupon: c),
                    title: Text(
                      '${c.name}  •  ${c.discount}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${c.business}\n'
                      'Categoría: ${c.category}\n'
                      'ID: ${c.id}  ·  Token-id: ${c.tokenId}\n'
                      'Vence: ${c.expiresAt}'
                      '${c.latitude != null && c.longitude != null ? '\nUbicación: ${c.latitude!.toStringAsFixed(5)}, ${c.longitude!.toStringAsFixed(5)}' : ''}',
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        switch (action) {
                          case 'edit':
                            onEdit(c);
                            break;
                          case 'toggle':
                            onToggleActive(c);
                            break;
                          case 'delete':
                            onDelete(c);
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
                          child: Text(c.active ? 'Dar de baja' : 'Dar de alta'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Eliminar',
                            style: TextStyle(color: AppColors.stampCoral),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
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
  const _CouponFormDialog({this.initial});

  @override
  State<_CouponFormDialog> createState() => _CouponFormDialogState();
}

class _CouponFormDialogState extends State<_CouponFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final _businessCtrl = TextEditingController(
    text: widget.initial?.business ?? '',
  );
  late final _discountCtrl = TextEditingController(
    text: widget.initial?.discount ?? '',
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
    _businessCtrl.dispose();
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
              TextFormField(
                controller: _businessCtrl,
                style: const TextStyle(color: Colors.black),
                decoration: const InputDecoration(labelText: 'Negocio'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
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
              TextFormField(
                controller: _discountCtrl,
                style: const TextStyle(color: Colors.black),
                decoration: const InputDecoration(
                  labelText: 'Descuento (ej. 20%)',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
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
                _businessCtrl.text.trim(),
                _discountCtrl.text.trim(),
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
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _setSelected(LatLng(position.latitude, position.longitude), moveMap: true);
    } catch (e) {
      _showMsg('No se pudo obtener la ubicación: $e');
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  Future<void> _searchAddress() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _searchResults = [];
    });
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=json&limit=5&addressdetails=0&q=${Uri.encodeQueryComponent(query)}',
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
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List<dynamic>;
        if (!mounted) return;
        setState(() {
          _searchResults = data.cast<Map<String, dynamic>>();
        });
        if (_searchResults.isEmpty) {
          _showMsg('No se encontraron resultados para "$query".');
        }
      } else {
        _showMsg('No se pudo buscar la dirección (código ${res.statusCode}).');
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
                      color: Colors.white,
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