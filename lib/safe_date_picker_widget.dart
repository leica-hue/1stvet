import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'vet_availability_utils.dart';

/// Safe date picker widget that ensures initialDate always satisfies the predicate
/// Use this instead of CalendarDatePicker to avoid assertion errors
class SafeDatePicker extends StatefulWidget {
  final String vetId;
  final DateTime? initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final Function(DateTime) onDateSelected;
  final String? hintText;

  const SafeDatePicker({
    super.key,
    required this.vetId,
    this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDateSelected,
    this.hintText,
  });

  @override
  State<SafeDatePicker> createState() => _SafeDatePickerState();
}

class _SafeDatePickerState extends State<SafeDatePicker> {
  DateTime? _selectedDate;
  DateTime? _validInitialDate;
  bool _isLoading = true;
  Map<String, bool> _availabilityCache = {};
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _initializeDatePicker();
  }

  Future<void> _initializeDatePicker() async {
    try {
      // Get a valid initial date that satisfies the predicate
      _validInitialDate = await VetAvailabilityUtils.getValidInitialDate(
        vetId: widget.vetId,
        preferredDate: widget.initialDate,
        firstDate: widget.firstDate,
        lastDate: widget.lastDate,
      );

      // Pre-load availability for next 60 days to improve performance
      await _preloadAvailability();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error loading date picker: $e';
        });
      }
    }
  }

  Future<void> _preloadAvailability() async {
    final startDate = _validInitialDate ?? DateTime.now();
    for (int i = 0; i < 60; i++) {
      final date = startDate.add(Duration(days: i));
      if (date.isAfter(widget.lastDate) || date.isAtSameMomentAs(widget.lastDate)) break;
      
      final key = '${date.year}-${date.month}-${date.day}';
      if (!_availabilityCache.containsKey(key)) {
        final canBook = await VetAvailabilityUtils.canVetAcceptAppointmentOnDate(
          widget.vetId,
          date,
        );
        _availabilityCache[key] = canBook;
      }
    }
  }

  bool _isDateSelectable(DateTime date) {
    final key = '${date.year}-${date.month}-${date.day}';
    // If not in cache, allow it (validation happens on selection)
    return _availabilityCache[key] ?? true;
  }

  Future<void> _selectDate() async {
    if (_isLoading || _validInitialDate == null) {
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: _validInitialDate!,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      selectableDayPredicate: (date) {
        return _isDateSelectable(date);
      },
      helpText: 'Select appointment date',
      cancelText: 'Cancel',
      confirmText: 'Select',
      fieldLabelText: 'Date',
      fieldHintText: 'Month/Day/Year',
    );

    if (picked != null) {
      // Validate the selected date
      final canBook = await VetAvailabilityUtils.canVetAcceptAppointmentOnDate(
        widget.vetId,
        picked,
      );

      if (!canBook) {
        if (mounted) {
          final remainingSlots = await VetAvailabilityUtils.getRemainingSlotsInMonth(
            widget.vetId,
            picked,
          );
          
          final monthName = DateFormat('MMMM yyyy').format(picked);
          String message;
          
          if (remainingSlots == 0) {
            message = 'This veterinarian has reached their monthly appointment limit of 20 appointments for $monthName. Please select another date or veterinarian.';
          } else {
            message = 'This veterinarian has limited availability for $monthName. Please try booking next month or with another veterinarian.';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      setState(() {
        _selectedDate = picked;
      });

      widget.onDateSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const ListTile(
        leading: CircularProgressIndicator(),
        title: Text('Loading date picker...'),
      );
    }

    if (_errorMessage != null) {
      return ListTile(
        leading: const Icon(Icons.error, color: Colors.red),
        title: Text(_errorMessage!),
      );
    }

    return ListTile(
      title: Text(widget.hintText ?? 'Select Date'),
      subtitle: Text(
        _selectedDate != null
            ? DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate!)
            : 'Tap to select date',
        style: TextStyle(
          color: _selectedDate != null ? Colors.black87 : Colors.grey,
          fontWeight: _selectedDate != null ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: const Icon(Icons.calendar_today),
      onTap: _selectDate,
    );
  }
}

/// Helper function to safely show CalendarDatePicker with proper initial date validation
/// This prevents the assertion error by ensuring initialDate satisfies the predicate
Future<DateTime?> showSafeCalendarDatePicker({
  required BuildContext context,
  required String vetId,
  DateTime? initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  bool Function(DateTime)? selectableDayPredicate,
}) async {
  // Get a valid initial date that satisfies the predicate
  final validInitialDate = await VetAvailabilityUtils.getValidInitialDate(
    vetId: vetId,
    preferredDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
  );

  // If selectableDayPredicate is provided, we need to ensure it's async-aware
  // Since CalendarDatePicker predicate is sync, we'll use showDatePicker instead
  // which is simpler and more reliable
  
  return await showDatePicker(
    context: context,
    initialDate: validInitialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    selectableDayPredicate: selectableDayPredicate,
    helpText: 'Select appointment date',
    cancelText: 'Cancel',
    confirmText: 'Select',
    fieldLabelText: 'Date',
    fieldHintText: 'Month/Day/Year',
  );
}
