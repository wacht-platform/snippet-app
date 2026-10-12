// Pull request data as the daemon returns it from the GitHub CLI.

String _s(dynamic v) => v?.toString() ?? '';
int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
String _login(dynamic author) =>
    author is Map ? _s(author['login']) : _s(author);

class GithubStatus {
  final bool available;
  final String reason;
  final String repo;
  final String url;
  final String viewer;
  final String permission;
  final Set<String> mergeMethods;
  final bool autoMerge;
  final bool deleteBranchOnMerge;
  const GithubStatus({
    required this.available,
    this.reason = '',
    this.repo = '',
    this.url = '',
    this.viewer = '',
    this.permission = '',
    this.mergeMethods = const {'merge', 'squash', 'rebase'},
    this.autoMerge = false,
    this.deleteBranchOnMerge = false,
  });
  bool get isAdmin => permission == 'ADMIN';
  factory GithubStatus.fromJson(Map<String, dynamic> j) => GithubStatus(
        available: j['available'] == true,
        reason: _s(j['reason']),
        repo: _s(j['repo']),
        url: _s(j['url']),
        viewer: _s(j['viewer']),
        permission: _s(j['permission']),
        mergeMethods: j['merge_methods'] is Map
            ? {
                for (final e in (j['merge_methods'] as Map).entries)
                  if (e.value == true) e.key.toString(),
              }
            : const {'merge', 'squash', 'rebase'},
        autoMerge: j['auto_merge'] == true,
        deleteBranchOnMerge: j['delete_branch_on_merge'] == true,
      );
}

enum ChecksState { none, passing, failing, pending }

class PrCheck {
  final String name;
  final String workflow;
  final String url;
  final ChecksState state;
  const PrCheck(
      {required this.name,
      required this.workflow,
      required this.url,
      required this.state});
  factory PrCheck.fromJson(Map<String, dynamic> j) {
    final conclusion = _s(j['conclusion'] ?? j['state']).toUpperCase();
    final status = _s(j['status']).toUpperCase();
    final state = switch (conclusion) {
      'FAILURE' || 'ERROR' || 'TIMED_OUT' || 'CANCELLED' || 'ACTION_REQUIRED' ||
      'STARTUP_FAILURE' =>
        ChecksState.failing,
      'SUCCESS' || 'NEUTRAL' || 'SKIPPED' => ChecksState.passing,
      _ => status == 'COMPLETED' ? ChecksState.passing : ChecksState.pending,
    };
    return PrCheck(
      name: _s(j['name'] ?? j['context']),
      workflow: _s(j['workflowName']),
      url: _s(j['detailsUrl'] ?? j['targetUrl']),
      state: state,
    );
  }
}

ChecksState rollup(List<PrCheck> checks) {
  if (checks.isEmpty) return ChecksState.none;
  if (checks.any((c) => c.state == ChecksState.failing)) {
    return ChecksState.failing;
  }
  if (checks.any((c) => c.state == ChecksState.pending)) {
    return ChecksState.pending;
  }
  return ChecksState.passing;
}

List<PrCheck> _checks(dynamic v) => ((v as List?) ?? const [])
    .whereType<Map>()
    .map((c) => PrCheck.fromJson(c.cast<String, dynamic>()))
    .toList();

class PrSummary {
  final int number;
  final String title;
  final String author;
  final String head;
  final String base;
  final bool draft;
  final String state;
  final String reviewDecision;
  final List<PrCheck> checks;
  final int additions;
  final int deletions;
  final String updatedAt;
  final String url;
  final List<String> reviewers;
  const PrSummary({
    required this.number,
    required this.title,
    required this.author,
    required this.head,
    required this.base,
    required this.draft,
    required this.state,
    required this.reviewDecision,
    required this.checks,
    required this.additions,
    required this.deletions,
    required this.updatedAt,
    required this.url,
    this.reviewers = const [],
  });
  factory PrSummary.fromJson(Map<String, dynamic> j) => PrSummary(
        number: _i(j['number']),
        title: _s(j['title']),
        author: _login(j['author']),
        head: _s(j['headRefName']),
        base: _s(j['baseRefName']),
        draft: j['isDraft'] == true,
        state: _s(j['state']),
        reviewDecision: _s(j['reviewDecision']),
        checks: _checks(j['statusCheckRollup']),
        additions: _i(j['additions']),
        deletions: _i(j['deletions']),
        updatedAt: _s(j['updatedAt']),
        url: _s(j['url']),
        reviewers: [
          for (final r in (j['reviewRequests'] as List?) ?? const [])
            if (r is Map) _s(r['login'] ?? r['name']),
        ],
      );
}

class PrFile {
  final String path;
  final int additions;
  final int deletions;
  final String changeType;
  const PrFile(
      {required this.path,
      required this.additions,
      required this.deletions,
      required this.changeType});
  factory PrFile.fromJson(Map<String, dynamic> j) => PrFile(
        path: _s(j['path']),
        additions: _i(j['additions']),
        deletions: _i(j['deletions']),
        changeType: _s(j['changeType']),
      );
}

class PrCommit {
  final String oid;
  final String headline;
  final String body;
  final String author;
  final String date;
  const PrCommit(
      {required this.oid,
      required this.headline,
      this.body = '',
      required this.author,
      required this.date});
  factory PrCommit.fromJson(Map<String, dynamic> j) {
    final authors = (j['authors'] as List?) ?? const [];
    final first = authors.isEmpty ? null : authors.first as Map?;
    return PrCommit(
      oid: _s(j['oid']),
      headline: _s(j['messageHeadline']),
      body: _s(j['messageBody']),
      author: first == null
          ? ''
          : (_s(first['login']).isNotEmpty ? _s(first['login']) : _s(first['name'])),
      date: _s(j['committedDate'] ?? j['authoredDate']),
    );
  }
}

/// A review or a conversation comment, for the timeline.
enum PrEventKind { comment, review, commit }

/// One entry on the conversation timeline: a comment, a review or a commit.
class PrEvent {
  final PrEventKind kind;
  final String author;
  final String body;
  final String at;
  final String reviewState;
  final String reviewId;
  final String sha;
  const PrEvent({
    this.kind = PrEventKind.comment,
    required this.author,
    required this.body,
    required this.at,
    this.reviewState = '',
    this.reviewId = '',
    this.sha = '',
  });
}

class PrThreadComment {
  final int id;
  final String body;
  final String author;
  final String at;
  final String reviewId;
  const PrThreadComment(
      {required this.id,
      required this.body,
      required this.author,
      required this.at,
      required this.reviewId});
  factory PrThreadComment.fromJson(Map<String, dynamic> j) => PrThreadComment(
        id: _i(j['id']),
        body: _s(j['body']),
        author: _s(j['author']),
        at: _s(j['created_at']),
        reviewId: _s(j['review_id']),
      );
}

/// A review thread on a diff: its line or range, state and comments.
class PrThread {
  final String id;
  final String path;
  final int line;
  final int? startLine;
  final String side;
  final bool resolved;
  final bool outdated;
  final List<PrThreadComment> comments;
  const PrThread({
    required this.id,
    required this.path,
    required this.line,
    required this.startLine,
    required this.side,
    required this.resolved,
    required this.outdated,
    required this.comments,
  });
  factory PrThread.fromJson(Map<String, dynamic> j) => PrThread(
        id: _s(j['id']),
        path: _s(j['path']),
        line: _i(j['line']),
        startLine: (j['start_line'] as num?)?.toInt(),
        side: _s(j['side']).isEmpty ? 'RIGHT' : _s(j['side']),
        resolved: j['resolved'] == true,
        outdated: j['outdated'] == true,
        comments: ((j['comments'] as List?) ?? const [])
            .whereType<Map>()
            .map((c) => PrThreadComment.fromJson(c.cast<String, dynamic>()))
            .toList(),
      );
}

class PrDetail {
  final PrSummary summary;
  final String body;
  final String mergeable;
  final String mergeState;
  final String createdAt;
  final String headOid;
  final String autoMergeMethod;
  final String autoMergeBy;
  final List<PrFile> files;
  final List<PrCommit> commits;
  final List<PrEvent> timeline;
  final List<PrThread> threads;
  const PrDetail({
    required this.summary,
    required this.body,
    required this.mergeable,
    required this.mergeState,
    required this.createdAt,
    this.headOid = '',
    this.autoMergeMethod = '',
    this.autoMergeBy = '',
    required this.files,
    required this.commits,
    required this.timeline,
    required this.threads,
  });
  factory PrDetail.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> maps(dynamic v) => ((v as List?) ?? const [])
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
    final commits = maps(j['commits']).map(PrCommit.fromJson).toList();
    final timeline = <PrEvent>[
      for (final r in maps(j['reviews']))
        if (_s(r['state']) != 'PENDING')
          PrEvent(
            kind: PrEventKind.review,
            author: _login(r['author']),
            body: _s(r['body']),
            at: _s(r['submittedAt']),
            reviewState: _s(r['state']),
            reviewId: _s(r['id']),
          ),
      for (final c in maps(j['comments']))
        PrEvent(
          author: _login(c['author']),
          body: _s(c['body']),
          at: _s(c['createdAt']),
        ),
      for (final c in commits)
        PrEvent(
          kind: PrEventKind.commit,
          author: c.author,
          body: c.headline,
          at: c.date,
          sha: c.oid,
        ),
    ]..sort((a, b) => a.at.compareTo(b.at));
    return PrDetail(
      summary: PrSummary.fromJson(j),
      body: _s(j['body']),
      mergeable: _s(j['mergeable']),
      mergeState: _s(j['mergeStateStatus']),
      createdAt: _s(j['createdAt']),
      headOid: _s(j['headRefOid']),
      autoMergeMethod: j['autoMergeRequest'] is Map
          ? _s((j['autoMergeRequest'] as Map)['mergeMethod'])
          : '',
      autoMergeBy: j['autoMergeRequest'] is Map
          ? _login((j['autoMergeRequest'] as Map)['enabledBy'])
          : '',
      files: maps(j['files']).map(PrFile.fromJson).toList(),
      commits: commits,
      timeline: timeline,
      threads: maps(j['threads']).map(PrThread.fromJson).toList(),
    );
  }
}

/// A comment you've written on a diff line, held until the review is
/// submitted.
class PendingComment {
  final String path;
  final int line;
  final String side;
  final int? startLine;
  final String? startSide;
  final String body;
  const PendingComment(
      {required this.path,
      required this.line,
      required this.side,
      this.startLine,
      this.startSide,
      required this.body});
  Map<String, dynamic> toJson() => {
        'path': path,
        'line': line,
        'side': side,
        if (startLine != null && startLine! < line) 'start_line': startLine,
        if (startLine != null && startLine! < line) 'start_side': startSide ?? side,
        'body': body,
      };
}

enum DiffKind { context, add, del, hunk }

class DiffLine {
  final DiffKind kind;
  final String text;
  final int? oldLine;
  final int? newLine;
  const DiffLine(this.kind, this.text, {this.oldLine, this.newLine});

  /// Where a review comment on this line anchors: the new file for added and
  /// unchanged lines, the old file for removed ones.
  (String side, int line)? get anchor => switch (kind) {
        DiffKind.add || DiffKind.context when newLine != null =>
          ('RIGHT', newLine!),
        DiffKind.del when oldLine != null => ('LEFT', oldLine!),
        _ => null,
      };
}

/// A unified diff split by file. Hunk bodies are read by the line counts in
/// their headers, so a changed line that happens to start with `--- ` or
/// `+++ ` is still read as content.
Map<String, List<DiffLine>> parseUnifiedDiff(String diff) {
  final out = <String, List<DiffLine>>{};
  List<DiffLine>? current;
  String? currentKey;
  var oldNo = 0;
  var newNo = 0;
  var oldLeft = 0;
  var newLeft = 0;
  final hunk = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$');
  for (final line in diff.split('\n')) {
    if (oldLeft > 0 || newLeft > 0) {
      if (current == null) break;
      if (line.startsWith('\\')) continue;
      if (line.startsWith('+')) {
        current.add(DiffLine(DiffKind.add, line.substring(1), newLine: newNo++));
        newLeft--;
      } else if (line.startsWith('-')) {
        current.add(DiffLine(DiffKind.del, line.substring(1), oldLine: oldNo++));
        oldLeft--;
      } else {
        current.add(DiffLine(DiffKind.context,
            line.startsWith(' ') ? line.substring(1) : line,
            oldLine: oldNo++, newLine: newNo++));
        oldLeft--;
        newLeft--;
      }
      continue;
    }
    if (line.startsWith('diff --git ')) {
      final m = RegExp(r' b/(.+)$').firstMatch(line);
      current = <DiffLine>[];
      currentKey = m?.group(1) ?? line;
      out[currentKey] = current;
      continue;
    }
    if (current == null) continue;
    if (line.startsWith('+++ b/')) {
      final path = line.substring(6);
      if (currentKey != null && currentKey != path) {
        out.remove(currentKey);
        out[path] = current;
        currentKey = path;
      }
      continue;
    }
    final h = hunk.firstMatch(line);
    if (h != null) {
      oldNo = int.parse(h.group(1)!);
      oldLeft = int.parse(h.group(2) ?? '1');
      newNo = int.parse(h.group(3)!);
      newLeft = int.parse(h.group(4) ?? '1');
      current.add(DiffLine(DiffKind.hunk, line));
    }
  }
  return out;
}
