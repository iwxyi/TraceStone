import 'package:flutter/material.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('语义搜索')),
      body: const Padding(
        padding: EdgeInsets.all(20),
        child: TextField(
          decoration: InputDecoration(
            hintText: '例如：去年让我感到被支持的时刻',
            border: OutlineInputBorder(),
          ),
        ),
      ),
    );
  }
}
