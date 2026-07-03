import 'memory_entry.dart';

class MemoryRetrievalResult {
  const MemoryRetrievalResult({
    required this.memory,
    required this.score,
    required this.reasons,
    required this.matchedTokens,
  });

  final MemoryEntry memory;
  final int score;
  final List<String> reasons;
  final List<String> matchedTokens;
}
