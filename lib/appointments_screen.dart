import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:table_calendar/table_calendar.dart';
import 'common_sidebar.dart';
import 'payment_option_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const FureverHealthyApp());
}

class FureverHealthyApp extends StatelessWidget {
  const FureverHealthyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AppointmentsPage(appointmentDoc: null),
    );
  }
}

class Appointment {
  String id;
  DateTime appointmentDateTime;
  String petName;
  String reason;
  String timeSlot;
  String userName;
  String status;
  String vetNotes;
  String userId;
  String vetId;
  DateTime? createdAt;
  String vetName;
  String vetSpecialty;
  int rating; // Retaining this for consistency, though runtime data might override
  int cost;
  String appointmentType;
  String userEmail;
  bool isRescheduled;

  Appointment({
    required this.id,
    required this.appointmentDateTime,
    required this.petName,
    required this.reason,
    required this.timeSlot,
    required this.userName,
    this.status = "Pending",
    this.vetNotes = "",
    required this.userId,
    required this.vetId,
    this.createdAt,
    this.vetName = '',
    this.vetSpecialty = '',
    this.rating = 0,
    this.cost = 0,
    this.appointmentType = '',
    this.userEmail = '',
    this.isRescheduled = false,
  });

  static Appointment fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final Timestamp? apptTs = data['appointmentDateTime'] as Timestamp?;
    final Timestamp? createdAtTs = data['createdAt'] as Timestamp?;
    final Timestamp? updatedAtTs = data['updatedAt'] as Timestamp?;

    // Check if appointment is rescheduled using multiple indicators
    bool isRescheduled = false;
    
    // Method 1: Check all possible explicit flag field names (case-insensitive check)
    final flagFields = ['isReschedule', 'rescheduleRequest', 'isRescheduled', 'rescheduled', 
                        'is_reschedule', 'reschedule_request', 'wasRescheduled'];
    for (final field in flagFields) {
      if (data[field] == true) {
        isRescheduled = true;
        break;
      }
    }
    
    // Method 2: Check for rescheduledAt timestamp (any variation)
    if (!isRescheduled) {
      final rescheduleTimestampFields = ['rescheduledAt', 'rescheduled_at', 'rescheduleDate', 
                                          'reschedule_date', 'rescheduledDate'];
      for (final field in rescheduleTimestampFields) {
        if (data[field] != null) {
          isRescheduled = true;
          break;
        }
      }
    }
    
    // Method 3: Check for original/previous appointment date fields
    if (!isRescheduled) {
      final originalDateFields = ['originalAppointmentDateTime', 'original_appointment_date_time',
                                   'previousAppointmentDateTime', 'previous_appointment_date_time',
                                   'oldAppointmentDateTime', 'old_appointment_date_time',
                                   'initialAppointmentDateTime', 'initial_appointment_date_time'];
      for (final field in originalDateFields) {
        if (data[field] != null) {
          isRescheduled = true;
          break;
        }
      }
    }
    
    // Method 4: If status is "pending" and there's an updatedAt that's different from createdAt,
    // it might indicate a reschedule (common pattern: rescheduled appointments go back to pending)
    if (!isRescheduled && createdAtTs != null && updatedAtTs != null) {
      final createdAt = createdAtTs.toDate();
      final updatedAt = updatedAtTs.toDate();
      final status = (data['status'] ?? '').toString().toLowerCase();
      
      // If updated more than 1 minute after creation and status is pending, likely rescheduled
      // Also check if there are any reschedule-related fields in the data
      if (updatedAt.difference(createdAt).inMinutes > 1 && status == 'pending') {
        final hasRescheduleIndicator = data.keys.any((key) => 
          key.toLowerCase().contains('reschedule') || 
          key.toLowerCase().contains('original') ||
          key.toLowerCase().contains('previous'));
        
        if (hasRescheduleIndicator) {
          isRescheduled = true;
        }
      }
    }
    
    // Method 5: Last resort - if appointment was updated significantly after creation
    // and we can't find other indicators, check if it's likely a reschedule
    // (This is a fallback for cases where reschedule flags aren't set)
    if (!isRescheduled && createdAtTs != null && updatedAtTs != null && apptTs != null) {
      final createdAt = createdAtTs.toDate();
      final updatedAt = updatedAtTs.toDate();
      final apptDate = apptTs.toDate();
      
      // If appointment was updated more than 10 minutes after creation
      // and the appointment date is in the future, it's likely been rescheduled
      if (updatedAt.difference(createdAt).inMinutes > 10 && 
          apptDate.isAfter(DateTime.now())) {
        // Only mark as rescheduled if status is pending or confirmed (not cancelled/completed)
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'pending' || status == 'confirmed') {
          isRescheduled = true;
        }
      }
    }
    
    // Method 6: Simple heuristic - if appointment was updated after creation 
    // and status is pending, it's likely been rescheduled
    // (This is a common pattern: rescheduled appointments often go back to pending)
    if (!isRescheduled && createdAtTs != null && updatedAtTs != null) {
      final createdAt = createdAtTs.toDate();
      final updatedAt = updatedAtTs.toDate();
      final status = (data['status'] ?? '').toString().toLowerCase();
      
      // If updated more than 2 minutes after creation and status is pending, treat as rescheduled
      // This catches cases where reschedule flags aren't set
      if (updatedAt.difference(createdAt).inMinutes > 2 && status == 'pending') {
        isRescheduled = true;
      }
    }
    
    // Debug: Print to help identify what fields exist (remove in production if needed)
    debugPrint('APPT ${doc.id} - isRescheduled: $isRescheduled, status: ${data['status']}, '
        'createdAt: $createdAtTs, updatedAt: $updatedAtTs, '
        'hasRescheduleFields: ${data.keys.where((k) => 
          k.toLowerCase().contains('reschedule') || 
          k.toLowerCase().contains('original') ||
          k.toLowerCase().contains('previous')).join(", ")}');

    return Appointment(
      id: doc.id,
      appointmentDateTime: apptTs?.toDate() ?? DateTime.now(),
      petName: data['petName'] ?? '',
      reason: data['reason'] ?? '',
      timeSlot: data['timeSlot'] ?? '',
      userName: data['userName'] ?? '',
      status: data['status'] ?? 'Pending',
      vetNotes: data['vetNotes'] ?? '',
      userId: data['userId'] ?? '',
      vetId: data['vetId'] ?? '',
      createdAt: createdAtTs?.toDate(),
      vetName: data['vetName'] ?? 'N/A',
      vetSpecialty: data['vetSpecialty'] ?? 'N/A',
      rating: (data['rating'] as num?)?.toInt() ?? 0,
      cost: (data['cost'] as num?)?.toInt() ?? 0,
      appointmentType: data['appointmentType'] ?? 'N/A',
      userEmail: data['userEmail'] ?? '',
      isRescheduled: isRescheduled,
    );
  }
}

class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({super.key, required appointmentDoc});

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String _selectedFilter = "all";
  final user = FirebaseAuth.instance.currentUser;
  bool _isPremium = false;
  static const int _monthlyAppointmentLimit = 20;
  bool _isCheckingAutoDecline = false; // Prevent multiple simultaneous checks

  @override
  void initState() {
    super.initState();
    _checkPremiumStatus().then((_) {
      // After checking premium status, auto-decline over-limit appointments
      _autoDeclineOverLimitAppointments();
    });
    
    // Set up a periodic check every 30 seconds to catch new appointments
    // This handles cases where appointments are created while the screen is open
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && !_isCheckingAutoDecline) {
        _autoDeclineOverLimitAppointments();
      }
    });
  }

  // Check if vet has premium status
  Future<void> _checkPremiumStatus() async {
    if (user == null) {
      setState(() => _isPremium = false);
      return;
    }

    try {
      final vetDoc = await FirebaseFirestore.instance
          .collection('vets')
          .doc(user!.uid)
          .get();
      
      if (vetDoc.exists) {
        final data = vetDoc.data();
        final premiumUntil = data?['premiumUntil'] as Timestamp?;
        final isPremium = data?['isPremium'] as bool? ?? false;
        
        bool hasActivePremium = false;
        if (premiumUntil != null) {
          final premiumDate = premiumUntil.toDate();
          hasActivePremium = premiumDate.isAfter(DateTime.now());
        }
        
        if (mounted) {
          setState(() {
            _isPremium = hasActivePremium || isPremium;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isPremium = false);
        }
      }
    } catch (e) {
      debugPrint("Error checking premium status: $e");
      if (mounted) {
        setState(() => _isPremium = false);
      }
    }
  }

  // Count appointments for the current month
  Future<int> _getMonthlyAppointmentCount() async {
    if (user == null) return 0;

    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

      // Fetch all appointments for this vet and filter by date in code
      // (Firestore doesn't support multiple range queries on same field)
      final snapshot = await FirebaseFirestore.instance
          .collection('user_appointments')
          .where('vetId', isEqualTo: user!.uid)
          .get();

      // Filter appointments by current month and count non-declined/cancelled
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

          // Check if appointment is in current month
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
      debugPrint("Error counting monthly appointments: $e");
      return 0;
    }
  }

  // Get count of confirmed/completed appointments only (excludes pending)
  Future<int> _getConfirmedAppointmentCount() async {
    if (user == null) return 0;

    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

      final snapshot = await FirebaseFirestore.instance
          .collection('user_appointments')
          .where('vetId', isEqualTo: user!.uid)
          .get();

      int count = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final apptDateTime = data['appointmentDateTime'];
        final status = (data['status'] ?? '').toString().toLowerCase();
        
        // Only count confirmed and completed appointments (exclude pending)
        if (status != 'confirmed' && status != 'completed') continue;
        
        if (apptDateTime != null) {
          DateTime apptDate;
          if (apptDateTime is Timestamp) {
            apptDate = apptDateTime.toDate();
          } else if (apptDateTime is DateTime) {
            apptDate = apptDateTime;
          } else {
            continue;
          }

          // Check if appointment is in current month
          if (apptDate.isAfter(startOfMonth.subtract(const Duration(days: 1))) &&
              apptDate.isBefore(endOfMonth.add(const Duration(days: 1)))) {
            count++;
          }
        }
      }
      
      return count;
    } catch (e) {
      debugPrint("Error counting confirmed appointments: $e");
      return 0;
    }
  }

  // Auto-decline appointments that exceed the monthly limit
  // This handles cases where appointments were created before validation was in place
  Future<void> _autoDeclineOverLimitAppointments() async {
    // Skip if vet is premium (unlimited appointments) or already checking
    if (_isPremium || user == null || _isCheckingAutoDecline) return;

    _isCheckingAutoDecline = true;

    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

      // Get count of confirmed/completed appointments (excluding pending)
      final confirmedCount = await _getConfirmedAppointmentCount();
      
      // Fetch all pending appointments for this vet
      final pendingSnapshot = await FirebaseFirestore.instance
          .collection('user_appointments')
          .where('vetId', isEqualTo: user!.uid)
          .where('status', isEqualTo: 'pending')
          .get();

      // Get all pending appointments in current month, sorted by creation date (oldest first)
      final List<Map<String, dynamic>> pendingInMonthList = [];
      
      for (var doc in pendingSnapshot.docs) {
        final data = doc.data();
        final apptDateTime = data['appointmentDateTime'];
        final createdAt = data['createdAt'];

        if (apptDateTime != null) {
          DateTime apptDate;
          if (apptDateTime is Timestamp) {
            apptDate = apptDateTime.toDate();
          } else if (apptDateTime is DateTime) {
            apptDate = apptDateTime;
          } else {
            continue;
          }

          // Check if appointment is in current month
          if (apptDate.isAfter(startOfMonth.subtract(const Duration(days: 1))) &&
              apptDate.isBefore(endOfMonth.add(const Duration(days: 1)))) {
            DateTime createdDate = DateTime.now();
            if (createdAt != null) {
              if (createdAt is Timestamp) {
                createdDate = createdAt.toDate();
              } else if (createdAt is DateTime) {
                createdDate = createdAt;
              }
            }
            
            pendingInMonthList.add({
              'id': doc.id,
              'petName': data['petName'] ?? 'Unknown Pet',
              'userName': data['userName'] ?? 'Unknown User',
              'userId': data['userId'] ?? '',
              'createdAt': createdDate,
              'appointmentDateTime': apptDate,
            });
          }
        }
      }

      // Sort by creation date (oldest first) - first come, first served
      pendingInMonthList.sort((a, b) => 
          (a['createdAt'] as DateTime).compareTo(b['createdAt'] as DateTime));

      final List<Map<String, dynamic>> overLimitAppointments = [];
      int pendingCount = 0;

      // Process pending appointments in order (oldest first)
      // Keep first appointments that fit within limit, decline the rest
      for (var appointment in pendingInMonthList) {
        pendingCount++;
        
        // If confirmed count + pending count would exceed the limit, mark it for decline
        if (confirmedCount + pendingCount > _monthlyAppointmentLimit) {
          overLimitAppointments.add({
            'id': appointment['id'],
            'petName': appointment['petName'],
            'userName': appointment['userName'],
            'userId': appointment['userId'],
          });
        }
      }

      // Auto-decline appointments that exceed the limit
      if (overLimitAppointments.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        final declinedCount = overLimitAppointments.length;

        for (var appointment in overLimitAppointments) {
          final appointmentRef = FirebaseFirestore.instance
              .collection('user_appointments')
              .doc(appointment['id']);

          batch.update(appointmentRef, {
            'status': 'declined',
            'vetNotes': 'Auto-declined: Monthly appointment limit of $_monthlyAppointmentLimit has been reached. Please try booking next month or with another veterinarian.',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        await batch.commit();

        // Get vet name for notifications
        String vetName = 'your veterinarian';
        try {
          final vetDoc = await FirebaseFirestore.instance
              .collection('vets')
              .doc(user!.uid)
              .get();
          vetName = vetDoc.data()?['name'] ?? 'your veterinarian';
        } catch (e) {
          debugPrint('Error fetching vet name for notifications: $e');
        }

        // Send notifications to users about declined appointments
        for (var appointment in overLimitAppointments) {
          try {
            final userId = appointment['userId'] as String?;
            
            if (userId != null && userId.isNotEmpty) {
              // Create notification for the user
              await FirebaseFirestore.instance.collection('notifications').add({
                'userId': userId,
                'title': 'Appointment Declined',
                'message': 'Your appointment with $vetName for ${appointment['petName']} has been declined. The veterinarian has reached their monthly appointment limit of $_monthlyAppointmentLimit appointments. Please try booking next month or with another veterinarian.',
                'type': 'appointment_declined',
                'appointmentId': appointment['id'],
                'petName': appointment['petName'],
                'vetName': vetName,
                'read': false,
                'createdAt': FieldValue.serverTimestamp(),
              });
              
              debugPrint('Notification sent to user $userId about declined appointment ${appointment['id']}');
            }
          } catch (e) {
            debugPrint('Error sending notification for appointment ${appointment['id']}: $e');
            // Continue with other appointments even if one notification fails
          }
        }

        // Show notification to vet about auto-declined appointments
        if (mounted && overLimitAppointments.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '⚠️ $declinedCount appointment(s) automatically declined due to monthly limit ($confirmedCount/$_monthlyAppointmentLimit confirmed)',
              ),
              backgroundColor: Colors.orange.shade700,
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: 'Upgrade',
                textColor: Colors.white,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PaymentOptionScreen()),
                  );
                },
              ),
            ),
          );
        }

        debugPrint('Auto-declined $declinedCount appointment(s) that exceeded monthly limit');
      }
    } catch (e) {
      debugPrint('Error auto-declining over-limit appointments: $e');
    } finally {
      _isCheckingAutoDecline = false;
    }
  }

  Stream<QuerySnapshot> _getAppointmentStream() {
    if (user != null) {
      // ✅ Vet will only see appointments assigned to them
      return FirebaseFirestore.instance
          .collection('user_appointments')
          .where('vetId', isEqualTo: user!.uid)
          .snapshots();
    } else {
      return const Stream.empty();
    }
  }
  
  // New method to fetch rating from the 'feedback' collection
  Future<int?> _getAppointmentRating(String appointmentId) async {
    try {
      final feedbackDoc = await FirebaseFirestore.instance
          .collection('feedback') // Assuming a 'feedback' collection
          .where('appointmentId', isEqualTo: appointmentId)
          .limit(1)
          .get();

      if (feedbackDoc.docs.isNotEmpty) {
        final data = feedbackDoc.docs.first.data();
        // Assuming the rating field is named 'rating' and is an integer
        final rating = (data['rating'] as num?)?.toInt();
        return rating;
      }
      return null;
    } catch (e) {
      debugPrint("Error fetching rating: $e");
      return null;
    }
  }


    bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _tabButton(String label) {
    final isSelected = _selectedFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ElevatedButton(
        onPressed: () {
          setState(() => _selectedFilter = label);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isSelected ? const Color(0xFF728D5A) : Colors.grey.shade300,
          foregroundColor: isSelected ? Colors.white : Colors.black,
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildAppointmentLimitBanner() {
    if (_isPremium) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade300, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.workspace_premium, color: Colors.green.shade700, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Premium: Unlimited appointments this month",
                style: TextStyle(
                  color: Colors.green.shade900,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<int>(
      future: _getMonthlyAppointmentCount(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final monthlyCount = snapshot.data ?? 0;
        final isAtLimit = monthlyCount >= _monthlyAppointmentLimit;
        final remaining = _monthlyAppointmentLimit - monthlyCount;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isAtLimit ? Colors.orange.shade50 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isAtLimit ? Colors.orange.shade300 : Colors.blue.shade300,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isAtLimit ? Icons.warning_amber_rounded : Icons.info_outline,
                color: isAtLimit ? Colors.orange.shade700 : Colors.blue.shade700,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isAtLimit
                      ? "Monthly limit reached ($monthlyCount/$_monthlyAppointmentLimit). Upgrade to Premium for unlimited appointments."
                      : "Monthly appointments: $monthlyCount/$_monthlyAppointmentLimit ($remaining remaining)",
                  style: TextStyle(
                    color: isAtLimit ? Colors.orange.shade900 : Colors.blue.shade900,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              if (isAtLimit) ...[
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PaymentOptionScreen()),
                    );
                  },
                  icon: const Icon(Icons.workspace_premium, size: 16),
                  label: const Text("Upgrade"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const CommonSidebar(currentScreen: 'Appointments'),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
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
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: const Icon(Icons.event_note, color: Color(0xFF728D5A), size: 26),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        "Appointments",
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Colors.black),
                      ),
                    ],
                  ),
                ),

                // Main Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _getAppointmentStream(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(
                              child: Text("No appointments found."));
                        }

                        final appointments = snapshot.data!.docs
                            .map((doc) => Appointment.fromDoc(doc))
                            .toList();

                        final filteredAppointments = appointments.where((appt) {
                            // Exclude cancelled appointments from "all" view - they should only show when "cancelled" filter is selected
                            final apptStatusLower = appt.status.toLowerCase();
                            final matchesStatus = (_selectedFilter == "all" && 
                                apptStatusLower != "completed" && 
                                apptStatusLower != "declined" && 
                                apptStatusLower != "cancelled")
                                || _selectedFilter == apptStatusLower;
                          final matchesDate = _selectedDay == null ||
                              _isSameDate(appt.appointmentDateTime, _selectedDay!);
                          return matchesStatus && matchesDate;
                        }).toList();

                        // Exclude cancelled appointments from calendar markers
                        final bookedDates = appointments
                            .where((appt) => appt.status.toLowerCase() != "cancelled")
                            .map((e) => e.appointmentDateTime)
                            .toList();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Appointment limit banner
                            _buildAppointmentLimitBanner(),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                _tabButton("all"),
                                _tabButton("pending"),
                                _tabButton("confirmed"),
                                _tabButton("declined"),
                                _tabButton("cancelled"),
                                _tabButton("completed"),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: filteredAppointments.isEmpty
                                        ? const Center(
                                              child: Text(
                                                "No appointments found.",
                                                style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.grey),
                                              ),
                                            )
                                        : ListView(
                                              children: filteredAppointments
                                                  .map((appt) =>
                                                      _appointmentCard(appt))
                                                  .toList(),
                                            ),
                                  ),
                                  const SizedBox(width: 20),
                                  _buildCalendarSection(bookedDates),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  

  // Helper function to format time slot for display
  // Handles multiple formats: legacy ("11:00"), old ("11:00 - 12:00 PM"), and new ("11:00 - 12:00 NN")
  String _formatTimeSlot(String timeSlot) {
    if (timeSlot.isEmpty) return timeSlot;
    
    // Migrate old format to new format for display
    if (timeSlot == '11:00 - 12:00 PM') {
      return '11:00 - 12:00 NN';
    }
    
    // Handle legacy format where it's just the start time (e.g., "11:00")
    // Convert to full range format "11:00 - 12:00 NN"
    if (timeSlot == '11:00' || timeSlot == '11:00 AM' || timeSlot == '11:00 PM') {
      return '11:00 - 12:00 NN';
    }
    
    // Map other legacy single time formats to their full ranges
    final timeSlotMap = {
      '08:00': '8:00 - 9:00 AM',
      '8:00': '8:00 - 9:00 AM',
      '8:00 AM': '8:00 - 9:00 AM',
      '09:00': '9:00 - 10:00 AM',
      '9:00': '9:00 - 10:00 AM',
      '9:00 AM': '9:00 - 10:00 AM',
      '10:00': '10:00 - 11:00 AM',
      '10:00 AM': '10:00 - 11:00 AM',
      '12:00': '11:00 - 12:00 NN',
      '12:00 PM': '11:00 - 12:00 NN',
      '13:00': '1:00 - 2:00 PM',
      '1:00': '1:00 - 2:00 PM',
      '1:00 PM': '1:00 - 2:00 PM',
      '14:00': '2:00 - 3:00 PM',
      '2:00': '2:00 - 3:00 PM',
      '2:00 PM': '2:00 - 3:00 PM',
      '15:00': '3:00 - 4:00 PM',
      '3:00': '3:00 - 4:00 PM',
      '3:00 PM': '3:00 - 4:00 PM',
      '16:00': '4:00 - 5:00 PM',
      '4:00': '4:00 - 5:00 PM',
      '4:00 PM': '4:00 - 5:00 PM',
    };
    
    // Check if it's a legacy single time format
    if (timeSlotMap.containsKey(timeSlot)) {
      return timeSlotMap[timeSlot]!;
    }
    
    // If it already contains the full range with NN, return as-is
    if (timeSlot.contains(' - ') && timeSlot.contains('NN')) {
      return timeSlot;
    }
    
    // If it contains the full range with PM/AM, return as-is
    // (other time slots like "1:00 - 2:00 PM" should display normally)
    if (timeSlot.contains(' - ') && (timeSlot.contains('PM') || timeSlot.contains('AM'))) {
      return timeSlot;
    }
    
    // For any other format, return as-is
    return timeSlot;
  }

  Widget _appointmentCard(Appointment appt) {
    Color statusColor;
    switch (appt.status) {
      case "confirmed":
        statusColor = Colors.green;
        break;
      case "declined":
        statusColor = Colors.red;
        break;
      case "completed":
        statusColor = Colors.blue;
        break;
      case "cancelled":
        statusColor = Colors.purple;
        break;
      default:
        statusColor = Colors.orange;
    }

    // Determine whether to fetch the rating
    final shouldFetchRating = appt.status == "completed";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      appt.petName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (appt.isRescheduled) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade300, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 14,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Rescheduled',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                "₱${appt.cost}",
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFF728D5A)),
              ),
              const SizedBox(width: 10),

              // ✅ Vet can update status
              DropdownButton<String>(
                value: appt.status,
                underline: const SizedBox(),
                items: [
                  "pending",
                  "confirmed",
                  "declined",
                  "completed",
                  "cancelled"
                ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (newStatus) async {
                  if (newStatus != null) {
                    // Check limit before confirming an appointment
                    if (newStatus == "confirmed" && appt.status != "confirmed") {
                      // Only check limit if vet is not premium
                      if (!_isPremium) {
                        final monthlyCount = await _getMonthlyAppointmentCount();
                        // If already at or over limit, prevent confirming new appointments
                        if (monthlyCount >= _monthlyAppointmentLimit) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Monthly appointment limit reached ($monthlyCount/$_monthlyAppointmentLimit). Upgrade to Premium for unlimited appointments.',
                              ),
                              backgroundColor: Colors.orange.shade700,
                              duration: const Duration(seconds: 4),
                              action: SnackBarAction(
                                label: 'Upgrade',
                                textColor: Colors.white,
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const PaymentOptionScreen()),
                                  );
                                },
                              ),
                            ),
                          );
                          return;
                        }
                      }
                    }
                    
                    await FirebaseFirestore.instance
                        .collection('user_appointments')
                        .doc(appt.id)
                        .update({'status': newStatus});
                  }
                },
              ),

              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text("${appt.reason} (${appt.appointmentType})"),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.access_time, size: 18),
              const SizedBox(width: 6),
              Text(_formatTimeSlot(appt.timeSlot)),
              const SizedBox(width: 20),
              const Icon(Icons.person, size: 18),
              const SizedBox(width: 6),
              Text(appt.userName),
              const SizedBox(width: 20),
              const Icon(Icons.email_outlined, size: 18),
              const SizedBox(width: 6),
              Text(appt.userEmail),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.medical_services_outlined, size: 18),
              const SizedBox(width: 6),
              Text("${appt.vetName} (${appt.vetSpecialty})",
                  style: const TextStyle(fontStyle: FontStyle.italic)),
              const Spacer(),
              // 👇 RATING DISPLAY
              if (shouldFetchRating)
                FutureBuilder<int?>(
                  future: _getAppointmentRating(appt.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                          width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));
                    }
                    final rating = snapshot.data ?? 0;
                    if (rating > 0) {
                      return Row(
                        children: [
                          const Icon(Icons.star, size: 16, color: Colors.amber),
                          Text(rating.toString()),
                        ],
                      );
                    } else if (snapshot.hasError) {
                      return const Text("Rating Error");
                    }
                    // Show N/A if no rating found
                    return const Text("Rating: N/A");
                  },
                )
              else 
                const Text("Rating: N/A"), // Display N/A for non-completed appointments
            ],
          ),
          if (appt.vetNotes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text("Notes: ${appt.vetNotes}",
                  style: const TextStyle(fontStyle: FontStyle.italic)),
            ),
          // Online Consultation button is removed here
        ] 
      ),
    );
  }


  Widget _buildCalendarSection(List<DateTime> bookedDates) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text("Booked Dates",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(height: 10),
          TableCalendar(
            firstDay: DateTime.utc(2025, 1, 1),
            lastDay: DateTime.utc(2025, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, date, events) {
                if (bookedDates.any((d) => isSameDay(d, date))) {
                  return Positioned(
                    bottom: 1,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }
                return null;
              },
            ),
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
            ),
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                  color: Colors.grey.shade400, shape: BoxShape.circle),
              selectedDecoration: const BoxDecoration(
                  color: Color(0xFF9DBD81), shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}