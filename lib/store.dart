import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class OpenTabDescriptor {
  final String instanceUrl;
  final String? sessionId;
  final String? filePath;
  final String title;
  final String? profile;

  /// Set for a diff tab: the changed file and which diff to show.
  final String? diffPath;
  final bool diffStaged;
  final bool diffUntracked;

  /// Which pane the tab was in, and — for a terminal tab — which pty it showed.
  ///
  /// A pane is a property of the tab, so it has to survive a restart; otherwise
  /// reopening the app would collapse every split back into the left pane.
  final String? pane;
  final String? termSessionKey;
  final String? termId;

  const OpenTabDescriptor({
    required this.instanceUrl,
    this.sessionId,
    this.filePath,
    required this.title,
    this.profile,
    this.diffPath,
    this.diffStaged = false,
    this.diffUntracked = false,
    this.pane,
    this.termSessionKey,
    this.termId,
  });

  factory OpenTabDescriptor.fromJson(Map<String, dynamic> j) =>
      OpenTabDescriptor(
        instanceUrl: j['instance_url'] as String? ?? '',
        sessionId: j['session_id'] as String?,
        filePath: j['file_path'] as String?,
        title: j['title'] as String? ?? '',
        profile: j['profile'] as String?,
        diffPath: j['diff_path'] as String?,
        diffStaged: j['diff_staged'] as bool? ?? false,
        diffUntracked: j['diff_untracked'] as bool? ?? false,
        pane: j['pane'] as String?,
        termSessionKey: j['term_session_key'] as String?,
        termId: j['term_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'instance_url': instanceUrl,
        if (sessionId != null) 'session_id': sessionId,
        if (filePath != null) 'file_path': filePath,
        'title': title,
        if (profile != null) 'profile': profile,
        if (diffPath != null) 'diff_path': diffPath,
        if (diffStaged) 'diff_staged': true,
        if (diffUntracked) 'diff_untracked': true,
        if (pane != null) 'pane': pane,
        if (termSessionKey != null) 'term_session_key': termSessionKey,
        if (termId != null) 'term_id': termId,
      };

  bool get isFile => filePath != null;
  bool get isDiff => diffPath != null;
  bool get isTerminal => termId != null;
}

class OpenTabsState {
  final List<OpenTabDescriptor> tabs;
  final int activeIndex;
  const OpenTabsState(this.tabs, this.activeIndex);
}

/// Persists the list of saved daemon instances in shared_preferences.
class InstanceStore {
  static const _key = 'instances';
  static const _tabsKey = 'open_tabs';

  Future<List<Instance>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw != null) {
      try {
        return (jsonDecode(raw) as List)
            .map((e) => Instance.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return [];
      }
    }
    // Migrate a legacy single connection from the first app build.
    final url = p.getString('url');
    final token = p.getString('token');
    if (url != null && token != null) {
      final inst = Instance(name: hostOf(url), url: url, token: token);
      await save([inst]);
      await p.remove('url');
      await p.remove('token');
      return [inst];
    }
    return [];
  }

  Future<OpenTabsState> loadOpenTabs() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_tabsKey);
    if (raw == null) return const OpenTabsState([], -1);
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final tabs = ((j['tabs'] as List?) ?? const [])
          .map((e) => OpenTabDescriptor.fromJson(e as Map<String, dynamic>))
          .where((t) =>
              t.instanceUrl.isNotEmpty &&
              (t.sessionId != null || t.filePath != null))
          .toList();
      final active = (j['active_index'] as num?)?.toInt() ?? -1;
      return OpenTabsState(tabs, active);
    } catch (_) {
      return const OpenTabsState([], -1);
    }
  }

  Future<void> saveOpenTabs(
      List<OpenTabDescriptor> tabs, int activeIndex) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _tabsKey,
        jsonEncode({
          'tabs': tabs.map((t) => t.toJson()).toList(),
          'active_index': activeIndex,
        }));
  }

  Future<void> save(List<Instance> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }
}
