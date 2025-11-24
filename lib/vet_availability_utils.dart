import 'package:cloud_firestore/cloud_firestore.dart';

/// Utility functions to check vet availability for appointment booking
/// These can be used in the user app when showing date pickers to filter dates
class VetAvailabilityUtils {
  static const int monthlyAppointmentLimit = 20;

  /// Check if a vet has premium status (unlimited appointments)
  static Future<bool> isVetPremium(String vetId) async {
    try {
      final vetDoc = await FirebaseFirestore.instance
          .collection('vets')
          .doc(vetId)
          .get();

      if (!vetDoc.exists) return false;

      final data = vetDoc.data();
      final premiumUntil = data?['premiumUntil'] as Timestamp?;
      final isPremium = data?['isPremium'] as bool? ?? false;

      // Check if premiumUntil date is still valid
      bool hasActivePremium = false;
      if (premiumUntil != null) {
        final premiumDate = premiumUntil.toDate();
        hasActivePremium = premiumDate.isAfter(DateTime.now());
      }

      return hasActivePremium || isPremium;
    } catch (e) {
      // On error, assume not premium to be safe
      return false;
    }
  }

  /// Count appointments for a vet in a specific month
  /// Only counts appointments that are not declined or cancelled
  static Future<int> getMonthlyAppointmentCount(String vetId, DateTime monthDate) async {
    try {
      final startOfMonth = DateTime(monthDate.year, monthDate.month, 1);
      final endOfMonth = DateTime(monthDate.year, monthDate.month + 1, 0, 23, 59, 59);

      // Fetch all appointments for this vet
      final snapshot = await FirebaseFirestore.instance
          .collection('user_appointments')
          .where('vetId', isEqualTo: vetId)
          .get();

      // Filter appointments by the specified month and count non-declined/cancelled
      int count = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final apptDateTime = data['appointmentDateTime'];

        if (apptDateTime != null) {
          DateTime apptDate;
          if (apptDateTime is Timestamp) {
            apptDate = apptDateTime.toDate();
          } else if (apptDateTime is DateTime) {
            apptDate = apptDateTime;
          } else {
            continue;
          }

          // Check if appointment is in the specified month
          if (apptDate.isAfter(startOfMonth.subtract(const Duration(days: 1))) &&
              apptDate.isBefore(endOfMonth.add(const Duration(days: 1)))) {
            final status = (data['status'] ?? '').toString().toLowerCase();
            if (status != 'declined' && status != 'cancelled') {
              count++;
            }
          }
        }
      }

      return count;
    } catch (e) {
      // On error, return 0 to allow booking (fail open)
      return 0;
    }
  }

  /// Check if a vet can accept appointments on a specific date
  /// Returns true if vet is premium OR hasn't reached monthly limit for that month
  static Future<bool> canVetAcceptAppointmentOnDate(String vetId, DateTime date) async {
    // Premium vets can always accept appointments
    final isPremium = await isVetPremium(vetId);
    if (isPremium) return true;

    // Check monthly count for non-premium vets
    final monthlyCount = await getMonthlyAppointmentCount(vetId, date);
    return monthlyCount < monthlyAppointmentLimit;
  }

  /// Find the first valid date where vet can accept appointments
  /// Starts from the given startDate and searches forward
  static Future<DateTime?> findFirstValidDate({
    required String vetId,
    required DateTime startDate,
    required DateTime lastDate,
  }) async {
    DateTime current = startDate;
    int maxDays = lastDate.difference(startDate).inDays;
    int checked = 0;

    // Search forward up to maxDays
    while (current.isBefore(lastDate) || current.isAtSameMomentAs(lastDate)) {
      if (checked > maxDays) break;

      // Check if vet can accept appointment on this date
      final canAccept = await canVetAcceptAppointmentOnDate(vetId, current);
      if (canAccept) {
        return current;
      }

      // Move to next day
      current = current.add(const Duration(days: 1));
      checked++;
    }

    // If no valid date found in the month, try the first day of next month
    final nextMonth = DateTime(startDate.year, startDate.month + 1, 1);
    if (nextMonth.isBefore(lastDate) || nextMonth.isAtSameMomentAs(lastDate)) {
      final canAcceptNextMonth = await canVetAcceptAppointmentOnDate(vetId, nextMonth);
      if (canAcceptNextMonth) {
        return nextMonth;
      }
    }

    return null; // No valid date found
  }

  /// Create a selectableDayPredicate function for date pickers
  /// Note: This returns a synchronous predicate, but actual availability checks are async
  /// For best results, use getValidInitialDate() to set a valid initialDate, or use
  /// isDateSelectable() to validate dates before showing the picker
  static bool Function(DateTime) createSelectableDayPredicate(String vetId) {
    // Cache monthly counts to avoid repeated queries
    final Map<String, int> monthlyCountCache = {};
    final Map<String, DateTime> countCheckTimeCache = {};
    final countCacheDuration = const Duration(minutes: 2);

    return (DateTime date) {
      // Note: We can't do async checks in a synchronous predicate
      // So we allow dates by default and do validation in the booking process
      // Or pre-fetch availability for the date range and cache it
      
      // Check cached monthly count (cached for 2 minutes)
      final monthKey = '${date.year}-${date.month}';
      final lastCheck = countCheckTimeCache[monthKey];
      
      if (lastCheck != null && 
          DateTime.now().difference(lastCheck) <= countCacheDuration) {
        // Use cached value
        final monthlyCount = monthlyCountCache[monthKey] ?? 0;
        return monthlyCount < monthlyAppointmentLimit;
      }

      // No cache or expired - allow selection (validation happens later)
      return true;
    };
  }

  /// Async version of selectableDayPredicate that properly checks availability
  /// Use this when you need to validate dates before showing CalendarDatePicker
  static Future<bool> isDateSelectable(String vetId, DateTime date) async {
    return await canVetAcceptAppointmentOnDate(vetId, date);
  }

  /// Get a valid initial date for CalendarDatePicker
  /// Ensures the initialDate satisfies the predicate
  static Future<DateTime> getValidInitialDate({
    required String vetId,
    DateTime? preferredDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    // If preferred date is provided and valid, use it
    if (preferredDate != null) {
      final canAccept = await canVetAcceptAppointmentOnDate(vetId, preferredDate);
      if (canAccept && 
          (preferredDate.isAfter(firstDate) || preferredDate.isAtSameMomentAs(firstDate)) &&
          (preferredDate.isBefore(lastDate) || preferredDate.isAtSameMomentAs(lastDate))) {
        return preferredDate;
      }
    }

    // Start from today or firstDate, whichever is later
    final startDate = preferredDate ?? DateTime.now();
    final actualStartDate = startDate.isBefore(firstDate) ? firstDate : startDate;

    // Find first valid date
    final validDate = await findFirstValidDate(
      vetId: vetId,
      startDate: actualStartDate,
      lastDate: lastDate,
    );

    // If no valid date found, return today (CalendarDatePicker will handle the error gracefully)
    return validDate ?? actualStartDate;
  }

  /// Get remaining appointment slots for a vet in a specific month
  /// Returns -1 for premium vets (unlimited)
  static Future<int> getRemainingSlotsInMonth(String vetId, DateTime monthDate) async {
    final isPremium = await isVetPremium(vetId);
    if (isPremium) return -1; // Unlimited

    final monthlyCount = await getMonthlyAppointmentCount(vetId, monthDate);
    return monthlyAppointmentLimit - monthlyCount;
  }
}
