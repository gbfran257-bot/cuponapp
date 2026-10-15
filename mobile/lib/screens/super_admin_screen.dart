import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'contract_screen.dart';

/// ─────────────────────────────────────────────────────────────
/// Modelos locales para el panel de súper admin, poblados con
/// datos reales del backend.
/// ─────────────────────────────────────────────────────────────
class Business {
  final String id;
  String name;
  bool active;
  String? adminId;
  String? adminName;
  String address;
  String phone;
  double commissionProduct;
  double commissionPercent;
  double commissionMoney;
  String contactName;
  String contactEmail;
  String rfc;
  String description;

  Business({
    required this.id,
    required this.name,
    this.active = true,
    this.adminId,
    this.adminName,
    this.address = '',
    this.phone = '',
    this.commissionProduct = 0,
    this.commissionPercent = 0,
    this.commissionMoney = 0,
    this.contactName = '',
    this.contactEmail = '',
    this.rfc = '',
    this.description = '',
  });

  static double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  factory Business.fromJson(Map<String, dynamic> json) => Business(
        id: json['id'].toString(),
        name: json['name'] as String,
        active: json['active'] as bool? ?? true,
        adminId: json['adminId']?.toString(),
        adminName: json['adminName'] as String?,
        address: json['address'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        commissionProduct: _d(json['commissionProduct']),
        commissionPercent: _d(json['commissionPercent']),
        commissionMoney: _d(json['commissionMoney']),
        contactName: json['contactName'] as String? ?? '',
        contactEmail: json['contactEmail'] as String? ?? '',
        rfc: json['rfc'] as String? ?? '',
        description: json['description'] as String? ?? '',
      );
}

class AdminUser {
  final String id;
  String name;
  String email;
  bool active;

  AdminUser({
    required this.id,
    required this.name,
    required this.email,
    this.active = true,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: json['id'].toString(),
        name: json['name'] as String,
        email: json['email'] as String,
        active: json['active'] as bool? ?? true,
      );
}

class AppUser {
  final String id;
  String name;
  String email;
  bool active;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.active = true,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'].toString(),
        name: json['name'] as String,
        email: json['email'] as String,
        active: json['active'] as bool? ?? true,
      );
}

class _CouponSummary {
  final String name;
  final String business;
  const _CouponSummary(this.name, this.business);

  factory _CouponSummary.fromJson(Map<String, dynamic> json) =>
      _CouponSummary(json['name'] as String, json['business'] as String);
}

class _RedemptionSummary {
  final String couponName;
  final String business;
  final String date;
  const _RedemptionSummary(this.couponName, this.business, this.date);

  factory _RedemptionSummary.fromJson(Map<String, dynamic> json) =>
      _RedemptionSummary(
        json['couponName'] as String,
        json['business'] as String,
        json['date'] as String,
      );
}

class _StatDetail {
  final String title;
  final String subtitle;
  const _StatDetail(this.title, [this.subtitle = '']);
}

String _money(double v) => '\$${v.toStringAsFixed(2)}';

double _asDouble(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

/// Subtítulo que se muestra debajo de cada tarjeta del Panorama.
const Map<String, String> _statSubtitles = {
  'Negocios activos': 'Ver negocios',
  'Administradores': 'Ver administradores',
  'Usuarios': 'Ver usuarios',
  'Cupones activos': 'Ver cupones',
  'Cupones canjeados (mes)': 'Ver y marcar pagados',
  'Ganancias del mes': 'Comisiones pagadas del mes',
  'Ganancias totales': 'Comisiones pagadas',
};

class _EarningsRow {
  final String title;
  final String detail;
  final int count;
  final double total;
  const _EarningsRow(this.title, this.detail, this.count, this.total);
}

class _EarningsPeriod {
  final double total;
  final int count;
  final List<_EarningsRow> byType;
  final List<_EarningsRow> byBusiness;

  const _EarningsPeriod({
    required this.total,
    required this.count,
    required this.byType,
    required this.byBusiness,
  });

  factory _EarningsPeriod.fromJson(Map<String, dynamic> j) {
    const typeLabels = {
      'producto': 'Cupón por producto',
      'porcentaje': 'Cupón con descuento en %',
      'dinero': 'Cupón con descuento en \$',
    };
    return _EarningsPeriod(
      total: _asDouble(j['total']),
      count: (j['count'] as num?)?.toInt() ?? 0,
      byType: (j['byType'] as List).map((t) {
        final m = t as Map<String, dynamic>;
        return _EarningsRow(
          typeLabels[m['type']] ?? m['type'].toString(),
          '',
          (m['count'] as num?)?.toInt() ?? 0,
          _asDouble(m['total']),
        );
      }).toList(),
      byBusiness: (j['byBusiness'] as List).map((b) {
        final m = b as Map<String, dynamic>;
        return _EarningsRow(
          m['name'].toString(),
          'Admin: ${m['adminName'] ?? 'Sin asignar'}',
          (m['count'] as num?)?.toInt() ?? 0,
          _asDouble(m['total']),
        );
      }).toList(),
    );
  }

  static String _canjes(int n) => '$n canje${n == 1 ? '' : 's'}';

  List<_StatDetail> toDetails() {
    return [
      _StatDetail('Total: ${_money(total)}', _canjes(count)),
      const _StatDetail('— Por tipo de cupón —'),
      ...byType.map(
        (r) => _StatDetail(r.title, '${_canjes(r.count)} · ${_money(r.total)}'),
      ),
      const _StatDetail('— Por negocio —'),
      ...byBusiness.map(
        (r) => _StatDetail(
          r.title,
          '${r.detail} · ${_canjes(r.count)} · ${_money(r.total)}',
        ),
      ),
    ];
  }
}

class _Earnings {
  final _EarningsPeriod month;
  final _EarningsPeriod all;
  const _Earnings(this.month, this.all);

  factory _Earnings.fromJson(Map<String, dynamic> j) => _Earnings(
        _EarningsPeriod.fromJson(j['month'] as Map<String, dynamic>),
        _EarningsPeriod.fromJson(j['all'] as Map<String, dynamic>),
      );
}

class SuperAdminScreen extends StatefulWidget {
  const SuperAdminScreen({super.key});

  @override
  State<SuperAdminScreen> createState() => _SuperAdminScreenState();
}

class _SuperAdminScreenState extends State<SuperAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Índices de pestaña, usados para saltar directo desde el Panorama.
  static const int _tabPanorama = 0;
  static const int _tabBusinesses = 1;
  static const int _tabAdmins = 2;
  static const int _tabUsers = 3;

  bool _loading = true;
  String? _loadError;

  Map<String, String> _stats = {};
  List<_CouponSummary> _activeCoupons = [];
  List<_RedemptionSummary> _redeemedThisMonth = [];
  List<Business> _businesses = [];
  List<AdminUser> _admins = [];
  List<AppUser> _users = [];
  _Earnings? _earnings;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final statsData = await apiService.getSuperAdminStats();
      final businessesData = await apiService.getBusinesses();
      final adminsData = await apiService.getAdmins();
      final usersData = await apiService.getUsers();
      final earnings = _Earnings.fromJson(await apiService.getEarnings());

      final stats = Map<String, String>.from(statsData['stats'] as Map);
      stats['Usuarios'] = usersData.length.toString();
      stats['Ganancias del mes'] = _money(earnings.month.total);
      stats['Ganancias totales'] = _money(earnings.all.total);

      setState(() {
        _earnings = earnings;
        _stats = stats;
        _activeCoupons = (statsData['activeCoupons'] as List)
            .map((c) => _CouponSummary.fromJson(c as Map<String, dynamic>))
            .toList();
        _redeemedThisMonth = (statsData['redeemedThisMonth'] as List)
            .map((r) => _RedemptionSummary.fromJson(r as Map<String, dynamic>))
            .toList();
        _businesses = businessesData
            .map((b) => Business.fromJson(b as Map<String, dynamic>))
            .toList();
        _admins = adminsData
            .map((a) => AdminUser.fromJson(a as Map<String, dynamic>))
            .toList();
        _users = usersData
            .map((u) => AppUser.fromJson(u as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('Error en _loadAll: $e\n$st');
      setState(() {
        _loadError = 'Error al cargar los datos: $e';
        _loading = false;
      });
    }
  }

  void _logout() {
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  // ── Negocios ─────────────────────────────────────────────────

  Future<void> _addBusiness() async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _BusinessFormDialog(
        title: 'Agregar negocio',
        admins: _admins.where((a) => a.active).toList(),
      ),
    );
    if (data == null) return;
    try {
      await apiService.createBusiness(data);
      await _loadAll();
      _showMsg('Negocio agregado ✅');
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  Future<void> _editBusiness(Business business) async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _BusinessFormDialog(
        title: 'Editar negocio',
        business: business,
        admins: _admins.where((a) => a.active).toList(),
      ),
    );
    if (data == null) return;
    try {
      await apiService.updateBusiness(business.id, data);
      await _loadAll();
      _showMsg('Negocio actualizado ✅');
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  Future<void> _toggleBusinessActive(Business business) async {
    try {
      await apiService.toggleBusinessStatus(business.id);
      await _loadAll();
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  Future<void> _removeBusiness(Business business) async {
    final confirmed = await _confirmRemove(
      title: 'Eliminar negocio',
      message:
          '¿Eliminar "${business.name}"? Sus cupones quedarán sin negocio asignado.',
    );
    if (confirmed != true) return;
    try {
      await apiService.deleteBusiness(business.id);
      await _loadAll();
      _showMsg('Negocio eliminado');
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  // ── Administradores ─────────────────────────────────────────

  Future<void> _addAdmin() async {
    final result = await showDialog<_PersonFormResult>(
      context: context,
      builder: (context) => const _PersonFormDialog(
        title: 'Agregar administrador',
      ),
    );
    if (result == null) return;
    try {
      await apiService.createAdmin(
        name: result.name,
        email: result.email,
        password: result.password,
      );
      await _loadAll();
      _showMsg('Administrador agregado ✅');
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  Future<void> _editAdmin(AdminUser admin) async {
    final result = await showDialog<_PersonFormResult>(
      context: context,
      builder: (context) => _PersonFormDialog(
        title: 'Editar administrador',
        initialName: admin.name,
        initialEmail: admin.email,
      ),
    );
    if (result == null) return;
    try {
      await apiService.updateAdmin(
        id: admin.id,
        name: result.name,
        email: result.email,
        password: result.password.isEmpty ? null : result.password,
      );
      await _loadAll();
      _showMsg('Administrador actualizado ✅');
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  Future<void> _toggleAdminActive(AdminUser admin) async {
    try {
      await apiService.toggleAdminStatus(admin.id);
      await _loadAll();
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  Future<void> _removeAdmin(AdminUser admin) async {
    final confirmed = await _confirmRemove(
      title: 'Quitar administrador',
      message: '¿Quitar a "${admin.name}" como administrador?',
    );
    if (confirmed != true) return;
    try {
      await apiService.deleteAdmin(admin.id);
      await _loadAll();
      _showMsg('Administrador eliminado');
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  // ── Usuarios ─────────────────────────────────────────────────

  Future<void> _addUser() async {
    final result = await showDialog<_PersonFormResult>(
      context: context,
      builder: (context) => const _PersonFormDialog(
        title: 'Agregar usuario',
      ),
    );
    if (result == null) return;
    try {
      await apiService.createUser(
        name: result.name,
        email: result.email,
        password: result.password,
      );
      await _loadAll();
      _showMsg('Usuario agregado ✅');
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  Future<void> _editUser(AppUser user) async {
    final result = await showDialog<_PersonFormResult>(
      context: context,
      builder: (context) => _PersonFormDialog(
        title: 'Editar usuario',
        initialName: user.name,
        initialEmail: user.email,
      ),
    );
    if (result == null) return;
    try {
      await apiService.updateUser(
        id: user.id,
        name: result.name,
        email: result.email,
        password: result.password.isEmpty ? null : result.password,
      );
      await _loadAll();
      _showMsg('Usuario actualizado ✅');
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  Future<void> _toggleUserActive(AppUser user) async {
    try {
      await apiService.toggleUserStatus(user.id);
      await _loadAll();
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  Future<void> _removeUser(AppUser user) async {
    final confirmed = await _confirmRemove(
      title: 'Eliminar usuario',
      message: '¿Eliminar a "${user.name}" como usuario?',
    );
    if (confirmed != true) return;
    try {
      await apiService.deleteUser(user.id);
      await _loadAll();
      _showMsg('Usuario eliminado');
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────

  Future<bool?> _confirmRemove({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(color: Colors.black)),
        content: Text(message, style: const TextStyle(color: Colors.black)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Quitar',
              style: TextStyle(color: AppColors.stampCoral),
            ),
          ),
        ],
      ),
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

  /// Al tocar una tarjeta del Panorama: si tiene su propia pestaña con
  /// CRUD (Negocios, Administradores, Usuarios), salta directo ahí.
  /// Si no (Cupones activos / canjeados), abre el detalle de solo
  /// lectura por ahora.
  void _onStatTap(String title, List<_StatDetail> readOnlyItems) {
    switch (title) {
      case 'Negocios activos':
        _tabController.animateTo(_tabBusinesses);
        return;
      case 'Administradores':
        _tabController.animateTo(_tabAdmins);
        return;
      case 'Usuarios':
        _tabController.animateTo(_tabUsers);
        return;
      case 'Cupones canjeados (mes)':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const _RedemptionsScreen()),
        ).then((_) {
          // Al volver, recargamos para reflejar en Ganancias lo que
          // se marcó como pagado.
          if (mounted) _loadAll();
        });
        return;
      default:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _StatDetailScreen(title: title, items: readOnlyItems),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Súper administrador')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadAll,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final statDetails = <String, List<_StatDetail>>{
      'Cupones activos': _activeCoupons
          .map((c) => _StatDetail(c.name, c.business))
          .toList(),
      'Cupones canjeados (mes)': _redeemedThisMonth
          .map((r) => _StatDetail(r.couponName, '${r.business} · ${r.date}'))
          .toList(),
      'Ganancias del mes': _earnings?.month.toDetails() ?? [],
      'Ganancias totales': _earnings?.all.toDetails() ?? [],
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Súper administrador'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Colors.black,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Panorama'),
            Tab(icon: Icon(Icons.storefront_outlined), text: 'Negocios'),
            Tab(
              icon: Icon(Icons.admin_panel_settings_outlined),
              text: 'Administradores',
            ),
            Tab(icon: Icon(Icons.people_outline), text: 'Usuarios'),
            Tab(icon: Icon(Icons.description_outlined), text: 'Contratos'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadAll,
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
          _OverviewTab(
            stats: _stats,
            details: statDetails,
            onOpenDetail: _onStatTap,
          ),
          _BusinessesTab(
            businesses: _businesses,
            onAdd: _addBusiness,
            onEdit: _editBusiness,
            onToggleActive: _toggleBusinessActive,
            onRemove: _removeBusiness,
          ),
          _PeopleTab<AdminUser>(
            emptyLabel: 'Aún no hay administradores.',
            addLabel: 'Agregar admin',
            people: _admins,
            nameOf: (a) => a.name,
            emailOf: (a) => a.email,
            activeOf: (a) => a.active,
            onAdd: _addAdmin,
            onEdit: _editAdmin,
            onToggleActive: _toggleAdminActive,
            onRemove: _removeAdmin,
          ),
          _PeopleTab<AppUser>(
            emptyLabel: 'Aún no hay usuarios.',
            addLabel: 'Agregar usuario',
            people: _users,
            nameOf: (u) => u.name,
            emailOf: (u) => u.email,
            activeOf: (u) => u.active,
            onAdd: _addUser,
            onEdit: _editUser,
            onToggleActive: _toggleUserActive,
            onRemove: _removeUser,
          ),
          const ContractsScreen(),
        ],
      ),
    );
  }
}

/// ───────────────────────── TAB: PANORAMA ─────────────────────────

class _OverviewTab extends StatelessWidget {
  final Map<String, String> stats;
  final Map<String, List<_StatDetail>> details;
  final void Function(String title, List<_StatDetail> readOnlyItems) onOpenDetail;

  const _OverviewTab({
    required this.stats,
    required this.details,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    final entries = stats.entries.toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        // Tarjetas compactas de alto fijo: se adaptan al ancho de la
        // pantalla (2 columnas en celular, más en escritorio) y nunca
        // se desbordan.
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          mainAxisExtent: 96,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final e = entries[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onOpenDetail(e.key, details[e.key] ?? const []),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300, width: 1.5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    e.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.inkTeal,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    e.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _statSubtitles[e.key] ?? 'Ver detalle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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

/// ─────────────── CANJES DEL MES + BOTÓN "PAGADO" ───────────────

const Map<String, String> _couponTypeShort = {
  'producto': 'Producto',
  'porcentaje': 'Porcentaje (%)',
  'dinero': 'Dinero (\$)',
};

class _RedemptionRow {
  final int id;
  final String couponName;
  final String business;
  final String adminName;
  final String? couponType; // null = canje anterior al sistema de comisiones
  final double commission;
  final String date;
  final bool paid;

  const _RedemptionRow({
    required this.id,
    required this.couponName,
    required this.business,
    required this.adminName,
    required this.couponType,
    required this.commission,
    required this.date,
    required this.paid,
  });

  factory _RedemptionRow.fromJson(Map<String, dynamic> j) => _RedemptionRow(
        id: (j['id'] as num).toInt(),
        couponName: j['couponName'].toString(),
        business: j['business']?.toString() ?? '',
        adminName: j['adminName']?.toString() ?? 'Sin asignar',
        couponType: j['couponType'] as String?,
        commission: _asDouble(j['commission']),
        date: j['date'].toString(),
        paid: j['paid'] as bool? ?? false,
      );
}

class _RedemptionsScreen extends StatefulWidget {
  const _RedemptionsScreen();

  @override
  State<_RedemptionsScreen> createState() => _RedemptionsScreenState();
}

class _RedemptionsScreenState extends State<_RedemptionsScreen> {
  bool _loading = true;
  String? _error;
  List<_RedemptionRow> _rows = [];
  int? _payingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await apiService.getMonthRedemptions();
      if (!mounted) return;
      setState(() {
        _rows = data
            .map((r) => _RedemptionRow.fromJson(r as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error al cargar los canjes: $e';
        _loading = false;
      });
    }
  }

  void _showMsg(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.stampCoral : null,
      ),
    );
  }

  Future<void> _markPaid(_RedemptionRow r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Marcar como pagado',
          style: TextStyle(color: Colors.black),
        ),
        content: Text(
          '¿Ya se pagó la comisión de "${r.couponName}" '
          '(${_money(r.commission)})?\n\n'
          'Al confirmar, se sumará a las ganancias.',
          style: const TextStyle(color: Colors.black),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
            child: const Text('Pagado'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _payingId = r.id);
    try {
      await apiService.markRedemptionPaid(r.id.toString());
      await _load(silent: true);
      _showMsg('Marcado como pagado ✅');
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    } finally {
      if (mounted) setState(() => _payingId = null);
    }
  }

  Widget _trailing(_RedemptionRow r) {
    if (r.couponType == null) {
      return Text(
        'Sin comisión',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      );
    }
    if (r.paid) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 18),
          SizedBox(width: 4),
          Text(
            'Pagado',
            style: TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }
    if (_payingId == r.id) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.2),
      );
    }
    return ElevatedButton(
      onPressed: () => _markPaid(r),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      child: const Text('Pagado'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _rows
        .where((r) => r.couponType != null && !r.paid)
        .fold<double>(0, (sum, r) => sum + r.commission);
    final paid = _rows
        .where((r) => r.paid)
        .fold<double>(0, (sum, r) => sum + r.commission);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cupones canjeados (mes)'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        'Por cobrar: ${_money(pending)}   ·   '
                        'Pagado: ${_money(paid)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _rows.isEmpty
                          ? const Center(
                              child: Text('No hay canjes este mes.'),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _rows.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final r = _rows[i];
                                return ListTile(
                                  isThreeLine: r.couponType != null,
                                  title: Text(
                                    r.couponName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${r.business} · Admin: ${r.adminName}\n'
                                    '${r.date}'
                                    '${r.couponType == null ? '' : '\nTipo: ${_couponTypeShort[r.couponType] ?? r.couponType} · Comisión: ${_money(r.commission)}'}',
                                  ),
                                  trailing: _trailing(r),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

/// Pantalla completa de solo lectura, usada solo para las tarjetas
/// que todavía no tienen su propia pestaña de CRUD (Cupones).
class _StatDetailScreen extends StatelessWidget {
  final String title;
  final List<_StatDetail> items;

  const _StatDetailScreen({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: items.isEmpty
          ? const Center(child: Text('No hay datos disponibles.'))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final it = items[i];
                return ListTile(
                  title: Text(
                    it.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: it.subtitle.isEmpty ? null : Text(it.subtitle),
                );
              },
            ),
    );
  }
}

/// ───────────────────────── TAB: NEGOCIOS ─────────────────────────

class _BusinessesTab extends StatelessWidget {
  final List<Business> businesses;
  final VoidCallback onAdd;
  final void Function(Business) onEdit;
  final void Function(Business) onToggleActive;
  final void Function(Business) onRemove;

  const _BusinessesTab({
    required this.businesses,
    required this.onAdd,
    required this.onEdit,
    required this.onToggleActive,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onAdd,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Agregar negocio'),
      ),
      body: businesses.isEmpty
          ? const Center(child: Text('Aún no hay negocios.'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: businesses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final b = businesses[i];
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    isThreeLine: true,
                    leading: CircleAvatar(
                      backgroundColor:
                          b.active ? AppColors.inkTeal : Colors.grey.shade400,
                      child: const Icon(Icons.storefront, color: Colors.white),
                    ),
                    title: Text(
                      b.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      [
                        b.active ? 'Activo' : 'Inactivo',
                        'Admin: ${b.adminName ?? 'Sin asignar'}',
                        if (b.phone.isNotEmpty) 'Tel: ${b.phone}',
                      ].join('\n'),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        switch (action) {
                          case 'edit':
                            onEdit(b);
                            break;
                          case 'toggle':
                            onToggleActive(b);
                            break;
                          case 'remove':
                            onRemove(b);
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
                          child: Text(b.active ? 'Desactivar' : 'Activar'),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
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

/// ─────────────────────── FORMULARIO: NEGOCIO ───────────────────────

class _BusinessFormDialog extends StatefulWidget {
  final String title;
  final Business? business;
  final List<AdminUser> admins;

  const _BusinessFormDialog({
    required this.title,
    required this.admins,
    this.business,
  });

  @override
  State<_BusinessFormDialog> createState() => _BusinessFormDialogState();
}

class _BusinessFormDialogState extends State<_BusinessFormDialog> {
  final _formKey = GlobalKey<FormState>();

  // Texto de los campos, del título y del menú desplegable: siempre negro.
  static const _black = TextStyle(color: Colors.black);

  static String _fmt(double? v) => (v == null || v == 0) ? '' : v.toString();

  late final _name = TextEditingController(text: widget.business?.name ?? '');
  late final _address =
      TextEditingController(text: widget.business?.address ?? '');
  late final _phone = TextEditingController(text: widget.business?.phone ?? '');
  late final _commProduct =
      TextEditingController(text: _fmt(widget.business?.commissionProduct));
  late final _commPercent =
      TextEditingController(text: _fmt(widget.business?.commissionPercent));
  late final _commMoney =
      TextEditingController(text: _fmt(widget.business?.commissionMoney));
  late final _contactName =
      TextEditingController(text: widget.business?.contactName ?? '');
  late final _contactEmail =
      TextEditingController(text: widget.business?.contactEmail ?? '');
  late final _rfc = TextEditingController(text: widget.business?.rfc ?? '');
  late final _description =
      TextEditingController(text: widget.business?.description ?? '');

  String? _adminId;

  @override
  void initState() {
    super.initState();
    _adminId = widget.business?.adminId;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _address,
      _phone,
      _commProduct,
      _commPercent,
      _commMoney,
      _contactName,
      _contactEmail,
      _rfc,
      _description,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Vacío = 0. Si hay texto, debe ser un número >= 0.
  String? _money(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim());
    return (n == null || n < 0) ? 'Monto inválido' : null;
  }

  double _num(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.title,
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w800,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _section('Datos del negocio'),
                TextFormField(
                  controller: _name,
                  style: _black,
                  decoration:
                      const InputDecoration(labelText: 'Nombre del negocio *'),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Nombre inválido'
                      : null,
                ),
                TextFormField(
                  controller: _address,
                  style: _black,
                  decoration: const InputDecoration(labelText: 'Dirección'),
                ),
                TextFormField(
                  controller: _phone,
                  style: _black,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                ),
                TextFormField(
                  controller: _description,
                  style: _black,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Descripción / giro del negocio',
                  ),
                ),

                _section('Administrador asignado'),
                DropdownButtonFormField<String>(
                  value: widget.admins.any((a) => a.id == _adminId)
                      ? _adminId
                      : null,
                  isExpanded: true,
                  style: _black,
                  decoration:
                      const InputDecoration(labelText: 'Administrador *'),
                  items: widget.admins
                      .map(
                        (a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(
                            '${a.name} (${a.email})',
                            overflow: TextOverflow.ellipsis,
                            style: _black,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _adminId = v),
                  validator: (v) =>
                      v == null ? 'Selecciona un administrador' : null,
                ),

                _section('Comisiones (MXN por cupón)'),
                TextFormField(
                  controller: _commProduct,
                  style: _black,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Cupón por producto',
                    prefixText: '\$ ',
                  ),
                  validator: _money,
                ),
                TextFormField(
                  controller: _commPercent,
                  style: _black,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Cupón con descuento en %',
                    prefixText: '\$ ',
                  ),
                  validator: _money,
                ),
                TextFormField(
                  controller: _commMoney,
                  style: _black,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Cupón con descuento en \$',
                    prefixText: '\$ ',
                  ),
                  validator: _money,
                ),

                _section('Contacto y datos fiscales'),
                TextFormField(
                  controller: _contactName,
                  style: _black,
                  decoration:
                      const InputDecoration(labelText: 'Nombre del contacto'),
                ),
                TextFormField(
                  controller: _contactEmail,
                  style: _black,
                  keyboardType: TextInputType.emailAddress,
                  decoration:
                      const InputDecoration(labelText: 'Correo de contacto'),
                  validator: (v) =>
                      (v != null && v.trim().isNotEmpty && !v.contains('@'))
                          ? 'Correo inválido'
                          : null,
                ),
                TextFormField(
                  controller: _rfc,
                  style: _black,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'RFC'),
                  validator: (v) => (v != null && v.trim().length > 13)
                      ? 'Máximo 13 caracteres'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.black),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, <String, dynamic>{
              'name': _name.text.trim(),
              'admin_id': int.parse(_adminId!),
              'address': _address.text.trim(),
              'phone': _phone.text.trim(),
              'commission_product': _num(_commProduct),
              'commission_percent': _num(_commPercent),
              'commission_money': _num(_commMoney),
              'contact_name': _contactName.text.trim(),
              'contact_email': _contactEmail.text.trim(),
              'rfc': _rfc.text.trim().toUpperCase(),
              'description': _description.text.trim(),
            });
          },
          child: Text(widget.business == null ? 'Agregar' : 'Guardar'),
        ),
      ],
    );
  }
}

/// ─────────────────────── TAB GENÉRICO: PERSONAS ───────────────────────

class _PeopleTab<T> extends StatelessWidget {
  final String emptyLabel;
  final String addLabel;
  final List<T> people;
  final String Function(T) nameOf;
  final String Function(T) emailOf;
  final bool Function(T) activeOf;
  final VoidCallback onAdd;
  final void Function(T) onEdit;
  final void Function(T) onToggleActive;
  final void Function(T) onRemove;

  const _PeopleTab({
    required this.emptyLabel,
    required this.addLabel,
    required this.people,
    required this.nameOf,
    required this.emailOf,
    required this.activeOf,
    required this.onAdd,
    required this.onEdit,
    required this.onToggleActive,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onAdd,
        icon: const Icon(Icons.person_add_alt),
        label: Text(addLabel),
      ),
      body: people.isEmpty
          ? Center(child: Text(emptyLabel))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: people.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final p = people[i];
                final name = nameOf(p);
                final active = activeOf(p);
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          active ? AppColors.inkTeal : Colors.grey.shade400,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.black),
                      ),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(emailOf(p)),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        switch (action) {
                          case 'edit':
                            onEdit(p);
                            break;
                          case 'toggle':
                            onToggleActive(p);
                            break;
                          case 'remove':
                            onRemove(p);
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
                          child: Text(active ? 'Desactivar' : 'Activar'),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text(
                            'Quitar',
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

/// ─────────────────── FORMULARIO: NOMBRE / CORREO / CONTRASEÑA ──────────

class _PersonFormResult {
  final String name;
  final String email;
  final String password;
  _PersonFormResult(this.name, this.email, this.password);
}

class _PersonFormDialog extends StatefulWidget {
  final String title;
  final String? initialName;
  final String? initialEmail;

  const _PersonFormDialog({
    required this.title,
    this.initialName,
    this.initialEmail,
  });

  @override
  State<_PersonFormDialog> createState() => _PersonFormDialogState();
}

class _PersonFormDialogState extends State<_PersonFormDialog> {
  final _formKey = GlobalKey<FormState>();
  static const _black = TextStyle(color: Colors.black);

  late final _nameCtrl = TextEditingController(text: widget.initialName ?? '');
  late final _emailCtrl = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;

  bool get _isEdit => widget.initialName != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.title,
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w800,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                style: _black,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
                validator: (v) => (v == null || v.trim().length < 3)
                    ? 'Ingresa un nombre'
                    : null,
              ),
              TextFormField(
                controller: _emailCtrl,
                style: _black,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                ),
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'Correo inválido' : null,
              ),
              TextFormField(
                controller: _passwordCtrl,
                style: _black,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: _isEdit
                      ? 'Contraseña (dejar vacío para no cambiar)'
                      : 'Contraseña',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) {
                  if (_isEdit) return null;
                  if (v == null || v.length < 6) {
                    return 'Mínimo 6 caracteres';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.black),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _PersonFormResult(
                _nameCtrl.text.trim(),
                _emailCtrl.text.trim(),
                _passwordCtrl.text.trim(),
              ),
            );
          },
          child: Text(_isEdit ? 'Guardar' : 'Agregar'),
        ),
      ],
    );
  }
}