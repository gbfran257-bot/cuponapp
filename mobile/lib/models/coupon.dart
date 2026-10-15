/// Categorías de cupón usadas tanto en el alta (panel de administrador)
/// como en el filtro de la app del usuario final.
const List<String> kCouponCategories = [
  'Comida y bebida',
  'Belleza y cuidado personal',
  'Entretenimiento',
  'Servicios',
  'Salud',
  'Restaurantes',
  'Ropa',
  'Tecnología',
  'Viajes',
  'Deportes',
  'Supermercados',
  'Hogar',
  'Otro',
];

/// Estado de UN cupón capturado, desde el punto de vista del usuario
/// final — usado para el resumen y los filtros de "Mis cupones".
/// Prioridad: canjeado > vencido > inactivo > pendiente.
enum CouponUserStatus { pending, redeemed, expired, inactive }

const Map<CouponUserStatus, String> kCouponUserStatusLabels = {
  CouponUserStatus.pending: 'Por canjear',
  CouponUserStatus.redeemed: 'Canjeados',
  CouponUserStatus.expired: 'Vencidos',
  CouponUserStatus.inactive: 'Dados de baja',
};

/// Cupón, tal como lo entrega el backend (CouponController.php).
///
/// Los campos `captureCode`, `capturePhotoUrl`, `redeemed` y
/// `redeemedAt` solo vienen llenos en /coupons/mine (GET_MY_COUPONS) —
/// en /coupons (catálogo) y en la respuesta de /coupons/capture llegan
/// como null/false, porque ahí no hay todavía (o no aplica) una captura
/// propia con código de canje.
class Coupon {
  final String id; // "C-001" (formateado, solo para mostrar)
  final String numericId;
  final String tokenId;
  final String name;
  final String business;
  final String discount;
  // 'producto' | 'porcentaje' | 'dinero'
  final String couponType;
  final String expiresAt; // dd/mm/aaaa
  final String expiresAtIso;
  final String category;
  final String? photoUrl;
  final double? latitude;
  final double? longitude;
  final bool active;
  final bool isExpired;

  final int maxCaptures;
  final int capturesCount;
  final int remainingCaptures;
  final int redeemedCount; // veces que el cupón se canjeó en total

  // Disponibilidad PARA ESTE usuario en particular.
  final bool captureAvailable;
  final bool alreadyCaptured;

  // Propios de "Mis cupones" (ver nota de la clase).
  final String? captureCode;
  final String? capturePhotoUrl; // foto que tomó el usuario al capturar
  final bool redeemed;
  final String? redeemedAt;

  const Coupon({
    required this.id,
    required this.numericId,
    required this.tokenId,
    required this.name,
    required this.business,
    required this.discount,
    this.couponType = 'porcentaje',
    required this.expiresAt,
    this.expiresAtIso = '',
    required this.category,
    this.photoUrl,
    this.latitude,
    this.longitude,
    this.active = true,
    this.isExpired = false,
    this.maxCaptures = 1,
    this.capturesCount = 0,
    this.remainingCaptures = 1,
    this.redeemedCount = 0,
    this.captureAvailable = false,
    this.alreadyCaptured = false,
    this.captureCode,
    this.capturePhotoUrl,
    this.redeemed = false,
    this.redeemedAt,
  });

  /// Estado de ESTA captura del usuario, para el resumen y los
  /// filtros de "Mis cupones". Solo tiene sentido cuando el cupón
  /// viene de /coupons/mine (alreadyCaptured == true).
  CouponUserStatus get status {
    if (redeemed) return CouponUserStatus.redeemed;
    if (isExpired) return CouponUserStatus.expired;
    if (!active) return CouponUserStatus.inactive;
    return CouponUserStatus.pending;
  }

  /// true solo si el usuario todavía puede mostrar su QR / código de
  /// barras en el negocio.
  bool get canRedeem => status == CouponUserStatus.pending;

  factory Coupon.fromJson(Map<String, dynamic> json) => Coupon(
        id: json['id'].toString(),
        numericId: json['numericId']?.toString() ?? '',
        tokenId: json['tokenId'].toString(),
        name: json['name']?.toString() ?? '',
        business: json['business']?.toString() ?? '',
        discount: json['discount']?.toString() ?? '',
        couponType: json['couponType'] as String? ?? 'porcentaje',
        expiresAt: json['expiresAt'] as String? ?? '',
        expiresAtIso: json['expiresAtIso'] as String? ?? '',
        category: json['category'] as String? ?? 'Otro',
        photoUrl: json['photoUrl'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        active: json['active'] as bool? ?? true,
        isExpired: json['isExpired'] as bool? ?? false,
        maxCaptures: (json['maxCaptures'] as num?)?.toInt() ?? 1,
        capturesCount: (json['capturesCount'] as num?)?.toInt() ?? 0,
        remainingCaptures: (json['remainingCaptures'] as num?)?.toInt() ?? 1,
        redeemedCount: (json['redeemedCount'] as num?)?.toInt() ?? 0,
        captureAvailable: json['captureAvailable'] as bool? ?? false,
        alreadyCaptured: json['alreadyCaptured'] as bool? ?? false,
        captureCode: json['captureCode'] as String?,
        capturePhotoUrl: json['capturePhotoUrl'] as String?,
        redeemed: json['redeemed'] as bool? ?? false,
        redeemedAt: json['redeemedAt'] as String?,
      );

  Coupon copyWith({
    int? capturesCount,
    int? remainingCaptures,
    bool? captureAvailable,
    bool? alreadyCaptured,
    bool? redeemed,
    String? redeemedAt,
  }) {
    return Coupon(
      id: id,
      numericId: numericId,
      tokenId: tokenId,
      name: name,
      business: business,
      discount: discount,
      couponType: couponType,
      expiresAt: expiresAt,
      expiresAtIso: expiresAtIso,
      category: category,
      photoUrl: photoUrl,
      latitude: latitude,
      longitude: longitude,
      active: active,
      isExpired: isExpired,
      maxCaptures: maxCaptures,
      capturesCount: capturesCount ?? this.capturesCount,
      remainingCaptures: remainingCaptures ?? this.remainingCaptures,
      redeemedCount: redeemedCount,
      captureAvailable: captureAvailable ?? this.captureAvailable,
      alreadyCaptured: alreadyCaptured ?? this.alreadyCaptured,
      captureCode: captureCode,
      capturePhotoUrl: capturePhotoUrl,
      redeemed: redeemed ?? this.redeemed,
      redeemedAt: redeemedAt ?? this.redeemedAt,
    );
  }
}