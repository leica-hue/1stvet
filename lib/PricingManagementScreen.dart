import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class PricingManagementScreen extends StatefulWidget {
  const PricingManagementScreen({super.key});

  @override
  State<PricingManagementScreen> createState() => _PricingManagementScreenState();
}

class _PricingManagementScreenState extends State<PricingManagementScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _currentVetId;
  String get _collectionName => 'app_settings';

  // Services must be added by the vet - no defaults
  final Map<String, dynamic> _defaultRates = {
    'dog_vaccination_rates': {},   // Empty - vet adds their own services
    'cat_vaccination_rates': {},   // Empty - vet adds their own services
    'deworming_rates': {},         // Empty - vet adds their own services
    'custom_services': {},         // Empty - vet adds their own services
  };

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _originalValues = {};
  final Set<String> _savingFields = {};
  bool _hasRemovedDefaults = false; // Flag to ensure we only remove defaults once
  
  // Availability state
  final Map<String, Map<String, bool>> _availability = {}; // {date: {timeRange: isAvailable}}
  final Map<String, Map<String, bool>> _localAvailabilityCache = {}; // Local cache for immediate updates
  bool _isLoadingAvailability = false; // Flag to prevent multiple simultaneous loads
  bool _isAvailabilityExpanded = true; // Keep expansion tile expanded by default
  int _availabilityRebuildCounter = 0; // Counter to force UI rebuild when dates are added
  
  // Time slots in Morning/Afternoon format (saved to Firebase in this format)
  static const List<Map<String, String>> _morningSlots = [
    {'display': '8:00 - 9:00 AM', 'key': '8:00 - 9:00 AM', 'start': '08:00'},
    {'display': '9:00 - 10:00 AM', 'key': '9:00 - 10:00 AM', 'start': '09:00'},
    {'display': '10:00 - 11:00 AM', 'key': '10:00 - 11:00 AM', 'start': '10:00'},
    {'display': '11:00 - 12:00 NN', 'key': '11:00 - 12:00 NN', 'start': '11:00'},
  ];
  
  static const List<Map<String, String>> _afternoonSlots = [
    {'display': '1:00 - 2:00 PM', 'key': '1:00 - 2:00 PM', 'start': '13:00'},
    {'display': '2:00 - 3:00 PM', 'key': '2:00 - 3:00 PM', 'start': '14:00'},
    {'display': '3:00 - 4:00 PM', 'key': '3:00 - 4:00 PM', 'start': '15:00'},
    {'display': '4:00 - 5:00 PM', 'key': '4:00 - 5:00 PM', 'start': '16:00'},
  ];
  
  // Get all time slot ranges
  List<Map<String, String>> get _allTimeSlotRanges => [
    ..._morningSlots,
    ..._afternoonSlots,
  ];
  
  // Legacy time slots for backward compatibility (migration helper)
  final List<String> _legacyTimeSlots = [
    '08:00', '09:00', '10:00', '11:00', '12:00',
    '13:00', '14:00', '15:00', '16:00', '17:00', '18:00'
  ];
  
  Timer? _availabilitySaveTimer;
  Timer? _pastDatesCheckTimer;

  @override
  void initState() {
    super.initState();
    _currentVetId = _auth.currentUser?.uid;
    _loadAvailability().then((_) {
      // Mark past dates/times as unavailable after loading
      _markPastDatesAsUnavailable();
      
      // Set up periodic check every 5 minutes to update past dates/times
      _pastDatesCheckTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
        _markPastDatesAsUnavailable();
      });
    });
  }

  @override
  void dispose() {
    _controllers.forEach((key, controller) => controller.dispose());
    _availabilitySaveTimer?.cancel();
    _pastDatesCheckTimer?.cancel();
    super.dispose();
  }

  String get _ratesDocId => 'vet_rates_${_currentVetId ?? "unknown"}';

  // Helper methods to check if date/time is in the past
  bool _isDateInPast(String dateStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return false;
    final today = DateTime.now();
    final dateOnly = DateTime(date.year, date.month, date.day);
    final todayOnly = DateTime(today.year, today.month, today.day);
    return dateOnly.isBefore(todayOnly);
  }

  bool _isTimeInPast(String dateStr, String timeStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return false;
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    
    // If date is in the past, all times are past
    if (dateOnly.isBefore(today)) return true;
    
    // If date is in the future, no times are past
    if (dateOnly.isAfter(today)) return false;
    
    // If date is today, check if time is past
    // Handle both formats: "8:00 - 9:00 AM" (new) or "08:00" (legacy)
    String startTimeStr;
    if (timeStr.contains(' - ')) {
      // New format: extract start time from range
      final parts = timeStr.split(' - ');
      if (parts.isEmpty) return false;
      startTimeStr = parts[0].trim();
      // Convert "8:00 AM" to "08:00" format
      final period = timeStr.contains('NN') ? 'NN' : (timeStr.contains('PM') ? 'PM' : 'AM');
      final timeParts = startTimeStr.split(':');
      if (timeParts.length != 2) return false;
      int hour = int.tryParse(timeParts[0]) ?? 0;
      final minute = int.tryParse(timeParts[1]) ?? 0;
      if (period == 'PM' && hour != 12) hour += 12;
      else if (period == 'NN') hour = 12; // NN (Noon) is 12:00
      else if (period == 'AM' && hour == 12) hour = 0;
      startTimeStr = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    } else {
      // Legacy format: already in "08:00" format
      startTimeStr = timeStr;
    }
    
    final timeParts = startTimeStr.split(':');
    if (timeParts.length != 2) return false;
    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);
    if (hour == null || minute == null) return false;
    
    final timeSlot = DateTime(now.year, now.month, now.day, hour, minute);
    return timeSlot.isBefore(now);
  }

  // Automatically mark past dates/times as unavailable
  Future<void> _markPastDatesAsUnavailable() async {
    if (_currentVetId == null) return;
    
    try {
      // Load all schedules from vet_schedules collection
      final schedulesQuery = _firestore
          .collection('vet_schedules')
          .where('vetId', isEqualTo: _currentVetId)
          .get();
      
      final querySnapshot = await schedulesQuery;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      bool hasChanges = false;
      
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final dateStr = data['date'] as String?;
        final timeSlots = _convertToMapStringDynamic(data['timeSlots']);
        
        if (dateStr == null || timeSlots.isEmpty) continue;
        
        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;
        
        final dateOnly = DateTime(date.year, date.month, date.day);
        bool needsUpdate = false;
        final Map<String, bool> updatedTimeSlots = Map<String, bool>.from(
          timeSlots.map((key, value) => MapEntry(key.toString(), value as bool))
        );
        
        // If date is in the past, mark entire date as unavailable
        if (dateOnly.isBefore(today)) {
          for (var slot in _allTimeSlotRanges) {
            final timeKey = slot['key']!;
            if (updatedTimeSlots[timeKey] == true) {
              updatedTimeSlots[timeKey] = false;
              needsUpdate = true;
            }
          }
        } else if (dateOnly.isAtSameMomentAs(today)) {
          // If date is today, mark past times as unavailable
          updatedTimeSlots.forEach((time, isAvailable) {
            if (_isTimeInPast(dateStr, time) && isAvailable == true) {
              updatedTimeSlots[time] = false;
              needsUpdate = true;
            }
          });
        }
        
        if (needsUpdate) {
          // Sort and save updated time slots
          final sortedTimeSlots = _sortTimeSlots(updatedTimeSlots);
          await _saveToVetSchedulesCollection(dateStr, sortedTimeSlots);
          hasChanges = true;
          print('AVAILABILITY: Marked past date/time as unavailable: $dateStr');
          
          // Update local state
          if (mounted) {
            setState(() {
              _availability[dateStr] = Map<String, bool>.from(
                sortedTimeSlots.map((key, value) => MapEntry(key.toString(), value as bool))
              );
            });
          }
        }
      }
      
      if (!hasChanges) {
        print('AVAILABILITY: No past dates/times to update');
      }
    } catch (e) {
      print('AVAILABILITY ERROR: Error marking past dates as unavailable: $e');
    }
  }

  Stream<DocumentSnapshot> _getRatesStream() {
    return _firestore.collection(_collectionName).doc(_ratesDocId).snapshots();
  }

  Future<void> _loadAvailability({bool forceReload = false}) async {
    if (_currentVetId == null) return;
    
    // Allow force reload even if already loading (for after adding dates)
    if (!forceReload && _isLoadingAvailability) return;
    
    _isLoadingAvailability = true;
    try {
      // Load from vet_schedules collection
      final schedulesQuery = _firestore
          .collection('vet_schedules')
          .where('vetId', isEqualTo: _currentVetId)
          .get();
      
      final querySnapshot = await schedulesQuery;
      final Map<String, Map<String, bool>> loadedSchedules = {};
      
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final date = data['date'] as String?;
        final timeSlots = data['timeSlots'] as Map<String, dynamic>?;
        
        if (date != null && timeSlots != null) {
          // Convert timeSlots to Map<String, bool>
          final convertedTimeSlots = <String, bool>{};
          bool needsMigration = false;
          timeSlots.forEach((key, value) {
            final timeKey = key.toString();
            // Migrate "11:00 - 12:00 PM" to "11:00 - 12:00 NN"
            if (timeKey == '11:00 - 12:00 PM') {
              convertedTimeSlots['11:00 - 12:00 NN'] = value as bool;
              needsMigration = true;
            }
            // Migrate legacy format if needed
            else if (_legacyTimeSlots.contains(timeKey)) {
              for (var slot in _allTimeSlotRanges) {
                if (slot['start'] == timeKey) {
                  convertedTimeSlots[slot['key']!] = value as bool;
                  break;
                }
              }
            } else {
              convertedTimeSlots[timeKey] = value as bool;
            }
          });
          
          // If migration is needed, update Firebase
          if (needsMigration && date != null) {
            final sortedTimeSlots = _sortTimeSlots(convertedTimeSlots);
            _saveToVetSchedulesCollection(date, sortedTimeSlots);
            print('AVAILABILITY: Migrated "11:00 - 12:00 PM" to "11:00 - 12:00 NN" for date $date');
          }
          
          // Sort time slots chronologically
          final sortedTimeSlots = _sortTimeSlots(convertedTimeSlots);
          loadedSchedules[date] = Map<String, bool>.from(
            sortedTimeSlots.map((key, value) => MapEntry(key.toString(), value as bool))
          );
        }
      }
      
      if (mounted) {
        setState(() {
          // Store current dates before clearing (to preserve newly added dates if Firebase hasn't propagated)
          final existingDates = Set<String>.from(_availability.keys);
          
          // Clear existing availability map and rebuild from Firebase data
          _availability.clear();
          
          // Add all dates from vet_schedules collection
          loadedSchedules.forEach((date, times) {
            _availability[date] = Map<String, bool>.from(times);
          });
          
          // If force reload, preserve any dates that were in state but not yet in Firebase
          // (This handles the case where Firebase hasn't fully propagated writes yet)
          if (forceReload) {
            existingDates.forEach((date) {
              if (!_availability.containsKey(date) && _localAvailabilityCache.containsKey(date)) {
                // Keep the date from local cache if it's not in Firebase yet
                _availability[date] = Map<String, bool>.from(_localAvailabilityCache[date]!);
              }
            });
          }
          
          // Then override with local cache (pending changes take priority)
          _localAvailabilityCache.forEach((date, times) {
            _availability[date] = Map<String, bool>.from(times);
          });
          
          print('AVAILABILITY: Loaded ${_availability.length} dates into state from vet_schedules. Dates: ${_availability.keys.toList()}');
        });
      }
    } catch (e) {
      print('Error loading availability: $e');
    } finally {
      _isLoadingAvailability = false;
    }
  }

  // Helper method to ensure time format is correct (e.g., "8:00 - 9:00 AM")
  String _ensureCorrectTimeFormat(String time) {
    // Check if it's already in the correct format (contains " - " and "AM", "PM", or "NN")
    if (time.contains(' - ') && (time.contains('AM') || time.contains('PM') || time.contains('NN'))) {
      // Migrate "11:00 - 12:00 PM" to "11:00 - 12:00 NN"
      if (time == '11:00 - 12:00 PM') {
        return '11:00 - 12:00 NN';
      }
      return time; // Already in correct format
    }
    
    // If it's in legacy format (e.g., "08:00"), convert it
    if (_legacyTimeSlots.contains(time)) {
      for (var slot in _allTimeSlotRanges) {
        if (slot['start'] == time) {
          return slot['key']!; // Return the correct format
        }
      }
    }
    
    // Return as-is if we can't determine (shouldn't happen)
    return time;
  }

  // Helper method to get sort order for time slots (chronological order)
  int _getTimeSlotSortOrder(String timeKey) {
    // Find the slot and return its index in the ordered list
    for (int i = 0; i < _allTimeSlotRanges.length; i++) {
      if (_allTimeSlotRanges[i]['key'] == timeKey) {
        return i;
      }
    }
    // If not found, return a high number to put it at the end
    return 999;
  }

  // Helper method to sort time slots chronologically
  Map<String, dynamic> _sortTimeSlots(Map<String, dynamic> timeSlots) {
    // Convert to list of entries, sort by order, then rebuild map
    final entries = timeSlots.entries.toList();
    entries.sort((a, b) {
      final orderA = _getTimeSlotSortOrder(a.key);
      final orderB = _getTimeSlotSortOrder(b.key);
      return orderA.compareTo(orderB);
    });
    
    // Create a LinkedHashMap to preserve insertion order (sorted order)
    // This ensures the keys are in the correct chronological order
    // Note: Firebase Firestore may not preserve map key order, but we sort here
    // and also sort when reading to ensure consistency
    final sortedMap = <String, dynamic>{};
    for (var entry in entries) {
      sortedMap[entry.key] = entry.value;
    }
    return sortedMap;
  }

  Future<void> _saveAvailability(String date, String time, bool isAvailable) async {
    if (_currentVetId == null) return;
    
    // Ensure time is in the correct format (e.g., "8:00 - 9:00 AM")
    final formattedTime = _ensureCorrectTimeFormat(time);
    
    // Update local cache immediately for instant UI feedback (without setState)
    if (!_localAvailabilityCache.containsKey(date)) {
      _localAvailabilityCache[date] = {};
    }
    _localAvailabilityCache[date]![formattedTime] = isAvailable;
    
    // Also update main availability map
    if (!_availability.containsKey(date)) {
      _availability[date] = {};
    }
    _availability[date]![formattedTime] = isAvailable;

    // Cancel previous timer if exists
    _availabilitySaveTimer?.cancel();

    // Debounce Firebase save to avoid too many writes
    _availabilitySaveTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        // Save each date from local cache to vet_schedules collection
        for (var entry in _localAvailabilityCache.entries) {
          final dateKey = entry.key;
          final cachedTimes = entry.value;
          
          // Load existing time slots from Firebase to merge with cached changes
          // This ensures we don't lose time slots that weren't toggled
          final scheduleDocId = '${_currentVetId}_$dateKey';
          final scheduleDocRef = _firestore.collection('vet_schedules').doc(scheduleDocId);
          final existingDoc = await scheduleDocRef.get();
          
          // Start with existing time slots or initialize all slots
          Map<String, dynamic> existingTimeSlots = {};
          
          if (existingDoc.exists && existingDoc.data() != null) {
            final data = existingDoc.data()!;
            final timeSlots = _convertToMapStringDynamic(data['timeSlots']);
            existingTimeSlots = Map<String, dynamic>.from(timeSlots);
          }
          
          // If no existing slots, initialize all slots with values from _availability
          if (existingTimeSlots.isEmpty && _availability.containsKey(dateKey)) {
            // Use current availability state as base
            _availability[dateKey]!.forEach((timeKey, value) {
              final formattedKey = _ensureCorrectTimeFormat(timeKey);
              existingTimeSlots[formattedKey] = value;
            });
          }
          
          // If still empty, initialize all slots as unavailable (default)
          if (existingTimeSlots.isEmpty) {
            for (var slot in _allTimeSlotRanges) {
              existingTimeSlots[slot['key']!] = false;
            }
          }
          
          // Migrate old format keys (e.g., "11:00 - 12:00 PM" to "11:00 - 12:00 NN")
          final keysToMigrate = <String>[];
          existingTimeSlots.forEach((key, value) {
            if (key == '11:00 - 12:00 PM') {
              keysToMigrate.add(key);
            }
          });
          for (var oldKey in keysToMigrate) {
            final value = existingTimeSlots.remove(oldKey);
            existingTimeSlots['11:00 - 12:00 NN'] = value;
          }
          
          // Merge cached changes into existing time slots
          cachedTimes.forEach((timeKey, value) {
            final formattedKey = _ensureCorrectTimeFormat(timeKey);
            existingTimeSlots[formattedKey] = value;
          });
          
          // Ensure all time slots exist (fill in any missing ones)
          for (var slot in _allTimeSlotRanges) {
            final timeKey = slot['key']!;
            if (!existingTimeSlots.containsKey(timeKey)) {
              // If slot is missing, use the cached value or default to false
              existingTimeSlots[timeKey] = cachedTimes.containsKey(timeKey) 
                  ? cachedTimes[timeKey] 
                  : (_availability[dateKey]?[timeKey] ?? false);
            }
          }
          
          // Sort time slots chronologically
          final sortedTimeSlots = _sortTimeSlots(existingTimeSlots);
          
          print('AVAILABILITY: Saving ${sortedTimeSlots.length} time slots for date $dateKey');
          print('AVAILABILITY: Time slots: ${sortedTimeSlots.keys.toList()}');
          
          // Save to vet_schedules collection
          await _saveToVetSchedulesCollection(dateKey, sortedTimeSlots);
        }
        
        // Clear the cache after successful save
        _localAvailabilityCache.clear();
      } catch (e) {
        print('Error saving availability: $e');
      }
    });
  }

  Future<void> _setDateAvailability(String date, bool isAvailable) async {
    if (_currentVetId == null) {
      print('AVAILABILITY ERROR: _currentVetId is null');
      return;
    }
    
    print('AVAILABILITY: Starting to set date availability for $date, isAvailable: $isAvailable');
    
    Map<String, dynamic> finalDateMap;
    
    try {
      // Create time slots map
      if (isAvailable) {
        // If marking as available, initialize all time slots as available (new format)
        final sortedTimes = <String, bool>{};
        print('AVAILABILITY: Total time slot ranges: ${_allTimeSlotRanges.length}');
        for (var slot in _allTimeSlotRanges) {
          // Use the key format which is "8:00 - 9:00 AM"
          final timeKey = slot['key']!;
          sortedTimes[timeKey] = true;
          print('AVAILABILITY: Adding time slot: $timeKey');
        }
        print('AVAILABILITY: Created ${sortedTimes.length} time slots before sorting');
        // Time slots are already in order from _allTimeSlotRanges, but ensure sorted
        finalDateMap = _sortTimeSlots(sortedTimes);
        print('AVAILABILITY: After sorting, ${finalDateMap.length} time slots');
      } else {
        // If marking as unavailable, set all time slots as unavailable
        final sortedTimes = <String, bool>{};
        print('AVAILABILITY: Total time slot ranges: ${_allTimeSlotRanges.length}');
        for (var slot in _allTimeSlotRanges) {
          // Use the key format which is "8:00 - 9:00 AM"
          final timeKey = slot['key']!;
          sortedTimes[timeKey] = false;
          print('AVAILABILITY: Adding time slot: $timeKey');
        }
        print('AVAILABILITY: Created ${sortedTimes.length} time slots before sorting');
        // Time slots are already in order from _allTimeSlotRanges, but ensure sorted
        finalDateMap = _sortTimeSlots(sortedTimes);
        print('AVAILABILITY: After sorting, ${finalDateMap.length} time slots');
      }
      
      print('AVAILABILITY: Setting date $date availability with format: ${finalDateMap.keys.toList()}');
      print('AVAILABILITY: Total time slots to save: ${finalDateMap.length}');
      
      // Save to vet_schedules collection only
      await _saveToVetSchedulesCollection(date, finalDateMap);
      
      print('AVAILABILITY: Date availability saved to vet_schedules collection successfully');
      
    } catch (e) {
      print('AVAILABILITY ERROR: Error in Firebase operations for date $date: $e');
      // Still update local state even if Firebase fails
      // Create a default date map
      finalDateMap = <String, bool>{};
      for (var slot in _allTimeSlotRanges) {
        finalDateMap[slot['key']!] = isAvailable;
      }
    }
    
    // Always update local state to reflect the changes, even if Firebase had issues
    if (mounted) {
      setState(() {
        // Update availability map with the sorted time slots
        _availability[date] = Map<String, bool>.from(
          finalDateMap.map((key, value) => MapEntry(key.toString(), value as bool))
        );
        
        // Also clear any local cache for this date since we just saved it
        if (_localAvailabilityCache.containsKey(date)) {
          _localAvailabilityCache.remove(date);
        }
        
        print('AVAILABILITY: Updated local state for date $date. Total dates: ${_availability.length}');
        print('AVAILABILITY: Current dates in state: ${_availability.keys.toList()}');
      });
    } else {
      print('AVAILABILITY WARNING: Widget not mounted, cannot update state');
    }
  }

  /// Save schedule to the new vet_schedules collection
  /// Document ID format: {vetId}_{date}
  /// Structure: {vetId, date, timeSlots, createdAt, updatedAt}
  Future<void> _saveToVetSchedulesCollection(String date, Map<String, dynamic> timeSlots) async {
    if (_currentVetId == null) return;
    
    try {
      // Ensure time slots are sorted chronologically before saving
      final sortedTimeSlots = _sortTimeSlots(timeSlots);
      
      final scheduleDocId = '${_currentVetId}_$date';
      final scheduleDocRef = _firestore.collection('vet_schedules').doc(scheduleDocId);
      
      // Check if document already exists
      final existingDoc = await scheduleDocRef.get();
      final now = FieldValue.serverTimestamp();
      
      if (existingDoc.exists) {
        // Update existing schedule with sorted time slots
        await scheduleDocRef.update({
          'timeSlots': sortedTimeSlots,
          'updatedAt': now,
        });
        print('SCHEDULE: Updated schedule in vet_schedules collection for date $date');
      } else {
        // Create new schedule document with sorted time slots
        await scheduleDocRef.set({
          'vetId': _currentVetId,
          'date': date,
          'timeSlots': sortedTimeSlots,
          'createdAt': now,
          'updatedAt': now,
        });
        print('SCHEDULE: Created new schedule in vet_schedules collection for date $date');
      }
      
      print('SCHEDULE: Document ID: $scheduleDocId');
      print('SCHEDULE: Time slots saved (sorted): ${sortedTimeSlots.keys.toList()}');
    } catch (e) {
      print('Error saving to vet_schedules collection: $e');
    }
  }

  /// Load schedules from the new vet_schedules collection (optional, for future migration)
  /// This method can be used to read from the new collection instead of the old one
  Future<Map<String, Map<String, bool>>> _loadFromVetSchedulesCollection() async {
    if (_currentVetId == null) return {};
    
    try {
      final schedulesQuery = _firestore
          .collection('vet_schedules')
          .where('vetId', isEqualTo: _currentVetId)
          .get();
      
      final querySnapshot = await schedulesQuery;
      final Map<String, Map<String, bool>> schedules = {};
      
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final date = data['date'] as String?;
        final timeSlots = data['timeSlots'] as Map<String, dynamic>?;
        
        if (date != null && timeSlots != null) {
          schedules[date] = timeSlots.map((key, value) => 
            MapEntry(key, value as bool));
        }
      }
      
      print('SCHEDULE: Loaded ${schedules.length} schedule(s) from vet_schedules collection');
      return schedules;
    } catch (e) {
      print('Error loading from vet_schedules collection: $e');
      return {};
    }
  }

  Future<void> _addMultipleDates() async {
    if (_currentVetId == null) return;
    
    DateTime? startDate;
    DateTime? endDate;
    
    // Show dialog to select date range
    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Date(s)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select a single date or a date range:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  '• Select only "From Date" for a single day\n• Select both dates for a range',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('From Date:'),
                  subtitle: Text(
                    startDate != null 
                        ? DateFormat('EEEE, MMMM d, yyyy').format(startDate!)
                        : 'Select start date',
                    style: TextStyle(
                      color: startDate != null ? Colors.black87 : Colors.grey,
                      fontWeight: startDate != null ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: startDate ?? DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        startDate = picked;
                        if (endDate != null && endDate!.isBefore(startDate!)) {
                          endDate = null;
                        }
                      });
                    }
                  },
                ),
                ListTile(
                  title: const Text('To Date:'),
                  subtitle: Text(
                    endDate != null 
                        ? DateFormat('EEEE, MMMM d, yyyy').format(endDate!)
                        : 'Select end date (optional)',
                    style: TextStyle(
                      color: endDate != null ? Colors.black87 : Colors.grey,
                      fontWeight: endDate != null ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    if (startDate == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please select start date first')),
                      );
                      return;
                    }
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: endDate ?? startDate!,
                      firstDate: startDate!,
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDialogState(() => endDate = picked);
                    }
                  },
                ),
                if (startDate != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF728D5A).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      endDate != null
                          ? '${endDate!.difference(startDate!).inDays + 1} date${endDate!.difference(startDate!).inDays + 1 != 1 ? 's' : ''} will be added'
                          : '1 date will be added (single day)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF728D5A),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: startDate == null 
                  ? null
                  : () => Navigator.pop(context, {
                    'startDate': startDate,
                    'endDate': endDate,
                  }),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF728D5A),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result == null || result['startDate'] == null) return;

    final start = result['startDate']!;
    final end = result['endDate'] ?? start;

    // Automatically add dates as available (no dialog needed)
    final bool isAvailable = true;
    
    // Add all dates in the range
    int addedCount = 0;
    
    // Collect all dates first, then add them sequentially
    final List<String> datesToAdd = [];
    DateTime currentDate = start;
    while (currentDate.isBefore(end.add(const Duration(days: 1)))) {
      final dateStr = DateFormat('yyyy-MM-dd').format(currentDate);
      datesToAdd.add(dateStr);
      currentDate = currentDate.add(const Duration(days: 1));
    }
    
    // Add all dates sequentially and collect them for batch state update
    final List<String> successfullyAddedDates = [];
    for (final dateStr in datesToAdd) {
      try {
        await _setDateAvailability(dateStr, isAvailable);
        successfullyAddedDates.add(dateStr);
        addedCount++;
      } catch (e) {
        print('Error adding date $dateStr: $e');
      }
    }

    // Force a UI rebuild after all dates are added
    if (mounted) {
      setState(() {
        // Ensure expansion tile is expanded to show the new dates
        _isAvailabilityExpanded = true;
        
        // Increment rebuild counter to force UI refresh
        _availabilityRebuildCounter++;
        
        print('AVAILABILITY: After adding dates, total dates in state: ${_availability.length}');
        print('AVAILABILITY: Dates in state: ${_availability.keys.toList()}');
        print('AVAILABILITY: Dates that were added: $successfullyAddedDates');
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $addedCount date${addedCount != 1 ? 's' : ''} added successfully!'),
          backgroundColor: const Color(0xFF6B8E23),
        ),
      );
    }
  }

  Future<void> _removeAvailabilityDate(String date) async {
    if (_currentVetId == null) return;
    
    setState(() {
      _availability.remove(date);
      _localAvailabilityCache.remove(date);
    });

    try {
      // Delete from vet_schedules collection
      final scheduleDocId = '${_currentVetId}_$date';
      await _firestore.collection('vet_schedules').doc(scheduleDocId).delete();
      print('AVAILABILITY: Removed date $date from vet_schedules collection');
    } catch (e) {
      print('Error removing availability date: $e');
    }
  }

  Future<void> _updatePrice(String field, String value) async {
    if (_currentVetId == null) return;

    final double? price = double.tryParse(value);
    if (price == null || price < 0) return;

    setState(() => _savingFields.add(field));

    try {
      final Map<String, dynamic> updateData = field.contains('.')
          ? {field.split('.')[0]: {field.split('.')[1]: price}}
          : {field: price};

      await _firestore
          .collection(_collectionName)
          .doc(_ratesDocId)
          .set({
            'vetId': _currentVetId,
            'updatedAt': FieldValue.serverTimestamp(),
            ...updateData,
          }, SetOptions(merge: true));

      _originalValues[field] = price.toStringAsFixed(2);
    } finally {
      setState(() => _savingFields.remove(field));
    }
  }

  Future<void> _addService(String baseField, String name, double price) async {
    if (_currentVetId == null) return;
    final docRef = _firestore.collection(_collectionName).doc(_ratesDocId);
    
    // Get current document to merge with existing services
    final docSnapshot = await docRef.get();
    final currentData = _convertToMapStringDynamic(docSnapshot.data());
    final existingServices = _convertToMapStringDynamic(currentData[baseField]);
    
    // Add new service to existing services
    existingServices[name] = price;
    
    await docRef.set({
      baseField: existingServices,
      'updatedAt': FieldValue.serverTimestamp(),
      'vetId': _currentVetId,
    }, SetOptions(merge: true));
  }

  Future<void> _removeService(String baseField, String name) async {
    if (_currentVetId == null) return;
    final docRef = _firestore.collection(_collectionName).doc(_ratesDocId);
    await docRef.update({
      '$baseField.$name': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Detect and remove old default services and fixed fees
  Future<void> _removeDefaultServices() async {
    if (_currentVetId == null) return;
    
    final docRef = _firestore.collection(_collectionName).doc(_ratesDocId);
    final docSnapshot = await docRef.get();
    if (!docSnapshot.exists) return;
    
    final data = _convertToMapStringDynamic(docSnapshot.data());
    final Map<String, dynamic> updates = {};
    bool hasChanges = false;
    
    // Remove fixed fees fields
    if (data.containsKey('consultation_fee_php')) {
      updates['consultation_fee_php'] = FieldValue.delete();
      hasChanges = true;
    }
    if (data.containsKey('urgent_surcharge_php')) {
      updates['urgent_surcharge_php'] = FieldValue.delete();
      hasChanges = true;
    }
    
    // Old default service keys to remove
    final defaultServiceKeys = {
      'dog_vaccination_rates': ['puppy_vaccination', 'adult_booster'],
      'cat_vaccination_rates': ['kitten_vaccination', 'adult_booster'],
      'deworming_rates': ['small_pet', 'large_pet'],
    };
    
    // Check and mark default services for removal
    defaultServiceKeys.forEach((category, keys) {
      final categoryData = _convertToMapStringDynamic(data[category]);
      keys.forEach((key) {
        if (categoryData.containsKey(key)) {
          updates['$category.$key'] = FieldValue.delete();
          hasChanges = true;
        }
      });
    });
    
    if (hasChanges) {
      updates['updatedAt'] = FieldValue.serverTimestamp();
      await docRef.update(updates);
    }
  }

  void _showAddServiceDialog(Map<String, dynamic> rates) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController priceController = TextEditingController();
    String selectedCategory = 'custom_services';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add New Service', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Service Category:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'custom_services',
                      child: Text('Custom Services'),
                    ),
                    DropdownMenuItem(
                      value: 'dog_vaccination_rates',
                      child: Text('Dog Vaccination'),
                    ),
                    DropdownMenuItem(
                      value: 'cat_vaccination_rates',
                      child: Text('Cat Vaccination'),
                    ),
                    DropdownMenuItem(
                      value: 'deworming_rates',
                      child: Text('Deworming'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedCategory = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Service Name',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., X-Ray, Surgery, Grooming',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Price (₱)',
                    border: OutlineInputBorder(),
                    prefixText: '₱ ',
                    hintText: '0.00',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                nameController.dispose();
                priceController.dispose();
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a service name')),
                  );
                  return;
                }

                final price = double.tryParse(priceController.text.trim());
                if (price == null || price < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid price')),
                  );
                  return;
                }

                // Convert name to a valid key (replace spaces with underscores, lowercase)
                final serviceKey = name.toLowerCase().replaceAll(' ', '_').replaceAll(RegExp(r'[^a-z0-9_]'), '');
                
                _addService(selectedCategory, serviceKey, price).then((_) {
                  nameController.dispose();
                  priceController.dispose();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Service "$name" added successfully!'),
                      backgroundColor: const Color(0xFF6B8E23),
                    ),
                  );
                }).catchError((error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Error adding service: $error'),
                      backgroundColor: Colors.red,
                    ),
                  );
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 222, 245, 175),
                foregroundColor: Colors.black87,
              ),
              child: const Text('Add Service'),
            ),
          ],
        ),
      ),
    );
  }


  String _formatPrice(dynamic price) {
    if (price == null) return '0.00';
    if (price is num) return price.toStringAsFixed(2);
    final num? parsed = num.tryParse(price.toString());
    return parsed != null ? parsed.toStringAsFixed(2) : '0.00';
  }

  String _formatServiceName(String key) {
    // Replace underscores with spaces and capitalize each word
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty
            ? ''
            : word[0].toUpperCase() + (word.length > 1 ? word.substring(1).toLowerCase() : ''))
        .join(' ');
  }

  // Helper function to safely convert LinkedMap/dynamic maps to Map<String, dynamic>
  Map<String, dynamic> _convertToMapStringDynamic(dynamic data) {
    if (data == null) return <String, dynamic>{};
    if (data is Map<String, dynamic>) return data;
    
    // Handle LinkedMap or Map<dynamic, dynamic>
    final Map<String, dynamic> result = {};
    if (data is Map) {
      data.forEach((key, value) {
        final String stringKey = key.toString();
        if (value is Map) {
          result[stringKey] = _convertToMapStringDynamic(value);
        } else {
          result[stringKey] = value;
        }
      });
    }
    return result;
  }

  Widget _buildDynamicServiceTile({
    required String title,
    required String baseFirestoreField,
    required Map<String, dynamic> rates,
    IconData icon = Icons.category_outlined,
  }) {
    final average = rates.isEmpty
        ? 0.0
        : rates.values.fold<double>(0.0, (sum, v) => sum + (v as num).toDouble()) / rates.length;

    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Icon(icon, color: const Color(0xFF728D5A), size: 32),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Colors.black87)),
        subtitle: Text('Average Rate: ₱${average.toStringAsFixed(2)}',
            style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        childrenPadding: const EdgeInsets.only(left: 20, right: 20, top: 8, bottom: 12),
        children: rates.entries.map((entry) {
          final tierKey = entry.key;
          final fullField = '$baseFirestoreField.$tierKey';
          final tierPrice = _formatPrice(entry.value);

          if (!_controllers.containsKey(fullField)) {
            _controllers[fullField] = TextEditingController(text: tierPrice);
            _originalValues[fullField] = tierPrice;
          }

          final controller = _controllers[fullField]!;
          final isSaving = _savingFields.contains(fullField);
          final isModified = controller.text != _originalValues[fullField];

          return Container(
            margin: const EdgeInsets.only(bottom: 8.0),
            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _formatServiceName(tierKey),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF728D5A), fontSize: 14),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                    ],
                    decoration: InputDecoration(
                      prefixText: '₱ ',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: Color(0xFF728D5A), width: 1.5),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => _removeService(baseFirestoreField, tierKey),
                ),
                SizedBox(
                  width: 40,
                  child: isSaving
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF728D5A)),
                          ),
                        )
                      : (isModified
                          ? IconButton(
                              icon: const Icon(Icons.check_circle_outline, color: Color(0xFF728D5A)),
                              onPressed: () => _updatePrice(fullField, controller.text),
                            )
                          : const SizedBox.shrink()),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentVetId == null) {
      return const Scaffold(
        body: Center(child: Text('⚠️ Please log in as a vet to manage your services.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9F5),
      // Polished header (consistent with other screens)
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            decoration: BoxDecoration(
              color: const Color(0xFFBDD9A4),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: Colors.black87),
                  tooltip: 'Back',
                ),
                const SizedBox(width: 4),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: const Icon(Icons.currency_exchange, color: Color(0xFF728D5A), size: 26),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Services Management',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.black),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showAddServiceDialog({}),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Service'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF728D5A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: StreamBuilder<DocumentSnapshot>(
                  stream: _getRatesStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFF728D5A)));
                    }

                    if (snapshot.hasError) {
                      return Center(child: Text('❌ Error loading rates: ${snapshot.error}'));
                    }

                    final Map<String, dynamic> snapshotData = _convertToMapStringDynamic(snapshot.data?.data());
                    
                    // Remove fixed fees from data immediately (don't display them)
                    final cleanedData = Map<String, dynamic>.from(snapshotData);
                    cleanedData.remove('consultation_fee_php');
                    cleanedData.remove('urgent_surcharge_php');
                    final ratesData = cleanedData.isNotEmpty ? cleanedData : _defaultRates;

                    if (snapshotData.isEmpty && snapshot.data?.exists == false) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _firestore.collection(_collectionName).doc(_ratesDocId).set({
                          'vetId': _currentVetId,
                          'dog_vaccination_rates': {},
                          'cat_vaccination_rates': {},
                          'deworming_rates': {},
                          'custom_services': {},
                          'createdAt': FieldValue.serverTimestamp(),
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                      });
                    }

                    // Automatically remove old default services and fixed fees on first load (only once)
                    if (!_hasRemovedDefaults) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _removeDefaultServices().then((_) {
                          _hasRemovedDefaults = true;
                        });
                      });
                    }

                    // Handle migration from old 'vaccination_rates' structure if it exists
                    if (ratesData.containsKey('vaccination_rates') && 
                        !ratesData.containsKey('dog_vaccination_rates') && 
                        !ratesData.containsKey('cat_vaccination_rates')) {
                      final oldVaccinationRates = _convertToMapStringDynamic(ratesData['vaccination_rates']);
                      final Map<String, dynamic> migrationData = {
                        'updatedAt': FieldValue.serverTimestamp(),
                      };
                      
                      // Migrate old data to new structure
                      if (oldVaccinationRates.containsKey('dog')) {
                        migrationData['dog_vaccination_rates'] = {'default': oldVaccinationRates['dog']};
                        ratesData['dog_vaccination_rates'] = {'default': oldVaccinationRates['dog']};
                      }
                      if (oldVaccinationRates.containsKey('cat')) {
                        migrationData['cat_vaccination_rates'] = {'default': oldVaccinationRates['cat']};
                        ratesData['cat_vaccination_rates'] = {'default': oldVaccinationRates['cat']};
                      }
                      
                      // Save migrated data to Firebase
                      if (migrationData.length > 1) {
                        _firestore.collection(_collectionName).doc(_ratesDocId).set(migrationData, SetOptions(merge: true));
                      }
                    }

                    final dogVaccinationRates =
                        _convertToMapStringDynamic(ratesData['dog_vaccination_rates'] ?? _defaultRates['dog_vaccination_rates']);
                    final catVaccinationRates =
                        _convertToMapStringDynamic(ratesData['cat_vaccination_rates'] ?? _defaultRates['cat_vaccination_rates']);
                    final dewormingRates =
                        _convertToMapStringDynamic(ratesData['deworming_rates'] ?? _defaultRates['deworming_rates']);
                    final customServices =
                        _convertToMapStringDynamic(ratesData['custom_services'] ?? _defaultRates['custom_services']);

                    // Check if vet has added any services yet
                    final hasAnyServices = dogVaccinationRates.isNotEmpty ||
                        catVaccinationRates.isNotEmpty ||
                        dewormingRates.isNotEmpty ||
                        customServices.isNotEmpty;

                    return ListView(
                      padding: const EdgeInsets.only(bottom: 80),
                      children: [
                        // Helpful banner for new vets
                        if (!hasAnyServices)
                          Container(
                            margin: const EdgeInsets.all(16.0),
                            padding: const EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF086),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF728D5A), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, color: Color(0xFF6B8E23), size: 28),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Get Started',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Add your services using the "Add Service" button below.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[800],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                          child: Text('Services',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
                        ),
                        _buildDynamicServiceTile(
                          title: 'Dog Vaccination 🐕',
                          baseFirestoreField: 'dog_vaccination_rates',
                          rates: dogVaccinationRates,
                          icon: Icons.vaccines_outlined,
                        ),
                        _buildDynamicServiceTile(
                          title: 'Cat Vaccination 🐱',
                          baseFirestoreField: 'cat_vaccination_rates',
                          rates: catVaccinationRates,
                          icon: Icons.vaccines_outlined,
                        ),
                        _buildDynamicServiceTile(
                          title: 'Deworming Service',
                          baseFirestoreField: 'deworming_rates',
                          rates: dewormingRates,
                          icon: Icons.bug_report_outlined,
                        ),
                        _buildDynamicServiceTile(
                          title: 'Custom Services',
                          baseFirestoreField: 'custom_services',
                          rates: customServices,
                          icon: Icons.medical_services_outlined,
                        ),
                        const SizedBox(height: 20),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                          child: Text('Available Times & Dates',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
                        ),
                        _buildAvailabilitySection(),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilitySection() {
    // Use local state - data is loaded in initState via _loadAvailability
    // Don't use FutureBuilder here to prevent refresh loops
    if (_isLoadingAvailability && _availability.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF728D5A)));
    }
    
    return _buildAvailabilityContent();
  }

  Widget _buildAvailabilityContent() {
    // Merge local cache with availability for display
    final Map<String, Map<String, bool>> displayData = {};
    
    // Start with Firebase data from _availability
    _availability.forEach((date, times) {
      displayData[date] = Map<String, bool>.from(times);
    });
    
    // Override with local cache (pending changes)
    _localAvailabilityCache.forEach((date, times) {
      displayData[date] = Map<String, bool>.from(times);
    });
    
    final List<String> dates = displayData.keys.toList()..sort();
    
    // Debug: Print what dates we're displaying
    print('AVAILABILITY UI: Displaying ${dates.length} dates: $dates');
    print('AVAILABILITY UI: _availability has ${_availability.length} dates: ${_availability.keys.toList()}');

    return Card(
          key: ValueKey('availability_${dates.length}_${_availabilityRebuildCounter}_${_availability.keys.join('_')}'),
          elevation: 0.5,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ExpansionTile(
            key: ValueKey('expansion_${dates.length}_${_availabilityRebuildCounter}_${_isAvailabilityExpanded}'),
            initiallyExpanded: _isAvailabilityExpanded,
            onExpansionChanged: (expanded) {
              setState(() {
                _isAvailabilityExpanded = expanded;
              });
            },
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            leading: const Icon(Icons.calendar_today, color: Color(0xFF728D5A), size: 32),
            title: const Text('Available Times & Dates', 
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Colors.black87)),
            subtitle: Text('${dates.length} date${dates.length != 1 ? 's' : ''} configured',
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            childrenPadding: const EdgeInsets.only(left: 20, right: 20, top: 8, bottom: 12),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton.icon(
                    onPressed: _addMultipleDates,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Date(s)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF728D5A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (dates.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'No availability dates added yet. Click "Add Date" to get started.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ...dates.map((dateStr) {
                  final date = DateTime.tryParse(dateStr);
                  final formattedDate = date != null 
                      ? DateFormat('EEEE, MMMM d, yyyy').format(date)
                      : dateStr;
                  
                  // Use merged display data
                  final times = displayData[dateStr] ?? {};
                  
                  // Check if date is in the past
                  final bool isDatePast = _isDateInPast(dateStr);
                  
                  // For past dates, all times are unavailable
                  // For today, mark past times as unavailable
                  final Map<String, bool> adjustedTimes = {};
                  times.forEach((time, isAvailable) {
                    if (isDatePast) {
                      adjustedTimes[time] = false;
                    } else if (_isTimeInPast(dateStr, time)) {
                      adjustedTimes[time] = false;
                    } else {
                      adjustedTimes[time] = isAvailable;
                    }
                  });
                  
                  // Check if date is available (if any time slot is true and not past)
                  final bool dateIsAvailable = adjustedTimes.values.any((value) => value == true);
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: dateIsAvailable 
                          ? const Color(0xFF728D5A).withOpacity(0.05)
                          : Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: dateIsAvailable 
                            ? const Color(0xFF728D5A).withOpacity(0.3)
                            : Colors.grey.shade300,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    formattedDate,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: Color(0xFF728D5A),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        dateIsAvailable ? Icons.check_circle : Icons.cancel,
                                        size: 16,
                                        color: dateIsAvailable 
                                            ? const Color(0xFF728D5A)
                                            : Colors.grey[600],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        dateIsAvailable ? 'Available' : 'Unavailable',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          color: dateIsAvailable 
                                              ? const Color(0xFF728D5A)
                                              : Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                // Toggle availability switch (disabled for past dates)
                                Switch(
                                  value: dateIsAvailable,
                                  onChanged: isDatePast 
                                      ? null 
                                      : (value) => _setDateAvailability(dateStr, value),
                                  activeColor: const Color(0xFF728D5A),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                  onPressed: () => _removeAvailabilityDate(dateStr),
                                  tooltip: 'Remove date',
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (dateIsAvailable) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Available Time Slots:',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Morning Section
                          const Text(
                            'Morning',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildTimeSlotRangeRow(
                            dateStr,
                            [_morningSlots[0], _morningSlots[1]],
                            adjustedTimes,
                          ),
                          const SizedBox(height: 8),
                          _buildTimeSlotRangeRow(
                            dateStr,
                            [_morningSlots[2], _morningSlots[3]],
                            adjustedTimes,
                          ),
                          const SizedBox(height: 16),
                          // Afternoon Section
                          const Text(
                            'Afternoon',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildTimeSlotRangeRow(
                            dateStr,
                            [_afternoonSlots[0], _afternoonSlots[1]],
                            adjustedTimes,
                          ),
                          const SizedBox(height: 8),
                          _buildTimeSlotRangeRow(
                            dateStr,
                            [_afternoonSlots[2], _afternoonSlots[3]],
                            adjustedTimes,
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          Text(
                            'This date is marked as unavailable. Toggle the switch above to make it available and set time slots.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
            ],
          ),
        );
  }
  
  // Build a row of time slot ranges (2 slots per row)
  Widget _buildTimeSlotRangeRow(
    String dateStr,
    List<Map<String, String>> slots,
    Map<String, bool> adjustedTimes,
  ) {
    return Row(
      children: slots.map((slot) {
        final display = slot['display']!;
        final key = slot['key']!; // Use the key format for Firebase (e.g., "8:00 - 9:00 AM")
        final isTimePast = _isTimeInPast(dateStr, key);
        // Check availability using the new key format
        final effectiveValue = isTimePast ? false : (adjustedTimes[key] == true);
        
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: _TimeSlotWidget(
              date: dateStr,
              time: display, // Display format
              timeKey: key, // Firebase key format
              initialValue: effectiveValue,
              isPast: isTimePast,
              onTap: isTimePast 
                  ? null 
                  : (isAvailable) {
                    // Save using the new key format (e.g., "8:00 - 9:00 AM")
                    _saveAvailability(dateStr, key, isAvailable);
                  },
              getCurrentValue: () {
                if (_isTimeInPast(dateStr, key)) return false;
                
                // Check local cache first
                if (_localAvailabilityCache.containsKey(dateStr) && 
                    _localAvailabilityCache[dateStr]!.containsKey(key)) {
                  return _localAvailabilityCache[dateStr]![key] == true;
                }
                // Check availability map
                if (_availability.containsKey(dateStr) && 
                    _availability[dateStr]!.containsKey(key)) {
                  return _availability[dateStr]![key] == true;
                }
                return adjustedTimes[key] == true;
              },
            ),
          ),
        );
      }).toList(),
    );
  }
}

// Individual stateful widget for each time slot to prevent full rebuild
class _TimeSlotWidget extends StatefulWidget {
  final String date;
  final String time; // Display format (e.g., "8:00 - 9:00 AM")
  final String? timeKey; // Firebase key format (e.g., "8:00 - 9:00 AM")
  final bool initialValue;
  final bool isPast;
  final Function(bool)? onTap;
  final bool Function() getCurrentValue;

  const _TimeSlotWidget({
    required this.date,
    required this.time,
    this.timeKey,
    required this.initialValue,
    required this.isPast,
    required this.onTap,
    required this.getCurrentValue,
  });

  @override
  State<_TimeSlotWidget> createState() => _TimeSlotWidgetState();
}

class _TimeSlotWidgetState extends State<_TimeSlotWidget> {
  late bool _isAvailable;

  @override
  void initState() {
    super.initState();
    _isAvailable = widget.initialValue;
  }

  @override
  void didUpdateWidget(_TimeSlotWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update if the initial value actually changed
    if (oldWidget.initialValue != widget.initialValue) {
      _isAvailable = widget.initialValue;
    }
  }

  void _handleTap() {
    if (widget.isPast || widget.onTap == null) return;
    
    setState(() {
      _isAvailable = !_isAvailable;
    });
    widget.onTap!(_isAvailable);
  }

  @override
  Widget build(BuildContext context) {
    // Get current value from parent's state
    final currentValue = widget.getCurrentValue();
    if (currentValue != _isAvailable) {
      // Sync with parent state if it changed externally
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isAvailable = currentValue;
          });
        }
      });
    }

    final isDisabled = widget.isPast;
    
    return GestureDetector(
      onTap: isDisabled ? null : _handleTap,
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0,
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: isDisabled
                ? Colors.grey[200]
                : (_isAvailable 
                    ? const Color(0xFF728D5A).withOpacity(0.1)
                    : Colors.grey[300]),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDisabled
                  ? Colors.grey[300]!
                  : (_isAvailable 
                      ? const Color(0xFF728D5A)
                      : Colors.grey[400]!),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDisabled 
                    ? Icons.access_time
                    : (_isAvailable ? Icons.check_circle : Icons.cancel),
                size: 16,
                color: isDisabled
                    ? Colors.grey[500]
                    : (_isAvailable 
                        ? const Color(0xFF728D5A)
                        : Colors.grey[600]),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.time + (isDisabled ? ' (Past)' : ''),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: isDisabled
                        ? Colors.grey[500]
                        : (_isAvailable 
                            ? const Color(0xFF728D5A)
                            : Colors.grey[600]),
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
 
 