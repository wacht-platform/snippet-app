import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../coordination/coordination_thread_state.dart';

class CoordinationBoardScreen extends StatefulWidget {
  const CoordinationBoardScreen(
      {super.key,
      required this.client,
      required this.threadId,
      required this.actorId});
  final DaemonClient client;
  final String threadId;
  final String actorId;
  @override
  State<CoordinationBoardScreen> createState() =>
      _CoordinationBoardScreenState();
}

class _CoordinationBoardScreenState extends State<CoordinationBoardScreen> {
  late final CoordinationThreadState state;
  final composer = TextEditingController();

  @override
  void initState() {
    super.initState();
    state = CoordinationThreadState(
        client: widget.client, threadId: widget.threadId);
    state.attachLive();
    state.refresh().whenComplete(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    state.dispose();
    composer.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final text = composer.text.trim();
    if (text.isEmpty) return;
    composer.clear();
    await state.send(
        actorKind: 'human',
        actorId: widget.actorId,
        body: text,
        idempotencyKey: 'mobile-${DateTime.now().microsecondsSinceEpoch}');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Coordination board')),
        body: Column(children: [
          Expanded(
              child: RefreshIndicator(
            onRefresh: () async {
              await state.refresh();
              if (mounted) setState(() {});
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: state.events.length,
              itemBuilder: (_, index) =>
                  _EventBubble(event: state.events[index]),
            ),
          )),
          if (state.error != null)
            Padding(
                padding: const EdgeInsets.all(8),
                child: Text(state.error!,
                    style: const TextStyle(color: Colors.red))),
          SafeArea(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Row(children: [
                    Expanded(
                        child: TextField(
                            controller: composer,
                            minLines: 1,
                            maxLines: 4,
                            decoration: const InputDecoration(
                                hintText: 'Message an agent…'))),
                    IconButton(
                        onPressed: state.sending ? null : send,
                        icon: const Icon(Icons.send)),
                  ]))),
        ]),
      );
}

class _EventBubble extends StatelessWidget {
  const _EventBubble({required this.event});
  final CoordinationEvent event;
  @override
  Widget build(BuildContext context) {
    final isMessage = event.eventType == 'message.posted';
    return Align(
      alignment: event.actorKind == 'human'
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.actorId,
                      style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 3),
                  Text(isMessage ? event.body : event.eventType),
                ],
              ))),
    );
  }
}
