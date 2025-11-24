import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  int totalPatients = 0;
  int totalAppointments = 0;
  int totalRatings = 0;
  double averageVetRating = 0.0; // Consistent naming

  // Premium status
  bool _isPremium = false;
  bool _isLoadingPremium = true;

  // Premium analytics data
  String _revenuePeriod = 'monthly'; // 'monthly' or 'weekly'
  Map<String, double> _revenueTrends = {};
  double _patientRetentionRate = 0.0;
  Map<int, int> _peakAppointmentTimes = {}; // hour -> count
  Map<String, int> _servicePopularity = {}; // service -> count
  Map<String, dynamic> _periodComparison = {}; // comparison data

  @override
  void initState() {
    super.initState();
    _checkPremiumStatus();
    _fetchAnalyticsData();
  }

  // Check premium status
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
        final data = vetDoc.data()!;
        final isPremium = data['isPremium'] ?? false;
        final premiumUntil = data['premiumUntil'] as Timestamp?;

        bool isActivePremium = false;
        if (isPremium && premiumUntil != null) {
          final premiumUntilDate = premiumUntil.toDate();
          isActivePremium = premiumUntilDate.isAfter(DateTime.now());
        }

        setState(() {
          _isPremium = isActivePremium;
          _isLoadingPremium = false;
        });

        // Fetch premium analytics if premium is active
        if (isActivePremium) {
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

  // ⚠️ TEMPORARY PLACEHOLDER FOR VET NAME ⚠️
  // You must replace the logic here with a proper way to fetch the vet's name
  // from their user ID (user!.uid) in a collection like 'vets' or 'users'.
  Future<String?> _getVetName(String userId) async {
    // 💡 EXAMPLE: Look up the vet's profile to get their name
    try {
      final vetDoc = await _firestore.collection('vets').doc(userId).get();
      if (vetDoc.exists && vetDoc.data()!.containsKey('name')) {
        return vetDoc.data()!['name'] as String;
      }
    } catch (e) {
      debugPrint("Error fetching vet name: $e");
    }
    // Return null or a default name if not found. Returning a name from your screenshots for now:
    return "Leica Dacao"; // <-- PLACEHOLDER! REPLACE WITH REAL FETCH LOGIC
  }


  void _fetchAnalyticsData() async {
    if (user == null) return;

    final userId = user!.uid;
    // 1. Get the Vet's name first. This is crucial if feedback is filtered by vetName.
    final currentVetName = await _getVetName(userId);
    if (currentVetName == null) {
      debugPrint("Vet Name not found. Cannot fetch ratings.");
      return;
    }


    // 2. We use a Stream for appointments to update in real-time
    _firestore
        .collection('user_appointments')
        .where('vetId', isEqualTo: userId)
        .snapshots()
        .listen((appointmentSnapshot) async {
      final appointmentDocs = appointmentSnapshot.docs;

      // Calculate Appointment and Patient Counts
      int appointmentCount = appointmentDocs.length;
      final patientSet = <String>{};
      for (var doc in appointmentDocs) {
        final data = doc.data();
        if (data.containsKey('userId')) {
          patientSet.add(data['userId']);
        }
      }

      // 3. CORRECTED: Fetch Ratings from 'feedback' collection using 'vetName'
      try {
        final feedbackSnapshot = await _firestore
            .collection('feedback')
            // Querying using 'vetName' as seen in your screenshot
            .where('vetName', isEqualTo: currentVetName) 
            .get();

        double totalRating = 0; 
        int ratingCount = 0;

        for (var doc in feedbackSnapshot.docs) {
          final data = doc.data();
          // The field name is 'rating' as seen in your screenshot
          if (data.containsKey('rating') && data['rating'] is num) {
            totalRating += (data['rating'] as num).toDouble();
            ratingCount++;
          }
        }

        setState(() {
          totalAppointments = appointmentCount;
          totalPatients = patientSet.length;
          // Updated data from 'feedback' collection
          totalRatings = ratingCount;
          averageVetRating = 
              ratingCount > 0 ? totalRating / ratingCount : 0.0;
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

  // Fetch premium analytics data
  Future<void> _fetchPremiumAnalytics() async {
    if (user == null) return;

    try {
      final appointmentsSnapshot = await _firestore
          .collection('user_appointments')
          .where('vetId', isEqualTo: user!.uid)
          .get();

      final appointments = appointmentsSnapshot.docs;
      
      // Calculate revenue trends
      _calculateRevenueTrends(appointments);
      
      // Calculate patient retention rate
      _calculatePatientRetention(appointments);
      
      // Calculate peak appointment times
      _calculatePeakTimes(appointments);
      
      // Calculate service popularity
      _calculateServicePopularity(appointments);
      
      // Calculate period comparison
      _calculatePeriodComparison(appointments);

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint("Error fetching premium analytics: $e");
    }
  }

  void _calculateRevenueTrends(List<QueryDocumentSnapshot> appointments) {
    final revenueMap = <String, double>{};

    for (var doc in appointments) {
      final data = doc.data() as Map<String, dynamic>;
      final cost = (data['cost'] as num?)?.toDouble() ?? 0.0;
      final apptDateTime = (data['appointmentDateTime'] as Timestamp?)?.toDate();
      
      if (apptDateTime == null || cost == 0) continue;

      String key;
      if (_revenuePeriod == 'monthly') {
        key = '${apptDateTime.year}-${apptDateTime.month.toString().padLeft(2, '0')}';
      } else {
        // Weekly: Get week start date (Monday of the week)
        final weekStart = apptDateTime.subtract(Duration(days: apptDateTime.weekday - 1));
        final weekEnd = weekStart.add(const Duration(days: 6));
        // Store as date range string for easy display
        key = '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}_${weekEnd.month.toString().padLeft(2, '0')}-${weekEnd.day.toString().padLeft(2, '0')}';
      }

      revenueMap[key] = (revenueMap[key] ?? 0.0) + cost;
    }

    setState(() {
      _revenueTrends = revenueMap;
    });
  }

  void _calculatePatientRetention(List<QueryDocumentSnapshot> appointments) {
    final now = DateTime.now();
    final lastMonth = now.subtract(const Duration(days: 30));
    final twoMonthsAgo = now.subtract(const Duration(days: 60));

    final lastMonthPatients = <String>{};
    final twoMonthsAgoPatients = <String>{};

    for (var doc in appointments) {
      final data = doc.data() as Map<String, dynamic>;
      final userId = data['userId'] as String?;
      final apptDateTime = (data['appointmentDateTime'] as Timestamp?)?.toDate();
      
      if (userId == null || apptDateTime == null) continue;

      if (apptDateTime.isAfter(twoMonthsAgo) && apptDateTime.isBefore(lastMonth)) {
        twoMonthsAgoPatients.add(userId);
      } else if (apptDateTime.isAfter(lastMonth)) {
        lastMonthPatients.add(userId);
      }
    }

    final returningPatients = lastMonthPatients.intersection(twoMonthsAgoPatients).length;
    final retentionRate = twoMonthsAgoPatients.isEmpty 
        ? 0.0 
        : (returningPatients / twoMonthsAgoPatients.length) * 100;

    setState(() {
      _patientRetentionRate = retentionRate;
    });
  }

  void _calculatePeakTimes(List<QueryDocumentSnapshot> appointments) {
    final peakTimes = <int, int>{};

    for (var doc in appointments) {
      final data = doc.data() as Map<String, dynamic>;
      final apptDateTime = (data['appointmentDateTime'] as Timestamp?)?.toDate();
      
      if (apptDateTime == null) continue;

      final hour = apptDateTime.hour;
      peakTimes[hour] = (peakTimes[hour] ?? 0) + 1;
    }

    setState(() {
      _peakAppointmentTimes = peakTimes;
    });
  }

  void _calculateServicePopularity(List<QueryDocumentSnapshot> appointments) {
    final serviceMap = <String, int>{};

    for (var doc in appointments) {
      final data = doc.data() as Map<String, dynamic>;
      final reason = data['reason'] as String? ?? data['appointmentType'] as String? ?? 'General';
      serviceMap[reason] = (serviceMap[reason] ?? 0) + 1;
    }

    setState(() {
      _servicePopularity = serviceMap;
    });
  }

  void _calculatePeriodComparison(List<QueryDocumentSnapshot> appointments) {
    final now = DateTime.now();
    final currentPeriodStart = _revenuePeriod == 'monthly'
        ? DateTime(now.year, now.month, 1)
        : now.subtract(Duration(days: now.weekday - 1));
    
    final previousPeriodStart = _revenuePeriod == 'monthly'
        ? DateTime(now.year, now.month - 1, 1)
        : currentPeriodStart.subtract(const Duration(days: 7));
    
    final previousPeriodEnd = _revenuePeriod == 'monthly'
        ? DateTime(now.year, now.month, 1).subtract(const Duration(days: 1))
        : currentPeriodStart.subtract(const Duration(days: 1));

    int currentAppointments = 0;
    double currentRevenue = 0.0;
    int previousAppointments = 0;
    double previousRevenue = 0.0;

    for (var doc in appointments) {
      final data = doc.data() as Map<String, dynamic>;
      final apptDateTime = (data['appointmentDateTime'] as Timestamp?)?.toDate();
      final cost = (data['cost'] as num?)?.toDouble() ?? 0.0;
      
      if (apptDateTime == null) continue;

      if (apptDateTime.isAfter(currentPeriodStart)) {
        currentAppointments++;
        currentRevenue += cost;
      } else if (apptDateTime.isAfter(previousPeriodStart) && apptDateTime.isBefore(previousPeriodEnd.add(const Duration(days: 1)))) {
        previousAppointments++;
        previousRevenue += cost;
      }
    }

    final appointmentChange = previousAppointments == 0 
        ? 0.0 
        : ((currentAppointments - previousAppointments) / previousAppointments) * 100;
    
    final revenueChange = previousRevenue == 0 
        ? 0.0 
        : ((currentRevenue - previousRevenue) / previousRevenue) * 100;

    setState(() {
      _periodComparison = {
        'currentAppointments': currentAppointments,
        'previousAppointments': previousAppointments,
        'currentRevenue': currentRevenue,
        'previousRevenue': previousRevenue,
        'appointmentChange': appointmentChange,
        'revenueChange': revenueChange,
      };
    });
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
          // Sidebar
          const CommonSidebar(currentScreen: 'Analytics'),
          
          // Main content
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
                ),

                // Main Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ListView(
                      children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _analyticsCard("Total Patients", "$totalPatients",
                              Icons.pets, Colors.green),
                          _analyticsCard("Appointments", "$totalAppointments",
                              Icons.event, Colors.blue),
                          _analyticsCard("Total Ratings", "$totalRatings",
                              Icons.star, Colors.orange),
                          _analyticsCard(
                            "Avg Rating",
                            "${averageVetRating.toStringAsFixed(1)} ⭐", 
                            Icons.star,
                            Colors.amber,
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
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
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w800),
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
                      
                      // Upgrade to Premium Section (for non-premium vets)
                      if (!_isPremium && !_isLoadingPremium) ...[
                        const SizedBox(height: 40),
                        _buildUpgradeToPremiumCard(),
                      ],
                      
                      // Premium Features Section
                      if (_isPremium && !_isLoadingPremium) ...[
                        const SizedBox(height: 40),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [primaryGreen.withOpacity(0.1), Colors.white],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: primaryGreen.withOpacity(0.3), width: 2),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.workspace_premium, color: primaryGreen, size: 28),
                              const SizedBox(width: 12),
                              const Text(
                                "Premium Analytics Dashboard",
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 30),
                        
                        // Revenue Trends
                        _buildRevenueTrendsCard(),
                        
                        const SizedBox(height: 24),
                        
                        // Patient Retention & Period Comparison Row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildPatientRetentionCard()),
                            const SizedBox(width: 16),
                            Expanded(child: _buildPeriodComparisonCard()),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Peak Times & Service Popularity Row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildPeakTimesCard()),
                            const SizedBox(width: 16),
                            Expanded(child: _buildServicePopularityCard()),
                          ],
                        ),
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

  Widget _analyticsCard(
      String title, String value, IconData icon, Color color) {
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
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  // Upgrade to Premium Card
  Widget _buildUpgradeToPremiumCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF728D5A).withOpacity(0.15), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF728D5A).withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF728D5A).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.workspace_premium,
                    color: Color(0xFF728D5A),
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Unlock Premium Analytics",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Get advanced insights and detailed analytics",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Premium Features:",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureItem("Advanced analytics dashboard"),
                  _buildFeatureItem("Revenue trends (monthly/weekly)"),
                  _buildFeatureItem("Patient retention rate"),
                  _buildFeatureItem("Peak appointment times"),
                  _buildFeatureItem("Service popularity charts"),
                  _buildFeatureItem("Comparison with previous periods"),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PaymentOptionScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF728D5A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.workspace_premium, size: 24),
                    SizedBox(width: 8),
                    Text(
                      "Upgrade to Premium",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String feature) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            color: const Color(0xFF728D5A),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              feature,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Premium Feature Widgets
  Widget _buildRevenueTrendsCard() {
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
                    _buildPeriodToggle('monthly', 'Monthly'),
                    const SizedBox(width: 8),
                    _buildPeriodToggle('weekly', 'Weekly'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 250,
              child: _revenueTrends.isEmpty
                  ? const Center(child: Text("No revenue data available"))
                  : _RevenueTrendsChart(
                      revenueData: _revenueTrends,
                      period: _revenuePeriod,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodToggle(String period, String label) {
    final isSelected = _revenuePeriod == period;
    return GestureDetector(
      onTap: () {
        setState(() {
          _revenuePeriod = period;
        });
        _fetchPremiumAnalytics();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF728D5A) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildPatientRetentionCard() {
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
              children: [
                const Icon(Icons.people_outline, color: Color(0xFF728D5A), size: 24),
                const SizedBox(width: 8),
                const Text(
                  "Patient Retention Rate",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  Text(
                    "${_patientRetentionRate.toStringAsFixed(1)}%",
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF728D5A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Returning Patients",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _patientRetentionRate / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                _patientRetentionRate >= 50
                    ? Colors.green
                    : _patientRetentionRate >= 30
                        ? Colors.orange
                        : Colors.red,
              ),
              minHeight: 8,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodComparisonCard() {
    final currentAppts = _periodComparison['currentAppointments'] ?? 0;
    final previousAppts = _periodComparison['previousAppointments'] ?? 0;
    final currentRev = (_periodComparison['currentRevenue'] ?? 0.0).toDouble();
    final previousRev = (_periodComparison['previousRevenue'] ?? 0.0).toDouble();
    final apptChange = (_periodComparison['appointmentChange'] ?? 0.0).toDouble();
    final revChange = (_periodComparison['revenueChange'] ?? 0.0).toDouble();

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
              children: [
                const Icon(Icons.compare_arrows, color: Color(0xFF728D5A), size: 24),
                const SizedBox(width: 8),
                const Text(
                  "Period Comparison",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildComparisonRow(
              "Appointments",
              currentAppts.toString(),
              previousAppts.toString(),
              apptChange,
            ),
            const SizedBox(height: 16),
            _buildComparisonRow(
              "Revenue",
              "₱${currentRev.toStringAsFixed(0)}",
              "₱${previousRev.toStringAsFixed(0)}",
              revChange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonRow(String label, String current, String previous, double change) {
    final isPositive = change >= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Current: $current",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Text(
                  "Previous: $previous",
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isPositive ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 16,
                    color: isPositive ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "${change.abs().toStringAsFixed(1)}%",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPeakTimesCard() {
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
              children: [
                const Icon(Icons.access_time, color: Color(0xFF728D5A), size: 24),
                const SizedBox(width: 8),
                const Text(
                  "Peak Appointment Times",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: _peakAppointmentTimes.isEmpty
                  ? const Center(child: Text("No appointment time data"))
                  : _PeakTimesChart(peakTimes: _peakAppointmentTimes),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServicePopularityCard() {
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
              children: [
                const Icon(Icons.pie_chart, color: Color(0xFF728D5A), size: 24),
                const SizedBox(width: 8),
                const Text(
                  "Service Popularity",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: _servicePopularity.isEmpty
                  ? const Center(child: Text("No service data available"))
                  : _ServicePopularityChart(serviceData: _servicePopularity),
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
              barRods: [BarChartRodData(toY: patients, color: Colors.green, width: 24, borderRadius: BorderRadius.circular(4))]),
          BarChartGroupData(
              x: 1,
              barRods: [BarChartRodData(toY: appointments, color: Colors.blue, width: 24, borderRadius: BorderRadius.circular(4))]),
          BarChartGroupData(
              x: 2,
              barRods: [BarChartRodData(toY: ratings, color: Colors.orange, width: 24, borderRadius: BorderRadius.circular(4))]),
        ],
      ),
    );
  }
}

// Premium Chart Widgets
class _RevenueTrendsChart extends StatelessWidget {
  final Map<String, double> revenueData;
  final String period;

  const _RevenueTrendsChart({
    required this.revenueData,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    if (revenueData.isEmpty) {
      return const Center(child: Text("No revenue data"));
    }

    final sortedKeys = revenueData.keys.toList()..sort();
    final maxRevenue = revenueData.values.reduce((a, b) => a > b ? a : b);
    final safeMaxY = (maxRevenue * 1.2).clamp(100.0, double.infinity);

    final barGroups = sortedKeys.asMap().entries.map((entry) {
      final index = entry.key;
      final key = entry.value;
      final value = revenueData[key]!;
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: value,
            color: const Color(0xFF728D5A),
            width: 20,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    }).toList();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: safeMaxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: safeMaxY / 5,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.shade300,
              strokeWidth: 1,
            );
          },
        ),
        borderData: FlBorderData(show: true),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => Text(
                "₱${value.toInt()}",
                style: const TextStyle(fontSize: 10, color: Colors.black54),
              ),
              reservedSize: 50,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= sortedKeys.length) return const Text("");
                final key = sortedKeys[value.toInt()];
                
                if (period == 'monthly') {
                  // Display month name (e.g., "Nov")
                  final monthNum = int.tryParse(key.split('-')[1]) ?? 1;
                  final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                  return Text(
                    monthNames[monthNum - 1],
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                  );
                } else {
                  // Display date range (e.g., "Nov 4-10")
                  final parts = key.split('_');
                  if (parts.length == 2) {
                    final startPart = parts[0].split('-');
                    final endPart = parts[1].split('-');
                    if (startPart.length == 3 && endPart.length == 2) {
                      final startMonth = int.tryParse(startPart[1]) ?? 1;
                      final startDay = int.tryParse(startPart[2]) ?? 1;
                      final endMonth = int.tryParse(endPart[0]) ?? 1;
                      final endDay = int.tryParse(endPart[1]) ?? 1;
                      
                      final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                                         'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                      
                      String label;
                      if (startMonth == endMonth) {
                        // Same month: "Nov 4-10"
                        label = '${monthNames[startMonth - 1]} $startDay-$endDay';
                      } else {
                        // Different months: "Nov 30-Dec 6"
                        label = '${monthNames[startMonth - 1]} $startDay-${monthNames[endMonth - 1]} $endDay';
                      }
                      
                      return Text(
                        label,
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      );
                    }
                  }
                  // Fallback to week number if parsing fails
                  return Text(
                    key,
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
                  );
                }
              },
            ),
          ),
        ),
        barGroups: barGroups,
      ),
    );
  }
}

class _PeakTimesChart extends StatelessWidget {
  final Map<int, int> peakTimes;

  const _PeakTimesChart({required this.peakTimes});

  @override
  Widget build(BuildContext context) {
    if (peakTimes.isEmpty) {
      return const Center(child: Text("No data"));
    }

    final sortedHours = peakTimes.keys.toList()..sort();
    final maxCount = peakTimes.values.reduce((a, b) => a > b ? a : b);
    final safeMaxY = (maxCount * 1.2).clamp(10.0, double.infinity);

    final barGroups = sortedHours.map((hour) {
      final count = peakTimes[hour]!;
      return BarChartGroupData(
        x: hour,
        barRods: [
          BarChartRodData(
            toY: count.toDouble(),
            color: hour >= 9 && hour <= 17 
                ? const Color(0xFF728D5A) 
                : Colors.orange.shade300,
            width: 16,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    }).toList();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: safeMaxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: safeMaxY / 4,
          getDrawingHorizontalLine: (value) {
            return FlLine(color: Colors.grey.shade300, strokeWidth: 1);
          },
        ),
        borderData: FlBorderData(show: true),
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
              reservedSize: 30,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                final hour = value.toInt();
                if (hour < 0 || hour > 23) return const Text("");
                return Text(
                  "$hour:00",
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
                );
              },
            ),
          ),
        ),
        barGroups: barGroups,
      ),
    );
  }
}

class _ServicePopularityChart extends StatelessWidget {
  final Map<String, int> serviceData;

  const _ServicePopularityChart({required this.serviceData});

  @override
  Widget build(BuildContext context) {
    if (serviceData.isEmpty) {
      return const Center(child: Text("No data"));
    }

    final sortedServices = serviceData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    final topServices = sortedServices.take(5).toList();
    final total = serviceData.values.reduce((a, b) => a + b);

    final pieChartSections = topServices.asMap().entries.map((entry) {
      final index = entry.key;
      final service = entry.value;
      final percentage = (service.value / total) * 100;
      
      final colors = [
        const Color(0xFF728D5A),
        Colors.blue.shade400,
        Colors.orange.shade400,
        Colors.purple.shade400,
        Colors.teal.shade400,
      ];

      return PieChartSectionData(
        value: service.value.toDouble(),
        title: "${percentage.toStringAsFixed(1)}%",
        color: colors[index % colors.length],
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: PieChart(
            PieChartData(
              sections: pieChartSections,
              centerSpaceRadius: 30,
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: topServices.asMap().entries.map((entry) {
              final index = entry.key;
              final service = entry.value;
              final colors = [
                const Color(0xFF728D5A),
                Colors.blue.shade400,
                Colors.orange.shade400,
                Colors.purple.shade400,
                Colors.teal.shade400,
              ];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colors[index % colors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        service.key.length > 15 
                            ? "${service.key.substring(0, 15)}..."
                            : service.key,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}