import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_widgets.dart';
import '../../../auth/session.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/usecases/booking_usecases.dart';
import '../bloc/booking_bloc.dart';

/// The booking form.
///
/// Deliberately NOT validated here: whether the slot is free, whether
/// the tutee can afford it, whether this pair has hit its weekly cap.
/// All three need the database, and checking them from the app would be
/// a race — two tutees could both be told a slot is free before either
/// had written anything. Oracle decides, under a row lock, and if it
/// refuses, the message it sends back is shown as-is.
class BookSessionPage extends StatefulWidget {
  const BookSessionPage({super.key});

  @override
  State<BookSessionPage> createState() => _BookSessionPageState();
}

class _BookSessionPageState extends State<BookSessionPage> {
  final _formKey = GlobalKey<FormState>();

  /// The other person, as a registration number. Yours is not asked
  /// for — you are signed in, so the app already knows it.
  final _otherRef = TextEditingController();

  final ApiClient _api = sl<ApiClient>();

  /// The tutor's published hours. A slot number means nothing on its
  /// own — it is counted per tutor — so the form fetches the real ones
  /// and shows them rather than asking anybody to guess.
  List<dynamic> _slots = [];
  int? _slotPicked;
  bool _loadingSlots = false;
  String? _slotError;
  final _venue = TextEditingController();

  /// 'LEARN' = the person booking is the tutee.
  /// 'TEACH' = the person booking is the tutor.
  ///
  /// Whichever they pick, the API enrols them into that subclass if
  /// they are not already in it -- and leaves the other one alone,
  /// because the specialization is OVERLAPPING. Pick LEARN today and
  /// TEACH next week and the Students screen shows you as BOTH.
  String _intent = 'LEARN';

  int _subjectId = 101;
  DateTime? _date;
  double _startTime = 16;
  double _duration = 1.0;
  String _mode = 'OFFLINE';

  /// Mirrors the seeded SUBJECT table.
  static const _subjects = {
    101: 'BACSE202 · Database Systems',
    102: 'BACSE203 · Data Communications',
    103: 'BACSE201 · Theory of Computation',
    104: 'BMAT201 · Probability and Statistics',
    105: 'BPHY101 · Engineering Physics',
    106: 'BMEE201 · Thermodynamics',
    107: 'BEEE202 · Signals and Systems',
    108: 'BACSE301 · Algorithms',
    109: 'BMGT101 · Principles of Management',
    110: 'BACSE204 · Operating Systems',
  };

  @override
  void dispose() {
    for (final c in [_otherRef, _venue]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book a session')),
      body: BlocListener<BookingBloc, BookingState>(
        listener: (context, state) {
          // Pop on success so the dialog with the session code appears
          // over the list, not over this form.
          if (state is BookingCreated) {
            Navigator.of(context).pop();
          } else if (state is BookingFailure) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: Text(state.message),
                duration: const Duration(seconds: 5),
              ));
          }
        },
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
            children: [
              const InfoBanner(
                'Credits are set aside when you book, and go to the tutor '
                'once you both confirm the session happened.',
                icon: Icons.lock_outline,
                tint: AppColors.accent,
              ),

              const SectionLabel('Are you learning or teaching?'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'LEARN',
                    label: Text('I am learning'),
                    icon: Icon(Icons.school_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: 'TEACH',
                    label: Text('I am teaching'),
                    icon: Icon(Icons.co_present_outlined, size: 18),
                  ),
                ],
                selected: {_intent},
                showSelectedIcon: false,
                onSelectionChanged: (set) {
                  setState(() {
                    _intent = set.first;
                    _slots = [];
                    _slotPicked = null;
                    _slotError = null;
                  });
                  _loadSlots();
                },
              ),
              const SizedBox(height: 8),
              InfoBanner(
                _intent == 'LEARN'
                    ? 'If you have not booked help before, this sets you up '
                      'as a learner. Anything you teach stays as it is.'
                    : 'If you have not taught before, this sets you up as a '
                      'mentor for the subject below. Anything you learn '
                      'stays as it is.',
                icon: Icons.account_tree_outlined,
              ),

              const SectionLabel('Who with'),
              TextFormField(
                controller: _otherRef,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontSize: 14.5),
                decoration: InputDecoration(
                  labelText: _intent == 'LEARN'
                      ? "Tutor's registration number"
                      : "Student's registration number",
                  hintText: '25BCE1001',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                onEditingComplete: _loadSlots,
                onChanged: (_) {
                  if (_slots.isNotEmpty || _slotError != null) {
                    setState(() {
                      _slots = [];
                      _slotPicked = null;
                      _slotError = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 6),
              Text(
                'Signed in as ${currentSession.value?.regNo ?? ""}',
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.textMuted),
              ),

              const SectionLabel('Subject'),
              _Dropdown<int>(
                value: _subjectId,
                items: _subjects,
                onChanged: (v) => setState(() => _subjectId = v),
              ),

              const SectionLabel('When'),
              _DateField(
                value: _date,
                onPick: (d) => setState(() => _date = d),
              ),
              const SizedBox(height: 12),
              _slotPicker(),

              const SizedBox(height: 18),
              _SliderRow(
                label: 'Start time',
                value: _startTime,
                min: 6,
                max: 21,
                divisions: 30,
                display: _clock(_startTime),
                onChanged: (v) => setState(() => _startTime = v),
              ),

              const SectionLabel('How long'),
              _DurationPicker(
                value: _duration,
                onChanged: (v) => setState(() => _duration = v),
              ),

              const SectionLabel('Where'),
              _ModeToggle(
                value: _mode,
                onChanged: (v) => setState(() => _mode = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _venue,
                style: const TextStyle(fontSize: 14.5),
                decoration: InputDecoration(
                  labelText: _mode == 'ONLINE' ? 'Meeting link' : 'Room',
                  hintText: _mode == 'ONLINE' ? 'Google Meet' : 'SJT 512',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Say where the session happens'
                    : null,
              ),

              const SizedBox(height: 26),
              _CostSummary(duration: _duration),
              const SizedBox(height: 18),

              BlocBuilder<BookingBloc, BookingState>(
                builder: (context, state) {
                  final busy = state is BookingLoading;
                  return SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox(
                              width: 19,
                              height: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.canvas,
                              ),
                            )
                          : Text('Book and set aside '
                              '${_duration.toStringAsFixed(1)} credits'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numField(TextEditingController c, String label, {String? hint}) =>
      TextFormField(
        controller: c,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 14.5),
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Required';
          if (int.tryParse(v.trim()) == null) return 'Numbers only';
          return null;
        },
      );


  // -------------------------------------------------------------------
  //  The tutor's published hours
  // -------------------------------------------------------------------

  /// Whose availability matters: the other person when you are learning,
  /// yourself when you are teaching.
  String get _tutorRef => _intent == 'LEARN'
      ? _otherRef.text.trim().toUpperCase()
      : (currentSession.value?.regNo ?? '');

  Future<void> _loadSlots() async {
    final ref = _tutorRef;
    if (ref.isEmpty) return;

    setState(() {
      _loadingSlots = true;
      _slotError = null;
    });

    try {
      final data = await _api.get('/api/skills/slots/$ref') as List;
      if (!mounted) return;
      setState(() {
        _slots = data;
        _slotPicked = data.isEmpty ? null : _slotNoOf(data.first);
        if (data.isNotEmpty) _applySlot(data.first);
        _loadingSlots = false;
      });
    } catch (e) {
      if (!mounted) return;
      final raw = '$e';
      final i = raw.indexOf(': ');
      setState(() {
        _slots = [];
        _slotPicked = null;
        _slotError = i > 0 && i < 40 ? raw.substring(i + 2) : raw;
        _loadingSlots = false;
      });
    }
  }

  static int _slotNoOf(dynamic s) =>
      (num.tryParse('${s['slotNo']}') ?? 0).toInt();

  static double _numOf(dynamic v) => (num.tryParse('$v') ?? 0).toDouble();

  /// Moves the start time inside the chosen slot, and nudges the date on
  /// to that slot's weekday, so the form cannot produce a booking the
  /// database would refuse.
  void _applySlot(dynamic slot) {
    final start = _numOf(slot['startTime']);
    final end = _numOf(slot['endTime']);

    _startTime = start;
    if (_startTime + _duration > end) {
      _duration = (end - start) >= 1 ? 1.0 : 0.5;
    }

    const days = {
      'MON': DateTime.monday,
      'TUE': DateTime.tuesday,
      'WED': DateTime.wednesday,
      'THU': DateTime.thursday,
      'FRI': DateTime.friday,
      'SAT': DateTime.saturday,
      'SUN': DateTime.sunday,
    };
    final want = days[slot['dayOfWeek']?.toString()];
    if (want != null) {
      var d = _date ?? DateTime.now().add(const Duration(days: 1));
      if (d.isBefore(DateTime.now())) {
        d = DateTime.now().add(const Duration(days: 1));
      }
      while (d.weekday != want) {
        d = d.add(const Duration(days: 1));
      }
      _date = d;
    }
  }

  Widget _slotPicker() {
    if (_loadingSlots) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_slotError != null) {
      return InfoBanner(_slotError!,
          icon: Icons.error_outline, tint: AppColors.negative);
    }

    if (_slots.isEmpty) {
      final askedFor = _intent == 'LEARN'
          ? 'Enter the tutor\'s registration number above to see when '
            'they are free.'
          : 'You have not added any free hours yet. Add them on the '
            'Subjects screen, under My hours.';
      return InfoBanner(askedFor, icon: Icons.schedule);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'FREE HOURS',
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        for (final slot in _slots)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SlotTile(
              day: slot['dayOfWeek']?.toString() ?? '',
              from: _numOf(slot['startTime']),
              to: _numOf(slot['endTime']),
              taken: slot['state'] != 'free',
              selected: _slotPicked == _slotNoOf(slot),
              onTap: () => setState(() {
                _slotPicked = _slotNoOf(slot);
                _applySlot(slot);
              }),
            ),
          ),
      ],
    );
  }

  static String _clock(double t) {
    final h = t.floor();
    final m = ((t - h) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final me = currentSession.value?.regNo ?? '';
    final other = _otherRef.text.trim().toUpperCase();

    if (me.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in again — your session expired.')),
      );
      return;
    }

    if (_slotPicked == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose one of the free hours.')),
      );
      return;
    }

    if (_date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a date for the session.')),
      );
      return;
    }

    context.read<BookingBloc>().add(SessionBooked(
          BookSessionParams(
            tuteeRef: _intent == 'LEARN' ? me : other,
            tutorRef: _intent == 'LEARN' ? other : me,
            subjectId: _subjectId,
            slotNo: _slotPicked!,
            schedDate: _date!,
            startTime: _startTime,
            durationHours: _duration,
            mode: _mode,
            venue: _venue.text.trim(),
            intent: _intent,
            studentRef: me,
          ),
        ));
  }
}

// ---------------------------------------------------------------------

class _Dropdown<T> extends StatelessWidget {
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(10),
            style:
                const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            icon: const Icon(Icons.expand_more,
                size: 20, color: AppColors.textMuted),
            items: items.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => v == null ? null : onChanged(v),
          ),
        ),
      );
}

class _DateField extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime> onPick;
  const _DateField({required this.value, required this.onPick});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? now.add(const Duration(days: 1)),
            firstDate: now.subtract(const Duration(days: 30)),
            lastDate: now.add(const Duration(days: 60)),
            builder: (context, child) => Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: AppColors.accent,
                  onPrimary: AppColors.canvas,
                  surface: AppColors.surface,
                ),
              ),
              child: child!,
            ),
          );
          if (picked != null) onPick(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: value == null ? AppColors.border : AppColors.accentDim,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_outlined,
                  size: 17, color: AppColors.textMuted),
              const SizedBox(width: 12),
              Text(
                value == null
                    ? 'Choose a date'
                    : '${_weekday(value!)}  '
                        '${value!.day.toString().padLeft(2, '0')}'
                        '/${value!.month.toString().padLeft(2, '0')}'
                        '/${value!.year}',
                style: TextStyle(
                  fontSize: 14.5,
                  color: value == null
                      ? AppColors.textMuted
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      );

  static String _weekday(DateTime d) =>
      const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][d.weekday - 1];
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              const Spacer(),
              Text(
                display,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.surfaceHover,
              thumbColor: AppColors.accent,
              overlayColor: AppColors.accentWash,
              trackHeight: 3,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      );
}

/// Only the four durations the CHECK constraint allows.
class _DurationPicker extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _DurationPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
        children: [0.5, 1.0, 1.5, 2.0].map((d) {
          final active = d == value;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onChanged(d),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.accentWash
                        : AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: active ? AppColors.accentDim : AppColors.border,
                    ),
                  ),
                  child: Text(
                    '${d}h',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active
                          ? AppColors.accent
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      );
}

class _ModeToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _ModeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
        children: ['OFFLINE', 'ONLINE'].map((m) {
          final active = m == value;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onChanged(m),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.accentWash
                        : AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: active ? AppColors.accentDim : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        m == 'ONLINE'
                            ? Icons.videocam_outlined
                            : Icons.place_outlined,
                        size: 16,
                        color: active
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        m == 'ONLINE' ? 'Online' : 'In person',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w500,
                          color: active
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      );
}

class _CostSummary extends StatelessWidget {
  final double duration;
  const _CostSummary({required this.duration});

  @override
  Widget build(BuildContext context) => Panel(
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('COST TO THE TUTEE',
                    style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 6),
                const Text(
                  'One hour of tutoring is one credit',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
            const Spacer(),
            Text(
              duration.toStringAsFixed(1),
              style: Theme.of(context).textTheme.displaySmall,
            ),
          ],
        ),
      );
}

/// One of a tutor's published hours.
class _SlotTile extends StatelessWidget {
  final String day;
  final double from;
  final double to;
  final bool taken;
  final bool selected;
  final VoidCallback onTap;

  const _SlotTile({
    required this.day,
    required this.from,
    required this.to,
    required this.taken,
    required this.selected,
    required this.onTap,
  });

  static const _full = {
    'MON': 'Monday',
    'TUE': 'Tuesday',
    'WED': 'Wednesday',
    'THU': 'Thursday',
    'FRI': 'Friday',
    'SAT': 'Saturday',
    'SUN': 'Sunday',
  };

  static String _hhmm(double t) {
    final h = t.floor();
    final m = ((t - h) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentWash : AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? AppColors.accentDim : AppColors.border),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? AppColors.accent : AppColors.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${_full[day] ?? day}  ·  ${_hhmm(from)} – ${_hhmm(to)}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              if (taken)
                const Text(
                  'partly booked',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
