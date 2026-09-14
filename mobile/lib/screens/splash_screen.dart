import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/ticket_card.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.inkTeal, AppColors.inkTealDark],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),
              _StampBadge(),
              const SizedBox(height: 18),
              Text(
                'Caza cupones\ncerca de ti',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .displayMedium
                    ?.copyWith(color: Colors.white, height: 1.15),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Descubre, captura y usa descuentos reales de negocios cerca de ti.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(0.8),
                      ),
                ),
              ),
              const Spacer(flex: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TicketCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/login'),
                        child: const Text('INICIAR SESIÓN'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/register'),
                        child: const Text('CREAR CUENTA'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sello circular rotado, como una marca de goma sobre papel.
class _StampBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.12,
      child: Container(
        width: 128,
        height: 128,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.85), width: 2),
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border:
                Border.all(color: Colors.white.withOpacity(0.85), width: 1.2),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'CUPÓN',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        color: Colors.white,
                        fontSize: 22,
                      ),
                ),
                Text(
                  'APP',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        color: AppColors.goldFoil,
                        fontSize: 22,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}