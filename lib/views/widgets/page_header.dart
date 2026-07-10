import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// The `.phead` component from the HTML: a back chevron in a soft rounded
/// square + screen title. Used at the top of every pushed (non-tab) screen.
class PageHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final VoidCallback? onBack;

  const PageHeader({super.key, required this.title, this.actions, this.onBack});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.white,
      elevation: 0,
      leadingWidth: 56,
      leading: Padding(
        padding: const EdgeInsets.only(left: 16,bottom:5,top:5),
        child: _RoundIconButton(
          icon: Icons.arrow_back_rounded,
          onTap: onBack ?? () => Navigator.of(context).maybePop(),
        ),
      ),
      title: Text(title, style: const TextStyle(color: AppColors.navy, fontSize: 17, fontWeight: FontWeight.w700)),
      actions: actions == null
          ? null
          : [...actions!, const SizedBox(width: 8)],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 19, color: AppColors.navy),
      ),
    );
  }
}

/// Reusable round icon action button (used for share/heart/etc in app bars).
class RoundIconAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  const RoundIconAction({super.key, required this.icon, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: _RoundIconButton2(icon: icon, onTap: onTap, color: color),
    );
  }
}

class _RoundIconButton2 extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  const _RoundIconButton2({required this.icon, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: color ?? AppColors.navy),
      ),
    );
  }
}
