import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  // Dummy data for demonstration — can be replaced with real database data
  int totalPatients = 42;
  int totalAppointments = 128;
  int totalFeedbacks = 19;
  double averageRating = 4.6;

  @override
  Widget build(BuildContext context) {
    const Color headerColor = Color(0xFFBDD9A4);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header bar with back button
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
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Main content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ListView(
                children: [
                  // Summary cards
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
                          Colors.amber),
                    ],
                  ),

                  const SizedBox(height: 40),

                  // Chart Section
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
                          const SizedBox(height: 300, child: _AnalyticsChart()),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Feedback Summary
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Recent Feedback Summary",
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 15),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _feedbackStat("Positive", 12, Colors.green),
                              _feedbackStat("Neutral", 5, Colors.orange),
                              _feedbackStat("Negative", 2, Colors.red),
                            ],
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
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(height: 10),
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(value,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _feedbackStat(String type, int count, Color color) {
    return Column(
      children: [
        Text(
          type,
          style: TextStyle(fontSize: 16, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          "$count",
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

// Chart widget
class _AnalyticsChart extends StatelessWidget {
  const _AnalyticsChart();

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                switch (value.toInt()) {
                  case 0:
                    return const Text("Patients");
                  case 1:
                    return const Text("Appointments");
                  case 2:
                    return const Text("Feedback");
                  default:
                    return const Text("");
                }
              },
            ),
          ),
        ),
        barGroups: [
          BarChartGroupData(x: 0, barRods: [
            BarChartRodData(toY: 42, color: Colors.green)
          ]),
          BarChartGroupData(x: 1, barRods: [
            BarChartRodData(toY: 128, color: Colors.blue)
          ]),
          BarChartGroupData(x: 2, barRods: [
            BarChartRodData(toY: 19, color: Colors.orange)
          ]),
        ],
      ),
    );
  }
}
