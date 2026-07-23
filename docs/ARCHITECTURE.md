# 拾年·Shinen 技术架构

## 架构原则

| 原则 | 说明 |
| --- | --- |
| 本地优先 | 日记、记忆、向量索引优先在端侧保存和检索 |
| 明文不上云 | 后端只处理账号、计费、额度，不接触日记明文 |
| AI 可替换 | 官方额度和用户自定义 Key 共存 |
| 离线可用 | 无网络时编辑、搜索、时光等本地能力仍可用 |
| 模块隔离 | 日记、洞察、成长线索、树洞、搜索、关系、设置独立演进 |
| 低压力体验 | 面向用户不设计打卡、任务、连续天数和完成率；后台队列只作为整理进度呈现 |

## 分层结构

| 层 | 职责 | 例子 |
| --- | --- | --- |
| Presentation | 页面、组件、交互状态 | 日记编辑页、成长线索页 |
| Application | 用例编排、权限检查、状态流转 | 保存日记、生成洞察、收藏成长线索 |
| Domain | 业务实体和规则 | DiaryEntry、StoneTask、MemoryShard |
| Data | 数据访问与外部服务适配 | ObjectBox、WebDAV、AI Client |

## 核心数据流

### 保存日记

```text
编辑输入
  ↓
草稿自动保存
  ↓
保存日记
  ↓
AI 原汁原味修复
  ↓
本地写入 DiaryEntry
  ↓
生成今日分析与成长线索
  ↓
更新记忆库、标签、人物、向量索引
```

### 语义搜索

```text
自然语言查询
  ↓
TFLite 本地嵌入模型生成 384 维向量
  ↓
ObjectBox Vector Search
  ↓
按时间、情绪、标签、图片等筛选
  ↓
返回相关日记、总结、人物互动
```

### WebDAV 备份

```text
本地数据快照
  ↓
Markdown + JSON + 媒体资源打包
  ↓
用户配置的 WebDAV 目录
  ↓
恢复时重建 ObjectBox 数据和向量索引
```

## 关键模块边界

| 模块 | 输入 | 输出 |
| --- | --- | --- |
| Diary | 文本、语音文本、图片、天气位置 | DiaryEntry、Draft、Attachment |
| AI Insight | DiaryEntry、Memory Context | 修复文本、洞察、摘要、标签、成长线索 |
| Growth Cues | AI 建议、用户编辑 | 低压力的一小步、微小变化记录 |
| Tree Hole | 用户问题、检索到的记忆 | 引用历史的回答、引导式追问 |
| Time | 周/月/年日记、成长线索 | 周报、月报、年报、真实变化回看 |
| Search | 查询文本、筛选条件 | 语义匹配结果 |
| Relationships | 日记实体识别结果 | 人物档案、互动记录、关系查询回答 |
| Settings | 用户配置 | 主题、安全、备份、AI、会员设置 |

## 后端边界

| 能做 | 不能做 |
| --- | --- |
| 账号登录 | 存储日记明文 |
| 会员状态 | 读取用户记忆库 |
| 使用额度统计 | 训练用户私有数据 |
| 支付回调 | 替用户托管 WebDAV 明文数据 |

## 待落地基础设施

| 能力 | 建议实现 |
| --- | --- |
| 依赖注入 | Riverpod Provider |
| 本地数据库 | ObjectBox Store + Entity |
| 安全存储 | flutter_secure_storage 保存 Key 与锁配置 |
| 生物识别 | local_auth |
| 权限 | permission_handler |
| 图片处理 | flutter_image_compress |
| 嵌入模型 | tflite_flutter 加载 assets/models |
