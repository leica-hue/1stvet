import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'common_sidebar.dart';
import 'payment_option_screen.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final user = FirebaseAuth.instance.currentUser;

  // Basic analytics
  int totalPatients = 0;
  int totalAppointments = 0;
  int totalRatings = 0;
  double averageVetRating = 0.0;
  
  // Premium status
  bool _isPremium = false;
  bool _isLoadingPremium = true;
  
  // Premium analytics data
  List<Map<String, dynamic>> _monthlyRevenue = [];
  List<Map<String, dynamic>> _weeklyRevenue = [];
  double _patientRetentionRate = 0.0;
  Map<String, int> _peakAppointmentTimes = {};
  Map<String, int> _servicePopularity = {};
  Map<String, dynamic> _periodComparison = {};
  String _revenuePeriod = 'monthly'; // 'monthly' or 'weekly'
  
  @override
  void initState() {
    super.initState();
    _checkPremiumStatus();
    _fetchAnalyticsData();
  }

  Future<void> _checkPremiumStatus() async {
    if (user == null) {
      setState(() {
        _isPremium = false;
        _isLoadingPremium = false;
      });
      return;
    }

    try {
      final vetDoc = await _firestore.collection('vets').doc(user!.uid).get();
      if (vetDoc.exists) {
        final data = vetDoc.data();
        final premiumUntil = data?['premiumUntil'] as Timestamp?;
        final isPremium = data?['isPremium'] as bool? ?? false;
        
        bool hasActivePremium = false;
        if (premiumUntil != null) {
          final premiumDate = premiumUntil.toDate();
          hasActivePremium = premiumDate.isAfter(DateTime.now());
        }
        
        setState(() {
          _isPremium = hasActivePremium || isPremium;
          _isLoadingPremium = false;
        });
        
        if (_isPremium) {
          _fetchPremiumAnalytics();
        }
      } else {
        setState(() {
          _isPremium = false;
          _isLoadingPremium = false;
        });
      }
    } catch (e) {
      debugPrint("Error checking premium status: $e");
      setState(() {
        _isPremium = false;
        _isLoadingPremium = false;
      });
    }
  }

  Future<String?> _getVetName(String userId) async {
    try {
      final vetDoc = await _firestore.collection('vets').doc(userId).get();
      if (vetDoc.exists && vetDoc.data()!.containsKey('name')) {
        return vetDoc.data()!['name'] as String;
      }
    } catch (e) {
      debugPrint("Error fetching vet name: $e");
    }
    return null;
  }

  void _fetchAnalyticsData() async {
    if (user == null) return;

    final userId = user!.uid;
    final currentVetName = await _getVetName(userId);
    if (currentVetName == null) {
      debugPrint("Vet Name not found. Cannot fetch ratings.");
      return;
    }

    _firestore
        .collection('user_appointments')
        .where('vetId', isEqualTo: userId)
        .snapshots()
        .listen((appointmentSnapshot) async {
      final appointmentDocs = appointmentSnapshot.docs;

      int appointmentCount = appointmentDocs.length;
      final patientSet = <String>{};
      for (var doc in appointmentDocs) {
        final data = doc.data();
        if (data.containsKey('userId')) {
          patientSet.add(data['userId']);
        }
      }

      try {
        final feedbackSnapshot = await _firestore
            .collection('feedback')
            .where('vetName', isEqualTo: currentVetName)
            .get();

        double totalRating = 0;
        int ratingCount = 0;

        for (var doc in feedbackSnapshot.docs) {
          final data = doc.data();
          if (data.containsKey('rating') && data['rating'] is num) {
            totalRating += (data['rating'] as num).toDouble();
            ratingCount++;
          }
        }

        setState(() {
          totalAppointments = appointmentCount;
          totalPatients = patientSet.length;
          totalRatings = ratingCount;
          averageVetRating = ratingCount > 0 ? totalRating / ratingCount : 0.0;
        });
      } catch (e) {
        debugPrint("Error fetching feedback data: $e");
        setState(() {
          totalRatings = 0;
          averageVetRating = 0.0;
        });
      }
    });
  }

  Future<void> _fetchPremiumAnalytics() async {
    if (user == null) return;

    try {
      final appointmentsSnapshot = await _firestore
          .collection('user_appointments')
          .where('vetId', isEqualTo: user!.uid)
          .get();

      final appointments = appointmentsSnapshot.docs.map((doc) => doc.data()).toList();
      
      // Calculate revenue trends
      _calculateRevenueTrends(appointments);
      
      // Calculate patient retention
      _calculatePatientRetention(appointments);
      
      // Calculate peak appointment times
      _calculatePeakTimes(appointments);
      
      // Calculate service popularity
      _calculateServicePopularity(appointments);
      
      // Calculate period comparison
      _calculatePeriodComparison(appointments);
      
      setState(() {});
    } catch (e) {
      debugPrint("Error fetching premium analytics: $e");
    }
  }

  void _calculateRevenueTrends(List<Map<String, dynamic>> appointments) {
    final now = DateTime.now();
    final monthlyRevenue = <String, double>{};
    final weeklyRevenue = <String, double>{};

    for (var apt in appointments) {
      final cost = (apt['cost'] as num?)?.toDouble() ?? 0.0;
      if (cost <= 0) continue;

      final timestamp = apt['appointmentDateTime'] as Timestamp?;
      if (timestamp == null) continue;

      final date = timestamp.toDate();
      
      // Monthly revenue
      final monthKey = DateFormat('MMM yyyy').format(date);
      monthlyRevenue[monthKey] = (monthlyRevenue[monthKey] ?? 0.0) + cost;
      
      // Weekly revenue (last 12 weeks)
      final weeksAgo = now.difference(date).inDays ~/ 7;
      if (weeksAgo < 12) {
        final weekKey = 'Week ${12 - weeksAgo}';
        weeklyRevenue[weekKey] = (weeklyRevenue[weekKey] ?? 0.0) + cost;
      }
    }

    _monthlyRevenue = monthlyRevenue.entries
        .map((e) => {'period': e.key, 'revenue': e.value})
        .toList()
      ..sort((a, b) => (a['period'] as String).compareTo(b['period'] as String));

    _weeklyRevenue = weeklyRevenue.entries
        .map((e) => {'period': e.key, 'revenue': e.value})
        .toList()
      ..sort((a, b) => (a['period'] as String).compareTo(b['period'] as String));
  }

  void _calculatePatientRetention(List<Map<String, dynamic>> appointments) {
    final patientAppointments = <String, List<DateTime>>{};
    
    for (var apt in appointments) {
      final userId = apt['userId'] as String?;
      if (userId == null) continue;
      
      final timestamp = apt['appointmentDateTime'] as Timestamp?;
      if (timestamp == null) continue;
      
      final date = timestamp.toDate();
      patientAppointments.putIfAbsent(userId, () => []).add(date);
    }

    int returningPatients = 0;
    for (var appointments in patientAppointments.values) {
      if (appointments.length > 1) {
        returningPatients++;
      }
    }

    final totalUniquePatients = patientAppointments.length;
    _patientRetentionRate = totalUniquePatients > 0
        ? (returningPatients / totalUniquePatients) * 100
        : 0.0;
  }

  void _calculatePeakTimes(List<Map<String, dynamic>> appointments) {
    final timeSlots = <String, int>{};
    
    for (var apt in appointments) {
      final timeSlot = apt['timeSlot'] as String? ?? '';
      if (timeSlot.isNotEmpty) {
        timeSlots[timeSlot] = (timeSlots[timeSlot] ?? 0) + 1;
      }
    }

    _peakAppointmentTimes = Map.fromEntries(
      timeSlots.entries.toList()..sort((a, b) => b.value.compareTo(a.value))
    );
  }

  void _calculateServicePopularity(List<Map<String, dynamic>> appointments) {
    final services = <String, int>{};
    
    for (var apt in appointments) {
      final service = apt['appointmentType'] as String? ?? 'General';
      services[service] = (services[service] ?? 0) + 1;
    }

    _servicePopularity = Map.fromEntries(
      services.entries.toList()..sort((a, b) => b.value.compareTo(a.value))
    );
  }

  void _calculatePeriodComparison(List<Map<String, dynamic>> appointments) {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    final lastMonth = DateTime(now.year, now.month - 1);
    
    double thisMonthRevenue = 0.0;
    double lastMonthRevenue = 0.0;
    int thisMonthAppointments = 0;
    int lastMonthAppointments = 0;

    for (var apt in appointments) {
      final timestamp = apt['appointmentDateTime'] as Timestamp?;
      if (timestamp == null) continue;
      
      final date = timestamp.toDate();
      final cost = (apt['cost'] as num?)?.toDouble() ?? 0.0;
      
      if (date.isAfter(thisMonth.subtract(const Duration(days: 1))) && 
          date.isBefore(thisMonth.add(const Duration(days: 32)))) {
        thisMonthRevenue += cost;
        thisMonthAppointments++;
      } else if (date.isAfter(lastMonth.subtract(const Duration(days: 1))) && 
                 date.isBefore(lastMonth.add(const Duration(days: 32)))) {
        lastMonthRevenue += cost;
        lastMonthAppointments++;
      }
    }

    final revenueChange = lastMonthRevenue > 0
        ? ((thisMonthRevenue - lastMonthRevenue) / lastMonthRevenue) * 100
        : 0.0;
    
    final appointmentChange = lastMonthAppointments > 0
        ? ((thisMonthAppointments - lastMonthAppointments) / lastMonthAppointments) * 100
        : 0.0;

    _periodComparison = {
      'thisMonthRevenue': thisMonthRevenue,
      'lastMonthRevenue': lastMonthRevenue,
      'revenueChange': revenueChange,
      'thisMonthAppointments': thisMonthAppointments,
      'lastMonthAppointments': lastMonthAppointments,
      'appointmentChange': appointmentChange,
    };
  }

  @override
  Widget build(BuildContext context) {
    const headerColor = Color(0xFFBDD9A4);
    const primaryGreen = Color(0xFF728D5A);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CommonSidebar(currentScreen: 'Analytics'),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                  decoration: BoxDecoration(
                    color: headerColor,
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: const Icon(Icons.analytics_outlined, color: primaryGreen, size: 26),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            "Vet Analytics Overview",
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.black),
                          ),
                        ],
                      ),
                      if (_isPremium)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade700,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.workspace_premium, color: Colors.white, size: 16),
                              SizedBox(width: 6),
                              Text(
                                "Premium",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Main Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ListView(
                      children: [
                        // Basic Analytics Cards
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _analyticsCard("Total Patients", "$totalPatients", Icons.pets, Colors.green),
                            _analyticsCard("Appointments", "$totalAppointments", Icons.event, Colors.blue),
                            _analyticsCard("Total Ratings", "$totalRatings", Icons.star, Colors.orange),
                            _analyticsCard("Avg Rating", "${averageVetRating.toStringAsFixed(1)} ⭐", Icons.star, Colors.amber),
                          ],
                        ),
                        const SizedBox(height: 40),
                        // Basic Activity Chart
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Activity Overview",
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  height: 300,
                                  child: _AnalyticsChart(
                                    patients: totalPatients.toDouble(),
                                    appointments: totalAppointments.toDouble(),
                                    ratings: totalRatings.toDouble(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Premium Features Section
                        if (_isPremium) ...[
                          const SizedBox(height: 40),
                          _buildPremiumSection(primaryGreen),
                        ] else if (!_isLoadingPremium) ...[
                          const SizedBox(height: 40),
                          _buildPremiumUpgradeCard(context, primaryGreen),
                        ],
                      ],
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

  Widget _buildPremiumSection(Color primaryGreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.workspace_premium, color: Colors.amber.shade700, size: 28),
            const SizedBox(width: 8),
            const Text(
              "Premium Analytics Dashboard",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 24),
        // Revenue Trends
        _buildRevenueTrendsCard(primaryGreen),
        const SizedBox(height: 24),
        // Patient Retention & Peak Times Row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildPatientRetentionCard(primaryGreen)),
            const SizedBox(width: 16),
            Expanded(child: _buildPeakTimesCard(primaryGreen)),
          ],
        ),
        const SizedBox(height: 24),
        // Service Popularity
        _buildServicePopularityCard(primaryGreen),
        const SizedBox(height: 24),
        // Period Comparison
        _buildPeriodComparisonCard(primaryGreen),
      ],
    );
  }

  Widget _buildRevenueTrendsCard(Color primaryGreen) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Revenue Trends",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                Row(
                  children: [
                    _periodToggleButton('monthly', 'Monthly', primaryGreen),
                    const SizedBox(width: 8),
                    _periodToggleButton('weekly', 'Weekly', primaryGreen),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 300,
              child: _RevenueChart(
                data: _revenuePeriod == 'monthly' ? _monthlyRevenue : _weeklyRevenue,
                period: _revenuePeriod,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodToggleButton(String value, String label, Color primaryGreen) {
    final isSelected = _revenuePeriod == value;
    return GestureDetector(
      onTap: () => setState(() => _revenuePeriod = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryGreen : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildPatientRetentionCard(Color primaryGreen) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Patient Retention Rate",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            Center(
              child: SizedBox(
                width: 150,
                height: 150,
                child: CircularProgressIndicator(
                  value: _patientRetentionRate / 100,
                  strokeWidth: 12,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(primaryGreen),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                "${_patientRetentionRate.toStringAsFixed(1)}%",
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                "Returning Patients",
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeakTimesCard(Color primaryGreen) {
    final topTimes = _peakAppointmentTimes.entries.take(5).toList();
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Peak Appointment Times",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            if (topTimes.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text("No appointment data available"),
                ),
              )
            else
              ...topTimes.asMap().entries.map((entry) {
                final index = entry.key;
                final timeSlot = entry.value.key;
                final count = entry.value.value;
                final maxCount = topTimes.first.value;
                final percentage = maxCount > 0 ? (count / maxCount) * 100 : 0.0;
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            timeSlot,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            "$count appointments",
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percentage / 100,
                          minHeight: 8,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            index == 0 ? primaryGreen : primaryGreen.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildServicePopularityCard(Color primaryGreen) {
    final services = _servicePopularity.entries.toList();
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Service Popularity",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            if (services.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text("No service data available"),
                ),
              )
            else
              SizedBox(
                height: 300,
                child: _ServicePopularityChart(services: services, primaryGreen: primaryGreen),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodComparisonCard(Color primaryGreen) {
    final revenueChange = _periodComparison['revenueChange'] as double? ?? 0.0;
    final appointmentChange = _periodComparison['appointmentChange'] as double? ?? 0.0;
    final thisMonthRevenue = _periodComparison['thisMonthRevenue'] as double? ?? 0.0;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Comparison with Previous Period",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _comparisonCard(
                    "Revenue",
                    "₱${thisMonthRevenue.toStringAsFixed(0)}",
                    "vs Last Month",
                    revenueChange,
                    Icons.attach_money,
                    primaryGreen,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _comparisonCard(
                    "Appointments",
                    "${_periodComparison['thisMonthAppointments'] ?? 0}",
                    "vs Last Month",
                    appointmentChange,
                    Icons.event,
                    Colors.blue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _comparisonCard(String title, String value, String subtitle, double change, IconData icon, Color color) {
    final isPositive = change >= 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                isPositive ? Icons.trending_up : Icons.trending_down,
                color: isPositive ? Colors.green : Colors.red,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                "${isPositive ? '+' : ''}${change.toStringAsFixed(1)}%",
                style: TextStyle(
                  color: isPositive ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumUpgradeCard(BuildContext context, Color primaryGreen) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade300, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              "Upgrade to Premium for Advanced Analytics",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              "Unlock powerful insights including revenue trends, patient retention, peak times, and more!",
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PaymentOptionScreen()),
                );
              },
              icon: const Icon(Icons.workspace_premium),
              label: const Text("Upgrade to Premium"),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _analyticsCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
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
            Icon(icon, color: color, size: 36),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsChart extends StatelessWidget {
  final double patients;
  final double appointments;
  final double ratings;

  const _AnalyticsChart({
    required this.patients,
    required this.appointments,
    required this.ratings,
  });

  @override
  Widget build(BuildContext context) {
    final maxY = [patients, appointments, ratings].reduce((a, b) => a > b ? a : b);
    final safeMaxY = (maxY * 1.2).clamp(10.0, double.infinity);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: safeMaxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: const TextStyle(fontSize: 10, color: Colors.black54),
              ),
              interval: (safeMaxY / 4).floorToDouble().clamp(1.0, double.infinity),
              reservedSize: 30,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                const style = TextStyle(fontSize: 12, fontWeight: FontWeight.bold);
                switch (value.toInt()) {
                  case 0:
                    return const Text("Patients", style: style);
                  case 1:
                    return const Text("Appoint.", style: style);
                  case 2:
                    return const Text("Ratings", style: style);
                  default:
                    return const Text("");
                }
              },
            ),
          ),
        ),
        barGroups: [
          BarChartGroupData(
            x: 0,
            barRods: [BarChartRodData(toY: patients, color: Colors.green, width: 24, borderRadius: BorderRadius.circular(4))],
          ),
          BarChartGroupData(
            x: 1,
            barRods: [BarChartRodData(toY: appointments, color: Colors.blue, width: 24, borderRadius: BorderRadius.circular(4))],
          ),
          BarChartGroupData(
            x: 2,
            barRods: [BarChartRodData(toY: ratings, color: Colors.orange, width: 24, borderRadius: BorderRadius.circular(4))],
          ),
        ],
      ),
    );
  }
}

class _RevenueChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final String period;

  const _RevenueChart({required this.data, required this.period});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text("No revenue data available"));
    }

    final maxRevenue = data.map((e) => (e['revenue'] as num).toDouble()).reduce((a, b) => a > b ? a : b);
    final safeMaxY = (maxRevenue * 1.2).clamp(100.0, double.infinity);

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) => Text(
                '₱${value.toInt()}',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < data.length) {
                  final periodLabel = data[value.toInt()]['period'] as String;
                  return Text(
                    periodLabel.length > 8 ? periodLabel.substring(0, 8) : periodLabel,
                    style: const TextStyle(fontSize: 10),
                  );
                }
                return const Text("");
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true),
        minX: 0,
        maxX: (data.length - 1).toDouble(),
        minY: 0,
        maxY: safeMaxY,
        lineBarsData: [
          LineChartBarData(
            spots: data.asMap().entries.map((entry) {
              return FlSpot(entry.key.toDouble(), (entry.value['revenue'] as num).toDouble());
            }).toList(),
            isCurved: true,
            color: const Color(0xFF728D5A),
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: const Color(0xFF728D5A).withOpacity(0.2)),
          ),
        ],
      ),
    );
  }
}

class _ServicePopularityChart extends StatelessWidget {
  final List<MapEntry<String, int>> services;
  final Color primaryGreen;

  const _ServicePopularityChart({required this.services, required this.primaryGreen});

  @override
  Widget build(BuildContext context) {
    if (services.isEmpty) {
      return const Center(child: Text("No service data available"));
    }

    final maxCount = services.first.value.toDouble();
    final safeMaxY = (maxCount * 1.2).clamp(10.0, double.infinity);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: safeMaxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < services.length) {
                  final serviceName = services[value.toInt()].key;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      serviceName.length > 10 ? '${serviceName.substring(0, 10)}...' : serviceName,
                      style: const TextStyle(fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return const Text("");
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barGroups: services.asMap().entries.map((entry) {
          final index = entry.key;
          final count = entry.value.value.toDouble();
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: count,
                color: primaryGreen.withOpacity(0.8 - (index * 0.1)),
                width: 20,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
