# TraceStone AI MVP 收束计划

本文档用于收束 AI 模块的近期开发行为。除非另有明确决定，AI 模块先按这里的流程和边界推进，不继续从 `AI_DESIGN.md` 中发散实现长期增强项。

## 目标

半天到一天内，把 AI 模块收束为一个稳定可用的 MVP 闭环：

1. 用户写完日记并明确退出保存后，后台开始整理。
2. 系统生成摘要、分段、基础向量、历史上下文和今日洞察。
3. 今日洞察以当前日记为主，引用历史时必须来自已检索到的来源。
4. 用户标记“不准确”后，系统带着上一版洞察快照、反馈和旧来源重新生成。
5. 过程可恢复、可重试、可调试，不阻塞日记保存。

## 当前阶段只做什么

### P0 必须完成

| 项目 | 要求 | 验收 |
| --- | --- | --- |
| 今日分析刷新 | 预览页点击重新分析必须立即有状态反馈 | 不继续显示旧分析；完成后显示新结果 |
| 队列稳定性 | `pending/running/incomplete/failed/completed` 状态可恢复 | App 重启或中断后可以继续未完成任务 |
| 旧结果处理 | 手动重跑时清理旧 insight 和旧 retrieval trace | 重跑期间不误导用户看到旧洞察 |
| 今日洞察生成 | 输出读后感、情绪、关键词、塑石建议、结构化 claims | 内容以今日日记为主，历史只作辅助 |
| 反馈重生成 | “不准确”反馈保存上一版洞察快照和来源摘要 | 新 prompt 能看到反馈、旧洞察、旧来源 |
| 开发者验证 | 开发者模式能看到 prompt、retrieval、feedback、queue、claims evidence | 能解释“AI 为什么这么说”和“为什么重跑变了” |
| 回归测试 | 关键 AI 服务测试和静态分析通过 | `flutter analyze` 和指定测试通过 |

### P1 可以顺手修，但不能拖慢收束

| 项目 | 边界 |
| --- | --- |
| 状态文案 | 只优化“正在分析/等待继续/失败可重试/已完成” |
| 队列进度卡片 | 只展示已有队列数据，不重做交互 |
| 调试信息 | 只补阻碍验证的问题，不新增大审计页 |
| 文档同步 | 只更新本收束文档和必要注释 |

## 当前阶段明确不做什么

这些不是不重要，而是不进入本轮收束：

- 不接入最终真实 embedding 模型。
- 不接入 ObjectBox Vector Search。
- 不做 AI 语义分段。
- 不做完整农历日期计算和长年份缓存。
- 不做完整画像/关系模型重构。
- 不做几千篇导入的完整产品化入口。
- 不做新的大型开发者审计功能。
- 不做复杂 UI 动效和高级可视化。
- 不做会员额度、官方 AI 服务端和支付相关能力。

## 固定 AI Pipeline

本轮只认下面这条流程：

```text
Save
  -> Enqueue
  -> Prepare
  -> Summary
  -> Segment
  -> Embedding
  -> Retrieve
  -> Generate Today Insight
  -> Update Candidates / Memory
  -> Complete
```

### 触发规则

- 实时自动保存只保存正文，不触发完整 AI Pipeline。
- 用户明确退出编辑页且内容已保存后，才入队。
- 手动点击“重新分析”会保存当前内容，清理旧洞察，重新入队。
- 用户反馈“不准确”会将当前 job 标记为可继续的重生成任务。

### 失败规则

- AI 未配置或不可用：保留本地摘要/分段/向量，状态显示等待 AI 可用。
- 摘要失败：使用正文预览作为降级摘要。
- 向量失败：保留结构化摘要和分段，允许后续补建向量。
- 洞察失败：保留已生成本地资料，job 标记为 `incomplete` 或 `failed`。
- App 被杀、Web 标签关闭或系统中断：下次启动把超时 `running` 标记为 `incomplete` 后继续。

## 今日洞察行为约束

今日洞察必须遵守：

1. 当前日记优先，不能让历史记录盖过今天。
2. 历史引用只能来自上下文中明确提供的摘要、片段、记忆或关系资料。
3. 事实、信号、推测、建议要分层，不能把推测说成事实。
4. 不允许凭空说“你一直以来都……”。
5. 关联历史优先使用摘要和片段，只有必要时才使用原文。
6. 多事件日记要分别理解，不能只抓住其中一个事件代表整篇日记。
7. 反馈重生成时必须明确避开上一版被指出的问题，并重新核对旧来源。

## 数据产物边界

本轮产物只要求这些稳定：

| 产物 | 用途 |
| --- | --- |
| `EntrySummary` | 历史压缩引用、搜索、周期总结 |
| `DiarySegment` | 多事件检索和局部关联 |
| `AiEmbedding` | 当前本地检索占位实现，后续可替换 |
| `AiRetrievalTrace` | 开发者验证来源和排序原因 |
| `DiaryInsight` | 今日洞察显示与反馈对象 |
| `AiFeedback` | 保存用户反馈、上一版洞察快照和来源摘要 |
| `MemoryEntry` | 长期记忆候选和后续问答上下文 |
| `AiAnalysisJob` | 持久化队列和可恢复状态 |

## 验收命令

每次改 AI 收束相关代码，至少运行：

```powershell
flutter analyze
flutter test test\ai_services_test.dart --plain-name "AI settings and feedback"
flutter test test\ai_services_test.dart --plain-name "manual analysis rerun replaces stale insight output"
```

如果改动涉及页面显示或开发者调试页，再运行：

```powershell
flutter test test\widget_test.dart --plain-name "AI debug page shows inaccurate feedback and requeue trace"
flutter test test\widget_test.dart --plain-name "AI debug page shows claim evidence and confidence"
```

收束完成前最终运行：

```powershell
flutter test
```

## 完成定义

AI MVP 收束完成需要同时满足：

- 新写一篇日记后，后台能完成整理并显示今日洞察。
- 点击重新分析有即时状态反馈，旧洞察不会假装是新结果。
- 未配置 AI 或 AI 失败时，日记保存不受影响，状态可解释。
- 反馈“不准确”后，重生成 prompt 包含反馈、上一版洞察快照和旧来源。
- 开发者模式能看到本次生成的 prompt、检索来源、反馈上下文和 claims evidence。
- 关键测试和 `flutter analyze` 通过。

## 后续再开阶段

完成本轮收束后，后续按独立阶段推进：

1. 替换或接入真实 embedding 模型。
2. 接 ObjectBox Vector Search 或其它成熟向量索引。
3. 引入 AI 语义分段和 AI 摘要质量评估。
4. 完整农历日期计算、纪念日索引和多年今日缓存。
5. 批量导入后的分批入队、暂停、继续和设备耗时校准。
6. 画像、关系、长期记忆生命周期的产品级管理。
