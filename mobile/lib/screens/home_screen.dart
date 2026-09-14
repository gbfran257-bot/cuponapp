import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';
import '../models/coupon.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _MenuOption {
  inicio,
  cupones,
  regresar,
}

enum _RedeemMethod { qr, barcode }

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  List<Coupon> _coupons = [];

  List<Coupon> _myCoupons = [];

  bool _loadingCoupons = false;

  bool _loadingMyCoupons = false;

  String? _loadError;

  String _selectedCategory = 'Todos';

  Position? _currentPosition;

  final Map<String, File> _capturedCouponPhotos = {};

  @override
  void initState() {
    super.initState();

    _loadCoupons();

    _loadMyCoupons();
  }

  // ============================================================
  // CUPONES DISPONIBLES
  // ============================================================

  Future<void> _loadCoupons({
    Position? position,
    String? category,
  }) async {
    if (mounted) {
      setState(() {
        _loadingCoupons = true;
      });
    }

    try {
      final data = await apiService.getCoupons(
        latitude: position?.latitude,
        longitude: position?.longitude,
        category: category,
      );

      final coupons = <Coupon>[];

      for (final item in data) {
        if (item is Map) {
          coupons.add(
            Coupon.fromJson(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }

      if (!mounted) return;

      setState(() {
        _coupons = coupons;
        _loadError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;

      setState(() {
        _loadError = e.message;
      });

      _showMsg(
        e.message,
        error: true,
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loadError =
            'No se pudo conectar con el servidor.';
      });

      _showMsg(
        'No se pudo conectar con el servidor.',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingCoupons = false;
        });
      }
    }
  }

  // ============================================================
  // MIS CUPONES CAPTURADOS
  // ============================================================

  Future<void> _loadMyCoupons() async {
    if (mounted) {
      setState(() {
        _loadingMyCoupons = true;
      });
    }

    try {
      final data = await apiService.getMyCoupons();

      final coupons = <Coupon>[];

      for (final item in data) {
        if (item is Map) {
          coupons.add(
            Coupon.fromJson(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }

      if (!mounted) return;

      setState(() {
        _myCoupons = coupons;
      });
    } on ApiException catch (e) {
      if (!mounted) return;

      _showMsg(
        e.message,
        error: true,
      );
    } catch (_) {
      if (!mounted) return;

      _showMsg(
        'No se pudieron cargar tus cupones.',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingMyCoupons = false;
        });
      }
    }
  }

  // ============================================================
  // UBICACIÓN
  // ============================================================

  Future<Position?> _obtenerUbicacionActual() async {
    try {
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        _showMsg(
          'Activa el GPS/ubicación del dispositivo.',
          error: true,
        );

        return null;
      }

      var permission =
          await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission();

        if (permission == LocationPermission.denied) {
          _showMsg(
            'Necesitamos permiso de ubicación para continuar.',
            error: true,
          );

          return null;
        }
      }

      if (permission ==
          LocationPermission.deniedForever) {
        _showMsg(
          'El permiso de ubicación está bloqueado. Actívalo en Ajustes.',
          error: true,
        );

        return null;
      }

      final position =
          await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return null;

      setState(() {
        _currentPosition = position;
      });

      return position;
    } catch (_) {
      _showMsg(
        'No se pudo obtener tu ubicación.',
        error: true,
      );

      return null;
    }
  }

  // ============================================================
  // CUPONES CERCA
  // ============================================================

  Future<void> _buscarCerca(
    Position position,
  ) async {
    if (!mounted) return;

    setState(() {
      _currentPosition = position;
    });

    await _loadCoupons(
      position: position,
      category: _selectedCategory == 'Todos'
          ? null
          : _selectedCategory,
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
      setState(() {
        _selectedCategory = result;
      });

      await _loadCoupons(
        position: _currentPosition,
        category: result == 'Todos'
            ? null
            : result,
      );
    }
  }

  // ============================================================
  // CAPTURAR CUPÓN
  // ============================================================

  Future<void> _capturarCupon(
    Coupon coupon,
  ) async {
    // ----------------------------------------------------------
    // Comprobar si está activo
    // ----------------------------------------------------------

    if (!_couponIsActive(coupon)) {
      _showMsg(
        'Este cupón ya no está activo.',
        error: true,
      );

      return;
    }

    // ----------------------------------------------------------
    // Comprobar disponibilidad
    // ----------------------------------------------------------

    if (!_couponCaptureAvailable(coupon)) {
      final remaining =
          _couponRemainingCaptures(coupon);

      if (remaining != null) {
        _showMsg(
          remaining > 0
              ? 'Este cupón no está disponible para captura.'
              : 'Este cupón ya alcanzó el máximo de capturas.',
          error: true,
        );
      } else {
        _showMsg(
          'Este cupón no está disponible para captura.',
          error: true,
        );
      }

      return;
    }

    // ----------------------------------------------------------
    // OBTENER UBICACIÓN REAL DEL USUARIO
    // ----------------------------------------------------------

    final position =
        await _obtenerUbicacionActual();

    if (position == null) {
      return;
    }

    // ----------------------------------------------------------
    // Mostrar mapa del negocio y luego abrir la cámara en modo RA
    // (realidad aumentada): el cupón flota sobre la cámara en vivo,
    // desplazándose según hacia dónde apuntes según el rumbo GPS +
    // la brújula del teléfono.
    // ----------------------------------------------------------

    if (!mounted) return;

    final photo = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _CaptureCouponScreen(
          coupon: coupon,
          currentPosition: position,
        ),
      ),
    );

    if (photo == null) {
      return;
    }

    try {
      if (!mounted) return;

      // --------------------------------------------------------
      // Mostrar carga
      // --------------------------------------------------------

      _showLoadingMessage(
        'Guardando captura...',
      );

      // --------------------------------------------------------
      // ENVIAR FOTO + UBICACIÓN A LARAVEL
      // --------------------------------------------------------

      final response =
          await apiService.captureCoupon(
        tokenId: coupon.tokenId,
        photo: photo,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .hideCurrentSnackBar();

      // --------------------------------------------------------
      // Guardar temporalmente la foto local
      // --------------------------------------------------------

      setState(() {
        _capturedCouponPhotos[
                coupon.tokenId] =
            photo;
      });

      // --------------------------------------------------------
      // Decrementar la disponibilidad al instante (sin esperar la
      // respuesta del servidor), para que la UI se sienta inmediata.
      // El `_loadCoupons`/`_loadMyCoupons` de abajo la reconcilia
      // con el valor real que devuelva Laravel.
      // --------------------------------------------------------

      setState(() {
        _coupons = _coupons
            .map((c) => c.tokenId == coupon.tokenId
                ? _decrementCapture(c)
                : c)
            .toList();
        _myCoupons = _myCoupons
            .map((c) => c.tokenId == coupon.tokenId
                ? _decrementCapture(c)
                : c)
            .toList();
      });

      // --------------------------------------------------------
      // Actualizar ambas listas desde Laravel
      // --------------------------------------------------------

      await Future.wait([
        _loadCoupons(
          position: _currentPosition,
          category:
              _selectedCategory == 'Todos'
                  ? null
                  : _selectedCategory,
        ),
        _loadMyCoupons(),
      ]);

      if (!mounted) return;

      // --------------------------------------------------------
      // Ir a MIS CUPONES
      // --------------------------------------------------------

      setState(() {
        _tabIndex = 1;
      });

      final message =
          _extractCaptureMessage(
        response,
      );

      _showMsg(
        message ??
            'Cupón capturado correctamente 📸',
      );
    } on ApiException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .hideCurrentSnackBar();

      _showMsg(
        e.message,
        error: true,
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .hideCurrentSnackBar();

      _showMsg(
        'No se pudo guardar la captura.',
        error: true,
      );
    }
  }

  String? _extractCaptureMessage(
    Map<String, dynamic> response,
  ) {
    final value = response['message'];

    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    return text.isEmpty ? null : text;
  }

  void _showLoadingMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration:
              const Duration(minutes: 1),
          content: Row(
            children: [
              const SizedBox(
                height: 18,
                width: 18,
                child:
                    CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(
                width: 12,
              ),
              Text(message),
            ],
          ),
        ),
      );
  }

  // ============================================================
  // CAMPOS DEL MODELO
  // ============================================================

  bool _couponIsActive(
    Coupon coupon,
  ) {
    return coupon.active;
  }

  bool _couponCaptureAvailable(
    Coupon coupon,
  ) {
    return coupon.captureAvailable;
  }

  int? _couponRemainingCaptures(
    Coupon coupon,
  ) {
    return coupon.remainingCaptures;
  }

  /// Regresa una copia del cupón con una captura más contabilizada,
  /// bajando `remainingCaptures` hacia 0 (nunca negativo) y apagando
  /// `captureAvailable` cuando ya no quedan.
  Coupon _decrementCapture(Coupon c) {
    final newCount = c.capturesCount + 1;
    final newRemaining =
        (c.maxCaptures - newCount).clamp(0, c.maxCaptures);
    return c.copyWith(
      capturesCount: newCount,
      remainingCaptures: newRemaining,
      captureAvailable: newRemaining > 0,
    );
  }

  // ============================================================
  // CANJE (código QR / de barras) — sobre cupones ya capturados,
  // en la pestaña "Mis cupones".
  // ============================================================

  void _abrirPanelCanje(
    Coupon c,
    _RedeemMethod method,
  ) {
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
    );
  }

  // ============================================================
  // MENSAJES
  // ============================================================

  void _showMsg(
    String msg, {
    bool error = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor:
              error
                  ? AppColors.stampCoral
                  : null,
        ),
      );
  }

  // ============================================================
  // MENÚ
  // ============================================================

  Future<void> _onMenuSelected(
    _MenuOption option,
  ) async {
    switch (option) {
      case _MenuOption.inicio:
        setState(() {
          _tabIndex = 0;
        });
        break;

      case _MenuOption.cupones:
        setState(() {
          _tabIndex = 1;
        });

        await _loadMyCoupons();
        break;

      case _MenuOption.regresar:
        try {
          await apiService.logout();
        } catch (_) {}

        if (!mounted) return;

        Navigator.pushNamedAndRemoveUntil(
          context,
          '/',
          (route) => false,
        );

        break;
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CUPÓN APP',
        ),
        leading:
            PopupMenuButton<_MenuOption>(
          icon: const Icon(
            Icons.menu,
          ),
          color: Colors.white,
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(12),
          ),
          onSelected:
              _onMenuSelected,
          itemBuilder: (context) => [
            _buildMenuItem(
              value:
                  _MenuOption.inicio,
              icon:
                  Icons.person_outline,
              label: 'Inicio',
              selected:
                  _tabIndex == 0,
            ),
            _buildMenuItem(
              value:
                  _MenuOption.cupones,
              icon: Icons
                  .confirmation_number_outlined,
              label: 'Mis cupones',
              selected:
                  _tabIndex == 1,
            ),
            const PopupMenuDivider(),
            _buildMenuItem(
              value:
                  _MenuOption.regresar,
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
              currentPosition:
                  _currentPosition,
              loading:
                  _loadingCoupons,
              selectedCategory:
                  _selectedCategory,
              onBuscarCerca:
                  _buscarCerca,
              onElegirCategoria:
                  _elegirCategoria,
              onCaptureCoupon:
                  _capturarCupon,
            )
          : _CuponesTab(
              coupons: _myCoupons,
              loading:
                  _loadingMyCoupons,
              error: _loadError,
              capturedPhotos:
                  _capturedCouponPhotos,
              onRetry:
                  _loadMyCoupons,
              onPickMethod:
                  _abrirPanelCanje,
            ),
    );
  }

  PopupMenuItem<_MenuOption>
      _buildMenuItem({
    required _MenuOption value,
    required IconData icon,
    required String label,
    bool selected = false,
    bool destructive = false,
  }) {
    final color = destructive
        ? AppColors.stampCoral
        : AppColors.inkTeal;

    return PopupMenuItem<_MenuOption>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: color,
          ),
          const SizedBox(
            width: 12,
          ),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: selected
                  ? FontWeight.w800
                  : FontWeight.w600,
            ),
          ),
          if (selected) ...[
            const Spacer(),
            Icon(
              Icons.check,
              size: 18,
              color: color,
            ),
          ],
        ],
      ),
    );
  }
}

// ================================================================
// INICIO
// ================================================================

class _InicioTab
    extends StatefulWidget {
  final List<Coupon> coupons;

  final Position? currentPosition;

  final bool loading;

  final String selectedCategory;

  final Future<void> Function(
    Position position,
  ) onBuscarCerca;

  final VoidCallback
      onElegirCategoria;

  final Future<void> Function(
    Coupon coupon,
  ) onCaptureCoupon;

  const _InicioTab({
    required this.coupons,
    required this.currentPosition,
    required this.loading,
    required this.selectedCategory,
    required this.onBuscarCerca,
    required this.onElegirCategoria,
    required this.onCaptureCoupon,
  });

  @override
  State<_InicioTab> createState() =>
      _InicioTabState();
}

class _InicioTabState
    extends State<_InicioTab> {
  final _searchCtrl =
      TextEditingController();

  final MapController _mapController =
      MapController();

  bool _loadingLocation = false;

  static const _defaultCenter =
      LatLng(
    18.6560,
    -99.1953,
  );

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void>
      _obtenerUbicacionActual() async {
    setState(() {
      _loadingLocation = true;
    });

    try {
      final serviceEnabled =
          await Geolocator
              .isLocationServiceEnabled();

      if (!serviceEnabled) {
        _showMsg(
          'Activa el GPS/ubicación del dispositivo.',
        );
        return;
      }

      var permission =
          await Geolocator
              .checkPermission();

      if (permission ==
          LocationPermission.denied) {
        permission =
            await Geolocator
                .requestPermission();

        if (permission ==
            LocationPermission.denied) {
          _showMsg(
            'Necesitamos permiso de ubicación para continuar.',
          );
          return;
        }
      }

      if (permission ==
          LocationPermission.deniedForever) {
        _showMsg(
          'Permiso denegado permanentemente. Actívalo en Ajustes.',
        );
        return;
      }

      final position =
          await Geolocator
              .getCurrentPosition(
        locationSettings:
            const LocationSettings(
          accuracy:
              LocationAccuracy.high,
        ),
      );

      if (!mounted) return;

      setState(() {
        _loadingLocation = false;
      });

      _mapController.move(
        LatLng(
          position.latitude,
          position.longitude,
        ),
        16,
      );

      await widget.onBuscarCerca(
        position,
      );
    } catch (_) {
      _showMsg(
        'No se pudo obtener la ubicación.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingLocation = false;
        });
      }
    }
  }

  Future<void>
      _buscarCuponesCerca() async {
    final position =
        widget.currentPosition ??
            await _obtenerPosition();

    if (position == null) {
      return;
    }

    await widget.onBuscarCerca(
      position,
    );
  }

  Future<Position?>
      _obtenerPosition() async {
    try {
      final serviceEnabled =
          await Geolocator
              .isLocationServiceEnabled();

      if (!serviceEnabled) {
        _showMsg(
          'Activa el GPS.',
        );
        return null;
      }

      var permission =
          await Geolocator
              .checkPermission();

      if (permission ==
          LocationPermission.denied) {
        permission =
            await Geolocator
                .requestPermission();
      }

      if (permission ==
              LocationPermission.denied ||
          permission ==
              LocationPermission
                  .deniedForever) {
        _showMsg(
          'No tenemos permiso de ubicación.',
        );
        return null;
      }

      return Geolocator
          .getCurrentPosition(
        locationSettings:
            const LocationSettings(
          accuracy:
              LocationAccuracy.high,
        ),
      );
    } catch (_) {
      _showMsg(
        'No se pudo obtener la ubicación.',
      );

      return null;
    }
  }

  void _showMsg(
    String msg,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(msg),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final center =
        widget.currentPosition != null
            ? LatLng(
                widget.currentPosition!
                    .latitude,
                widget.currentPosition!
                    .longitude,
              )
            : _defaultCenter;

    final markers = <Marker>[
      if (widget.currentPosition !=
          null)
        Marker(
          point: LatLng(
            widget.currentPosition!
                .latitude,
            widget.currentPosition!
                .longitude,
          ),
          width: 40,
          height: 40,
          child: const Icon(
            Icons.person_pin_circle,
            color: AppColors.inkTeal,
            size: 40,
          ),
        ),
      ...widget.coupons
          .where(
            (c) =>
                c.latitude != null &&
                c.longitude != null,
          )
          .map(
            (c) => Marker(
              point: LatLng(
                c.latitude!,
                c.longitude!,
              ),
              width: 42,
              height: 56,
              child: _CouponMarkerIcon(
                coupon: c,
                onTap: () {
                  _mostrarCapturar(
                    context,
                    c,
                  );
                },
              ),
            ),
          ),
    ];

    return Padding(
      padding:
          const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchCtrl,
            decoration:
                const InputDecoration(
              hintText:
                  'Buscar cupones o negocios',
              prefixIcon:
                  Icon(Icons.search),
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          if (widget.selectedCategory !=
              'Todos')
            Padding(
              padding:
                  const EdgeInsets.only(
                bottom: 10,
              ),
              child: Align(
                alignment:
                    Alignment.centerLeft,
                child: InputChip(
                  label: Text(
                    'Categoría: ${widget.selectedCategory}',
                  ),
                  onDeleted:
                      widget.onElegirCategoria,
                  deleteIcon:
                      const Icon(
                    Icons.close,
                    size: 16,
                  ),
                ),
              ),
            ),

          OutlinedButton.icon(
            onPressed:
                _loadingLocation
                    ? null
                    : _obtenerUbicacionActual,
            icon: _loadingLocation
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.my_location,
                    size: 18,
                  ),
            label: const Text(
              'Ubicación actual',
            ),
          ),

          const SizedBox(
            height: 10,
          ),

          Row(
            children: [
              Expanded(
                child:
                    ElevatedButton.icon(
                  onPressed:
                      widget.loading
                          ? null
                          : _buscarCuponesCerca,
                  icon: widget.loading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                            color:
                                Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons
                              .near_me_outlined,
                          size: 18,
                        ),
                  label: const Text(
                    'Cupones cerca',
                  ),
                ),
              ),

              const SizedBox(
                width: 10,
              ),

              Expanded(
                child:
                    ElevatedButton.icon(
                  onPressed:
                      widget.onElegirCategoria,
                  icon: const Icon(
                    Icons.category_outlined,
                    size: 18,
                  ),
                  label: const Text(
                    'Por categoría',
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 16,
          ),

          Expanded(
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(14),
              child: FlutterMap(
                mapController:
                    _mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 14,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName:
                        'com.cuponapp.app',
                  ),
                  MarkerLayer(
                    markers: markers,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarCapturar(
    BuildContext context,
    Coupon coupon,
  ) {
    final available =
        coupon.captureAvailable;

    final remaining =
        coupon.remainingCaptures;

    showModalBottomSheet(
      context: context,
      shape:
          const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return Padding(
          padding:
              const EdgeInsets.fromLTRB(
            20,
            20,
            20,
            28,
          ),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _CouponPhoto(
                    photoUrl:
                        coupon.photoUrl,
                    size: 60,
                  ),

                  const SizedBox(
                    width: 12,
                  ),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Text(
                          coupon.name,
                          style:
                              const TextStyle(
                            fontWeight:
                                FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          coupon.business,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: 12,
              ),

              _InfoRow(
                label: 'Descuento',
                value:
                    coupon.discount,
              ),

              _InfoRow(
                label: 'Categoría',
                value:
                    coupon.category,
              ),

              _InfoRow(
                label: 'Capturas',
                value:
                    '${coupon.capturesCount}/${coupon.maxCaptures}',
              ),

              _InfoRow(
                label: 'Disponibles',
                value:
                    remaining.toString(),
              ),

              const SizedBox(
                height: 12,
              ),

              if (!coupon.active)
                const _StatusBox(
                  text:
                      'Este cupón está inactivo.',
                  icon:
                      Icons.pause_circle,
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

              const SizedBox(
                height: 12,
              ),

              SizedBox(
                width:
                    double.infinity,
                child:
                    ElevatedButton.icon(
                  onPressed:
                      !coupon.active ||
                              !available
                          ? null
                          : () {
                              Navigator.pop(
                                context,
                              );

                              widget
                                  .onCaptureCoupon(
                                coupon,
                              );
                            },
                  icon: const Icon(
                    Icons.camera_alt,
                  ),
                  label: const Text(
                    'CAZAR CUPÓN',
                  ),
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

class _CouponMarkerIcon
    extends StatelessWidget {
  final Coupon coupon;

  final VoidCallback onTap;

  const _CouponMarkerIcon({
    required this.coupon,
    required this.onTap,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final available =
        coupon.active &&
            coupon.captureAvailable;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            clipBehavior:
                Clip.antiAlias,
            decoration:
                const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 4,
                ),
              ],
            ),
            child:
                coupon.photoUrl == null
                    ? Container(
                        color: available
                            ? AppColors
                                .inkTeal
                            : Colors.grey,
                        child:
                            const Icon(
                          Icons.local_offer,
                          color:
                              Colors.white,
                          size: 16,
                        ),
                      )
                    : Image.network(
                        coupon.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) =>
                                Container(
                          color: available
                              ? AppColors
                                  .inkTeal
                              : Colors.grey,
                          child:
                              const Icon(
                            Icons
                                .local_offer,
                            color:
                                Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
          ),

          const Icon(
            Icons.arrow_drop_down,
            size: 20,
            color:
                AppColors.stampCoral,
          ),
        ],
      ),
    );
  }
}

// ================================================================
// MIS CUPONES
// ================================================================

class _CuponesTab
    extends StatelessWidget {
  final List<Coupon> coupons;

  final bool loading;

  final String? error;

  final Future<void> Function()
      onRetry;

  final void Function(
    Coupon coupon,
    _RedeemMethod method,
  ) onPickMethod;

  final Map<String, File>
      capturedPhotos;

  const _CuponesTab({
    required this.coupons,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onPickMethod,
    required this.capturedPhotos,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    if (loading && coupons.isEmpty) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    if (error != null &&
        coupons.isEmpty) {
      return Center(
        child: Padding(
          padding:
              const EdgeInsets.all(24),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              Text(
                error!,
                textAlign:
                    TextAlign.center,
              ),

              const SizedBox(
                height: 16,
              ),

              ElevatedButton(
                onPressed: onRetry,
                child: const Text(
                  'Reintentar',
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (coupons.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRetry,
        child: ListView(
          children: const [
            SizedBox(
              height: 120,
            ),
            Center(
              child: Text(
                'Aún no tienes cupones capturados.',
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView.builder(
        padding:
            const EdgeInsets.all(16),
        itemCount: coupons.length,
        itemBuilder: (context, i) {
          final c = coupons[i];

          return Padding(
            padding:
                const EdgeInsets.only(
              bottom: 12,
            ),
            child: _CouponCard(
              coupon: c,
              capturedPhoto:
                  capturedPhotos[
                      c.tokenId],
              onPickMethod: (method) =>
                  onPickMethod(c, method),
            ),
          );
        },
      ),
    );
  }
}

// ================================================================
// TARJETA
// ================================================================

class _CouponCard
    extends StatelessWidget {
  final Coupon coupon;

  final File? capturedPhoto;

  final void Function(_RedeemMethod) onPickMethod;

  const _CouponCard({
    required this.coupon,
    required this.capturedPhoto,
    required this.onPickMethod,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final c = coupon;

    final available =
        c.active &&
            c.captureAvailable;

    return Container(
      decoration:
          BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      padding:
          const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          if (capturedPhoto != null)
            Container(
              width:
                  double.infinity,
              height: 190,
              margin:
                  const EdgeInsets.only(
                bottom: 14,
              ),
              clipBehavior:
                  Clip.antiAlias,
              decoration:
                  BoxDecoration(
                borderRadius:
                    BorderRadius.circular(
                  12,
                ),
              ),
              child: Image.file(
                capturedPhoto!,
                fit: BoxFit.cover,
              ),
            ),

          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              _CouponPhoto(
                photoUrl: c.photoUrl,
                size: 70,
              ),

              const SizedBox(
                width: 12,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      c.name,
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),

                    const SizedBox(
                      height: 4,
                    ),

                    Text(
                      c.business,
                    ),

                    const SizedBox(
                      height: 5,
                    ),

                    Text(
                      c.discount,
                      style:
                          const TextStyle(
                        color:
                            AppColors
                                .goldFoil,
                        fontWeight:
                            FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 12,
          ),

          _InfoRow(
            label: 'Categoría',
            value: c.category,
          ),

          _InfoRow(
            label: 'ID',
            value: c.id,
          ),

          _InfoRow(
            label: 'Token-id',
            value: c.tokenId,
          ),

          _InfoRow(
            label: 'Vence',
            value: c.expiresAt,
          ),

          _InfoRow(
            label: 'Capturas',
            value:
                '${c.capturesCount}/${c.maxCaptures}',
          ),

          _InfoRow(
            label: 'Disponibles',
            value:
                c.remainingCaptures
                    .toString(),
          ),

          const SizedBox(
            height: 14,
          ),

          if (!c.active)
            const _StatusBox(
              text:
                  'Cupón inactivo.',
              icon:
                  Icons.pause_circle,
            )
          else if (c.alreadyCaptured)
            const _StatusBox(
              text: 'Ya capturaste este cupón.',
              icon: Icons.check_circle,
              success: true,
            )
          else if (!available)
            _StatusBox(
              text:
                  c.remainingCaptures <=
                          0
                      ? 'Este cupón alcanzó el máximo de capturas.'
                      : 'Este cupón no está disponible para captura.',
              icon: Icons.block,
            )
          else if (capturedPhoto != null)
            const _StatusBox(
              text:
                  'Cupón capturado correctamente.',
              icon:
                  Icons.check_circle,
              success: true,
            ),

          const SizedBox(
            height: 12,
          ),

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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
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

class _StatusBox
    extends StatelessWidget {
  final String text;

  final IconData icon;

  final bool success;

  const _StatusBox({
    required this.text,
    required this.icon,
    this.success = false,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final color = success
        ? Colors.green
        : AppColors.stampCoral;

    return Container(
      width:
          double.infinity,
      padding:
          const EdgeInsets.all(10),
      decoration:
          BoxDecoration(
        color:
            color.withOpacity(0.10),
        borderRadius:
            BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: color,
            size: 20,
          ),

          const SizedBox(
            width: 8,
          ),

          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontWeight:
                    FontWeight.w700,
              ),
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

class _CouponPhoto
    extends StatelessWidget {
  final String? photoUrl;

  final double size;

  const _CouponPhoto({
    required this.photoUrl,
    this.size = 56,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: size,
      height: size,
      clipBehavior:
          Clip.antiAlias,
      decoration:
          BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.shade200,
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: photoUrl == null
          ? Icon(
              Icons.storefront,
              color:
                  Colors.grey.shade500,
              size: size * 0.5,
            )
          : Image.network(
              photoUrl!,
              fit: BoxFit.cover,
              errorBuilder:
                  (_, __, ___) =>
                      Icon(
                Icons.storefront,
                color:
                    Colors.grey.shade500,
                size: size * 0.5,
              ),
              loadingBuilder:
                  (
                context,
                child,
                progress,
              ) {
                if (progress == null) {
                  return child;
                }

                return Center(
                  child: SizedBox(
                    width:
                        size * 0.4,
                    height:
                        size * 0.4,
                    child:
                        const CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
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

class _InfoRow
    extends StatelessWidget {
  final String label;

  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(
        top: 3,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color:
                    Colors.grey.shade600,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),

          Expanded(
            child: Text(
              value,
              style:
                  const TextStyle(
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// PANTALLA PREVIA DE CAPTURA
// ================================================================

class _CaptureCouponScreen
    extends StatelessWidget {
  final Coupon coupon;

  final Position currentPosition;

  const _CaptureCouponScreen({
    required this.coupon,
    required this.currentPosition,
  });

  Future<void> _abrirCamaraRA(
    BuildContext context,
  ) async {
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
  Widget build(
    BuildContext context,
  ) {
    final businessLocation =
        coupon.latitude != null &&
                coupon.longitude != null
            ? LatLng(
                coupon.latitude!,
                coupon.longitude!,
              )
            : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Capturar cupón',
        ),
      ),

      body: SafeArea(
        child: Column(
          children: [

            // ======================================================
            // MAPA
            // ======================================================

            Expanded(
              flex: 2,
              child:
                  businessLocation != null
                      ? FlutterMap(
                          options:
                              MapOptions(
                            initialCenter:
                                businessLocation,
                            initialZoom: 18,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName:
                                  'com.cuponapp.app',
                            ),

                            MarkerLayer(
                              markers: [
                                Marker(
                                  point:
                                      businessLocation,
                                  width: 60,
                                  height: 60,
                                  child:
                                      const Icon(
                                    Icons
                                        .location_on,
                                    color:
                                        AppColors
                                            .stampCoral,
                                    size: 55,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Container(
                          color:
                              Colors.grey.shade200,
                          alignment:
                              Alignment.center,
                          child:
                              const Text(
                            'Este cupón no tiene ubicación registrada.',
                          ),
                        ),
            ),

            // ======================================================
            // INFORMACIÓN + BOTÓN
            // ======================================================

            Expanded(
              flex: 3,
              child: Container(
                width:
                    double.infinity,
                padding:
                    const EdgeInsets
                        .fromLTRB(
                  20,
                  16,
                  20,
                  10,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .stretch,
                  children: [

                    // ==================================================
                    // INFORMACIÓN DESPLAZABLE
                    // ==================================================

                    Expanded(
                      child:
                          SingleChildScrollView(
                        physics:
                            const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .stretch,
                          children: [

                            // ==================================================
                            // NOMBRE DEL CUPÓN
                            // ==================================================

                            Text(
                              coupon.name,
                              style:
                                  const TextStyle(
                                fontSize: 22,
                                fontWeight:
                                    FontWeight.w900,
                              ),
                            ),

                            const SizedBox(
                              height: 4,
                            ),

                            // ==================================================
                            // NEGOCIO
                            // ==================================================

                            Text(
                              coupon.business,
                              style:
                                  const TextStyle(
                                fontSize: 16,
                              ),
                            ),

                            const SizedBox(
                              height: 10,
                            ),

                            // ==================================================
                            // DESCUENTO
                            // ==================================================

                            Text(
                              coupon.discount,
                              style:
                                  const TextStyle(
                                fontSize: 24,
                                fontWeight:
                                    FontWeight.w900,
                                color:
                                    AppColors
                                        .goldFoil,
                              ),
                            ),

                            const SizedBox(
                              height: 10,
                            ),

                            // ==================================================
                            // CAPTURAS
                            // ==================================================

                            _InfoRow(
                              label:
                                  'Tus capturas',
                              value:
                                  '${coupon.capturesCount}/${coupon.maxCaptures}',
                            ),

                            // ==================================================
                            // DISPONIBLES
                            // ==================================================

                            _InfoRow(
                              label:
                                  'Disponibles',
                              value:
                                  coupon
                                      .remainingCaptures
                                      .toString(),
                            ),

                            const SizedBox(
                              height: 10,
                            ),

                            // ==================================================
                            // UBICACIÓN ACTUAL
                            // ==================================================

                            Container(
                              padding:
                                  const EdgeInsets
                                      .all(
                                10,
                              ),
                              decoration:
                                  BoxDecoration(
                                color: Colors
                                    .grey
                                    .shade100,
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                  10,
                                ),
                              ),
                              child: Text(
                                'Tu ubicación actual:\n'
                                '${currentPosition.latitude.toStringAsFixed(6)}, '
                                '${currentPosition.longitude.toStringAsFixed(6)}',
                                style:
                                    const TextStyle(
                                  fontSize: 12,
                                ),
                              ),
                            ),

                            const SizedBox(
                              height: 10,
                            ),

                            // ==================================================
                            // INSTRUCCIÓN
                            // ==================================================

                            const Text(
                              'Acércate a la ubicación del negocio y captura una fotografía del cupón.',
                              style:
                                  TextStyle(
                                fontSize: 14,
                              ),
                            ),

                            const SizedBox(
                              height: 12,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ==================================================
                    // BOTÓN SIEMPRE VISIBLE
                    // ==================================================

                    const SizedBox(
                      height: 8,
                    ),

                    SizedBox(
                      height: 52,
                      child:
                          ElevatedButton.icon(
                        onPressed: () {
                          _abrirCamaraRA(context);
                        },
                        icon: const Icon(
                          Icons.camera_alt,
                        ),
                        label: const Text(
                          'ABRIR CÁMARA',
                          style: TextStyle(
                            fontWeight:
                                FontWeight.w800,
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
// aproximada, no "exacta" al centímetro.
//
// Requiere agregar a pubspec.yaml (si no los tienes ya):
//   camera: ^0.10.6
//   flutter_compass: ^0.8.1
// y los permisos de cámara habituales (Android ya los trae el
// plugin `camera`; iOS necesita NSCameraUsageDescription en
// Info.plist, que probablemente ya tengas por el flujo anterior).

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

  // Clave para poder "fotografiar" exactamente lo que se ve en
  // pantalla (cámara en vivo + la burbuja del cupón encima), en vez
  // de solo lo que capta el sensor de la cámara.
  final GlobalKey _captureKey = GlobalKey();

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
    } catch (e) {
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

  /// En vez de usar `controller.takePicture()` (que solo guarda lo
  /// que ve el sensor), tomamos una "captura de pantalla" del
  /// RepaintBoundary que envuelve la cámara + la burbuja del cupón,
  /// para que la foto final incluya ambas cosas tal como se ven.
  Future<void> _tomarFoto() async {
    if (_taking) return;
    setState(() => _taking = true);
    try {
      // Pequeña espera para asegurar que el frame actual ya se
      // terminó de pintar antes de capturarlo.
      await Future.delayed(const Duration(milliseconds: 20));

      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('No se pudo preparar la captura.');
      }

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('No se pudo generar la imagen.');
      }
      final bytes = byteData.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/cupon_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      Navigator.pop(context, file);
    } catch (_) {
      if (!mounted) return;
      setState(() => _taking = false);
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
              // Todo lo que va DENTRO de este RepaintBoundary es lo
              // que queda grabado en la foto final (cámara + cupón
              // flotando encima). El botón de disparo queda AFUERA
              // a propósito, para que no salga en la imagen.
              RepaintBoundary(
                key: _captureKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(controller),
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
                        border:
                            Border.all(color: AppColors.stampCoral, width: 4),
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
  /// dirección de la brújula) — la misma aproximación que usan los
  /// juegos de "cazar" con RA basados en ubicación.
  Widget _buildArOverlay(BuildContext context) {
    final bearing = _bearingToCoupon;
    final heading = _heading;

    if (bearing == null || heading == null) {
      return Center(child: _FloatingCouponBubble(coupon: widget.coupon));
    }

    var diff = (bearing - heading) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    const fieldOfView = 60.0;
    final width = MediaQuery.of(context).size.width;

    if (diff.abs() > fieldOfView / 2) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              diff > 0 ? Icons.arrow_forward_ios : Icons.arrow_back_ios,
              color: Colors.white,
              size: 40,
            ),
            const SizedBox(height: 8),
            Text(
              diff > 0 ? 'Gira a la derecha' : 'Gira a la izquierda',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    final dx = (diff / (fieldOfView / 2)) * (width / 2 - 60);
    return Align(
      alignment: Alignment.center,
      child: Transform.translate(
        offset: Offset(dx, 0),
        child: _FloatingCouponBubble(coupon: widget.coupon),
      ),
    );
  }
}

/// Burbuja flotante con la foto del cupón, con un ligero vaivén
/// (como un personaje flotando esperando a ser atrapado).
class _FloatingCouponBubble extends StatefulWidget {
  final Coupon coupon;

  const _FloatingCouponBubble({required this.coupon});

  @override
  State<_FloatingCouponBubble> createState() => _FloatingCouponBubbleState();
}

class _FloatingCouponBubbleState extends State<_FloatingCouponBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);
  late final Animation<double> _float = Tween<double>(begin: -10, end: 10)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
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
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 12),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: _CouponPhoto(photoUrl: coupon.photoUrl, size: 130),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              coupon.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
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

  // El token real de canje es el token-id del cupón (no el ID interno).
  String get _token => coupon.tokenId;

  @override
  Widget build(BuildContext context) {
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
            Center(
              child: method == _RedeemMethod.qr
                  ? _QrPlaceholder(token: _token)
                  : _BarcodePattern(token: _token),
            ),
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  Text(
                    'Token / Clave',
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

/// Espacio reservado para el QR real.
///
/// TODO: agrega el paquete `qr_flutter` a pubspec.yaml y reemplaza este
/// widget por:
///   QrImageView(data: token, size: 180)
/// QR real y escaneable, generado a partir del token del cupón.
class _QrPlaceholder extends StatelessWidget {
  final String token;
  const _QrPlaceholder({required this.token});

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

/// Patrón visual tipo código de barras, generado a partir del token
/// (no es un código de barras real/escaneable, solo referencia visual).
///
/// TODO: si necesitas que sea escaneable de verdad, agrega el paquete
/// `barcode_widget` y reemplaza este widget por un BarcodeWidget real.
/// Código de barras real y escaneable (Code128), generado a partir
/// del token del cupón.
class _BarcodePattern extends StatelessWidget {
  final String token;
  const _BarcodePattern({required this.token});

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