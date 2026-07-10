import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Shown for any Phase-2 route (see app_routes.dart). Keeps every button
/// in the app tappable and navigable while those screens are built out —
/// replace with a real screen + ViewModel following the Phase-1 screens
/// as a template.
class ComingSoonScreen extends StatelessWidget {
  final String title;
  const ComingSoonScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: AppColors.shSm),
                child: const Icon(Icons.hourglass_top_rounded, color: AppColors.sky, size: 38),
              ),
              const SizedBox(height: 20),
              Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.navy)),
              const SizedBox(height: 8),
              const Text(
                'This screen is part of Phase 2 (telehealth, tests, family, insurance & chat) and is not built yet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: AppColors.muted, height: 1.5),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(color: AppColors.blush, borderRadius: BorderRadius.circular(20)),
                child: const Text('Coming soon', style: TextStyle(color: AppColors.rose, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
