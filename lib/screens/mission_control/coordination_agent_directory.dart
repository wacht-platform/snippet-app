import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';

class CoordinationAgentDirectory extends StatefulWidget {
  const CoordinationAgentDirectory({super.key, required this.client});
  final DaemonClient client;
  @override
  State<CoordinationAgentDirectory> createState() =>
      _CoordinationAgentDirectoryState();
}

class _CoordinationAgentDirectoryState
    extends State<CoordinationAgentDirectory> {
  List<CoordinationAgent> agents = const [];
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      agents = await widget.client.coordinationAgents();
    } catch (e) {
      error = '$e';
    }
    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Agents')),
        body: RefreshIndicator(
          onRefresh: refresh,
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
                  ? ListView(children: [
                      Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Could not load agents',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                Text(error!),
                                const SizedBox(height: 16),
                                FilledButton(
                                    onPressed: refresh,
                                    child: const Text('Retry')),
                              ]))
                    ])
                  : agents.isEmpty
                      ? ListView(children: const [
                          Padding(
                              padding: EdgeInsets.fromLTRB(24, 72, 24, 24),
                              child: Column(children: [
                                Icon(Icons.groups_outlined, size: 48),
                                SizedBox(height: 16),
                                Text('No agents registered',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600)),
                                SizedBox(height: 8),
                                Text(
                                    'Specialized agents will appear here after they are registered with Mission Control.',
                                    textAlign: TextAlign.center),
                              ])),
                        ])
                      : ListView.builder(
                          itemCount: agents.length,
                          itemBuilder: (_, index) {
                            final agent = agents[index];
                            return ListTile(
                              leading: CircleAvatar(
                                  child: Text(agent.displayName.isEmpty
                                      ? '?'
                                      : agent.displayName[0])),
                              title: Text(agent.displayName),
                              subtitle: Text(
                                  '@${agent.handle} · ${agent.role} · ${agent.capabilities.join(', ')}'),
                              trailing: Text(agent.status),
                            );
                          },
                        ),
        ),
      );
}
