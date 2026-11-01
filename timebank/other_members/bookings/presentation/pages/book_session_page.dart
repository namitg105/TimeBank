import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_widgets.dart';
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

  final _tuteeId = TextEditingController();
  final _tutorId = TextEditingController();
  final _slotNo = TextEditingController(text: '1');
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
    for (final c in [_tuteeId, _tutorId, _slotNo, _venue]) {
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
                'The tutee is charged the moment this is booked. The credits '
                'sit in escrow and reach the tutor only when both sides '
                'confirm the session happened.',
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
                onSelectionChanged: (set) =>
                    setState(() => _intent = set.first),
              ),
              const SizedBox(height: 8),
              InfoBanner(
                _intent == 'LEARN'
                    ? 'You will be added to the TUTEE table if you are not '
                      'already in it. You stay a tutor if you were one -- '
                      'the specialization is overlapping, so nothing is '
                      'taken away.'
                    : 'You will be added to the TUTOR table if you are not '
                      'already in it, with a BRONZE badge and a skill row '
                      'for the subject below. You stay a tutee if you were '
                      'one.',
                icon: Icons.account_tree_outlined,
              ),

              const SectionLabel('Who'),
              Row(
                children: [
                  Expanded(
                    child: _numField(
                      _intent == 'LEARN' ? _tuteeId : _tutorId,
                      'Your student id',
                      hint: '1003',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _numField(
                      _intent == 'LEARN' ? _tutorId : _tuteeId,
                      _intent == 'LEARN' ? "Tutor's id" : "Tutee's id",
                      hint: _intent == 'LEARN' ? '101' : '102',
                    ),
                  ),
                ],
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
              _numField(_slotNo, "The tutor's slot number", hint: '1'),
              const SizedBox(height: 4),
              const InfoBanner(
                'The slot has to belong to that tutor, and the date has to '
                'fall on the slot\'s weekday. Both are checked by the '
                'database, not here.',
              ),

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
                          : Text('Book and hold '
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

  static String _clock(double t) {
    final h = t.floor();
    final m = ((t - h) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (_date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a date for the session.')),
      );
      return;
    }

    context.read<BookingBloc>().add(SessionBooked(
          BookSessionParams(
            tuteeId: int.parse(_tuteeId.text.trim()),
            tutorId: int.parse(_tutorId.text.trim()),
            subjectId: _subjectId,
            slotNo: int.parse(_slotNo.text.trim()),
            schedDate: _date!,
            startTime: _startTime,
            durationHours: _duration,
            mode: _mode,
            venue: _venue.text.trim(),
            intent: _intent,
            studentId: int.parse(
              (_intent == 'LEARN' ? _tuteeId : _tutorId).text.trim(),
            ),
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
