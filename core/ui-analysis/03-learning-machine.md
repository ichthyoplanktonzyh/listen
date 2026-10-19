# LearningMachine — 词汇学习状态图

**文件**: `lib/controllers/learning_controller.dart`
**Store 类型**: `Store<LearningState>`

## 概述

LearningMachine 管理用户与词汇学习相关的交互状态：单词选择、词典查询、发音播放、词句诊断、短语候选。

## 层次化状态图

```
LearningMachine
├── WordSelection                    ← 单词选择生命周期
│   ├── NoWord                       ← 未选中任何单词
│   └── WordSelected                 ← 选中一个单词
│       ├── DetailsLoading           ← 正在获取词典/发音数据
│       ├── DetailsReady             ← 数据就绪
│       │   ├── ShowingDictionary    ← 显示词典视图
│       │   ├── ShowingPronunciation ← 显示发音视图
│       │   └── ShowingContent       ← 显示学习内容编辑
│       └── DetailsError             ← 获取失败
├── Diagnosis                        ← 诊断状态
│   ├── NotAvailable                 ← 无当前 cue 或无 diagnosis
│   ├── Loading                      ← 正在请求诊断
│   └── Ready(diagnosis)             ← 诊断就绪
├── PhraseCandidates                 ← 短语候选状态
│   ├── NoCandidates
│   └── CandidatesAvailable(list)
└── SidePanelNavigation              ← 侧面板 Tab 选择
    ├── TabTranscript     (0)
    ├── TabResources      (1)
    ├── TabWordLearning   (2)
    └── TabDiagnosis      (3)
```

## 正交区域分析

### 1. WordSelection 区域

```
WordSelection {
  状态 NoWord {
    entry: selectedWordDetails=null, selectedToken=null
    
    on SELECT_WORD(token, cue):
      WordSelected.DetailsLoading / 
        fetchWordDetails(token.normalized),
        setSelectedToken(token),
        setSelectedCue(cue)
    on SELECT_WORD_PROFILE(lemma):
      WordSelected.DetailsLoading /
        fetchWordDetails(lemma)
  }
  
  状态 WordSelected {
    entry: sidePanel=2 (自动切换到单词学习面板)
    exit:  selectedWordDetails=null
    
    子状态 DetailsLoading {
      entry: await api.wordDetails()
      
      on LOAD_SUCCEEDED(details):
        DetailsReady / selectWord(details)
      on LOAD_FAILED(error):
        DetailsError
    }
    
    子状态 DetailsReady {
      entry: selectedWordDetails != null
      
      内部导航：
        on SHOW_DICTIONARY: ShowingDictionary
        on SHOW_PRONUNCIATION: ShowingPronunciation
        on SHOW_CONTENT: ShowingContent
      
      on UPDATE_WORD_STATUS(status):
        / api.updateWordProfile()
        / 刷新 diagnosis
      on OBSERVE_HEARD:
        / api.createObservation(heard=true)
        / 刷新 diagnosis
      on OBSERVE_NOT_HEARD:
        / api.createObservation(heard=false)
        / 刷新 diagnosis
      on CLEAR_SELECTION:
        NoWord / clearSelection()
    }
    
    子状态 DetailsError {
      on RETRY: DetailsLoading
      on CLEAR_SELECTION: NoWord
    }
  }
}
```

### 2. Diagnosis 区域

Diagnosis 的状态随时间轴自动更新，每切换一个 cue 时触发。

```
Diagnosis {
  状态 NotAvailable {
    entry: diagnosis=null
  }
  
  状态 Loading {
    entry: await api.diagnose(cue.id)
    
    on DIAGNOSE_SUCCEEDED(result):
      Ready / setDiagnosis(result)
    on DIAGNOSE_FAILED:
      NotAvailable / setDiagnosis(null)
  }
  
  状态 Ready(diagnosis) {
    on CUE_CHANGED(newCue):
      Loading / _refreshDiagnosis()
  }
  
  // 全局转移：由 Orchestrator 的 _onPosition 驱动
  on CUE_CHANGED(cue):
    NotAvailable/Ready --[guard: cue已切换]--> Loading
}
```

### 3. PhraseCandidates 区域

```
PhraseCandidates {
  状态 NoCandidates {
    entry: phraseCandidates=[]
  }
  
  状态 CandidatesAvailable(list) {
    on CUE_CHANGED:
      NoCandidates / _loadPhraseCandidates(newCue)
    on SELECT_CANDIDATE(candidate):
      / _openPhrase()
  }
  
  // 每个 cue 变更时重新加载
  on CUE_CHANGED(cue):
    → NoCandidates / _loadPhraseCandidates(cue)
  on CANDIDATES_LOADED(list) [if list.isEmpty]:
    → NoCandidates
  on CANDIDATES_LOADED(list) [if list.isNotEmpty]:
    → CandidatesAvailable(list)
}
```

### 4. SidePanelNavigation 区域

```
SidePanelNavigation {
  深度历史状态 (Deep History) {
    // 记住上次用户选择的 tab
    initial: TabTranscript
    
    on SELECT_TAB(index):
      → TabTranscript / TabResources / TabWordLearning / TabDiagnosis
  }
  
  状态 TabTranscript { entry: sidePanel=0 }
  状态 TabResources  { entry: sidePanel=1 }
  状态 TabWordLearning { 
    entry: sidePanel=2
    // 如果没有选中的单词，显示 "noWordSelected"
  }
  状态 TabDiagnosis { 
    entry: sidePanel=3
    guard: diagnosis != null
  }
}
```

## 跨状态机同步

```
┌─────────────────────────────────────────────────────┐
│                 事件总线（Event Bus）                  │
├─────────────────────────────────────────────────────┤
│  PlayerMachine         SubtitleMachine               │
│  ┌────────────────┐    ┌────────────────────┐        │
│  │ POSITION_UPDATE │───→│ CUE_CHANGED        │        │
│  └────────────────┘    └────────┬───────────┘        │
│                                 │                    │
│                                 ▼                    │
│                       ┌──────────────────┐           │
│                       │ LearningMachine   │           │
│                       │ ├─ _refreshDiagnosis()      │
│                       │ ├─ _loadPhraseCandidates()  │
│                       │ └─ _ensurePronunciation()  │
│                       └──────────────────┘           │
└─────────────────────────────────────────────────────┘
```

## 当前实现中的 Statecharts 问题

### 问题 1：Word Selected 的显式性

当前 `selectedWordDetails` 使用 `null` 编码 "无选中单词"，但 `selectedToken` 和 `selectedCue` 也有独立的 null 语义。Statecharts 提倡用显式的 **NoWord / WordSelected** 状态替代分散的 null 检查。

### 问题 2：Diagnosis 与 Cue 的同步竞争

```dart
// 当前实现的问题：异步竞态
_refreshDiagnosis() async {
  final value = await service.diagnose(cue.id);
  if (mounted && cue.id == subtitleController.currentPrimaryCue?.id) {
    learningController.setDiagnosis(value);
  }
}
```

`cue.id` 检查旨在避免过时响应，但若 Cue 快速切换多次，仍可能存在中间状态的诊断结果被最终覆盖的问题。Statecharts 中可用 **取消前一个请求** 或 **请求序列号** 来建模。

### 问题 3：单词状态更新散落多处

单词状态更新在 `WordSelection.DetailsReady` 中通过 `setSelectedWordStatus()` 完成，但也通过 `_markFirstWord()` 快捷键在 Orchestrator 层完成。这些路径应统一在状态机的 `UPDATE_WORD_STATUS` 事件处理中。

## 改进建议

```dart
// 使用 sealed class 区分 WordSelection 状态
sealed class WordSelectionState {}
class NoWord extends WordSelectionState {}
class LoadingDetails extends WordSelectionState {
  final String lemma;
}
class DetailsReady extends WordSelectionState {
  final Map<String, dynamic> details;
  final Map<String, dynamic>? dictionary;
  final Map<String, dynamic>? pronunciation;
  final DetailView view; // dictionary / pronunciation / content
}
class DetailsError extends WordSelectionState {
  final String error;
}
```
