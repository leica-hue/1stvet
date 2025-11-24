# Fix for CalendarDatePicker Error

## ⚠️ WHY THIS ERROR APPEARS

**This error appears on the user side when booking because:**

The user app is using `CalendarDatePicker` with an `initialDate` (2025-11-24) that doesn't satisfy the `selectableDayPredicate`. The predicate filters out dates where the vet has reached their monthly appointment limit, but the initialDate is still set to a date in a filtered month.

**Flutter Requirement:** The `initialDate` MUST satisfy the `selectableDayPredicate`, or Flutter throws an assertion error.

## Problem

The error occurs when `CalendarDatePicker` is used with an `initialDate` that doesn't satisfy the `selectableDayPredicate`. This happens when:

- A vet has reached their monthly appointment limit
- The initialDate (e.g., 2025-11-24) falls in a month where the vet can't accept more appointments
- The predicate filters out that date, but initialDate is still set to it

## Solution

Use the `VetAvailabilityUtils` helper functions to ensure the `initialDate` is always valid.

### Step 1: Import the utility

```dart
import 'vet_availability_utils.dart';
```

### Step 2: Get a valid initial date before showing CalendarDatePicker

```dart
// Get valid initial date that satisfies the predicate
final validInitialDate = await VetAvailabilityUtils.getValidInitialDate(
  vetId: selectedVetId,
  preferredDate: DateTime(2025, 11, 24), // Your preferred date
  firstDate: DateTime.now(),
  lastDate: DateTime.now().add(const Duration(days: 365)),
);

// Now use it in CalendarDatePicker
CalendarDatePicker(
  initialDate: validInitialDate,
  firstDate: DateTime.now(),
  lastDate: DateTime.now().add(const Duration(days: 365)),
  selectableDayPredicate: (date) async {
    // Use async predicate or sync version with pre-loaded cache
    return await VetAvailabilityUtils.isDateSelectable(selectedVetId, date);
  },
)
```

### Step 3: Alternative - Use async predicate wrapper

Since `selectableDayPredicate` needs to be synchronous, you have two options:

#### Option A: Pre-fetch availability and cache (Recommended)

```dart
// Pre-fetch availability for the next 30 days and cache it
Map<String, bool> availabilityCache = {};

Future<void> preloadAvailability(String vetId, DateTime startDate) async {
  for (int i = 0; i < 30; i++) {
    final date = startDate.add(Duration(days: i));
    final key = '${date.year}-${date.month}-${date.day}';
    availabilityCache[key] = await VetAvailabilityUtils.isDateSelectable(vetId, date);
  }
}

// Then use cached predicate
CalendarDatePicker(
  initialDate: validInitialDate,
  firstDate: DateTime.now(),
  lastDate: DateTime.now().add(const Duration(days: 30)),
  selectableDayPredicate: (date) {
    final key = '${date.year}-${date.month}-${date.day}';
    return availabilityCache[key] ?? true; // Default to true if not cached
  },
)
```

#### Option B: Use showDatePicker instead (Simpler)

If `CalendarDatePicker` is causing issues, you can use `showDatePicker` which is simpler:

```dart
final picked = await showDatePicker(
  context: context,
  initialDate: await VetAvailabilityUtils.getValidInitialDate(
    vetId: selectedVetId,
    preferredDate: DateTime(2025, 11, 24),
    firstDate: DateTime.now(),
    lastDate: DateTime.now().add(const Duration(days: 365)),
  ),
  firstDate: DateTime.now(),
  lastDate: DateTime.now().add(const Duration(days: 365)),
  selectableDayPredicate: (date) {
    // For showDatePicker, you can use a sync predicate with cached data
    // Or pre-validate before showing
    return true; // Allow all dates, validate on selection
  },
);
```

### Step 4: Validate after user selects date

Even if you use a predicate, always validate when the user selects a date:

```dart
final selectedDate = await showDatePicker(...);

if (selectedDate != null) {
  final canBook = await VetAvailabilityUtils.canVetAcceptAppointmentOnDate(
    selectedVetId, 
    selectedDate
  );
  
  if (!canBook) {
    // Show error message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'This veterinarian has reached their monthly appointment limit for ${DateFormat('MMMM yyyy').format(selectedDate)}. Please select another date or veterinarian.',
        ),
        backgroundColor: Colors.red,
      ),
    );
    return; // Don't proceed with booking
  }
  
  // Proceed with booking
}
```

## Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'vet_availability_utils.dart';

class BookingScreen extends StatefulWidget {
  final String vetId;
  
  const BookingScreen({super.key, required this.vetId});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  DateTime? selectedDate;
  Map<String, bool> availabilityCache = {};

  @override
  void initState() {
    super.initState();
    _preloadAvailability();
  }

  Future<void> _preloadAvailability() async {
    final now = DateTime.now();
    for (int i = 0; i < 60; i++) { // Pre-load next 60 days
      final date = now.add(Duration(days: i));
      final key = '${date.year}-${date.month}-${date.day}';
      final canBook = await VetAvailabilityUtils.canVetAcceptAppointmentOnDate(
        widget.vetId, 
        date
      );
      availabilityCache[key] = canBook;
    }
    if (mounted) setState(() {});
  }

  Future<void> _selectDate() async {
    // Get valid initial date
    final validInitialDate = await VetAvailabilityUtils.getValidInitialDate(
      vetId: widget.vetId,
      preferredDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    final picked = await showDatePicker(
      context: context,
      initialDate: validInitialDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      selectableDayPredicate: (date) {
        // Use cached availability
        final key = '${date.year}-${date.month}-${date.day}';
        return availabilityCache[key] ?? true; // Default to true if not cached
      },
    );

    if (picked != null) {
      // Double-check availability (in case cache is stale)
      final canBook = await VetAvailabilityUtils.canVetAcceptAppointmentOnDate(
        widget.vetId,
        picked,
      );

      if (!canBook) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'This veterinarian has reached their monthly appointment limit for ${DateFormat('MMMM yyyy').format(picked)}. Please select another date.',
              ),
              backgroundColor: Colors.red,
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
      appBar: AppBar(title: const Text('Book Appointment')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ListTile(
              title: const Text('Select Date'),
              subtitle: Text(
                selectedDate != null
                    ? DateFormat('EEEE, MMMM d, yyyy').format(selectedDate!)
                    : 'Tap to select',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectDate,
            ),
            // Rest of booking form...
          ],
        ),
      ),
    );
  }
}
```

## Key Points

1. **Always validate initialDate**: Use `getValidInitialDate()` to ensure it satisfies the predicate
2. **Pre-load availability**: Cache availability for the date range you'll show
3. **Double-check on selection**: Even with predicate, validate when user selects
4. **Show helpful messages**: Explain why dates aren't available
5. **Consider using showDatePicker**: It's simpler than CalendarDatePicker for this use case

## Testing

1. Test with premium vet (should allow all dates)
2. Test with basic vet at limit (should filter dates in that month)
3. Test with basic vet below limit (should allow dates)
4. Test month transitions (different months have different limits)
