import 'package:flutter/material.dart';

class MapPickerPage extends StatelessWidget {
  const MapPickerPage({
    super.key,
    required this.weather,
    required this.temperature,
  });

  final String weather;
  final String? temperature;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('地图选点')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('地图选点仅在 Web 端可用。'),
        ),
      ),
    );
  }
}
