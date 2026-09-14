/// Categorías disponibles para los cupones. Es la ÚNICA lista de
/// categorías de la app — tanto el formulario de alta de cupones
/// (admin_screen.dart) como el filtro de categorías
/// (categoria_cupones_screen.dart) la usan, para que un cupón dado de
/// alta con una categoría siempre pueda encontrarse filtrando por
/// esa misma categoría.
const List<String> kCouponCategories = [
  'Comida y bebida',
  'Belleza y cuidado personal',
  'Entretenimiento',
  'Servicios',
  'Salud',
  'Otro',
];

/// Igual que [kCouponCategories] pero con "Todos" al inicio, para el
/// modo filtro de categoria_cupones_screen.dart (permite quitar el
/// filtro y ver todos los cupones de nuevo).
const List<String> kCouponFilterCategories = ['Todos', ...kCouponCategories];

/// Modelo de cupón usado en la app del usuario final.
class Coupon {
  final String id;
  final String tokenId;
  final String name;
  final String business;
  final String discount;
  final String expiresAt;
  final String category;
  final String? photoUrl;
  final double? latitude;
  final double? longitude;
  final bool active;
  final int maxCaptures;
  final int capturesCount;
  final int remainingCaptures;
  final bool captureAvailable;
  final bool alreadyCaptured;

  const Coupon({
    required this.id,
    required this.tokenId,
    required this.name,
    required this.business,
    required this.discount,
    required this.expiresAt,
    required this.category,
    this.photoUrl,
    this.latitude,
    this.longitude,
    this.active = true,
    this.maxCaptures = 1,
    this.capturesCount = 0,
    this.remainingCaptures = 1,
    this.captureAvailable = true,
    this.alreadyCaptured = false,
  });

  /// Copia el cupón cambiando solo los campos indicados. Se usa en
  /// home_screen.dart para actualizar la UI al instante justo
  /// después de capturar, sin esperar la respuesta del servidor.
  Coupon copyWith({
    int? capturesCount,
    int? remainingCaptures,
    bool? captureAvailable,
    bool? alreadyCaptured,
  }) {
    return Coupon(
      id: id,
      tokenId: tokenId,
      name: name,
      business: business,
      discount: discount,
      expiresAt: expiresAt,
      category: category,
      photoUrl: photoUrl,
      latitude: latitude,
      longitude: longitude,
      active: active,
      maxCaptures: maxCaptures,
      capturesCount: capturesCount ?? this.capturesCount,
      remainingCaptures: remainingCaptures ?? this.remainingCaptures,
      captureAvailable: captureAvailable ?? this.captureAvailable,
      alreadyCaptured: alreadyCaptured ?? this.alreadyCaptured,
    );
  }

  /// Mapea el JSON que devuelve GET /api/coupons o /api/coupons/mine
  /// (ver CouponController::formatForUser en el backend).
  factory Coupon.fromJson(Map<String, dynamic> json) {
    return Coupon(
      id: json['id'] as String,
      tokenId: json['tokenId'] as String,
      name: json['name'] as String,
      business: json['business'] as String,
      discount: json['discount'] as String,
      expiresAt: json['expiresAt'] as String? ?? '',
      category: json['category'] as String? ?? 'Otro',
      photoUrl: json['photoUrl'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      active: json['active'] as bool? ?? true,
      maxCaptures: (json['maxCaptures'] as num?)?.toInt() ?? 1,
      capturesCount: (json['capturesCount'] as num?)?.toInt() ?? 0,
      remainingCaptures: (json['remainingCaptures'] as num?)?.toInt() ?? 1,
      captureAvailable: json['captureAvailable'] as bool? ?? true,
      alreadyCaptured: json['alreadyCaptured'] as bool? ?? false,
    );
  }
}