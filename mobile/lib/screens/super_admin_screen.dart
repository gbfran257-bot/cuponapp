import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../services/api_service.dart';

/// ─────────────────────────────────────────────────────────────
/// Modelos locales para el panel de súper admin, poblados con
/// datos reales del backend.
/// ─────────────────────────────────────────────────────────────
class Business {
  final String id;
  String name;
  bool active;

  Business({required this.id, required this.name, this.active = true});

  factory Business.fromJson(Map<String, dynamic> json) => Business(
        id: json['id'] as String,
        name: json['name'] as String,
        active: json['active'] as bool? ?? true,
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
        id: json['id'] as String,
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
        id: json['id'] as String,
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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

      final stats = Map<String, String>.from(statsData['stats'] as Map);
      stats['Usuarios'] = usersData.length.toString();

      setState(() {
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

  // ── Negocios ─────────────────────────────────────────────────

  Future<void> _addBusiness() async {
    final name = await _showNameDialog(title: 'Agregar negocio');
    if (name == null) return;
    try {
      await apiService.createBusiness(name);
      await _loadAll();
      _showMsg('Negocio agregado ✅');
    } on ApiException catch (e) {
      _showMsg(e.message, error: true);
    } catch (e) {
      _showMsg('No se pudo conectar con el servidor.', error: true);
    }
  }

  Future<void> _editBusiness(Business business) async {
    final name = await _showNameDialog(
      title: 'Editar negocio',
      initialName: business.name,
    );
    if (name == null) return;
    try {
      await apiService.updateBusiness(business.id, name);
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
      message: '¿Eliminar "${business.name}"? Sus cupones quedarán sin negocio asignado.',
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

  Future<String?> _showNameDialog({
    required String title,
    String? initialName,
  }) {
    final ctrl = TextEditingController(text: initialName ?? '');
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Nombre del negocio'),
            validator: (v) =>
                (v == null || v.trim().length < 2) ? 'Nombre inválido' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context, ctrl.text.trim());
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
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
        title: Text(title),
        content: Text(message),
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
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Súper administrador'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          indicatorColor: Colors.white,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Panorama'),
            Tab(icon: Icon(Icons.storefront_outlined), text: 'Negocios'),
            Tab(
              icon: Icon(Icons.admin_panel_settings_outlined),
              text: 'Administradores',
            ),
            Tab(icon: Icon(Icons.people_outline), text: 'Usuarios'),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        // Antes 1.4 (tarjetas demasiado bajas para el número + la
        // etiqueta, por eso se veía "BOTTOM OVERFLOWED"). Con 1.0
        // queda más cuadrada y le da a los textos el alto que
        // necesitan sin recortarse.
        childAspectRatio: 1.0,
        children: stats.entries.map((e) {
          return InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: () => onOpenDetail(e.key, details[e.key] ?? const []),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey.shade300, width: 2),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e.value,
                    // Antes displaySmall: mucho más grande de lo que
                    // cabía en la tarjeta. headlineSmall es más chico
                    // pero se sigue viendo como número protagonista.
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppColors.inkTeal,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          e.key,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(height: 1.15),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: Colors.grey.shade500,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
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
                    leading: CircleAvatar(
                      backgroundColor:
                          b.active ? AppColors.inkTeal : Colors.grey.shade400,
                      child: const Icon(Icons.storefront, color: Colors.white),
                    ),
                    title: Text(
                      b.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(b.active ? 'Activo' : 'Inactivo'),
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
                        style: const TextStyle(color: Colors.white),
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
      title: Text(widget.title),
      // El diálogo por defecto no crece con el contenido cuando el
      // teclado aparece, y eso era lo que causaba el
      // "BOTTOM OVERFLOWED" en la captura: el Form con sus 3 campos
      // más el teclado ya no cabían. Con SingleChildScrollView el
      // contenido se puede desplazar en vez de recortarse, y
      // insetPadding le da margen para respirar en pantallas chicas.
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
                validator: (v) => (v == null || v.trim().length < 3)
                    ? 'Ingresa un nombre'
                    : null,
              ),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                ),
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'Correo inválido' : null,
              ),
              TextFormField(
                controller: _passwordCtrl,
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