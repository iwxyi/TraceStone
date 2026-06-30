# 溯石 TraceStone

溯石是一款以日记为数据源、以 AI 累计记忆与分析为核心、注重数据主权与隐私的跨平台成长伴侣 App。

> 产品目标：通过持续、真实的个人记录，构建专属认知镜像，陪伴用户穿越时间，看见并塑造更好的自己。

## 核心能力

| 模块 | 说明 | 优先级 |
| --- | --- | --- |
| 日记记录 | 自动创建日记页，支持文本、语音、图片、天气与位置元数据 | P0 |
| AI 洞察 | 保存后进行原汁原味修复、今日洞察、记忆更新与行动建议 | P0 |
| 塑石 | 将 AI 建议转化为可追踪的微小行动任务 | P0 |
| 成长陪伴 | 基于个人记忆库的多轮问答与引导式反思 | P0 |
| 总结回顾 | 周/月/年总结、时间线、日历与趋势统计 | P0/P1 |
| 语义搜索 | 本地向量检索，支持自然语言查询与筛选 | P0 |
| 人际关系 | 自动识别人名、别名管理、互动记录与关系查询 | P0/P1 |
| 数据主权 | WebDAV 备份恢复、自定义 AI Key、本地优先与离线可用 | P0 |
| 个性化 | 日夜间模式、主题皮肤、日记锁、提醒、导出与字体缩放 | P0/P1 |

## 技术选型

| 层级 | 技术 |
| --- | --- |
| 客户端 | Flutter |
| 本地数据库 | ObjectBox |
| 向量检索 | ObjectBox Vector Search |
| 本地嵌入 | all-MiniLM-L6-v2 TFLite，384 维向量 |
| 语音识别 | 平台原生 API 或第三方 SDK |
| 图片压缩 | flutter_image_compress |
| WebDAV | webdav_client |
| 后端边界 | 仅账号、计费、使用统计，不接触日记明文 |

## 项目结构

```text
TraceStone/
├── assets/                     # 图片、动效、字体等资源
├── docs/
│   └── PRD.md                  # 产品需求文档
├── lib/
│   ├── app/                    # App 入口、壳层、依赖装配
│   ├── core/                   # 通用常量、主题、路由、工具
│   │   ├── constants/
│   │   ├── routing/
│   │   ├── theme/
│   │   └── utils/
│   ├── data/                   # 数据模型、仓储、服务、本地存储
│   │   ├── local/
│   │   ├── models/
│   │   ├── repositories/
│   │   └── services/
│   └── features/               # 业务功能模块
│       ├── diary/              # 日记创建、编辑、草稿、媒体输入
│       ├── ai_insight/         # AI 修复、洞察、记忆更新
│       ├── shaping_stone/      # 塑石建议、采纳、打卡、追踪
│       ├── companion/          # 成长陪伴问答
│       ├── review/             # 周/月/年总结与回顾
│       ├── search/             # 语义搜索、标签与筛选
│       ├── relationships/      # 人际实体、别名、关系图谱
│       └── settings/           # WebDAV、自定义 AI、会员、隐私设置
└── test/                       # 单元测试与组件测试
```

每个业务模块默认采用三层结构：

| 目录 | 职责 |
| --- | --- |
| `domain/` | 业务实体、值对象、领域规则 |
| `application/` | 用例、状态协调、业务流程编排 |
| `presentation/` | 页面、组件、交互状态 |

## 当前工程骨架

| 文件 | 作用 |
| --- | --- |
| `lib/main.dart` | Flutter 应用入口 |
| `lib/app/trace_stone_app.dart` | App 根组件 |
| `lib/core/theme/app_theme.dart` | 溪石、墨砚、晨雾主题框架 |
| `lib/core/routing/app_routes.dart` | 路由命名 |
| `lib/core/constants/app_constants.dart` | 产品级常量 |
| `lib/features/*/README.md` | 各功能模块职责说明 |

## 本地开发

### 环境要求

| 工具 | 建议版本 |
| --- | --- |
| Flutter | 3.x stable |
| Dart | 随 Flutter stable |
| Android Studio / Xcode | 用于移动端构建 |

### 启动

```bash
flutter pub get
flutter run
```

### 测试

```bash
flutter test
```

### 代码检查

```bash
flutter analyze
```

## 隐私与数据原则

| 原则 | 要求 |
| --- | --- |
| 本地优先 | 日记明文、记忆库、向量索引优先存储在用户设备 |
| 用户主权 | 支持 WebDAV 备份恢复与可读 Markdown + JSON 导出 |
| AI 可替换 | 支持官方额度，也支持用户自定义 Key 与端点 |
| 后端最小化 | 后端不保存、不分析、不接触日记明文 |
| 原汁原味 | AI 修复只改错别字、标点与明显语病，不重写用户风格 |

## MVP 范围

| 阶段 | 交付内容 |
| --- | --- |
| M1 | 日记编辑、草稿保存、基础主题、日记锁框架 |
| M2 | AI 修复、今日洞察、塑石建议与采纳 |
| M3 | 本地记忆库、语义搜索、成长陪伴问答 |
| M4 | WebDAV 备份恢复、周期总结、导出 |
| M5 | 人际关系洞察、图表统计、会员中心 |

## 文档

| 文档 | 说明 |
| --- | --- |
| [`docs/PRD.md`](docs/PRD.md) | 产品需求文档 |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | 技术架构与模块边界 |
| [`docs/MVP_ROADMAP.md`](docs/MVP_ROADMAP.md) | MVP 迭代计划 |
