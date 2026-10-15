import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/coupon.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _MenuOption { inicio, cupones, regresar }

enum _RedeemMethod { qr, barcode }

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tabIndex = 0;

  List<Coupon> _coupons = [];
  List<Coupon> _myCoupons = [];

  bool _loadingCoupons = false;
  bool _loadingMyCoupons = false;

  // Errores separados: antes compartían una sola variable y el error del
  // catálogo aparecía dentro de "Mis cupones".
  String? _loadError;
  String? _myLoadError;

  String _selectedCategory = 'Todos';

  Position? _currentPosition;

  final Map<String, File> _capturedCouponPhotos = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCoupons();
    _loadMyCoupons();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Al volver a la app (por ejemplo después de que el negocio escaneó el
  // código) se refresca "Mis cupones" para reflejar el canje.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadMyCoupons();
    }
  }

  // ============================================================
  // CUPONES DISPONIBLES
  // ============================================================

  Future<void> _loadCoupons({Position? position, String? category}) async {
    if (mounted) setState(() => _loadingCoupons = true);

    try {
      final data = await apiService.getCoupons(
        latitude: position?.latitude,
        longitude: position?.longitude,
        category: category,
      );

      final coupons = <Coupon>[];
      for (final item in data) {
        if (item is Map) {
          coupons.add(Coupon.fromJson(Map<String, dynamic>.from(item)));
        }
      }

      if (!mounted) return;
      setState(() {
        _coupons = coupons;
        _loadError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.message);
      _showMsg(e.message, error: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadError = 'No se pudo conectar con el servidor.');
      _showMsg('No se pudo conectar con el servidor.', error: true);
    } finally {
      if (mounted) setState(() => _loadingCoupons = false);
    }
  }

  // ============================================================
  // MIS CUPONES CAPTURADOS
  // ============================================================

  Future<void> _loadMyCoupons() async {
    if (mounted) setState(() => _loadingMyCoupons = true);

    try {
      final data = await apiService.getMyCoupons();

      final coupons = <Coupon>[];
      for (final item in data) {
        if (item is Map) {
          coupons.add(Coupon.fromJson(Map<String, dynamic>.from(item)));
        }
      }

      if (!mounted) return;
      setState(() {
        _myCoupons = coupons;
        _myLoadError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _myLoadError = e.message);
      _showMsg(e.message, error: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _myLoadError = 'No se pudieron cargar tus cupones.');
      _showMsg('No se pudieron cargar tus cupones.', error: true);
    } finally {
      if (mounted) setState(() => _loadingMyCoupons = false);
    }
  }

  // ============================================================
  // UBICACIÓN
  // ============================================================

  Future<Position?> _obtenerUbicacionActual() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMsg('Activa el GPS/ubicación del dispositivo.', error: true);
        return null;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showMsg(
            'Necesitamos permiso de ubicación para continuar.',
            error: true,
          );
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showMsg(
          'El permiso de ubicación está bloqueado. Actívalo en Ajustes.',
          error: true,
        );
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return null;
      setState(() => _currentPosition = position);
      return position;
    } catch (_) {
      _showMsg('No se pudo obtener tu ubicación.', error: true);
      return null;
    }
  }

  // ============================================================
  // CUPONES CERCA
  // ============================================================

  Future<void> _buscarCerca(Position position) async {
    if (!mounted) return;
    setState(() => _currentPosition = position);

    await _loadCoupons(
      position: position,
      category: _selectedCategory == 'Todos' ? null : _selectedCategory,
    );
  }

  // ============================================================
  // CATEGORÍA
  // ============================================================

  Future<void> _elegirCategoria() async {
    final result = await Navigator.pushNamed(
      context,
      '/categorias',
      arguments: _selectedCategory,
    );

    if (result is String && mounted) {
      setState(() => _selectedCategory = result);

      await _loadCoupons(
        position: _currentPosition,
        category: result == 'Todos' ? null : result,
      );
    }
  }

  // ============================================================
  // CAPTURAR CUPÓN
  // ============================================================

  Future<void> _capturarCupon(Coupon coupon) async {
    if (!coupon.active) {
      _showMsg('Este cupón ya no está activo.', error: true);
      return;
    }

    if (coupon.isExpired) {
      _showMsg('Este cupón ya venció.', error: true);
      return;
    }

    if (coupon.alreadyCaptured) {
      _showMsg('Ya capturaste este cupón anteriormente.', error: true);
      return;
    }

    if (!coupon.captureAvailable) {
      _showMsg(
        coupon.remainingCaptures > 0
            ? 'Este cupón no está disponible para captura.'
            : 'Este cupón ya alcanzó el máximo de capturas.',
        error: true,
      );
      return;
    }

    // Ubicación real del usuario.
    final position = await _obtenerUbicacionActual();
    if (position == null) return;

    if (!mounted) return;

    // Mapa del negocio y luego cámara en modo RA.
    final photo = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (_) => _CaptureCouponScreen(
          coupon: coupon,
          currentPosition: position,
        ),
      ),
    );

    if (photo == null) return;

    try {
      if (!mounted) return;

      _showLoadingMessage('Guardando captura...');

      final response = await apiService.captureCoupon(
        tokenId: coupon.tokenId,
        photo: photo,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      setState(() {
        _capturedCouponPhotos[coupon.tokenId] = photo;

        // Actualización inmediata del catálogo: el cupón queda marcado
        // como capturado por este usuario. Después se reconcilia con el
        // valor real del servidor.
        _coupons = _coupons
            .map((c) => c.tokenId == coupon.tokenId ? _markCaptured(c) : c)
            .toList();
      });

      await Future.wait([
        _loadCoupons(
          position: _currentPosition,
          category: _selectedCategory == 'Todos' ? null : _selectedCategory,
        ),
        _loadMyCoupons(),
      ]);

      if (!mounted) return;

      setState(() => _tabIndex = 1);

      _showMsg(
        _extractCaptureMessage(response) ?? 'Cupón capturado correctamente 📸',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showMsg(e.message, error: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showMsg('No se pudo guardar la captura.', error: true);
    }
  }

  String? _extractCaptureMessage(Map<String, dynamic> response) {
    final value = response['message'];
    if (value == null) return null;

    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  void _showLoadingMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(minutes: 1),
          content: Row(
            children: [
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Text(message),
            ],
          ),
        ),
      );
  }

  /// Copia del cupón (del catálogo) ya capturado por este usuario: suma
  /// una captura, baja los cupos restantes y ya no permite capturarlo de
  /// nuevo.
  Coupon _markCaptured(Coupon c) {
    final newCount = c.capturesCount + 1;
    final newRemaining =
        (c.maxCaptures - newCount).clamp(0, c.maxCaptures).toInt();
    return c.copyWith(
      capturesCount: newCount,
      remainingCaptures: newRemaining,
      captureAvailable: false,
      alreadyCaptured: true,
    );
  }

  // ============================================================
  // CANJE (código QR / de barras) — sobre cupones ya capturados,
  // en la pestaña "Mis cupones".
  // ============================================================

  void _abrirPanelCanje(Coupon c, _RedeemMethod method) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: _RedeemPanel(
            coupon: c,
            method: method,
            onCancel: () => Navigator.of(context).pop(),
          ),
        );
      },
      // Al cerrar el panel se refresca la lista, por si el negocio ya
      // escaneó el código y el cupón pasó a "Canjeado".
    ).whenComplete(_loadMyCoupons);
  }

  // ============================================================
  // MENSAJES
  // ============================================================

  void _showMsg(String msg, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: error ? AppColors.stampCoral : null,
        ),
      );
  }

  // ============================================================
  // MENÚ
  // ============================================================

  Future<void> _onMenuSelected(_MenuOption option) async {
    switch (option) {
      case _MenuOption.inicio:
        setState(() => _tabIndex = 0);
        break;

      case _MenuOption.cupones:
        setState(() => _tabIndex = 1);
        await _loadMyCoupons();
        break;

      case _MenuOption.regresar:
        try {
          await apiService.logout();
        } catch (_) {}

        if (!mounted) return;

        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        break;
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CUPÓN APP'),
        leading: PopupMenuButton<_MenuOption>(
          icon: const Icon(Icons.menu),
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onSelected: _onMenuSelected,
          itemBuilder: (context) => [
            _buildMenuItem(
              value: _MenuOption.inicio,
              icon: Icons.person_outline,
              label: 'Inicio',
              selected: _tabIndex == 0,
            ),
            _buildMenuItem(
              value: _MenuOption.cupones,
              icon: Icons.confirmation_number_outlined,
              label: 'Mis cupones',
              selected: _tabIndex == 1,
            ),
            const PopupMenuDivider(),
            _buildMenuItem(
              value: _MenuOption.regresar,
              icon: Icons.logout,
              label: 'Cerrar sesión',
              destructive: true,
            ),
          ],
        ),
      ),
      body: _tabIndex == 0
          ? _InicioTab(
              coupons: _coupons,
              currentPosition: _currentPosition,
              loading: _loadingCoupons,
              error: _loadError,
              selectedCategory: _selectedCategory,
              onBuscarCerca: _buscarCerca,
              onElegirCategoria: _elegirCategoria,
              onCaptureCoupon: _capturarCupon,
            )
          : _CuponesTab(
              coupons: _myCoupons,
              loading: _loadingMyCoupons,
              error: _myLoadError,
              capturedPhotos: _capturedCouponPhotos,
              onRetry: _loadMyCoupons,
              onPickMethod: _abrirPanelCanje,
            ),
    );
  }

  PopupMenuItem<_MenuOption> _buildMenuItem({
    required _MenuOption value,
    required IconData icon,
    required String label,
    bool selected = false,
    bool destructive = false,
  }) {
    final color = destructive ? AppColors.stampCoral : AppColors.inkTeal;

    return PopupMenuItem<_MenuOption>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          if (selected) ...[
            const Spacer(),
            Icon(Icons.check, size: 18, color: color),
          ],
        ],
      ),
    );
  }
}

// ================================================================
// INICIO
// ================================================================

class _InicioTab extends StatefulWidget {
  final List<Coupon> coupons;
  final Position? currentPosition;
  final bool loading;
  final String? error;
  final String selectedCategory;
  final Future<void> Function(Position position) onBuscarCerca;
  final VoidCallback onElegirCategoria;
  final Future<void> Function(Coupon coupon) onCaptureCoupon;

  const _InicioTab({
    required this.coupons,
    required this.currentPosition,
    required this.loading,
    required this.error,
    required this.selectedCategory,
    required this.onBuscarCerca,
    required this.onElegirCategoria,
    required this.onCaptureCoupon,
  });

  @override
  State<_InicioTab> createState() => _InicioTabState();
}

class _InicioTabState extends State<_InicioTab> {
  final _searchCtrl = TextEditingController();
  final MapController _mapController = MapController();

  bool _loadingLocation = false;

  static const _defaultCenter = LatLng(18.6560, -99.1953);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Pide permisos y devuelve la posición actual (o null con mensaje).
  Future<Position?> _obtenerPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMsg('Activa el GPS/ubicación del dispositivo.');
        return null;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showMsg('Necesitamos permiso de ubicación para continuar.');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showMsg('Permiso denegado permanentemente. Actívalo en Ajustes.');
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (_) {
      _showMsg('No se pudo obtener la ubicación.');
      return null;
    }
  }

  Future<void> _obtenerUbicacionActual() async {
    setState(() => _loadingLocation = true);

    try {
      final position = await _obtenerPosition();
      if (position == null || !mounted) return;

      _mapController.move(LatLng(position.latitude, position.longitude), 16);

      await widget.onBuscarCerca(position);
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  Future<void> _buscarCuponesCerca() async {
    final position = widget.currentPosition ?? await _obtenerPosition();
    if (position == null) return;

    await widget.onBuscarCerca(position);
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final pos = widget.currentPosition;
    final center =
        pos != null ? LatLng(pos.latitude, pos.longitude) : _defaultCenter;

    final markers = <Marker>[
      if (pos != null)
        Marker(
          point: LatLng(pos.latitude, pos.longitude),
          width: 40,
          height: 40,
          child: const Icon(
            Icons.person_pin_circle,
            color: AppColors.inkTeal,
            size: 40,
          ),
        ),
      ...widget.coupons
          .where((c) => c.latitude != null && c.longitude != null)
          .map(
            (c) => Marker(
              point: LatLng(c.latitude!, c.longitude!),
              width: 42,
              height: 56,
              child: _CouponMarkerIcon(
                coupon: c,
                onTap: () => _mostrarCapturar(context, c),
              ),
            ),
          ),
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Buscar cupones o negocios',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          if (widget.selectedCategory != 'Todos')
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  label: Text('Categoría: ${widget.selectedCategory}'),
                  onDeleted: widget.onElegirCategoria,
                  deleteIcon: const Icon(Icons.close, size: 16),
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _loadingLocation ? null : _obtenerUbicacionActual,
            icon: _loadingLocation
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location, size: 18),
            label: const Text('Ubicación actual'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: widget.loading ? null : _buscarCuponesCerca,
                  icon: widget.loading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.near_me_outlined, size: 18),
                  label: const Text('Cupones cerca'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: widget.onElegirCategoria,
                  icon: const Icon(Icons.category_outlined, size: 18),
                  label: const Text('Por categoría'),
                ),
              ),
            ],
          ),
          if (widget.error != null && widget.coupons.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                widget.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.stampCoral),
              ),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(initialCenter: center, initialZoom: 14),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.cuponapp.app',
                  ),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarCapturar(BuildContext context, Coupon coupon) {
    final available = coupon.captureAvailable;
    final remaining = coupon.remainingCaptures;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _CouponPhoto(photoUrl: coupon.photoUrl, size: 60),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          coupon.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        Text(coupon.business),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _InfoRow(label: 'Descuento', value: coupon.discount),
              _InfoRow(label: 'Categoría', value: coupon.category),
              _InfoRow(
                label: 'Capturas',
                value: '${coupon.capturesCount}/${coupon.maxCaptures}',
              ),
              _InfoRow(label: 'Disponibles', value: remaining.toString()),
              const SizedBox(height: 12),
              if (!coupon.active)
                const _StatusBox(
                  text: 'Este cupón está inactivo.',
                  icon: Icons.pause_circle,
                )
              else if (coupon.isExpired)
                const _StatusBox(
                  text: 'Este cupón ya venció.',
                  icon: Icons.event_busy,
                )
              else if (coupon.alreadyCaptured)
                const _StatusBox(
                  text: 'Ya capturaste este cupón anteriormente.',
                  icon: Icons.check_circle,
                  success: true,
                )
              else if (!available)
                _StatusBox(
                  text: remaining <= 0
                      ? 'Este cupón ya alcanzó el máximo de capturas.'
                      : 'Este cupón no está disponible para captura.',
                  icon: Icons.block,
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: !coupon.active || coupon.isExpired || !available
                      ? null
                      : () {
                          Navigator.pop(context);
                          widget.onCaptureCoupon(coupon);
                        },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('CAZAR CUPÓN'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ================================================================
// MARCADOR
// ================================================================

class _CouponMarkerIcon extends StatelessWidget {
  final Coupon coupon;
  final VoidCallback onTap;

  const _CouponMarkerIcon({required this.coupon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final available = coupon.active && coupon.captureAvailable;

    Widget fallback() => Container(
          color: available ? AppColors.inkTeal : Colors.grey,
          child: const Icon(Icons.local_offer, color: Colors.white, size: 16),
        );

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)],
            ),
            child: coupon.photoUrl == null
                ? fallback()
                : Image.network(
                    coupon.photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => fallback(),
                  ),
          ),
          const Icon(
            Icons.arrow_drop_down,
            size: 20,
            color: AppColors.stampCoral,
          ),
        ],
      ),
    );
  }
}

// ================================================================
// MIS CUPONES
// ================================================================

/// Filtro de "Mis cupones". "all" no filtra nada.
enum _MyCouponFilter { all, pending, redeemed, expired, inactive }

const Map<_MyCouponFilter, String> _myFilterLabels = {
  _MyCouponFilter.all: 'Todos',
  _MyCouponFilter.pending: 'Por canjear',
  _MyCouponFilter.redeemed: 'Canjeados',
  _MyCouponFilter.expired: 'Vencidos',
  _MyCouponFilter.inactive: 'Dados de baja',
};

bool _matchesMyFilter(Coupon c, _MyCouponFilter f) {
  switch (f) {
    case _MyCouponFilter.all:
      return true;
    case _MyCouponFilter.pending:
      return c.status == CouponUserStatus.pending;
    case _MyCouponFilter.redeemed:
      return c.status == CouponUserStatus.redeemed;
    case _MyCouponFilter.expired:
      return c.status == CouponUserStatus.expired;
    case _MyCouponFilter.inactive:
      return c.status == CouponUserStatus.inactive;
  }
}

class _CuponesTab extends StatefulWidget {
  final List<Coupon> coupons;
  final bool loading;
  final String? error;
  final Future<void> Function() onRetry;
  final void Function(Coupon coupon, _RedeemMethod method) onPickMethod;
  final Map<String, File> capturedPhotos;

  const _CuponesTab({
    required this.coupons,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onPickMethod,
    required this.capturedPhotos,
  });

  @override
  State<_CuponesTab> createState() => _CuponesTabState();
}

class _CuponesTabState extends State<_CuponesTab> {
  _MyCouponFilter _filter = _MyCouponFilter.all;

  @override
  Widget build(BuildContext context) {
    if (widget.loading && widget.coupons.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.error != null && widget.coupons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: widget.onRetry,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.coupons.isEmpty) {
      return RefreshIndicator(
        onRefresh: widget.onRetry,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text('Aún no tienes cupones capturados.')),
          ],
        ),
      );
    }

    int count(CouponUserStatus s) =>
        widget.coupons.where((c) => c.status == s).length;

    final visible = widget.coupons
        .where((c) => _matchesMyFilter(c, _filter))
        .toList();

    // Primero los "Por canjear" (el que vence antes, arriba); después el
    // resto en el orden que manda el servidor.
    visible.sort((a, b) {
      int rank(Coupon c) => c.status == CouponUserStatus.pending ? 0 : 1;
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      if (rank(a) == 0) return a.expiresAtIso.compareTo(b.expiresAtIso);
      return 0;
    });

    return Column(
      children: [
        _MyCouponsStatsRow(
          total: widget.coupons.length,
          pending: count(CouponUserStatus.pending),
          redeemed: count(CouponUserStatus.redeemed),
          expired: count(CouponUserStatus.expired),
          inactive: count(CouponUserStatus.inactive),
          selected: _filter,
          onSelect: (f) => setState(() => _filter = f),
        ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRetry,
            child: visible.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text(
                          'No hay cupones en "${_myFilterLabels[_filter]}".',
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final c = visible[i];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CouponCard(
                          coupon: c,
                          capturedPhoto: widget.capturedPhotos[c.tokenId],
                          onPickMethod: (method) =>
                              widget.onPickMethod(c, method),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

/// Fila de tarjetas con el resumen de "Mis cupones". Tocar una
/// tarjeta filtra la lista de abajo; tocarla otra vez la quita.
class _MyCouponsStatsRow extends StatelessWidget {
  final int total;
  final int pending;
  final int redeemed;
  final int expired;
  final int inactive;
  final _MyCouponFilter selected;
  final void Function(_MyCouponFilter) onSelect;

  const _MyCouponsStatsRow({
    required this.total,
    required this.pending,
    required this.redeemed,
    required this.expired,
    required this.inactive,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cards = <_MyStatCardData>[
      _MyStatCardData('$total', 'Capturados', 'Ver todos', _MyCouponFilter.all),
      _MyStatCardData(
        '$pending',
        'Por canjear',
        'Listos para usar',
        _MyCouponFilter.pending,
      ),
      _MyStatCardData(
        '$redeemed',
        'Canjeados',
        'Ya usados',
        _MyCouponFilter.redeemed,
      ),
      _MyStatCardData(
        '$expired',
        'Vencidos',
        'Fecha pasada',
        _MyCouponFilter.expired,
      ),
      _MyStatCardData(
        '$inactive',
        'Dados de baja',
        'Ya no válidos',
        _MyCouponFilter.inactive,
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
            final isSelected = d.filter == selected;

            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () =>
                  onSelect(isSelected ? _MyCouponFilter.all : d.filter),
              child: Container(
                width: 112,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
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

class _MyStatCardData {
  final String value;
  final String label;
  final String subtitle;
  final _MyCouponFilter filter;

  const _MyStatCardData(this.value, this.label, this.subtitle, this.filter);
}

// ================================================================
// TARJETA
// ================================================================

class _CouponCard extends StatelessWidget {
  final Coupon coupon;
  final File? capturedPhoto;
  final void Function(_RedeemMethod) onPickMethod;

  const _CouponCard({
    required this.coupon,
    required this.capturedPhoto,
    required this.onPickMethod,
  });

  /// Caja de estado según la prioridad canjeado > vencido > inactivo >
  /// pendiente (la misma que usa el resumen de arriba).
  Widget _buildStatusBox(Coupon c) {
    final status = c.status;

    if (status == CouponUserStatus.redeemed) {
      return _StatusBox(
        text: c.redeemedAt != null
            ? 'Canjeado el ${c.redeemedAt}.'
            : 'Este cupón ya fue canjeado.',
        icon: Icons.verified,
        success: true,
      );
    }
    if (status == CouponUserStatus.expired) {
      return const _StatusBox(
        text: 'Este cupón ya venció.',
        icon: Icons.event_busy,
      );
    }
    if (status == CouponUserStatus.inactive) {
      return const _StatusBox(
        text: 'Cupón dado de baja.',
        icon: Icons.pause_circle,
      );
    }
    return const _StatusBox(
      text: 'Capturado. Listo para canjear.',
      icon: Icons.check_circle,
      success: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = coupon;

    final hasPhoto = capturedPhoto != null || c.capturePhotoUrl != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPhoto)
            Container(
              width: double.infinity,
              height: 190,
              margin: const EdgeInsets.only(bottom: 14),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: capturedPhoto != null
                  ? Image.file(capturedPhoto!, fit: BoxFit.cover)
                  : Image.network(
                      c.capturePhotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CouponPhoto(photoUrl: c.photoUrl, size: 70),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(c.business),
                    const SizedBox(height: 5),
                    Text(
                      c.discount,
                      style: const TextStyle(
                        color: AppColors.goldFoil,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(label: 'Categoría', value: c.category),
          _InfoRow(label: 'ID', value: c.id),
          _InfoRow(label: 'Token-id', value: c.tokenId),
          _InfoRow(label: 'Vence', value: c.expiresAt),
          _InfoRow(label: 'Capturas', value: '${c.capturesCount}/${c.maxCaptures}'),
          _InfoRow(label: 'Disponibles', value: c.remainingCaptures.toString()),
          const SizedBox(height: 14),
          _buildStatusBox(c),
          const SizedBox(height: 12),
          if (!c.canRedeem)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    c.status == CouponUserStatus.redeemed
                        ? 'Cupón ya canjeado'
                        : c.status == CouponUserStatus.expired
                            ? 'Cupón vencido'
                            : 'Cupón dado de baja',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<_RedeemMethod>(
                tooltip: 'Elegir método de canje',
                onSelected: onPickMethod,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _RedeemMethod.qr,
                    child: Row(
                      children: [
                        Icon(Icons.qr_code_2, size: 18),
                        SizedBox(width: 10),
                        Text('Código QR'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _RedeemMethod.barcode,
                    child: Row(
                      children: [
                        Icon(Icons.barcode_reader, size: 18),
                        SizedBox(width: 10),
                        Text('Código de barras'),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.inkTeal,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Canjear con QR o número de barras',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ================================================================
// ESTADO
// ================================================================

class _StatusBox extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool success;

  const _StatusBox({
    required this.text,
    required this.icon,
    this.success = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = success ? Colors.green : AppColors.stampCoral;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// FOTO DEL CUPÓN
// ================================================================

class _CouponPhoto extends StatelessWidget {
  final String? photoUrl;
  final double size;

  const _CouponPhoto({required this.photoUrl, this.size = 56});

  @override
  Widget build(BuildContext context) {
    Widget fallback() => Icon(
          Icons.storefront,
          color: Colors.grey.shade500,
          size: size * 0.5,
        );

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.shade200,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: photoUrl == null
          ? fallback()
          : Image.network(
              photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback(),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;

                return Center(
                  child: SizedBox(
                    width: size * 0.4,
                    height: size * 0.4,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            ),
    );
  }
}

// ================================================================
// INFO ROW
// ================================================================

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// PANTALLA PREVIA DE CAPTURA
// ================================================================

class _CaptureCouponScreen extends StatelessWidget {
  final Coupon coupon;
  final Position currentPosition;

  const _CaptureCouponScreen({
    required this.coupon,
    required this.currentPosition,
  });

  Future<void> _abrirCamaraRA(BuildContext context) async {
    final photo = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (_) => _ARCaptureScreen(
          coupon: coupon,
          currentPosition: currentPosition,
        ),
      ),
    );

    if (photo != null && context.mounted) {
      Navigator.pop(context, photo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final businessLocation = coupon.latitude != null && coupon.longitude != null
        ? LatLng(coupon.latitude!, coupon.longitude!)
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Capturar cupón')),
      body: SafeArea(
        child: Column(
          children: [
            // Mapa del negocio
            Expanded(
              flex: 2,
              child: businessLocation != null
                  ? FlutterMap(
                      options: MapOptions(
                        initialCenter: businessLocation,
                        initialZoom: 18,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.cuponapp.app',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: businessLocation,
                              width: 60,
                              height: 60,
                              child: const Icon(
                                Icons.location_on,
                                color: AppColors.stampCoral,
                                size: 55,
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Container(
                      color: Colors.grey.shade200,
                      alignment: Alignment.center,
                      child: const Text(
                        'Este cupón no tiene ubicación registrada.',
                      ),
                    ),
            ),

            // Información + botón
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              coupon.name,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              coupon.business,
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              coupon.discount,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: AppColors.goldFoil,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _InfoRow(
                              label: 'Tus capturas',
                              value:
                                  '${coupon.capturesCount}/${coupon.maxCaptures}',
                            ),
                            _InfoRow(
                              label: 'Disponibles',
                              value: coupon.remainingCaptures.toString(),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Tu ubicación actual:\n'
                                '${currentPosition.latitude.toStringAsFixed(6)}, '
                                '${currentPosition.longitude.toStringAsFixed(6)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Acércate a la ubicación del negocio y captura una fotografía del cupón.',
                              style: TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () => _abrirCamaraRA(context),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text(
                          'ABRIR CÁMARA',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// PANTALLA DE CAPTURA EN "REALIDAD AUMENTADA"
// ================================================================
//
// Muestra la cámara en vivo con el cupón flotando encima, como en un
// juego de "cazar" criaturas. IMPORTANTE — esto es una aproximación
// con GPS + brújula (el mismo truco que usan la mayoría de apps de
// RA basadas en ubicación): no es un anclaje 3D real como el que
// daría ARCore/ARKit, así que la posición del cupón en pantalla es
// aproximada.
//
// Requiere en pubspec.yaml:
//   camera, flutter_compass, geolocator
// y el permiso de cámara (iOS: NSCameraUsageDescription en Info.plist).

class _ARCaptureScreen extends StatefulWidget {
  final Coupon coupon;
  final Position currentPosition;

  const _ARCaptureScreen({
    required this.coupon,
    required this.currentPosition,
  });

  @override
  State<_ARCaptureScreen> createState() => _ARCaptureScreenState();
}

class _ARCaptureScreenState extends State<_ARCaptureScreen> {
  CameraController? _cameraController;
  Future<void>? _initFuture;
  StreamSubscription<CompassEvent>? _compassSub;
  double? _heading;
  bool _taking = false;
  String? _cameraError;

  // Para componer la foto real + el cupón y guardarlo como una sola imagen.
  final GlobalKey _captureKey = GlobalKey();
  File? _frozenPhoto;

  double? get _bearingToCoupon {
    final c = widget.coupon;
    if (c.latitude == null || c.longitude == null) return null;

    return Geolocator.bearingBetween(
      widget.currentPosition.latitude,
      widget.currentPosition.longitude,
      c.latitude!,
      c.longitude!,
    );
  }

  double? get _distanceToCoupon {
    final c = widget.coupon;
    if (c.latitude == null || c.longitude == null) return null;

    return Geolocator.distanceBetween(
      widget.currentPosition.latitude,
      widget.currentPosition.longitude,
      c.latitude!,
      c.longitude!,
    );
  }

  @override
  void initState() {
    super.initState();
    _initFuture = _initCamera();
    _compassSub = FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      setState(() => _heading = event.heading);
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() => _cameraController = controller);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cameraError = 'No se pudo acceder a la cámara.');
    }
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  /// Toma la foto real con la cámara (`takePicture`), la congela en
  /// pantalla, dibuja el cupón encima y captura esa composición. Como
  /// el RepaintBoundary ya no contiene el CameraPreview (que sale negro
  /// en muchos Android), la imagen guardada sí incluye la foto y el cupón.
  Future<void> _tomarFoto() async {
    final controller = _cameraController;
    if (_taking || controller == null || !controller.value.isInitialized) {
      return;
    }

    setState(() => _taking = true);

    try {
      final shot = await controller.takePicture();
      if (!mounted) return;

      final photo = File(shot.path);
      await precacheImage(FileImage(photo), context);
      if (!mounted) return;
      setState(() => _frozenPhoto = photo);

      // Espera a que Flutter pinte la composición.
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;

      File result = photo; // respaldo: la foto sola
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 2.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          final out = File('${shot.path}_cupon.png');
          await out.writeAsBytes(bytes.buffer.asUint8List());
          result = out;
        }
      }

      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _taking = false;
        _frozenPhoto = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo tomar la foto. Intenta de nuevo.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Cazar cupón',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (_cameraError != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _cameraError!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final controller = _cameraController;
          if (controller == null || !controller.value.isInitialized) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              if (_frozenPhoto == null) ...[
                CameraPreview(controller),
                _buildArOverlay(context),
              ] else
                RepaintBoundary(
                  key: _captureKey,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(_frozenPhoto!, fit: BoxFit.cover),
                      _buildArOverlay(context),
                    ],
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 30,
                child: Center(
                  child: GestureDetector(
                    onTap: _tomarFoto,
                    child: Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: AppColors.stampCoral,
                          width: 4,
                        ),
                      ),
                      child: _taking
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : const Icon(
                              Icons.camera_alt,
                              size: 32,
                              color: Colors.black87,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Superpone el cupón sobre la vista de cámara, desplazado según
  /// hacia dónde apunte el teléfono (rumbo GPS hacia el negocio vs.
  /// dirección de la brújula). El HUD (marco de esquinas + insignia de
  /// distancia) se dibuja siempre; solo cambia lo que hay al centro.
  Widget _buildArOverlay(BuildContext context) {
    final bearing = _bearingToCoupon;
    final heading = _heading;
    final distance = _distanceToCoupon;

    Widget hud(Widget center) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const _ArCornerFrame(),
          Center(child: center),
          if (distance != null) _ArDistanceBadge(distanceMeters: distance),
        ],
      );
    }

    if (bearing == null || heading == null) {
      return hud(_FloatingCouponBubble(coupon: widget.coupon));
    }

    var diff = (bearing - heading) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    const fieldOfView = 60.0;
    final width = MediaQuery.of(context).size.width;

    if (diff.abs() > fieldOfView / 2) {
      return hud(_ArTurnIndicator(turnRight: diff > 0));
    }

    final dx = (diff / (fieldOfView / 2)) * (width / 2 - 60);

    return hud(
      Transform.translate(
        offset: Offset(dx, 0),
        child: _FloatingCouponBubble(coupon: widget.coupon),
      ),
    );
  }
}

// ================================================================
// HUD DE REALIDAD AUMENTADA
// ================================================================

/// Marco de esquinas estilo "visor táctico", para dar sensación de
/// escaneo profesional sobre la vista de cámara.
class _ArCornerFrame extends StatelessWidget {
  const _ArCornerFrame();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 90, 24, 130),
        child: CustomPaint(
          painter: _ArCornerPainter(),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ArCornerPainter extends CustomPainter {
  const _ArCornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.goldFoil.withOpacity(0.9)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 26.0;

    // Superior izquierda
    canvas.drawLine(Offset.zero, const Offset(len, 0), paint);
    canvas.drawLine(Offset.zero, const Offset(0, len), paint);
    // Superior derecha
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - len, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, len), paint);
    // Inferior izquierda
    canvas.drawLine(Offset(0, size.height), Offset(len, size.height), paint);
    canvas.drawLine(
      Offset(0, size.height),
      Offset(0, size.height - len),
      paint,
    );
    // Inferior derecha
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - len, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - len),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Insignia superior con la distancia en línea recta hasta el cupón.
class _ArDistanceBadge extends StatelessWidget {
  final double distanceMeters;

  const _ArDistanceBadge({required this.distanceMeters});

  @override
  Widget build(BuildContext context) {
    final label = distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
        : '${distanceMeters.toStringAsFixed(0)} m';

    return Positioned(
      top: 18,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppColors.goldFoil.withOpacity(0.7)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.gps_fixed, size: 14, color: AppColors.goldFoil),
              const SizedBox(width: 6),
              Text(
                'A $label del cupón',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Indicador de giro con brillo pulsante, para cuando el cupón está
/// fuera del campo de visión de la cámara.
class _ArTurnIndicator extends StatefulWidget {
  final bool turnRight;

  const _ArTurnIndicator({required this.turnRight});

  @override
  State<_ArTurnIndicator> createState() => _ArTurnIndicatorState();
}

class _ArTurnIndicatorState extends State<_ArTurnIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final glow = 0.35 + (_controller.value * 0.35);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.stampCoral.withOpacity(0.25),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.stampCoral.withOpacity(glow),
                    blurRadius: 26,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                widget.turnRight
                    ? Icons.arrow_forward_ios
                    : Icons.arrow_back_ios,
                color: Colors.white,
                size: 36,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                widget.turnRight ? 'Gira a la derecha' : 'Gira a la izquierda',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Burbuja flotante con la foto del cupón — ahora una tarjeta
/// "holográfica" que gira en 3D sobre su eje, con anillos de energía
/// pulsando alrededor y un destello que la recorre, además del vaivén
/// original (como un objeto de juego flotando esperando a ser atrapado).
class _FloatingCouponBubble extends StatefulWidget {
  final Coupon coupon;

  const _FloatingCouponBubble({required this.coupon});

  @override
  State<_FloatingCouponBubble> createState() => _FloatingCouponBubbleState();
}

class _FloatingCouponBubbleState extends State<_FloatingCouponBubble>
    with TickerProviderStateMixin {
  // Vaivén vertical, como antes.
  late final AnimationController _floatController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  late final Animation<double> _float = Tween<double>(begin: -10, end: 10)
      .animate(
        CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
      );

  // Giro 3D tipo holograma sobre el eje vertical de la tarjeta.
  late final AnimationController _rotationController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  // Anillos de energía y destello.
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _floatController.dispose();
    _rotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coupon = widget.coupon;

    return AnimatedBuilder(
      animation: _float,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _float.value),
        child: child,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 190,
            height: 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _EnergyRing(controller: _pulseController, delay: 0.0),
                _EnergyRing(controller: _pulseController, delay: 0.5),
                AnimatedBuilder(
                  animation: _rotationController,
                  builder: (context, _) {
                    final angle = _rotationController.value * 2 * math.pi;
                    // Entre 90° y 270° se ve la cara trasera del
                    // "holograma"; se compensa el ángulo para que no se
                    // muestre invertida.
                    final showBack =
                        angle > math.pi / 2 && angle < 3 * math.pi / 2;
                    final displayAngle = showBack ? angle - math.pi : angle;

                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0012)
                        ..rotateY(displayAngle),
                      child: showBack
                          ? _HologramBack(coupon: coupon)
                          : _CouponFace(coupon: coupon),
                    );
                  },
                ),
                // Destello: usa Transform.translate en lugar de un margin
                // (un margin negativo lanzaba el error del cuadro rojo).
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, _) => ClipOval(
                      child: Opacity(
                        opacity: 0.35,
                        child: Transform.translate(
                          offset: Offset(
                            (150 * _pulseController.value) - 75,
                            0,
                          ),
                          child: Transform.rotate(
                            angle: -0.6,
                            child: Container(
                              width: 36,
                              height: 190,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(0),
                                    Colors.white.withOpacity(0.9),
                                    Colors.white.withOpacity(0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.inkTeal, AppColors.stampCoral],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.inkTeal.withOpacity(0.5),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  coupon.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Anillo de energía que se expande y se desvanece, en bucle. Dos
/// instancias con distinto `delay` dan el efecto de "ondas" continuas
/// alrededor de la tarjeta.
class _EnergyRing extends StatelessWidget {
  final AnimationController controller;
  final double delay;

  const _EnergyRing({required this.controller, required this.delay});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = (controller.value + delay) % 1.0;
        final size = 128 + (62 * t);
        final opacity = (1 - t).clamp(0.0, 1.0) * 0.55;

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.goldFoil.withOpacity(opacity),
              width: 2.5,
            ),
          ),
        );
      },
    );
  }
}

/// Cara frontal de la tarjeta-holograma: la foto real del cupón con un
/// borde degradado dorado y sombra "flotante" para dar volumen.
class _CouponFace extends StatelessWidget {
  final Coupon coupon;

  const _CouponFace({required this.coupon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      height: 130,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.goldFoil, Colors.white, AppColors.stampCoral],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.goldFoil.withOpacity(0.6),
            blurRadius: 20,
            spreadRadius: 2,
          ),
          const BoxShadow(color: Colors.black45, blurRadius: 12),
        ],
      ),
      child: ClipOval(
        child: _CouponPhoto(photoUrl: coupon.photoUrl, size: 122),
      ),
    );
  }
}

/// Cara trasera del "holograma": se ve un instante al girar la
/// tarjeta, mostrando el descuento como si fuera una moneda de dos
/// caras.
class _HologramBack extends StatelessWidget {
  final Coupon coupon;

  const _HologramBack({required this.coupon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      height: 130,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            AppColors.inkTeal.withOpacity(0.95),
            AppColors.inkTeal.withOpacity(0.6),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.8), width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.inkTeal.withOpacity(0.7),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_offer, color: Colors.white, size: 22),
          const SizedBox(height: 4),
          Text(
            coupon.discount,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// PANEL DE CANJE (código QR / de barras)
// ================================================================
//
// Se usa en "Mis cupones": una vez que ya capturaste el cupón (con
// la cámara en modo RA), lo canjeas en el negocio mostrando este
// código QR o de barras al empleado.

class _RedeemPanel extends StatelessWidget {
  final Coupon coupon;
  final _RedeemMethod method;
  final VoidCallback onCancel;

  const _RedeemPanel({
    required this.coupon,
    required this.method,
    required this.onCancel,
  });

  // Código real que se escanea/teclea al canjear: el de ESTA captura
  // del usuario (único, distinto para cada persona que capturó el
  // mismo cupón). Ya no hay respaldo con el token-id del cupón: el
  // servidor solo canjea con el código de la captura.
  String get _token => coupon.captureCode ?? '';

  @override
  Widget build(BuildContext context) {
    final hasToken = _token.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(
                  method == _RedeemMethod.qr
                      ? Icons.qr_code_2
                      : Icons.barcode_reader,
                  color: AppColors.inkTeal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    method == _RedeemMethod.qr
                        ? 'Canjear con código QR'
                        : 'Canjear con código de barras',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _CouponPhoto(photoUrl: coupon.photoUrl, size: 44),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${coupon.name} · ${coupon.business}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (!hasToken)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Este cupón aún no tiene código de canje. '
                  'Cierra este panel y actualiza la lista.',
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              Center(
                child: method == _RedeemMethod.qr
                    ? _QrCode(token: _token)
                    : _BarcodeCode(token: _token),
              ),
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    Text(
                      'Código de canje',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      _token,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: onCancel,
              child: const Text('CERRAR'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Código QR real y escaneable, generado a partir del código de canje.
class _QrCode extends StatelessWidget {
  final String token;

  const _QrCode({required this.token});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(12),
      ),
      child: QrImageView(
        data: token,
        size: 180,
        backgroundColor: Colors.white,
      ),
    );
  }
}

/// Código de barras real y escaneable (Code128), generado a partir
/// del código de canje.
class _BarcodeCode extends StatelessWidget {
  final String token;

  const _BarcodeCode({required this.token});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(12),
      ),
      child: bw.BarcodeWidget(
        barcode: bw.Barcode.code128(),
        data: token,
        width: 220,
        height: 90,
        drawText: false,
      ),
    );
  }
}