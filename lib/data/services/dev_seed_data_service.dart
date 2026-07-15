import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/diary_analysis_status.dart';
import '../models/diary_entry.dart';
import '../repositories/ai_analysis_queue_repository.dart';
import '../repositories/diary_repository.dart';
import '../repositories/insight_repository.dart';

class DevSeedDataService {
  DevSeedDataService({
    DiaryRepository? diaryRepository,
    AiAnalysisQueueRepository? queueRepository,
    InsightRepository? insightRepository,
    AssetBundle? assetBundle,
  })  : _diaryRepository = diaryRepository ?? const DiaryRepository(),
        _queueRepository = queueRepository ?? const AiAnalysisQueueRepository(),
        _insightRepository = insightRepository ?? const InsightRepository(),
        _assetBundle = assetBundle ?? rootBundle;

  static const defaultAssetPath = 'assets/dev/diary_seed_dataset.json';

  final DiaryRepository _diaryRepository;
  final AiAnalysisQueueRepository _queueRepository;
  final InsightRepository _insightRepository;
  final AssetBundle _assetBundle;

  Future<DevSeedImportResult> importDiaryDataset({
    String assetPath = defaultAssetPath,
    bool enqueueAi = true,
  }) async {
    final raw = await _loadDataset(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('测试数据格式错误：根节点必须是对象');
    }
    final entriesJson = decoded['entries'];
    if (entriesJson is! List) {
      throw const FormatException('测试数据格式错误：entries 必须是数组');
    }
    final importedIds = <String>[];
    var created = 0;
    var updated = 0;
    var enqueued = 0;
    final batchStartedAt = DateTime.now();
    final batchId = 'dev-seed:${batchStartedAt.microsecondsSinceEpoch}';
    final batchLabel = '开发者测试日记 ${_dateLabel(batchStartedAt)}';

    final entries = <DiaryEntry>[];
    for (final item in entriesJson) {
      if (item is! Map) continue;
      final json = {
        for (final entry in item.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      final entry = DiaryEntry.fromJson(json);
      if (entry.id.trim().isEmpty || entry.content.trim().isEmpty) continue;
      entries.add(entry);
    }
    entries.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      return a.createdAt.compareTo(b.createdAt);
    });

    for (final entry in entries) {
      final existing = await _diaryRepository.getEntryById(entry.id);
      await _diaryRepository.saveEntry(entry);
      importedIds.add(entry.id);
      if (existing == null) {
        created += 1;
      } else {
        updated += 1;
      }
      if (enqueueAi) {
        await _queueRepository.enqueueEntry(
          entry,
          batchId: batchId,
          batchLabel: batchLabel,
        );
        await _insightRepository.saveStatus(DiaryAnalysisStatus(
          entryId: entry.id,
          state: DiaryAnalysisState.queued,
          updatedAt: DateTime.now(),
          message: '开发者测试数据已导入，等待整理 AI 资料',
        ));
        enqueued += 1;
      }
    }
    return DevSeedImportResult(
      importedIds: importedIds,
      createdCount: created,
      updatedCount: updated,
      enqueuedCount: enqueued,
    );
  }

  Future<String> _loadDataset(String assetPath) async {
    try {
      final raw = await _assetBundle.loadString(assetPath);
      if (raw.trim().isEmpty) {
        throw StateError('资源为空：$assetPath');
      }
      return raw;
    } on Object {
      if (assetPath != defaultAssetPath) {
        rethrow;
      }
      return _builtInDatasetJson();
    }
  }

  String _builtInDatasetJson() {
    final entries = <Map<String, Object?>>[];
    final templates = [
      (
        date: DateTime(2024, 2, 10),
        title: '春节回家',
        content: '春节回家吃年夜饭，和爸妈聊到今年想把工作节奏放稳。晚上看烟花时觉得自己比去年更能接受慢一点。',
        location: '杭州',
        weather: '多云',
        temperature: '8',
      ),
      (
        date: DateTime(2024, 4, 3),
        title: '第一次见小红',
        content: '下午在西湖边第一次见小红。她提到喜欢摄影和爵士乐，我们聊到天黑。回去路上有点心动，但也提醒自己不要太快下判断。',
        location: '杭州',
        weather: '晴',
        temperature: '19',
      ),
      (
        date: DateTime(2024, 5, 5),
        title: '端午前的粽子',
        content: '妈妈提前包了粽子，说今年端午家里可能聚不齐。我想到每年端午其实都有不同的变化，节日像一个锚点。',
        location: '杭州',
        weather: '小雨',
        temperature: '22',
      ),
      (
        date: DateTime(2024, 6, 18),
        title: '领导一对一',
        content: '和领导陈总一对一，他建议我不要只做执行，要提前暴露风险。我当时有点防御，但后来觉得这是升职前必须补的能力。',
        location: '上海',
        weather: '阴',
        temperature: '27',
      ),
      (
        date: DateTime(2024, 8, 22),
        title: '新加坡出差',
        content:
            '飞到新加坡参加客户 workshop，住在 Tanjong Pagar 附近。晚上一个人走到滨海湾，觉得独处的时候判断更清楚。',
        location: '新加坡',
        weather: '阵雨',
        temperature: '30',
      ),
      (
        date: DateTime(2024, 11, 9),
        title: '健身恢复',
        content: '恢复力量训练，深蹲重量不大，但动作稳定。晚饭吃了鸡胸和米饭，睡前焦虑明显少一点。',
        location: '杭州',
        weather: '晴',
        temperature: '16',
      ),
      (
        date: DateTime(2025, 1, 15),
        title: '绩效反馈',
        content: '绩效反馈是 B+。陈总说我的判断力提升了，但向上同步还不够主动。晚上复盘时列了三条改进：提前同步、写风险、明确需求边界。',
        location: '上海',
        weather: '阴',
        temperature: '7',
      ),
      (
        date: DateTime(2025, 3, 2),
        title: '杭州梅花',
        content: '孤山的梅花开得正好，比去年记忆里早一点。拍了几张照片发给小红，她回了一个很开心的表情。',
        location: '杭州',
        weather: '晴',
        temperature: '13',
      ),
      (
        date: DateTime(2025, 3, 28),
        title: '小红的边界',
        content: '和小红吃饭，她说最近工作压力大，不太想频繁见面。我有点失落，但也意识到关系不能只靠我的节奏推进。',
        location: '杭州',
        weather: '小雨',
        temperature: '17',
      ),
      (
        date: DateTime(2025, 5, 31),
        title: '端午节',
        content: '端午节和外婆视频，她问我有没有吃粽子。想到去年端午妈妈说家里聚不齐，今年虽然还是没聚齐，但我主动打了电话。',
        location: '上海',
        weather: '多云',
        temperature: '25',
      ),
      (
        date: DateTime(2025, 7, 12),
        title: '对象周期记录',
        content: '小林说今天身体不舒服，应该是周期第一天。我买了热饮和止痛药。她说不用太紧张，但我想把这个规律记住，别每次都临时反应。',
        location: '杭州',
        weather: '晴',
        temperature: '33',
      ),
      (
        date: DateTime(2025, 9, 4),
        title: '向上管理',
        content: '项目会上陈总临时改方向，我没有当场争论，会后发了风险清单和两个备选方案。他回复说这样沟通更有效。',
        location: '上海',
        weather: '阴',
        temperature: '28',
      ),
      (
        date: DateTime(2025, 12, 20),
        title: '年终总结',
        content: '今年最大的变化是开始记录证据，而不是只记录情绪。和小红渐渐变淡，但我没有像以前那样反复追问答案。',
        location: '杭州',
        weather: '晴',
        temperature: '6',
      ),
      (
        date: DateTime(2026, 1, 6),
        title: '升职准备',
        content: '开始准备晋升材料。最难写的是影响力部分，因为很多事我做了但没有沉淀结果。以后每周要记录关键决策和影响。',
        location: '上海',
        weather: '阴',
        temperature: '5',
      ),
      (
        date: DateTime(2026, 2, 24),
        title: '梅花又开',
        content:
            '杭州植物园梅花已经开了一部分，和去年孤山那次不一样，今年更早，也更冷。想到可以问自己：哪些变化是季节，哪些是我自己的状态。',
        location: '杭州',
        weather: '晴',
        temperature: '10',
      ),
      (
        date: DateTime(2026, 4, 18),
        title: '复杂的一天',
        content:
            '早上健身，硬拉状态一般。\n---\n中午和陈总讨论预算，他担心投入产出。\n---\n晚上小林说周期推迟了两天，我们都有点紧张，约定先观察。',
        location: '上海',
        weather: '小雨',
        temperature: '20',
      ),
      (
        date: DateTime(2026, 6, 19),
        title: '新加坡复盘',
        content: '客户又提到去年新加坡 workshop 的方案，说那次梳理很清楚。我才意识到那段出差其实是我开始独立负责客户沟通的节点。',
        location: '上海',
        weather: '多云',
        temperature: '29',
      ),
      (
        date: DateTime(2026, 7, 3),
        title: 'AI 测试日',
        content: '今天专门测试洞察、搜索、总结和记忆。想问的问题包括第一次见小红是什么时候、去年梅花何时开、怎么向上管理陈总。',
        location: '杭州',
        weather: '晴',
        temperature: '31',
      ),
    ];

    final followUps = [
      (
        days: 38,
        title: '春节后的节奏',
        content: '春节后回到上海，发现自己没有以前那么急着证明什么。给爸妈打电话时也更能耐心听他们讲琐事。',
      ),
      (
        days: 45,
        title: '和小红第二次见面',
        content: '又和小红见了一次，她带我去一家很小的咖啡店。相比第一次的兴奋，这次更多是在观察彼此真实的节奏。',
      ),
      (
        days: 32,
        title: '端午计划调整',
        content: '端午当天还是没能全家聚齐，但我提前订了粽子寄回去。节日不一定要完美，重要的是我没有完全缺席。',
      ),
      (
        days: 41,
        title: '同步风险清单',
        content: '按陈总的建议，把项目风险提前写成一页纸发出去。会议上争论少了很多，因为大家先看到了同一份证据。',
      ),
      (
        days: 25,
        title: '新加坡客户晚餐',
        content: '新加坡第二天和客户吃饭，对方真正关心的不是功能列表，而是上线后谁负责推动。我意识到客户沟通也需要向上管理。',
      ),
      (
        days: 29,
        title: '健身后的睡眠',
        content: '连续训练三周后，睡眠明显更沉。重量没有涨很多，但焦虑下降比体型变化更先出现。',
      ),
      (
        days: 36,
        title: '绩效改进计划',
        content: '把 B+ 的反馈拆成四周行动：每周同步一次判断，每次会前写目标，会后补结论。这样比单纯说我要努力更可执行。',
      ),
      (
        days: 26,
        title: '梅花花期对比',
        content: '翻到去年梅花照片，发现今年开的时间差不多，但我注意到的东西变了：去年看人，今年更多看自己的状态。',
      ),
      (
        days: 34,
        title: '小红渐渐疏远',
        content: '小红回复变慢，我没有继续追问。以前我会急着要答案，这次先把注意力放回自己的生活。',
      ),
      (
        days: 37,
        title: '端午后的电话',
        content: '外婆后来又打电话问工作忙不忙。我没有敷衍，认真讲了最近的项目，她听不太懂，但一直说注意身体。',
      ),
      (
        days: 31,
        title: '小林周期复盘',
        content: '小林这次周期大概 31 天。她提醒我记录可以，但不要把她当成一个需要管理的项目。我觉得这句话很重要。',
      ),
      (
        days: 43,
        title: '向上管理有效的一次',
        content: '这周再次遇到方向变化，我先问目标和边界，再给方案。陈总说这次沟通比以前成熟很多。',
      ),
      (
        days: 30,
        title: '年终材料初稿',
        content: '整理年终材料时发现，真正能支撑成长的不是情绪总结，而是一个个具体决策、证据和后续影响。',
      ),
      (
        days: 44,
        title: '晋升答辩模拟',
        content: '做了一次晋升答辩模拟，卡在“你带动了谁”这个问题上。接下来要把协作影响写得更具体。',
      ),
      (
        days: 35,
        title: '梅花落了',
        content: '再去植物园时梅花已经落了不少。花期很短，但记录下来以后，明年就能比较得更准确。',
      ),
      (
        days: 28,
        title: '复杂日子的拆分',
        content: '回看那天的记录，健身、预算、小林周期其实是三件事。以后写日记时可以用分割线分开，AI 分析也应该分别理解。',
      ),
      (
        days: 39,
        title: '客户沟通节点',
        content: '复盘新加坡项目后，我把客户沟通方法写成模板：背景、判断、风险、下一步。它开始能复用到别的项目。',
      ),
      (
        days: 21,
        title: 'AI 测试问题清单',
        content: '继续测试 AI：它应该能从小红、梅花、陈总、新加坡这些线索里多步检索，而不是只搜一个关键词。',
      ),
    ];

    for (var index = 0; index < templates.length * 2; index++) {
      final templateIndex = index % templates.length;
      final template = templates[templateIndex];
      final isFollowUp = index >= templates.length;
      final followUp = followUps[templateIndex];
      final date = isFollowUp
          ? template.date.add(Duration(days: followUp.days))
          : template.date;
      final id = 'dev-seed-fallback-${index.toString().padLeft(2, '0')}';
      entries.add({
        'id': id,
        'date': date.toIso8601String(),
        'createdAt': date.toIso8601String(),
        'updatedAt': date.toIso8601String(),
        'content': isFollowUp
            ? '# ${followUp.title}\n\n${followUp.content}'
            : '# ${template.title}\n\n${template.content}',
        'location': template.location,
        'weather': template.weather,
        'temperature': template.temperature,
      });
    }
    return jsonEncode({'entries': entries});
  }

  String _dateLabel(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }
}

class DevSeedImportResult {
  const DevSeedImportResult({
    required this.importedIds,
    required this.createdCount,
    required this.updatedCount,
    required this.enqueuedCount,
  });

  final List<String> importedIds;
  final int createdCount;
  final int updatedCount;
  final int enqueuedCount;

  int get totalCount => importedIds.length;

  String get summary =>
      'total=$totalCount created=$createdCount updated=$updatedCount '
      'queued=$enqueuedCount';
}
