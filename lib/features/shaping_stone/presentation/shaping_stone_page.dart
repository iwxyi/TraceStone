import 'package:flutter/material.dart';

class ShapingStonePage extends StatelessWidget {
  const ShapingStonePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('塑石')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          Text('主动雕刻自己',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
          SizedBox(height: 12),
          Text('AI 建议会在这里转化为可编辑、可提醒、可打卡的微小行动。'),
        ],
      ),
    );
  }
}
