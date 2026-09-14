import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Recorta un rectángulo con muescas semicirculares en los bordes
/// izquierdo y derecho, como un boleto de rifa. Es el elemento de
/// firma visual reutilizado en Splash, Login y Registro.
class _TicketClipper extends CustomClipper<Path> {
  final double notchRadius;
  _TicketClipper({this.notchRadius = 14});

  @override
  Path getClip(Size size) {
    final r = notchRadius;
    final midY = size.height / 2;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, midY - r)
      ..arcToPoint(
        Offset(size.width, midY + r),
        radius: Radius.circular(r),
        clockwise: false,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..lineTo(0, midY + r)
      ..arcToPoint(
        Offset(0, midY - r),
        radius: Radius.circular(r),
        clockwise: false,
      )
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Línea punteada de "perforación", decorativa, para separar secciones
/// dentro de una tarjeta tipo boleto.
class DashedDivider extends StatelessWidget {
  final Color color;
  const DashedDivider({super.key, this.color = const Color(0x332C2C2C)});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 6.0;
        const spacing = 5.0;
        final count = (constraints.maxWidth / (dashWidth + spacing)).floor();
        return SizedBox(
          height: 1,
          child: Row(
            children: List.generate(
              count,
              (_) => Padding(
                padding: const EdgeInsets.only(right: spacing),
                child: Container(width: dashWidth, height: 1.4, color: color),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tarjeta blanca con muescas laterales y sombra suave, usada como
/// contenedor principal de formularios y del panel de bienvenida.
class TicketCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const TicketCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
  });

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _TicketClipper(),
      child: Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: AppColors.inkTealDark.withOpacity(0.18),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}
