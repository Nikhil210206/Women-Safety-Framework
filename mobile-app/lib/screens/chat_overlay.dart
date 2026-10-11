import 'package:flutter/material.dart';
import 'package:mobile_app/services/ai_api_service.dart';
import 'package:mobile_app/theme/wsf.dart';
import 'package:mobile_app/ui/guardian_orb.dart';
import 'package:mobile_app/ui/kit.dart';
import 'package:mobile_app/ui/motion.dart';

/// Chat with the guardian about the user's surroundings.
///
/// Open with:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,  // Required — lets the sheet resize with the keyboard
///   backgroundColor: Colors.transparent,
///   builder: (_) => ChatOverlay(lat: lat, lng: lng),
/// );
/// ```
class ChatOverlay extends StatefulWidget {
  final double lat;
  final double lng;
  final String language;

  const ChatOverlay({
    super.key,
    required this.lat,
    required this.lng,
    this.language = 'en-IN',
  });

  @override
  State<ChatOverlay> createState() => _ChatOverlayState();
}

class _ChatOverlayState extends State<ChatOverlay> {
  final AiApiService _ai = AiApiService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isSending = false;

  static const List<String> _starters = [
    'is this area safe at night?',
    'where is the nearest police station?',
    'what should i watch out for here?',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _isSending) return;

    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(text: query, isUser: true));
      _isSending = true;
    });
    _scrollToBottom();

    final reply = await _ai.sendChatQuery(
      query: query,
      lat: widget.lat,
      lng: widget.lng,
      language: widget.language,
    );

    if (!mounted) return;
    setState(() {
      _messages.add(_ChatMessage(
        text: reply ?? 'The guardian is offline right now. Stay alert.',
        isUser: false,
      ));
      _isSending = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // viewInsets.bottom lifts the sheet above the keyboard.
    // isScrollControlled: true on showModalBottomSheet allows this to work.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Wsf.ink,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(color: Wsf.line, width: 2)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 14, 6),
              child: Row(
                children: [
                  GuardianOrb(
                    size: 64,
                    mood: _isSending ? OrbMood.listening : OrbMood.calm,
                    glow: false,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ask the guardian', style: Wsf.display(24, height: 1)),
                        const SizedBox(height: 5),
                        Eyebrow(_isSending ? 'thinking' : 'knows where you are standing'),
                      ],
                    ),
                  ),
                  DiscButton(
                    icon: Icons.close_rounded,
                    size: 40,
                    bg: Wsf.ink3,
                    border: null,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),

            // ── Chat history ─────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: MediaQuery.of(context).size.height * 0.42,
              child: _messages.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Eyebrow('try asking'),
                          const SizedBox(height: 12),
                          for (final (i, q) in _starters.indexed)
                            FadeSlide(
                              delay: Duration(milliseconds: 80 * i),
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Pressable(
                                  onTap: () {
                                    _controller.text = q;
                                    _sendMessage();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(color: Wsf.line, width: 2),
                                    ),
                                    child: Text(q, style: Wsf.body(size: 15, color: Wsf.bone)),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: _messages.length + (_isSending ? 1 : 0),
                      itemBuilder: (_, i) => i == _messages.length
                          ? const _TypingBubble()
                          : _BubbleTile(message: _messages[i]),
                    ),
            ),

            // ── Input row ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      keyboardAppearance: Brightness.dark,
                      style: Wsf.body(size: 15.5, color: Wsf.bone),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'ask about this area',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        border: _pill(Colors.transparent),
                        enabledBorder: _pill(Colors.transparent),
                        focusedBorder: _pill(Wsf.volt),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DiscButton(
                    icon: Icons.arrow_upward_rounded,
                    size: 52,
                    bg: Wsf.volt,
                    fg: Wsf.voltDeep,
                    border: null,
                    loading: _isSending,
                    onTap: _isSending ? null : _sendMessage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  OutlineInputBorder _pill(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: c, width: 2),
      );
}

/// One message. The user's are volt and sit right; the guardian's are dark
/// and sit left.
class _BubbleTile extends StatelessWidget {
  final _ChatMessage message;
  const _BubbleTile({required this.message});

  @override
  Widget build(BuildContext context) {
    final user = message.isUser;
    return FadeSlide(
      duration: const Duration(milliseconds: 420),
      offset: const Offset(0, 12),
      child: Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: user ? Wsf.volt : Wsf.ink3,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(22),
              topRight: const Radius.circular(22),
              bottomLeft: Radius.circular(user ? 22 : 6),
              bottomRight: Radius.circular(user ? 6 : 22),
            ),
          ),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          child: Text(
            message.text,
            style: Wsf.body(
              size: 15,
              height: 1.45,
              color: user ? Wsf.voltDeep : Wsf.bone,
              weight: user ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Three dots that take turns hopping while a reply is on its way.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(color: Wsf.ink3, borderRadius: BorderRadius.circular(22)),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  () {
                    final phase = (_c.value - i * 0.16) % 1.0;
                    final hop = phase < 0.4 ? Curves.easeOut.transform(1 - (phase / 0.2 - 1).abs()) : 0.0;
                    return Container(
                      width: 8,
                      height: 8,
                      margin: EdgeInsets.only(right: i == 2 ? 0 : 5),
                      transform: Matrix4.translationValues(0, -5 * hop, 0),
                      decoration: BoxDecoration(
                        color: Color.lerp(Wsf.boneFaint, Wsf.volt, hop),
                        shape: BoxShape.circle,
                      ),
                    );
                  }(),
              ],
            ),
          ),
        ),
      );
}

class _ChatMessage {
  final String text;
  final bool isUser;
  const _ChatMessage({required this.text, required this.isUser});
}
