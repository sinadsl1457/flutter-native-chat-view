import 'package:flutter/material.dart';

import '../features/chat/data/fake/fake_chat_repository.dart';
import '../features/chat/domain/entities/chat_message.dart';
import '../features/chat/presentation/pages/chat_page.dart';

class NativeChatDemoApp extends StatelessWidget {
  const NativeChatDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Native Chat View',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFE6007E),
      ),
      home: const ChatPage(
        roomId: 1,
        peer: ChatPeer(
          id: FakeChatRepository.peerId,
          nickname: '하린',
          avatarUrl: 'https://picsum.photos/seed/peer/200/200',
        ),
      ),
    );
  }
}
