import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int totalPatients = 0;
  int totalAppointments = 0;
  int totalFeedbacks = 0;
  double averageRating = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchAnalyticsData();
    _listenToRatings(); // ✅ Listen to shared ratings doc
  }

  void _fetchAnalyticsData() {
    // Patients collection
    _firestore.collection('patients').snapshots().listen((snapshot) {
      setState(() {
        totalPatients = snapshot.docs.length;
      });
    });

    // Appointments collection
    _firestore.collection('appointments').snapshots().listen((snapshot) {
      setState(() {
        totalAppointments = snapshot.docs.length;
      });
    });
  }

  // ✅ Real-time listener for the ratings/overall doc
  void _listenToRatings() {
    _firestore.collection('ratings').doc('overall').snapshots().listen((doc) {
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          averageRating = (data['avg'] ?? 0).toDouble();
          totalFeedbacks = (data['count'] ?? 0).toInt();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const headerColor = Color(0xFFBDD9A4);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            color: headerColor,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black87),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                const Text(
                  "Vet Analytics Overview",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
                      _analyticsCard("Feedback", "$totalFeedbacks",
                          Icons.message, Colors.orange),
                      _analyticsCard(
                        "Avg Rating",
                        "${averageRating.toStringAsFixed(1)} ⭐",
                        Icons.star,
                        Colors.amber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Activity Overview",
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 300,
                            child: _AnalyticsChart(
                              patients: totalPatients.toDouble(),
                              appointments: totalAppointments.toDouble(),
                              feedback: totalFeedbacks.toDouble(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade300,
              blurRadius: 5,
              offset: const Offset(0, 3),
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
                  fontSize: 16,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
  final double feedback;

  const _AnalyticsChart({
    required this.patients,
    required this.appointments,
    required this.feedback,
  });

  @override
  Widget build(BuildContext context) {
    final maxY = [patients, appointments, feedback].reduce((a, b) => a > b ? a : b);
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
                    return const Text("Feedback", style: style);
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
              barRods: [BarChartRodData(toY: feedback, color: Colors.orange, width: 24, borderRadius: BorderRadius.circular(4))]),
        ],
      ),
    );
  }
}
