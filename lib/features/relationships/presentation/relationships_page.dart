import 'package:flutter/material.dart';

class RelationshipsPage extends StatelessWidget {
  const RelationshipsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关系')),
      body: const Center(child: Text('人物识别、别名管理和关系查询。')),
    );
  }
}
