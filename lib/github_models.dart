/// Pull request data as the daemon returns it from the GitHub CLI.

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
  const GithubStatus({
    required this.available,
    this.reason = '',
    this.repo = '',
    this.url = '',
    this.viewer = '',
    this.permission = '',
  });
  factory GithubStatus.fromJson(Map<String, dynamic> j) => GithubStatus(
        available: j['available'] == true,
        reason: _s(j['reason']),
        repo: _s(j['repo']),
        url: _s(j['url']),
        viewer: _s(j['viewer']),
        permission: _s(j['permission']),
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
  final String author;
  final String date;
  const PrCommit(
      {required this.oid,
      required this.headline,
      required this.author,
      required this.date});
  factory PrCommit.fromJson(Map<String, dynamic> j) {
    final authors = (j['authors'] as List?) ?? const [];
    final first = authors.isEmpty ? null : authors.first as Map?;
    return PrCommit(
      oid: _s(j['oid']),
      headline: _s(j['messageHeadline']),
      author: first == null
          ? ''
          : (_s(first['login']).isNotEmpty ? _s(first['login']) : _s(first['name'])),
      date: _s(j['committedDate'] ?? j['authoredDate']),
    );
  }
}

/// A review or a conversation comment, for the timeline.
class PrEvent {
  final String author;
  final String body;
  final String at;
  final String reviewState;
  const PrEvent(
      {required this.author,
      required this.body,
      required this.at,
      this.reviewState = ''});
}

class PrInlineComment {
  final int id;
  final int? inReplyTo;
  final String path;
  final int line;
  final String side;
  final bool outdated;
  final String body;
  final String author;
  final String at;
  const PrInlineComment({
    required this.id,
    required this.inReplyTo,
    required this.path,
    required this.line,
    required this.side,
    required this.outdated,
    required this.body,
    required this.author,
    required this.at,
  });
  factory PrInlineComment.fromJson(Map<String, dynamic> j) => PrInlineComment(
        id: _i(j['id']),
        inReplyTo: (j['in_reply_to'] as num?)?.toInt(),
        path: _s(j['path']),
        line: _i(j['line']),
        side: _s(j['side']).isEmpty ? 'RIGHT' : _s(j['side']),
        outdated: j['outdated'] == true,
        body: _s(j['body']),
        author: _s(j['author']),
        at: _s(j['created_at']),
      );
}

class PrDetail {
  final PrSummary summary;
  final String body;
  final String mergeable;
  final List<PrFile> files;
  final List<PrCommit> commits;
  final List<PrEvent> timeline;
  final List<PrInlineComment> inline;
  const PrDetail({
    required this.summary,
    required this.body,
    required this.mergeable,
    required this.files,
    required this.commits,
    required this.timeline,
    required this.inline,
  });
  factory PrDetail.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> maps(dynamic v) => ((v as List?) ?? const [])
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
    final timeline = <PrEvent>[
      for (final r in maps(j['reviews']))
        if (_s(r['state']) != 'PENDING')
          PrEvent(
            author: _login(r['author']),
            body: _s(r['body']),
            at: _s(r['submittedAt']),
            reviewState: _s(r['state']),
          ),
      for (final c in maps(j['comments']))
        PrEvent(
          author: _login(c['author']),
          body: _s(c['body']),
          at: _s(c['createdAt']),
        ),
    ]..sort((a, b) => a.at.compareTo(b.at));
    return PrDetail(
      summary: PrSummary.fromJson(j),
      body: _s(j['body']),
      mergeable: _s(j['mergeable']),
      files: maps(j['files']).map(PrFile.fromJson).toList(),
      commits: maps(j['commits']).map(PrCommit.fromJson).toList(),
      timeline: timeline,
      inline: maps(j['inline_comments']).map(PrInlineComment.fromJson).toList(),
    );
  }
}

/// A comment you've written on a diff line, held until the review is
/// submitted.
class PendingComment {
  final String path;
  final int line;
  final String side;
  final String body;
  const PendingComment(
      {required this.path,
      required this.line,
      required this.side,
      required this.body});
  Map<String, dynamic> toJson() =>
      {'path': path, 'line': line, 'side': side, 'body': body};
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

/// A unified diff split by file.
Map<String, List<DiffLine>> parseUnifiedDiff(String diff) {
  final out = <String, List<DiffLine>>{};
  List<DiffLine>? current;
  var oldNo = 0;
  var newNo = 0;
  final hunk = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)$');
  for (final line in diff.split('\n')) {
    if (line.startsWith('diff --git ')) {
      final m = RegExp(r' b/(.+)$').firstMatch(line);
      current = <DiffLine>[];
      out[m?.group(1) ?? line] = current;
      continue;
    }
    if (current == null) continue;
    if (line.startsWith('+++ ')) {
      if (line.startsWith('+++ b/')) {
        final path = line.substring(6);
        final key = out.entries.firstWhere((e) => identical(e.value, current)).key;
        if (key != path) {
          out.remove(key);
          out[path] = current;
        }
      }
      continue;
    }
    if (line.startsWith('--- ') ||
        line.startsWith('index ') ||
        line.startsWith('new file') ||
        line.startsWith('deleted file') ||
        line.startsWith('similarity ') ||
        line.startsWith('rename ') ||
        line.startsWith('old mode') ||
        line.startsWith('new mode') ||
        line.startsWith('Binary files')) {
      continue;
    }
    final h = hunk.firstMatch(line);
    if (h != null) {
      oldNo = int.parse(h.group(1)!);
      newNo = int.parse(h.group(2)!);
      current.add(DiffLine(DiffKind.hunk, line));
      continue;
    }
    if (line.startsWith('+')) {
      current.add(DiffLine(DiffKind.add, line.substring(1), newLine: newNo++));
    } else if (line.startsWith('-')) {
      current.add(DiffLine(DiffKind.del, line.substring(1), oldLine: oldNo++));
    } else if (line.startsWith(' ')) {
      current.add(DiffLine(DiffKind.context, line.substring(1),
          oldLine: oldNo++, newLine: newNo++));
    } else if (line.startsWith('\\')) {
      continue;
    }
  }
  return out;
}
