import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/friendly_error.dart';
import '../../../core/constants/chore_constants.dart';
import '../../../features/household/providers/household_provider.dart';
import '../../../features/household/providers/members_provider.dart';
import '../models/chore_form_init_data.dart';
import '../models/chore_template.dart';
import '../providers/chore_templates_provider.dart';
import '../providers/chores_provider.dart';
import '../../../router/app_router.dart';

// Category/effort/interval-unit labels used to be duplicated here (with
// diverging category wording — "Laundry Room" vs. chore_model.dart's
// "Laundry") — both now pull from `core/constants/chore_constants.dart`
// (TASK-065).

// ---------------------------------------------------------------------------
// CreateChoreScreen
// ---------------------------------------------------------------------------

/// Admin-only screen for creating or editing a chore definition.
///
/// **Create mode** (default): [initData] is `null`; an empty form is shown and
/// `POST /households/{id}/chores` is called on submit.
///
/// **Edit mode**: [initData] is supplied (typically via [GoRouterState.extra]);
/// the form is pre-populated and `PATCH /households/{id}/chores/{definitionId}`
/// is called on submit. A banner reminds the admin that changes only affect
/// future instances.
///
/// Navigate to edit mode:
/// ```dart
/// context.goNamed(
///   AppRoutes.createChore,
///   pathParameters: {'householdId': householdId},
///   extra: ChoreFormInitData.fromModel(chore),
/// );
/// ```
class CreateChoreScreen extends ConsumerStatefulWidget {
  const CreateChoreScreen({
    super.key,
    required this.householdId,
    this.initData,
  });

  final String householdId;

  /// Non-null when the screen is opened in edit mode.
  final ChoreFormInitData? initData;

  @override
  ConsumerState<CreateChoreScreen> createState() => _CreateChoreScreenState();
}

class _CreateChoreScreenState extends ConsumerState<CreateChoreScreen> {
  // ---------------------------------------------------------------------------
  // Form key & controllers
  // ---------------------------------------------------------------------------

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  /// Read-only TextEditingController used exclusively to display the formatted
  /// due date inside the TextFormField that acts as the date picker trigger.
  final _dateController = TextEditingController();

  /// Controller for the recurrence interval number (e.g. "2" → every 2 weeks).
  final _intervalNController = TextEditingController();

  // ---------------------------------------------------------------------------
  // Form state
  // ---------------------------------------------------------------------------

  String? _category;
  String _effortLevel = 'medium';

  /// `one_off` | `recurring`
  String _choreType = 'one_off';

  DateTime? _firstDueDate;

  /// Tracks whether the admin has actually tapped through the date picker
  /// this session, as opposed to `_firstDueDate` merely holding the
  /// pre-populated edit-mode value untouched. [_pickDate] only ever offers
  /// today-or-later dates, so a past `_firstDueDate` can only mean "this is
  /// the original edit-mode value, unchanged" — see the due-date validator
  /// below (TASK-060).
  bool _dueDateManuallyChanged = false;

  /// `days` | `weeks` | `months`
  String _intervalUnit = 'weeks';

  /// `null` means "auto-assign".
  String? _assigneeId;

  bool _isSubmitting = false;

  // ---------------------------------------------------------------------------
  // Derived helpers
  // ---------------------------------------------------------------------------

  bool get _isEditMode => widget.initData != null;
  bool get _isRecurring => _choreType == 'recurring';

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    final init = widget.initData;
    if (init != null) {
      _titleController.text = init.title;
      _descriptionController.text = init.description ?? '';
      _category = init.category;
      _effortLevel = init.effortLevel;
      _choreType = init.choreType;
      _firstDueDate = init.firstDueDate;
      if (init.firstDueDate != null) {
        _dateController.text = DateFormat(
          'EEE, d MMM yyyy',
        ).format(init.firstDueDate!);
      }
      _intervalUnit = init.intervalUnit ?? 'weeks';
      _intervalNController.text = (init.intervalN ?? 1).toString();
      _assigneeId = init.assigneeId;
    } else {
      _intervalNController.text = '1';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _dateController.dispose();
    _intervalNController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Date picker
  // ---------------------------------------------------------------------------

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: _firstDueDate != null && !_firstDueDate!.isBefore(today)
          ? _firstDueDate!
          : today,
      firstDate: today,
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        _firstDueDate = picked;
        _dueDateManuallyChanged = true;
        _dateController.text = DateFormat('EEE, d MMM yyyy').format(picked);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Copy from existing task (TASK-108)
  // ---------------------------------------------------------------------------

  /// Opens the "copy from existing task" picker; on selection, copies exactly
  /// title/description/category/effort_level ("score") into the form. The due
  /// date, chore type, recurrence and assignee stay untouched.
  Future<void> _pickTemplateToCopy() async {
    // Await the provider's future: nothing watches it (the button only reads),
    // so the first tap may trigger the build — valueOrNull would be null.
    final List<ChoreTemplate> templates;
    try {
      templates =
          await ref.read(choreTemplatesProvider(widget.householdId).future);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
      return;
    }

    if (!mounted) return;
    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No existing tasks to copy yet.')),
      );
      return;
    }

    // Dismiss the keyboard first (TASK-109, adversarial review): with the
    // keyboard up, the sheet would open at 50% of the reduced height and the
    // first rows would be hidden behind it.
    FocusManager.instance.primaryFocus?.unfocus();

    final chosen = await showModalBottomSheet<ChoreTemplate>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CopyTaskSheet(templates: templates),
    );

    if (chosen != null && mounted) {
      setState(() {
        _titleController.text = chosen.title;
        _descriptionController.text = chosen.description ?? '';
        _category = chosen.category;
        _effortLevel = chosen.effortLevel;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    // Trigger Form validation (including the date FormField).
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);

    final body = <String, dynamic>{
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      'category': _category,
      'effort_level': _effortLevel,
      'chore_type': _choreType,
      'first_due_date': DateFormat('yyyy-MM-dd').format(_firstDueDate!),
      'recurrence_rule': _isRecurring
          ? {
              'interval_unit': _intervalUnit,
              'interval_n': int.parse(_intervalNController.text.trim()),
            }
          : null,
      'assignee_id': _assigneeId,
    };

    try {
      final notifier = ref.read(
        choresNotifierProvider(widget.householdId).notifier,
      );

      if (_isEditMode) {
        await notifier.updateChoreDefinition(
          widget.initData!.definitionId,
          body,
        );
      } else {
        await notifier.createChore(body);
      }

      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.goNamed(
            AppRoutes.choreList,
            pathParameters: {'householdId': widget.householdId},
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // ---------------------------------------------------------------------------
    // Admin guard
    // ---------------------------------------------------------------------------

    final isAdmin = ref.watch(isAdminProvider(widget.householdId));

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_isEditMode ? 'Edit Chore' : 'Create Chore'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Admin access required',
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Only household admins can create or edit chores.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ---------------------------------------------------------------------------
    // Members for assignee dropdown
    // ---------------------------------------------------------------------------

    final membersAsync = ref.watch(membersNotifierProvider(widget.householdId));

    return Scaffold(
      appBar: AppBar(title: Text(_isEditMode ? 'Edit Chore' : 'Create Chore')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // -----------------------------------------------------------------
              // Edit-mode banner
              // -----------------------------------------------------------------
              if (_isEditMode) ...[
                _EditModeBanner(theme: theme),
                const SizedBox(height: 20),
              ],

              // -----------------------------------------------------------------
              // Copy from existing task (create mode only, TASK-108)
              // -----------------------------------------------------------------
              if (!_isEditMode) ...[
                OutlinedButton.icon(
                  key: const Key('copy_from_task_button'),
                  onPressed: _pickTemplateToCopy,
                  icon: const Icon(Icons.content_copy),
                  label: const Text('Copy from existing task'),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // -----------------------------------------------------------------
              // Title
              // -----------------------------------------------------------------
              TextFormField(
                key: const Key('title_field'),
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  hintText: 'e.g. Vacuum living room',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Title is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // -----------------------------------------------------------------
              // Description
              // -----------------------------------------------------------------
              TextFormField(
                key: const Key('description_field'),
                controller: _descriptionController,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'Add any notes or instructions…',
                ),
              ),
              const SizedBox(height: 16),

              // -----------------------------------------------------------------
              // Category
              // -----------------------------------------------------------------
              DropdownButtonFormField<String>(
                key: const Key('category_dropdown'),
                initialValue: _category,
                // TASK-112: without isExpanded the button's internal
                // IndexedStack sizes to the widest item and overflows the
                // field on narrow screens / large text scales
                // ("RenderFlex overflowed by N pixels on the right").
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category *'),
                items: categoryLabels.entries.map((entry) {
                  return DropdownMenuItem<String>(
                    value: entry.key,
                    child: Row(
                      children: [
                        Icon(categoryIcons[entry.key], size: 18),
                        const SizedBox(width: 10),
                        // Flexible + ellipsis lets long labels shrink to the
                        // field width instead of overflowing (the open menu
                        // constrains items to the button width too, so this
                        // is safe there as well).
                        Flexible(
                          child: Text(
                            entry.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _category = v),
                validator: (v) => v == null ? 'Please select a category' : null,
              ),
              const SizedBox(height: 20),

              // -----------------------------------------------------------------
              // Effort level
              // -----------------------------------------------------------------
              const _SectionLabel(label: 'Effort Level'),
              const SizedBox(height: 10),
              _EffortLevelSelector(
                key: const Key('effort_level_selector'),
                value: _effortLevel,
                onChanged: (v) => setState(() => _effortLevel = v),
              ),
              const SizedBox(height: 20),

              // -----------------------------------------------------------------
              // Chore type
              // -----------------------------------------------------------------
              const _SectionLabel(label: 'Chore Type'),
              const SizedBox(height: 4),
              RadioGroup<String>(
                groupValue: _choreType,
                onChanged: (v) => setState(() => _choreType = v!),
                child: const Column(
                  children: [
                    RadioListTile<String>(
                      key: Key('type_one_off'),
                      contentPadding: EdgeInsets.zero,
                      title: Text('One-off'),
                      subtitle: Text('Happens only once'),
                      value: 'one_off',
                    ),
                    RadioListTile<String>(
                      key: Key('type_recurring'),
                      contentPadding: EdgeInsets.zero,
                      title: Text('Recurring'),
                      subtitle: Text('Repeats on a schedule'),
                      value: 'recurring',
                    ),
                  ],
                ),
              ),

              // -----------------------------------------------------------------
              // Recurrence rule (shown only for recurring)
              // -----------------------------------------------------------------
              if (_isRecurring) ...[
                const SizedBox(height: 4),
                _RecurrenceSection(
                  intervalUnit: _intervalUnit,
                  intervalNController: _intervalNController,
                  onUnitChanged: (v) => setState(() => _intervalUnit = v),
                ),
              ],
              const SizedBox(height: 16),

              // -----------------------------------------------------------------
              // First due date
              // -----------------------------------------------------------------
              TextFormField(
                key: const Key('due_date_field'),
                controller: _dateController,
                readOnly: true,
                onTap: _pickDate,
                decoration: const InputDecoration(
                  labelText: 'First Due Date *',
                  hintText: 'Tap to select a date',
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
                // Validator reads from parent state, not the text controller.
                validator: (_) {
                  if (_firstDueDate == null) {
                    return 'Please select a due date';
                  }
                  // In edit mode, a chore whose due date already passed must
                  // still be saveable unchanged (TASK-060) — `_pickDate` only
                  // ever offers today-or-later dates, so skipping the
                  // past-date check here can only let through the original,
                  // untouched edit-mode value, never a newly-chosen past date.
                  final dateUnchangedInEditMode =
                      _isEditMode && !_dueDateManuallyChanged;
                  if (dateUnchangedInEditMode) {
                    return null;
                  }
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);
                  if (_firstDueDate!.isBefore(today)) {
                    return 'Due date cannot be in the past';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // -----------------------------------------------------------------
              // Assignee (optional)
              // -----------------------------------------------------------------
              membersAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (members) => DropdownButtonFormField<String?>(
                  key: const Key('assignee_dropdown'),
                  initialValue: _assigneeId,
                  decoration: const InputDecoration(
                    labelText: 'Assignee (optional)',
                    hintText: 'Auto-assign',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Auto-assign'),
                    ),
                    ...members.map(
                      (m) => DropdownMenuItem<String?>(
                        value: m.userId,
                        child: Text(m.displayName),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _assigneeId = v),
                ),
              ),
              const SizedBox(height: 32),

              // -----------------------------------------------------------------
              // Submit button
              // -----------------------------------------------------------------
              ElevatedButton(
                key: const Key('submit_button'),
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_isEditMode ? 'Save Changes' : 'Create Chore'),
              ),
            ],
          ),
        ), // SingleChildScrollView
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit-mode banner
// ---------------------------------------------------------------------------

class _EditModeBanner extends StatelessWidget {
  const _EditModeBanner({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('edit_mode_banner'),
      color: theme.colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              color: theme.colorScheme.onSecondaryContainer,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Changes apply to future instances only.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section label
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

// ---------------------------------------------------------------------------
// Effort level selector (SegmentedButton, Material 3)
// ---------------------------------------------------------------------------

class _EffortLevelSelector extends StatelessWidget {
  const _EffortLevelSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: effortLevels.entries.map((entry) {
        final meta = entry.value;
        return ButtonSegment<String>(
          value: entry.key,
          label: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(meta.label),
              Text(
                '${meta.points} pts',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      selected: {value},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) onChanged(selection.first);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Recurrence section
// ---------------------------------------------------------------------------

class _RecurrenceSection extends StatelessWidget {
  const _RecurrenceSection({
    required this.intervalUnit,
    required this.intervalNController,
    required this.onUnitChanged,
  });

  final String intervalUnit;
  final TextEditingController intervalNController;
  final ValueChanged<String> onUnitChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('recurrence_section'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recurrence schedule',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // "Every N" — integer field
                Flexible(
                  flex: 2,
                  child: TextFormField(
                    key: const Key('interval_n_field'),
                    controller: intervalNController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Every'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Required';
                      }
                      final n = int.tryParse(v.trim());
                      if (n == null || n < 1) return 'Min 1';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Unit dropdown
                Flexible(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    key: const Key('interval_unit_dropdown'),
                    initialValue: intervalUnit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                    items: intervalUnitLabels.entries.map((entry) {
                      return DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) onUnitChanged(v);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// "Copy from existing task" bottom sheet (TASK-108)
// ---------------------------------------------------------------------------

class _CopyTaskSheet extends StatelessWidget {
  const _CopyTaskSheet({required this.templates});

  final List<ChoreTemplate> templates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Canonical bottom-sheet list (TASK-109): DraggableScrollableSheet with a
    // plain, non-shrinkWrap ListView driven by its controller. The previous
    // Flexible-inside-min-Column + shrinkWrap ListView was fragile — with
    // enough tasks it could hit "RenderFlex children have non-zero flex but
    // incoming height constraints are unbounded" or overflow the screen.
    //
    // The header is the list's FIRST ITEM rather than a fixed widget above
    // the scrollable: a fixed header would overflow the sheet when dragged to
    // minChildSize on short/landscape screens with large text (adversarial
    // review 2026-08-18). The modal's useSafeArea covers top/left/right; the
    // list's bottom padding covers the home-indicator / nav-bar inset.
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.2,
      maxChildSize: 0.85,
      builder: (context, scrollController) => ListView.separated(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: templates.length + 1,
        separatorBuilder: (context, index) => index == 0
            ? const SizedBox(height: 12)
            : const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Copy from existing task',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Select a task — title, description, category and score are copied.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            );
          }
          return _CopyTaskRow(template: templates[index - 1]);
        },
      ),
    );
  }
}

class _CopyTaskRow extends StatelessWidget {
  const _CopyTaskRow({required this.template});

  final ChoreTemplate template;

  @override
  Widget build(BuildContext context) {
    final meta = effortLevels[template.effortLevel];
    final catLabel = categoryLabels[template.category] ?? template.category;
    final catColor =
        categoryColors[template.category] ?? const Color(0xFF9CA3AF);
    final catIcon = categoryIcons[template.category];

    return ListTile(
      key: Key('copy_task_${template.id}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(catIcon, color: catColor),
      title: Text(
        template.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        meta != null
            ? '$catLabel · ${meta.label} · ${meta.points} pts'
            : catLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => Navigator.pop(context, template),
    );
  }
}
