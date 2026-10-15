import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

class Contract {
  final String id;
  final String businessId;
  final String businessName;
  final String? adminId;
  final String? adminName;
  final String? adminEmail;
  final String contractNumber;
  final String status;
  final String statusLabel;
  final String? contactName;
  final String? contactEmail;
  final String? rfc;
  final String? address;
  final String? phone;
  final double commissionProduct;
  final double commissionPercent;
  final double commissionMoney;
  final String? description;
  final String pdfUrl;
  final String? documentHash;
  final bool adminSigned;
  final String? adminSignedName;
  final String? adminSignedEmail;
  final String? adminSignedAt;
  final bool superSigned;
  final String? superSignedName;
  final String? superSignedEmail;
  final String? superSignedAt;
  final String? createdAt;

  const Contract({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.contractNumber,
    required this.status,
    required this.statusLabel,
    required this.commissionProduct,
    required this.commissionPercent,
    required this.commissionMoney,
    required this.pdfUrl,
    this.adminId,
    this.adminName,
    this.adminEmail,
    this.contactName,
    this.contactEmail,
    this.rfc,
    this.address,
    this.phone,
    this.description,
    this.documentHash,
    this.adminSigned = false,
    this.adminSignedName,
    this.adminSignedEmail,
    this.adminSignedAt,
    this.superSigned = false,
    this.superSignedName,
    this.superSignedEmail,
    this.superSignedAt,
    this.createdAt,
  });

  factory Contract.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

    return Contract(
      id: json['id'].toString(),
      businessId: json['businessId']?.toString() ?? '',
      businessName: json['businessName']?.toString() ?? '',
      adminId: json['adminId']?.toString(),
      adminName: json['adminName']?.toString(),
      adminEmail: json['adminEmail']?.toString(),
      contractNumber: json['contractNumber']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      statusLabel: json['statusLabel']?.toString() ?? '',
      contactName: json['contactName']?.toString(),
      contactEmail: json['contactEmail']?.toString(),
      rfc: json['rfc']?.toString(),
      address: json['address']?.toString(),
      phone: json['phone']?.toString(),
      commissionProduct: d(json['commissionProduct']),
      commissionPercent: d(json['commissionPercent']),
      commissionMoney: d(json['commissionMoney']),
      description: json['description']?.toString(),
      pdfUrl: json['pdfUrl']?.toString() ?? '',
      documentHash: json['documentHash']?.toString(),
      adminSigned: json['adminSigned'] == true,
      adminSignedName: json['adminSignedName']?.toString(),
      adminSignedEmail: json['adminSignedEmail']?.toString(),
      adminSignedAt: json['adminSignedAt']?.toString(),
      superSigned: json['superSigned'] == true,
      superSignedName: json['superSignedName']?.toString(),
      superSignedEmail: json['superSignedEmail']?.toString(),
      superSignedAt: json['superSignedAt']?.toString(),
      createdAt: json['createdAt']?.toString(),
    );
  }
}

class ContractsScreen extends StatefulWidget {
  const ContractsScreen({super.key});

  @override
  State<ContractsScreen> createState() => _ContractsScreenState();
}

class _ContractsScreenState extends State<ContractsScreen> {
  bool _loading = true;
  String? _error;
  List<Contract> _contracts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await apiService.getContracts();
      final contracts = data
          .whereType<Map>()
          .map((e) => Contract.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      if (!mounted) return;
      setState(() {
        _contracts = contracts;
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
        _error = 'No se pudieron cargar los contratos: $e';
        _loading = false;
      });
    }
  }

  Future<void> _openPdf(Contract contract) async {
    if (contract.pdfUrl.isEmpty) {
      _showMessage('Este contrato todavía no tiene PDF.', error: true);
      return;
    }

    final uri = Uri.tryParse(contract.pdfUrl);
    if (uri == null) {
      _showMessage('La URL del PDF no es válida.', error: true);
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _showMessage('No se pudo abrir el PDF.', error: true);
    }
  }

  Future<void> _accept(Contract contract) async {
    final isAdminStep = contract.status == 'pending_admin';
    final title = isAdminStep
        ? 'Aceptar convenio'
        : 'Aceptar convenio como súper administrador';

    // Un solo diálogo: texto legal + recuadro para firmar a mano.
    final signature = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SignatureDialog(title: title),
    );

    if (signature == null) return;

    try {
      await apiService.acceptContract(contract.id, signature);
      if (!mounted) return;
      _showMessage('Aceptación electrónica registrada ✅');
      await _load();
    } on ApiException catch (e) {
      _showMessage(e.message, error: true);
    } catch (e) {
      _showMessage('No se pudo registrar la aceptación.', error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.stampCoral : null,
      ),
    );
  }

  Color _statusColor(Contract contract) {
    switch (contract.status) {
      case 'accepted':
        return Colors.green;
      case 'pending_super_admin':
        return Colors.orange.shade800;
      default:
        return Colors.blueGrey;
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return 'Pendiente';
    final parsed = DateTime.tryParse(iso)?.toLocal();
    if (parsed == null) return iso;
    return '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}/'
        '${parsed.year} ${parsed.hour.toString().padLeft(2, '0')}:'
        '${parsed.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    if (_contracts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 180),
            Center(child: Text('Aún no hay contratos o convenios.')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _contracts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final c = _contracts[index];
          final statusColor = _statusColor(c);
          final canAccept =
              c.status == 'pending_admin' || c.status == 'pending_super_admin';

          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.description_outlined, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.businessName,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('Contrato ${c.contractNumber}'),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(.10),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                c.statusLabel,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Text('Administrador: ${c.adminName ?? 'Sin asignar'}'),
                  if (c.adminEmail?.isNotEmpty == true)
                    Text('Correo: ${c.adminEmail}'),
                  const SizedBox(height: 8),
                  Text('RFC: ${c.rfc?.isNotEmpty == true ? c.rfc : 'No proporcionado'}'),
                  Text('Teléfono: ${c.phone?.isNotEmpty == true ? c.phone : 'No proporcionado'}'),
                  if (c.address?.isNotEmpty == true) Text('Domicilio: ${c.address}'),
                  const SizedBox(height: 10),
                  Text(
                    'Comisión por producto: \$${c.commissionProduct.toStringAsFixed(2)}',
                  ),
                  Text(
                    'Comisión porcentual: ${c.commissionPercent.toStringAsFixed(2)}%',
                  ),
                  Text(
                    'Comisión monetaria: \$${c.commissionMoney.toStringAsFixed(2)}',
                  ),
                  const SizedBox(height: 12),
                  _SignatureRow(
                    title: 'Administrador',
                    signed: c.adminSigned,
                    name: c.adminSignedName,
                    date: _fmtDate(c.adminSignedAt),
                  ),
                  const SizedBox(height: 8),
                  _SignatureRow(
                    title: 'Súper administrador',
                    signed: c.superSigned,
                    name: c.superSignedName,
                    date: _fmtDate(c.superSignedAt),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _openPdf(c),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Ver PDF'),
                      ),
                      if (canAccept)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.stampCoral,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () => _accept(c),
                          icon: const Icon(Icons.draw_outlined),
                          label: const Text('Aceptar y firmar'),
                        ),
                    ],
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

class _SignatureRow extends StatelessWidget {
  final String title;
  final bool signed;
  final String? name;
  final String date;

  const _SignatureRow({
    required this.title,
    required this.signed,
    required this.name,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: signed ? Colors.green.withOpacity(.07) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            signed ? Icons.verified_outlined : Icons.pending_outlined,
            color: signed ? Colors.green : Colors.grey.shade700,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(signed ? 'Aceptado por ${name ?? 'usuario'}' : 'Pendiente'),
                Text('Fecha: $date'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────
/// Diálogo de firma manual. Devuelve la firma como PNG en base64
/// (sin prefijo "data:") o null si el usuario cancela.
/// ─────────────────────────────────────────────────────────────

void _drawStrokes(Canvas canvas, List<List<Offset>> strokes, double scale) {
  final line = Paint()
    ..color = Colors.black
    ..strokeWidth = 3 * scale
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  final dot = Paint()
    ..color = Colors.black
    ..style = PaintingStyle.fill;

  for (final stroke in strokes) {
    if (stroke.isEmpty) continue;
    if (stroke.length == 1) {
      canvas.drawCircle(stroke.first * scale, 1.5 * scale, dot);
      continue;
    }
    final path = Path()
      ..moveTo(stroke.first.dx * scale, stroke.first.dy * scale);
    for (final p in stroke.skip(1)) {
      path.lineTo(p.dx * scale, p.dy * scale);
    }
    canvas.drawPath(path, line);
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) => _drawStrokes(canvas, strokes, 1.0);

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

class _SignatureDialog extends StatefulWidget {
  final String title;
  const _SignatureDialog({required this.title});

  @override
  State<_SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<_SignatureDialog> {
  final GlobalKey _padKey = GlobalKey();
  final List<List<Offset>> _strokes = [];
  String? _error;
  bool _busy = false;

  bool get _isEmpty => _strokes.isEmpty;

  Future<String> _exportPng() async {
    final size = _padKey.currentContext!.size!;
    const outW = 400.0;
    final scale = outW / size.width;
    final outH = size.height * scale;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // Fondo blanco sólido: el PNG no lleva transparencia.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, outW, outH),
      Paint()..color = Colors.white,
    );
    _drawStrokes(canvas, _strokes, scale);

    final image = await recorder.endRecording().toImage(
          outW.round(),
          outH.round(),
        );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return base64Encode(data!.buffer.asUint8List());
  }

  Future<void> _submit() async {
    if (_isEmpty) {
      setState(() => _error = 'Dibuja tu firma en el recuadro.');
      return;
    }
    setState(() => _busy = true);
    try {
      final b64 = await _exportPng();
      if (!mounted) return;
      Navigator.pop(context, b64);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'No se pudo generar la firma. Inténtalo de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Al continuar se registrará la aceptación electrónica dentro de '
            'CUPON APP con el usuario autenticado, nombre, correo, fecha y '
            'hora y, cuando el servidor la proporcione, la dirección IP. '
            'Tu firma manual aparecerá en el PDF del convenio.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          const Text(
            'Firma aquí con el dedo o el mouse:',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.maxFinite,
            height: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                key: _padKey,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black54),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => setState(() {
                    _error = null;
                    _strokes.add([d.localPosition]);
                  }),
                  onPanUpdate: (d) => setState(() {
                    _strokes.last.add(d.localPosition);
                  }),
                  child: Stack(
                    children: [
                      if (_isEmpty)
                        const Center(
                          child: Text(
                            'Firma aquí',
                            style: TextStyle(color: Colors.black38),
                          ),
                        ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _SignaturePainter(_strokes),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _isEmpty || _busy
                  ? null
                  : () => setState(() {
                        _strokes.clear();
                        _error = null;
                      }),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Limpiar'),
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: const TextStyle(
                color: AppColors.stampCoral,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.stampCoral,
            foregroundColor: Colors.black,
          ),
          onPressed: _busy ? null : _submit,
          child: const Text('Aceptar y firmar'),
        ),
      ],
    );
  }
}