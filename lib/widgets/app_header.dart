import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final bool showBackButton;
  final VoidCallback? onBack;
  final Color? backgroundColor;

  const AppHeader({
    super.key,
    this.showBackButton = false,
    this.onBack,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    if (!isDesktop) {
      if (showBackButton) {
        return AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: onBack,
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return DragToMoveArea(
      child: Container(
        height: 40,
        color: backgroundColor ?? Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            if (showBackButton) ...[
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Colors.black87),
                onPressed: onBack,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: 12),
            ],
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.remove_rounded, size: 16, color: Colors.black54),
              onPressed: () => windowManager.minimize(),
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
              tooltip: 'Minimize',
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.crop_square_rounded, size: 14, color: Colors.black54),
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
              tooltip: 'Maximize',
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16, color: Colors.black54),
              onPressed: () => windowManager.close(),
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
              tooltip: 'Close',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(40);
}
