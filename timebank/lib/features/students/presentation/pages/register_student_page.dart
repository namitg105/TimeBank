import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_widgets.dart';
import '../../domain/usecases/student_usecases.dart';
import '../bloc/student_bloc.dart';

/// Registration form.
///
/// Validation happens twice, on purpose and at different depths:
///
///   here            — shape only (is this an email, are the digits 10),
///                     so the user gets an answer without a round trip
///   RegisterStudent — the same rules again, because a second screen
///                     calling the use case must not be able to skip them
///   Oracle          — the rules that only the database can know, such as
///                     whether this registration number is already taken
///
/// The last layer is the authority. The first two exist for speed and
/// for a kinder message.
class RegisterStudentPage extends StatefulWidget {
  const RegisterStudentPage({super.key});

  @override
  State<RegisterStudentPage> createState() => _RegisterStudentPageState();
}

class _RegisterStudentPageState extends State<RegisterStudentPage> {
  final _formKey = GlobalKey<FormState>();

  final _regNo = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _block = TextEditingController();
  final _room = TextEditingController();
  final _city = TextEditingController();
  final _phone = TextEditingController();

  DateTime? _dob;
  int _deptId = 1;

  static const _departments = {
    1: 'Computer Science and Engineering',
    2: 'Mechanical Engineering',
    3: 'Electrical Engineering',
    4: 'Advanced Sciences',
    5: 'Business Studies',
  };

  @override
  void dispose() {
    for (final c in [
      _regNo, _first, _last, _email, _block, _room, _city, _phone
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register a student')),
      body: BlocListener<StudentBloc, StudentState>(
        listener: (context, state) {
          if (state is StudentActionSuccess) {
            Navigator.of(context).pop();
          } else if (state is StudentFailure) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: Text(state.message),
                backgroundColor: AppColors.surfaceHover,
              ));
          }
        },
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
            children: [
              const InfoBanner(
                'Registering writes two rows in one transaction: the student, '
                'and their 3.0 starter credits in the ledger. A student can '
                'never exist without an opening balance.',
                icon: Icons.account_balance_wallet_outlined,
                tint: AppColors.accent,
              ),

              const SectionLabel('Identity'),
              _field(_regNo, 'Registration number', hint: '25BCE1099',
                  caps: true),
              _field(_first, 'First name'),
              _field(_last, 'Last name'),
              _field(_email, 'Email', hint: 'name@vit.ac.in',
                  keyboard: TextInputType.emailAddress),

              const SectionLabel('Date of birth'),
              _DateField(
                value: _dob,
                onPick: (d) => setState(() => _dob = d),
              ),

              const SectionLabel('Department'),
              _DeptPicker(
                value: _deptId,
                departments: _departments,
                onChanged: (v) => setState(() => _deptId = v),
              ),
              const SizedBox(height: 8),
              const InfoBanner(
                'A department does not limit what a student may tutor. '
                'A Mechanical student can teach Database Systems, and one '
                'already does.',
                icon: Icons.swap_horiz,
              ),

              const SectionLabel('Contact (optional)'),
              _field(_phone, 'Phone', hint: '10 digits',
                  keyboard: TextInputType.phone, isRequired: false,
                  formatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ]),
              Row(
                children: [
                  Expanded(
                      child: _field(_block, 'Block', isRequired: false)),
                  const SizedBox(width: 12),
                  Expanded(child: _field(_room, 'Room', isRequired: false)),
                ],
              ),
              _field(_city, 'Home city', isRequired: false),

              const SizedBox(height: 26),
              BlocBuilder<StudentBloc, StudentState>(
                builder: (context, state) {
                  final busy = state is StudentLoading;
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
                          : const Text('Register and grant credits'),
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

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool isRequired = true,
    bool caps = false,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          keyboardType: keyboard,
          inputFormatters: formatters,
          textCapitalization:
              caps ? TextCapitalization.characters : TextCapitalization.words,
          style: const TextStyle(fontSize: 14.5),
          decoration: InputDecoration(labelText: label, hintText: hint),
          validator: (v) {
            if (!isRequired) return null;
            if (v == null || v.trim().isEmpty) return '$label is required';
            if (label == 'Email' &&
                !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
              return 'That does not look like an email address';
            }
            return null;
          },
        ),
      );

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (_dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a date of birth.')),
      );
      return;
    }

    context.read<StudentBloc>().add(StudentRegistered(
          RegisterStudentParams(
            regNo: _regNo.text,
            firstName: _first.text,
            lastName: _last.text,
            email: _email.text,
            dob: _dob!,
            deptId: _deptId,
            block: _block.text.isEmpty ? null : _block.text,
            roomNo: _room.text.isEmpty ? null : _room.text,
            city: _city.text.isEmpty ? null : _city.text,
            phone: _phone.text.isEmpty ? null : _phone.text,
          ),
        ));
  }
}

// ---------------------------------------------------------------------

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
            initialDate: value ?? DateTime(now.year - 19),
            firstDate: DateTime(now.year - 45),
            lastDate: DateTime(now.year - 15),
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
              const Icon(Icons.calendar_today_outlined,
                  size: 17, color: AppColors.textMuted),
              const SizedBox(width: 12),
              Text(
                value == null
                    ? 'Choose a date'
                    : '${value!.day.toString().padLeft(2, '0')}'
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
}

class _DeptPicker extends StatelessWidget {
  final int value;
  final Map<int, String> departments;
  final ValueChanged<int> onChanged;

  const _DeptPicker({
    required this.value,
    required this.departments,
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
          child: DropdownButton<int>(
            value: value,
            isExpanded: true,
            dropdownColor: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(10),
            style: const TextStyle(
                fontSize: 14, color: AppColors.textPrimary),
            icon: const Icon(Icons.expand_more,
                size: 20, color: AppColors.textMuted),
            items: departments.entries
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
