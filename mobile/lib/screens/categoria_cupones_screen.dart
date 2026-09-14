import 'package:flutter/material.dart';

import '../models/coupon.dart' show kCouponCategories;

class CategoriaCuponesScreen extends StatefulWidget {
  const CategoriaCuponesScreen({super.key});

  @override
  State<CategoriaCuponesScreen> createState() =>
      _CategoriaCuponesScreenState();
}

class _CategoriaCuponesScreenState extends State<CategoriaCuponesScreen> {
  final Set<String> categoriasSeleccionadas = {};

  void _continuar() {
    if (categoriasSeleccionadas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos una categoría')),
      );
      return;
    }

    final seleccion = categoriasSeleccionadas.toList();
    if (Navigator.canPop(context)) {
      // Se abrió desde "Por categoría" en HomeScreen: regresamos la
      // selección para que filtre la lista de cupones allá.
      Navigator.pop(context, seleccion);
    } else {
      // Se abrió como paso inicial del flujo (p. ej. justo después del
      // registro): no hay a dónde regresar, así que se continúa
      // directo a home.
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Elige tus categorías')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '¿Qué cupones te interesan?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            const Text(
              'Selecciona las categorías para mostrarte los cupones que más te interesan.',
              style: TextStyle(fontSize: 16),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: GridView.builder(
                itemCount: kCouponCategories.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.8,
                ),
                itemBuilder: (context, index) {
                  final categoria = kCouponCategories[index];
                  final seleccionada = categoriasSeleccionadas.contains(
                    categoria,
                  );

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (seleccionada) {
                          categoriasSeleccionadas.remove(categoria);
                        } else {
                          categoriasSeleccionadas.add(categoria);
                        }
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: seleccionada
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: seleccionada
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade300,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          categoria,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: seleccionada ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 15),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _continuar,
                child: const Text('Continuar', style: TextStyle(fontSize: 17)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}