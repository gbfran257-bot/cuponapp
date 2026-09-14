/// Roles disponibles en la app.
///
/// TODO: cuando conectemos el backend (Laravel), este valor debe venir
/// del response de POST /api/login, por ejemplo:
///   { "user": {...}, "role": "administrador" }
/// y se parsea con UserRole.fromString(json['role']).
enum UserRole {
  usuario,
  administrador,
  superAdministrador;

  static UserRole fromString(String value) {
    switch (value.trim().toLowerCase()) {
      case 'administrador':
      case 'admin':
        return UserRole.administrador;
      case 'super_administrador':
      case 'superadministrador':
      case 'super_admin':
      case 'superadmin':
        return UserRole.superAdministrador;
      case 'usuario':
      default:
        return UserRole.usuario;
    }
  }

  /// Ruta a la que debe navegar cada rol justo después del login.
  String get homeRoute {
    switch (this) {
      case UserRole.usuario:
        return '/home';
      case UserRole.administrador:
        return '/admin';
      case UserRole.superAdministrador:
        return '/super-admin';
    }
  }
}
