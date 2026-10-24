import 'package:flutter/material.dart';

/// 입력창은 Flutter 로 둔다. 키보드·IME·텍스트 편집은 Flutter 가 잘 하는 영역이고,
/// 네이티브로 옮긴 것은 "긴 목록 스크롤" 하나뿐이다.
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key, required this.focusNode, required this.onSend});

  final FocusNode focusNode;
  final void Function(String text) onSend;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: widget.focusNode,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '메시지 입력 ("실패" 를 넣으면 전송 실패)',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              onPressed: _send,
              icon: const Icon(Icons.arrow_upward_rounded),
              tooltip: '보내기',
            ),
          ],
        ),
      ),
    );
  }
}
