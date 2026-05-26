import 'package:flutter/material.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EasyRent'),
      ),
      body: const Center(
        child: Text('🚧 Dashboard à implémenter'),
      ),
    );
  }
}
