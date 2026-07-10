import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

void showToast(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(children: [
        const Icon(Icons.check, color: Colors.white, size: 14),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              onAction?.call();
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(actionLabel, style: const TextStyle(color: AppColors.sky, fontWeight: FontWeight.w700, fontSize: 13.5)),
          ),
      ]),
      backgroundColor: AppColors.navy,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 74),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      duration: const Duration(milliseconds: 2200),
      elevation: 8,
    ),
  );
}