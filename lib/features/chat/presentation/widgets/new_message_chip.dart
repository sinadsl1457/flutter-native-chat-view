import 'package:flutter/material.dart';

/// 위로 스크롤해 있는 동안 표시. 누르면 최신 메시지로 이동.
class NewMessageChip extends StatelessWidget {
  const NewMessageChip({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.arrow_downward_rounded, size: 18),
      label: const Text('최신 메시지'),
      onPressed: onTap,
      elevation: 2,
    );
  }
}
