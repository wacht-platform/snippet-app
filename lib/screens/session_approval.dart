part of 'session.dart';

bool _looksLikeQuestionAnswer(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  if (t == 'user skipped the question') return true;
  return t.contains('\n→ ') || t.startsWith('→ ');
}

class _QuestionRecord extends StatelessWidget {
  final Map<String, dynamic> event;
  final String? answer;
  const _QuestionRecord(this.event, {this.answer});

  List<Map<String, dynamic>> get _questions {
    final qd = event['questions'];
    final raw = qd is Map ? qd['questions'] : event['questions'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  String? get _context {
    final qd = event['questions'];
    final ctx = qd is Map ? qd['context'] : event['context'];
    final s = ctx?.toString() ?? '';
    if (s.isEmpty || s == 'null') return null;
    return s;
  }

  Map<String, String> get _answers {
    final out = <String, String>{};
    final src = (answer ?? event['answer'] ?? event['value'] ?? '').toString();
    if (src.trim().isEmpty) return out;
    final qs = _questions;
    if (qs.length <= 1) {
      final text = qs.isEmpty ? '' : (qs.first['text']?.toString() ?? '');
      var body = src.trim();
      if (text.isNotEmpty && body.startsWith(text)) {
        body = body.substring(text.length).trim();
        if (body.startsWith('→')) body = body.substring(1).trim();
      } else if (body.contains('\n→ ')) {
        body = body.split('\n→ ').skip(1).join('\n→ ').trim();
      }
      out[qs.isEmpty ? '0' : qs.first['id']?.toString() ?? '0'] = body;
      return out;
    }
    final parts = src.split(RegExp(r'\n\n+'));
    for (final part in parts) {
      final idx = part.indexOf('\n→ ');
      if (idx < 0) continue;
      final qText = part.substring(0, idx).trim();
      final a = part.substring(idx + 3).trim();
      for (final q in qs) {
        if ((q['text']?.toString() ?? '').trim() == qText) {
          out[q['id']?.toString() ?? qText] = a;
          break;
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final qs = _questions;
    final answers = _answers;
    final ctx = _context;
    final answered = answers.isNotEmpty;
    Widget answer(String text) => Container(
          margin: const EdgeInsets.only(top: S.s6),
          padding: const EdgeInsets.only(left: S.s8),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.accent, width: 2)),
          ),
          child: Text(text, style: sans(13, height: 1.45, color: AppColors.fg2)),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              AppIcon('message', size: 12, color: AppColors.fg3),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    qs.length > 1 ? 'Questions · ${qs.length}' : 'Question',
                    style: mono(10, color: AppColors.fg3)),
              ),
              Text(answered ? 'answered' : 'no answer',
                  style: mono(10,
                      color: answered ? AppColors.ok : AppColors.fg3)),
            ]),
            if (ctx != null) ...[
              const SizedBox(height: 5),
              Text(ctx,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, height: 1.4, color: AppColors.fg3)),
            ],
            for (var i = 0; i < qs.length; i++) ...[
              SizedBox(height: i == 0 ? 5 : S.s12),
              Text(
                  qs.length > 1
                      ? '${i + 1}. ${qs[i]['text'] ?? ''}'
                      : qs[i]['text']?.toString() ?? '',
                  style: sans(13,
                      height: 1.45, weight: W.label, color: AppColors.fg1)),
              if (answers[qs[i]['id']?.toString() ?? ''] != null ||
                  answers['0'] != null)
                answer(answers[qs[i]['id']?.toString()] ?? answers['0'] ?? ''),
            ],
            if (qs.isEmpty && (event['text'] != null)) ...[
              const SizedBox(height: 5),
              Text(event['text']?.toString() ?? '',
                  style: sans(13,
                      height: 1.45, weight: W.label, color: AppColors.fg1)),
            ],
          ],
        ),
      ),
    );
  }
}

class ApprovalBar extends StatefulWidget {
  final List<Map<String, dynamic>> events;
  final void Function(Map<String, dynamic>) onSend;
  final bool showApproveAll;
  const ApprovalBar(
      {super.key,
      required this.events,
      required this.onSend,
      this.showApproveAll = false});
  @override
  State<ApprovalBar> createState() => ApprovalBarState();
}

class ApprovalBarState extends State<ApprovalBar> {
  bool _sent = false;

  void _decide(Map<String, dynamic> m) {
    if (_sent) return;
    setState(() => _sent = true);
    widget.onSend(m);
  }

  Map<String, dynamic>? get _request {
    for (var i = widget.events.length - 1; i >= 0; i--) {
      final e = widget.events[i];
      if (e['kind'] == 'approval_request') return e;
    }
    return null;
  }

  static final _vaultPrefix = RegExp(
      r'^\s*⚠?\s*uses vault secret\(s\) \[([^\]]*)\]\s*[—-]\s*',
      dotAll: true);

  @override
  Widget build(BuildContext context) {
    final req = _request;
    final tool = req?['tool_name']?.toString() ?? '';
    var detail = (req?['summary']?.toString() ?? '').trim();
    if (detail.isEmpty) detail = toolArgSummary(tool, req?['arguments']);
    final vault = _vaultPrefix.firstMatch(detail);
    final secrets = vault == null
        ? const <String>[]
        : vault
            .group(1)!
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
    if (vault != null) detail = detail.substring(vault.end).trim();
    final isVault = secrets.isNotEmpty;
    final index = (req?['index'] as num?)?.toInt() ?? 1;
    final total = (req?['total'] as num?)?.toInt() ?? 1;
    final question = switch (tool) {
      'bash' => 'Run this command?',
      'change_files' => 'Make these file changes?',
      '' => 'Allow this action?',
      _ => 'Allow ${toolTitle(tool).toLowerCase()}?',
    };
    final isShell = tool == 'bash';

    final allow = Btn(_sent ? 'Sending' : 'Allow',
        small: true,
        disabled: _sent,
        onTap: () => _decide({'kind': 'approve'}));
    final reject = Btn('Reject',
        small: true,
        variant: BtnVariant.secondary,
        disabled: _sent,
        onTap: () => _decide({'kind': 'deny'}));
    final canAlways = widget.showApproveAll && !isVault;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, S.s4, 0, S.s6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(S.s12),
        decoration: BoxDecoration(
          color: AppColors.raised,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(
              color: (isVault ? AppColors.run : AppColors.accent)
                  .withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              AppIcon(isVault ? 'lock-key' : toolIcon(tool),
                  size: 15, color: isVault ? AppColors.run : AppColors.accent),
              const SizedBox(width: S.s8),
              Expanded(
                  child: Text(question,
                      style: TS.ui(AppColors.fg1)
                          .copyWith(fontWeight: FontWeight.w600))),
              if (total > 1) ...[
                const SizedBox(width: S.s8),
                Tag('$index of $total', mono: true),
              ],
            ]),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: S.s8),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.fromLTRB(S.s8, S.s6, S.s8, S.s6),
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: BorderRadius.circular(R.sm + 2),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText.rich(TextSpan(children: [
                        if (isShell)
                          TextSpan(
                              text: '\$ ',
                              style: mono(12,
                                  height: 1.45, color: AppColors.accent)),
                        TextSpan(
                            text: detail,
                            style: mono(12, height: 1.45, color: AppColors.fg1)),
                      ])),
                    ),
                  ),
                ),
              ),
            ],
            if (isVault) ...[
              const SizedBox(height: S.s8),
              InsetPanel(
                tone: Tone.run,
                padding: const EdgeInsets.all(S.s8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Uses vault secrets · values stay on the machine',
                        style: TS.meta(AppColors.run)),
                    const SizedBox(height: S.s6),
                    Wrap(spacing: S.s6, runSpacing: S.s6, children: [
                      for (final name in secrets)
                        Tag(name, tone: Tone.run, icon: 'key', mono: true),
                    ]),
                  ],
                ),
              ),
            ],
            const SizedBox(height: S.s8),
              Row(children: [
                if (canAlways)
                  TextAction('Always allow',
                      onTap: _sent
                          ? null
                          : () => _decide({'kind': 'approve_all'})),
                const Spacer(),
                reject,
                const SizedBox(width: S.s8),
                allow,
              ]),
          ],
        ),
      ),
    );
  }
}

/// The agent's plan as a compact checklist: done steps recede, the step in
/// progress is highlighted, and the optional explanation says why it changed.
class _PlanCard extends StatelessWidget {
  final List<Map> steps;
  final String explanation;
  const _PlanCard(this.steps, this.explanation);

  @override
  Widget build(BuildContext context) {
    final done = steps.where((s) => s['status'] == 'done').length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Plan · $done of ${steps.length} done',
                style: mono(10, color: AppColors.fg3)),
            if (explanation.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(explanation, style: sans(12, color: AppColors.fg2)),
            ],
            const SizedBox(height: 6),
            for (final step in steps) _row(step),
          ],
        ),
      ),
    );
  }

  Widget _row(Map step) {
    final status = step['status']?.toString() ?? 'pending';
    final (icon, color) = switch (status) {
      'done' => (Icons.check_circle, AppColors.ok),
      'in_progress' => (Icons.radio_button_checked, AppColors.accent),
      _ => (Icons.radio_button_unchecked, AppColors.fg4),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 13, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              step['step']?.toString() ?? '',
              style: sans(13,
                  color: status == 'done' ? AppColors.fg3 : AppColors.fg1,
                  weight: status == 'in_progress' ? W.label : W.body),
            ),
          ),
        ],
      ),
    );
  }
}

class QuestionBar extends StatefulWidget {
  final Map<String, dynamic> question;
  final void Function(Map<String, dynamic>) onSend;
  const QuestionBar({super.key, required this.question, required this.onSend});
  @override
  State<QuestionBar> createState() => QuestionBarState();
}

class QuestionBarState extends State<QuestionBar> {
  final Map<String, TextEditingController> _text = {};
  final Map<String, String> _choice = {};
  final Set<String> _skipped = {};
  final Set<String> _freeText = {};
  bool _sent = false;
  int _step = 0;

  TextEditingController _controllerFor(String id) {
    return _text.putIfAbsent(id, () {
      final c = TextEditingController();
      c.addListener(_onAnswerChanged);
      return c;
    });
  }

  void _onAnswerChanged() {
    if (mounted) setState(() {});
  }

  Map<String, dynamic>? get _currentQuestion => _questions.isEmpty
      ? null
      : _questions[_step.clamp(0, _questions.length - 1)];

  List<Map<String, dynamic>> get _questions =>
      ((widget.question['questions'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  String _kind(Map<String, dynamic> q) =>
      (q['answer_kind'] is Map ? q['answer_kind']['kind'] : null)?.toString() ??
      'free_text';

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _ready {
    final q = _currentQuestion;
    if (q == null) return false;
    final id = q['id'].toString();
    if (_skipped.contains(id)) return true;
    final textMode = _kind(q) == 'free_text' || _freeText.contains(id);
    return textMode
        ? (_text[id]?.text.trim().isNotEmpty ?? false)
        : (_choice[id]?.isNotEmpty ?? false);
  }

  String _answerFor(Map<String, dynamic> q) {
    final id = q['id'].toString();
    if (_skipped.contains(id)) return 'user skipped the question';
    final textMode = _kind(q) == 'free_text' || _freeText.contains(id);
    return textMode ? (_text[id]?.text.trim() ?? '') : (_choice[id] ?? '');
  }

  void _submit() {
    if (_questions.isEmpty || !_ready || _sent) return;
    if (_step < _questions.length - 1) {
      setState(() => _step++);
      return;
    }
    setState(() => _sent = true);
    final parts =
        _questions.map((q) => '${q['text']}\n→ ${_answerFor(q)}').toList();
    widget.onSend({'kind': 'answer', 'value': parts.join('\n\n')});
  }

  void _skip() {
    final q = _currentQuestion;
    if (q == null || _sent) return;
    _skipped.add(q['id'].toString());
    _freeText.remove(q['id'].toString());
    _choice.remove(q['id'].toString());
    if (_step < _questions.length - 1) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _toggleFreeText() {
    final q = _currentQuestion;
    if (q == null || _sent) return;
    final id = q['id'].toString();
    setState(() {
      _skipped.remove(id);
      _freeText.contains(id) ? _freeText.remove(id) : _freeText.add(id);
    });
  }

  Widget _freeTextToggle(String id) => InkWell(
        onTap: _sent ? null : _toggleFreeText,
        borderRadius: BorderRadius.circular(R.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(_freeText.contains(id) ? 'check' : 'edit',
                size: 14, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(
                _freeText.contains(id)
                    ? 'Writing a response'
                    : 'Write your own answer',
                style: TS.label(AppColors.accent)),
          ]),
        ),
      );

  Widget _skipButton() => TextButton(
        onPressed: _sent ? null : _skip,
        style: TextButton.styleFrom(
            foregroundColor: AppColors.fg3,
            padding: const EdgeInsets.symmetric(horizontal: 8)),
        child: Text('Skip', style: TS.meta()),
      );

  Widget _chip(String label, bool sel, VoidCallback onTap) => Material(
        color: sel ? AppColors.accentBg : AppColors.hover,
        shape: StadiumBorder(
          side: BorderSide(
            color: sel ? AppColors.accent : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s6),
            child: Text(label,
                style: TS.label(sel ? AppColors.accent : AppColors.fg2)),
          ),
        ),
      );

  Widget _choiceRow(String label, bool sel, VoidCallback onTap) => Material(
        color: sel ? AppColors.accentBg : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
          side: BorderSide(
            color: sel ? AppColors.accent : AppColors.border2,
            width: sel ? 1.2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s8),
            child: Row(children: [
              Expanded(
                  child: Text(label,
                      style: TS.ui(sel ? AppColors.fg1 : AppColors.fg2))),
              if (sel) ...[
                const SizedBox(width: 10),
                AppIcon('check', size: 16, color: AppColors.accent)
              ],
            ]),
          ),
        ),
      );

  List<Widget> _inputFor(Map<String, dynamic> q) {
    final id = q['id'].toString();
    final k = _kind(q);
    final opts =
        k == 'confirm' ? const ['Confirm', 'Cancel'] : const ['Yes', 'No'];
    final vals =
        k == 'confirm' ? const ['confirm', 'cancel'] : const ['yes', 'no'];
    final choices =
        ((q['answer_kind']?['choices'] as List?) ?? const []).map((e) {
      if (e is Map) {
        final label = '${e['label'] ?? ''}'.trim();
        final value = '${e['value'] ?? ''}'.trim();
        final v = value.isEmpty ? label : value;
        return (value: v, label: label.isEmpty ? v : label);
      }
      final s = '$e';
      return (value: s, label: s);
    }).toList();
    final controller = _controllerFor(id);
    return [
      if (k == 'single_choice')
        ...choices.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: S.s6),
              child: _choiceRow(
                  c.label,
                  _choice[id] == c.value,
                  () => setState(() {
                        _choice[id] = c.value;
                        _freeText.remove(id);
                      })),
            )),
      if (k == 'yes_no' || k == 'confirm')
        Wrap(spacing: 8, children: [
          for (var i = 0; i < opts.length; i++)
            _chip(opts[i], _choice[id] == vals[i],
                () => setState(() => _choice[id] = vals[i])),
        ]),
      if (k == 'single_choice' || k == 'yes_no' || k == 'confirm')
        _freeTextToggle(id),
      if (k == 'free_text' || _freeText.contains(id))
        AppField(
            controller: controller,
            hint: 'Write your answer',
            minLines: 2,
            maxLines: 4,
            onSubmitted: (_) => _submit()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.question['context']?.toString();
    final total = _questions.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, S.s4, 0, S.s6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        // Same card as the transcript's, outlined in accent: it is the one
        // thing waiting on you.
        decoration: BoxDecoration(
          color: AppColors.surface1,
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                AppIcon('message', size: 12, color: AppColors.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_sent ? 'Sending…' : 'Question',
                      style: mono(10, color: AppColors.fg3)),
                ),
                Text(total > 1 ? '${_step + 1} of $total' : 'waiting on you',
                    style: mono(10, color: AppColors.accent)),
              ]),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (ctx != null && ctx.isNotEmpty && ctx != 'null') ...[
                        const SizedBox(height: 6),
                        Text(ctx,
                            style: sans(kMobile ? 13 : 12,
                                height: 1.4, color: AppColors.fg3)),
                      ],
                      ...() {
                        final q = _currentQuestion;
                        if (q == null) return <Widget>[];
                        return <Widget>[
                          const SizedBox(height: 6),
                          Text(q['text']?.toString() ?? '',
                              style: sans(kMobile ? 15 : 14,
                                  height: 1.4,
                                  weight: W.label,
                                  color: AppColors.fg1)),
                          const SizedBox(height: S.s8),
                          ..._inputFor(q),
                        ];
                      }(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: S.s8),
              Row(children: [
                _skipButton(),
                if (_step > 0) ...[
                  const SizedBox(width: 4),
                  Btn('Back',
                      small: true,
                      variant: BtnVariant.ghost,
                      onTap: _sent ? null : () => setState(() => _step--)),
                ],
                const Spacer(),
                Btn(
                    _sent
                        ? 'Sending…'
                        : (_step < total - 1 ? 'Continue' : 'Submit'),
                    small: true,
                    disabled: !_ready || _sent,
                    onTap: (_ready && !_sent) ? _submit : null),
              ]),
            ]),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  const _WaveformPainter(this.samples);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (samples.isEmpty) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint..color = AppColors.fg4,
      );
      return;
    }
    final waveformWidth = math.min(size.width, samples.length * 4.0);
    for (var i = 0; i < samples.length; i++) {
      final amplitude = samples[i].clamp(0.04, 1.0).toDouble();
      final half =
          (size.height * 0.45 * amplitude).clamp(2.0, size.height * 0.45);
      final x = i * 4.0 + 2.0;
      if (x > waveformWidth) break;
      canvas.drawLine(
        Offset(x, size.height / 2 - half),
        Offset(x, size.height / 2 + half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.samples != samples;
}

class _Attachment {
  final String name;
  final bool isImage;
  final bool isAudio;
  final String? localPath;
  String? remotePath;
  bool uploading = true;

  /// Text pasted into the composer, kept as a card and sent inline.
  String? pastedText;
  _Attachment(
      {required this.name,
      required this.isImage,
      required this.isAudio,
      this.localPath});

  _Attachment.pasted(String text)
      : name = 'Pasted text',
        isImage = false,
        isAudio = false,
        localPath = null,
        pastedText = text,
        uploading = false;

  /// Brought back from a saved draft: already uploaded (or pasted), so ready.
  _Attachment.fromDraft(DraftAttachment d)
      : name = d.name,
        isImage = d.isImage,
        isAudio = d.isAudio,
        localPath = d.localPath,
        remotePath = d.remotePath,
        pastedText = d.pastedText,
        uploading = false;

  DraftAttachment toDraft() => DraftAttachment(
        name: name,
        isImage: isImage,
        isAudio: isAudio,
        localPath: localPath,
        remotePath: remotePath,
        pastedText: pastedText,
      );

  bool get ready => remotePath != null || pastedText != null;

  /// How this attachment is referenced in the outgoing message.
  String get marker {
    final pasted = pastedText;
    if (pasted != null) return pastedTextBlock(pasted);
    return isImage
        ? '[attached image — call view_image on this exact path to see it: $remotePath]'
        : '[attached file — read it at this exact path: $remotePath]';
  }
}

class _SendBtn extends StatelessWidget {
  final bool enabled;
  final bool running;
  final VoidCallback? onTap;
  const _SendBtn({required this.enabled, this.running = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final size = kMobile ? M.minTarget : 32.0;
    final iconSize = running ? 14.0 : 16.0;
    final fill = !enabled
        ? AppColors.hover
        : running
            ? AppColors.fg1
            : AppColors.accentFill;
    final ink = !enabled
        ? AppColors.fg4
        : running
            ? AppColors.canvas
            : AppColors.accentFg;
    return Material(
      color: fill,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
              child: AppIcon(running ? 'stop' : 'arrow-up',
                  size: iconSize, color: ink)),
        ),
      ),
    );
  }
}

class _SessionActionsPanel extends StatefulWidget {
  final HarnessState? session;
  final void Function(String text) onSetGoal;
  final VoidCallback onCancelGoal;
  final VoidCallback onResumeGoal;
  final VoidCallback onLanes;
  final VoidCallback? onTasks;
  final VoidCallback? onGiveWork;
  final bool hideShell;
  final VoidCallback onTerm;
  final VoidCallback onGit;
  final VoidCallback onFiles;
  final VoidCallback onProcesses;
  final VoidCallback onRecurring;
  final VoidCallback onCompact;
  final VoidCallback onCheckpoints;
  final bool hideWorkspace;
  final bool hideGoal;
  final bool hideCheckpoints;
  const _SessionActionsPanel({
    required this.session,
    required this.onSetGoal,
    required this.onCancelGoal,
    required this.onResumeGoal,
    required this.onLanes,
    this.onTasks,
    this.onGiveWork,
    this.hideShell = false,
    required this.onTerm,
    required this.onGit,
    required this.onFiles,
    required this.onProcesses,
    required this.onRecurring,
    required this.onCompact,
    required this.onCheckpoints,
    this.hideWorkspace = false,
    this.hideGoal = false,
    this.hideCheckpoints = false,
  });

  @override
  State<_SessionActionsPanel> createState() => _SessionActionsPanelState();
}

class _SessionActionsPanelState extends State<_SessionActionsPanel> {
  String? _open;
  late final TextEditingController _goalCtl = TextEditingController();

  @override
  void dispose() {
    _goalCtl.dispose();
    super.dispose();
  }

  void _toggle(String id) => setState(() => _open = _open == id ? null : id);

  Widget _group(String label, List<Widget> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child:
              Text(label.toUpperCase(), style: caps(10, color: AppColors.fg3)),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(R.md),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Container(height: 1, color: AppColors.border),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _row({
    required String icon,
    required String label,
    String? detail,
    String? value,
    String? id,
    VoidCallback? onTap,
    Widget? child,
  }) {
    final open = id != null && _open == id;
    final expandable = id != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap ?? (expandable ? () => _toggle(id) : null),
            child: Container(
              constraints: const BoxConstraints(minHeight: M.minTarget + 8),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                AppIcon(icon, size: 17, color: AppColors.fg3),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: sans(M.rowTitle,
                              weight: W.label, color: AppColors.fg1)),
                      if (detail != null) ...[
                        const SizedBox(height: 2),
                        Text(detail,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: sans(M.meta, color: AppColors.fg3)),
                      ],
                    ],
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: sans(M.meta, color: AppColors.fg3)),
                  ),
                ],
                const SizedBox(width: 8),
                if (expandable)
                  AppIcon(open ? 'chevron-down' : 'chevron-right',
                      size: 15, color: AppColors.fg4),
              ]),
            ),
          ),
        ),
        if (open && child != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: child,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final goalOn = s?.goal?.ongoing ?? false;

    final sessionRows = <Widget>[
      if (!widget.hideGoal)
        _row(
          icon: 'zap',
          label: goalOn ? 'Goal' : 'Set a goal',
          detail: goalOn
              ? 'The agent is driving toward this autonomously'
              : 'Give the agent something to work toward on its own',
          id: 'goal',
          value: goalOn ? (s!.goal!.paused ? 'paused' : 'running') : null,
          child: goalOn
              ? Btn(s!.goal!.paused ? 'Resume goal' : 'Cancel goal',
                  variant: BtnVariant.secondary,
                  onTap: s.goal!.paused
                      ? widget.onResumeGoal
                      : widget.onCancelGoal)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppField(
                        controller: _goalCtl,
                        hint: 'What should the agent work toward?',
                        minLines: 2,
                        maxLines: 4),
                    const SizedBox(height: 8),
                    Btn('Set goal', onTap: () {
                      final t = _goalCtl.text.trim();
                      if (t.isEmpty) return;
                      widget.onSetGoal(t);
                      _goalCtl.clear();
                    }),
                  ],
                ),
        ),
      if (!kMacOS && !widget.hideGoal && (s?.lanes.isNotEmpty ?? false))
        _row(
            icon: 'layers',
            label: 'Lanes',
            detail: 'Background work running in parallel',
            onTap: widget.onLanes),
      if (widget.onTasks != null)
        _row(
            icon: 'layers',
            label: 'Tasks',
            detail: 'Plan and progress for this run',
            onTap: widget.onTasks),
      if (widget.onGiveWork != null)
        _row(
            icon: 'send',
            label: 'Message an agent',
            detail: 'Send a message to an agent from this session',
            onTap: widget.onGiveWork),
      _row(
          icon: 'scheduled',
          label: 'Scheduled',
          detail: 'Recurring jobs on this machine',
          onTap: widget.onRecurring),
    ];

    final workspaceRows = <Widget>[
      if (!kMacOS)
        _row(
            icon: 'git-branch',
            label: 'Git',
            detail: 'Status, diffs, stage and commit',
            onTap: widget.onGit),
      _row(
          icon: 'folder',
          label: 'Files',
          detail: 'Browse the workspace',
          onTap: widget.onFiles),
      if (!widget.hideShell)
        _row(
            icon: 'terminal',
            label: 'Session shell',
            detail: 'A terminal in this workspace',
            onTap: widget.onTerm),
      _row(
          icon: 'list',
          label: 'Processes',
          detail: 'What is running on the machine',
          onTap: widget.onProcesses),
    ];

    final historyRows = <Widget>[
      _row(
          icon: 'minimize',
          label: 'Compact history',
          detail: 'Summarise older turns to free context',
          onTap: widget.onCompact),
      if (!widget.hideCheckpoints)
        _row(
            icon: 'history',
            label: 'Checkpoints',
            detail: 'Restore the workspace to an earlier point',
            onTap: widget.onCheckpoints),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _group('Session', sessionRows),
        if (!widget.hideWorkspace) _group('Workspace', workspaceRows),
        _group('History', historyRows),
      ],
    );
  }
}
