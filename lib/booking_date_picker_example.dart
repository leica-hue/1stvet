// EXAMPLE: How to fix the CalendarDatePicker error in user booking app
// This file shows how to properly use date pickers when booking appointments

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'vet_availability_utils.dart';
import 'safe_date_picker_widget.dart';

/// Example booking screen that prevents CalendarDatePicker assertion errors
class BookingScreenExample extends StatefulWidget {
  final String vetId;
  final String vetName;

  const BookingScreenExample({
    super.key,
    required this.vetId,
    required this.vetName,
  });

  @override
  State<BookingScreenExample> createState() => _BookingScreenExampleState();
}

class _BookingScreenExampleState extends State<BookingScreenExample> {
  DateTime? selectedDate;
  DateTime? validInitialDate;
  Map<String, bool> availabilityCache = {};
  bool isLoadingDates = true;

  @override
  void initState() {
    super.initState();
    _initializeDatePicker();
  }

  /// Initialize date picker with a valid initial date
  Future<void> _initializeDatePicker() async {
    try {
      // Get a valid initial date that satisfies the predicate
      validInitialDate = await VetAvailabilityUtils.getValidInitialDate(
        vetId: widget.vetId,
        preferredDate: DateTime(2025, 11, 24), // Your original initial date
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );

      // Pre-load availability for performance
      await _preloadAvailability();

      setState(() {
        isLoadingDates = false;
      });
    } catch (e) {
      debugPrint('Error initializing date picker: $e');
      // Fallback to today
      validInitialDate = DateTime.now();
      setState(() {
        isLoadingDates = false;
      });
    }
  }

  /// Pre-load availability for the next 60 days
  Future<void> _preloadAvailability() async {
    final startDate = validInitialDate ?? DateTime.now();
    for (int i = 0; i < 60; i++) {
      final date = startDate.add(Duration(days: i));
      final key = '${date.year}-${date.month}-${date.day}';
      
      if (!availabilityCache.containsKey(key)) {
        final canBook = await VetAvailabilityUtils.canVetAcceptAppointmentOnDate(
          widget.vetId,
          date,
        );
        availabilityCache[key] = canBook;
      }
    }
  }

  /// Select date using safe date picker
  Future<void> _selectDate() async {
    if (isLoadingDates || validInitialDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait, loading date picker...'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: validInitialDate!,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      selectableDayPredicate: (date) {
        // Use cached availability
        final key = '${date.year}-${date.month}-${date.day}';
        return availabilityCache[key] ?? true; // Default to true if not cached
      },
      helpText: 'Select appointment date',
    );

    if (picked != null) {
      // Double-check availability (in case cache is stale)
      final canBook = await VetAvailabilityUtils.canVetAcceptAppointmentOnDate(
        widget.vetId,
        picked,
      );

      if (!canBook) {
        final monthName = DateFormat('MMMM yyyy').format(picked);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'This veterinarian has reached their monthly appointment limit for $monthName. Please select another date or veterinarian.',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      setState(() {
        selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Book with ${widget.vetName}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Date selection using safe date picker widget
            if (isLoadingDates)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Text('Loading date picker...'),
                    ],
                  ),
                ),
              )
            else
              Card(
                child: ListTile(
                  title: const Text('Select Appointment Date'),
                  subtitle: Text(
                    selectedDate != null
                        ? DateFormat('EEEE, MMMM d, yyyy').format(selectedDate!)
                        : 'Tap to select date',
                    style: TextStyle(
                      color: selectedDate != null ? Colors.black87 : Colors.grey,
                      fontWeight: selectedDate != null ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: _selectDate,
                ),
              ),

            const SizedBox(height: 16),

            // Alternative: Use SafeDatePicker widget (recommended)
            SafeDatePicker(
              vetId: widget.vetId,
              initialDate: selectedDate,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              onDateSelected: (date) {
                setState(() {
                  selectedDate = date;
                });
              },
              hintText: 'Select Appointment Date',
            ),

            // Rest of booking form...
            const Spacer(),

            ElevatedButton(
              onPressed: selectedDate != null ? _bookAppointment : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.green,
                disabledBackgroundColor: Colors.grey,
              ),
              child: const Text(
                'Book Appointment',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _bookAppointment() async {
    if (selectedDate == null) return;

    // Final validation before booking
    try {
      final canBook = await VetAvailabilityUtils.canVetAcceptAppointmentOnDate(
        widget.vetId,
        selectedDate!,
      );

      if (!canBook) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This veterinarian is not available on the selected date. Please choose another date.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Proceed with booking...
      // await createAppointment(...);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appointment booked successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error booking appointment: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

/// Quick fix function - Use this to replace existing CalendarDatePicker calls
Future<DateTime?> fixCalendarDatePickerError({
  required BuildContext context,
  required String vetId,
  DateTime? initialDate,
}) async {
  // Get valid initial date
  final validInitialDate = await VetAvailabilityUtils.getValidInitialDate(
    vetId: vetId,
    preferredDate: initialDate ?? DateTime(2025, 11, 24),
    firstDate: DateTime.now(),
    lastDate: DateTime.now().add(const Duration(days: 365)),
  );

  // Use showDatePicker instead of CalendarDatePicker (simpler and more reliable)
  return await showDatePicker(
    context: context,
    initialDate: validInitialDate,
    firstDate: DateTime.now(),
    lastDate: DateTime.now().add(const Duration(days: 365)),
    // Optional: Add predicate here if you want to filter dates
    // selectableDayPredicate: (date) { ... },
  );
}
