import 'package:flutter/material.dart';

import '../../../data/models/ai_context_package.dart';
import '../../../data/models/memory_retrieval_result.dart';
import '../../../data/services/ai_context_builder.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _contextBuilder = const AiContextBuilder();
  Future<AiContextPackage?>? _searchFuture;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search() {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searchFuture = _contextBuilder.buildForSearch(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('语义搜索')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SearchBar(
            controller: _controller,
            hintText: '例如：去年让我感到被支持的时刻',
            leading: const Icon(Icons.search),
            trailing: [
              IconButton(
                tooltip: '搜索',
                onPressed: _search,
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 16),
          FutureBuilder<AiContextPackage?>(
            future: _searchFuture,
            builder: (context, snapshot) {
              if (_searchFuture == null) return const _SearchHint();
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              final package = snapshot.data;
              final results = package?.relatedMemories ?? const [];
              if (results.isEmpty) return const _EmptyResult();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(package!.debugSummary,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  for (final result in results) ...[
                    _SearchResultCard(result: result),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(Icons.manage_search_outlined, size: 44),
          SizedBox(height: 14),
          Text('可以搜索情绪、关系、事件、地点或一段自然语言。'),
        ],
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(Icons.search_off_outlined, size: 44),
          SizedBox(height: 14),
          Text('暂时没有找到相关记忆。'),
        ],
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({required this.result});

  final MemoryRetrievalResult result;

  @override
  Widget build(BuildContext context) {
    final memory = result.memory;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(memory.title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                ),
                Text('score ${result.score}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(memory.summary),
            if (memory.emotion.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(memory.emotion,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (result.reasons.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reason in result.reasons)
                    Chip(label: Text(reason)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
