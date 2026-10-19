# PlayerMachine — 媒体播放状态图

**文件**: `lib/controllers/player_controller.dart`
**Store 类型**: `Store<PlayerState>`

## 概述

PlayerMachine 管理媒体播放的完整生命周期。作为正交区域中最核心的状态机，它为 SubtitleMachine 和 LearningMachine 提供时间基准（position）。

## 层次化状态图

```
PlayerMachine
├── MediaLifecycle         ← 媒体加载/打开生命周期
│   ├── Idle               ← 初始状态
│   ├── Opening            ← 正在打开媒体
│   ├── Ready              ← 媒体已就绪
│   └── Failed             ← 打开失败
├── PlaybackControl        ← 播放控制
│   ├── Stopped            ← 停止 / 未播放
│   ├── Playing            ← 正在播放
│   │   ├── Normal         ← 常规播放
│   │   ├── LoopCue        ← 循环当前字幕条（subtitleController.loopCue）
│   │   └── LoopRange      ← 循环源范围（sourceLoopStart/End）
│   └── Paused             ← 暂停
└── TrackSelection          ← 音轨/字幕轨选择（正交区域）
    ├── AudioTrack
    └── EmbeddedSubtitleTrack
```

## 状态详细说明

### 1. MediaLifecycle 区域

```
状态 Idle {
  entry: mediaId=null, mediaPath=null, position=Duration.zero
  
  on OPEN_MEDIA(path): Opening / _openMediaPath(path)
  on OPEN_ONLINE(url):  Opening / tools.resolveOnlineMedia(url)
}

状态 Opening {
  entry: status='Opening ...', position=Duration.zero
  
  on OPEN_SUCCEEDED(media): Ready / setMedia(), _loadSubtitleResources()
  on OPEN_FAILED(error):    Failed / status='Playback failed: $error'
}

状态 Ready {
  entry: status='Playing ...'
  exit:  saveProgress(), _saveSettings()
  
  子状态 Playing {
    entry: adapter.play()
    
    on PAUSE:          Paused / adapter.pause()
    on SEEK(position): → / adapter.seek(position)
    on POSITION_UPDATE: → / setPosition(value), _onPosition()
    
    on LOOP_CUE_ENABLE:   LoopCue
    on LOOP_CUE_DISABLE:  Normal
    on LOOP_RANGE_START:  LoopRange
    on LOOP_RANGE_END:    Normal
  }
  
  子状态 Paused {
    entry: adapter.pause()
    
    on PLAY:   Playing / adapter.play()
    on SEEK:   → / adapter.seek()  (seek 后仍保持暂停)
  }
  
  on CLOSE_MEDIA: Idle / clearMedia(), adapter.dispose()
}
```

### 2. PlaybackControl — 内部层次

```
PlaybackControl {
  entry: playing=false
  exit:  saveProgress()
  
  状态 Stopped {
    on PLAY:  Playing
  }
  
  状态 Playing {
    entry: playing=true
    
    子状态 Normal {
      // 常规播放，无循环行为
    }
    
    子状态 LoopCue {
      // 当 subtitleController.loopCue=true
      guard: currentPrimaryCue != null
      on POSITION_UPDATE(position):
        if position >= primaryCursor.mediaEnd(currentCue) →
          adapter.seek(mediaStart(currentCue))
    }
    
    子状态 LoopRange {
      // 当 sourceLoopStart && sourceLoopEnd 被设置
      guard: sourceLoopStart != null && sourceLoopEnd != null
      on POSITION_UPDATE(position):
        if position >= sourceLoopEnd →
          adapter.seek(sourceLoopStart)
    }
  }
  
  状态 Paused {
    entry: playing=false
  }
}
```

## 状态转移表

| 当前状态 | 事件 | 守卫 | 下一状态 | 动作 |
|---------|------|------|---------|------|
| Idle | OPEN_MEDIA | path != null | Opening | status='Opening' |
| Idle | OPEN_ONLINE | url != null | Opening | resolve url |
| Opening | open succeed | mounted | Ready | setMedia(), load subtitles |
| Opening | open failed | — | Failed | status=error |
| Failed | RETRY | — | Idle | clear state |
| Ready | CLOSE_MEDIA | — | Idle | clearMedia(), dispose adapter |
| Playing | PAUSE | — | Paused | adapter.pause() |
| Paused | PLAY | — | Playing | adapter.play() |
| Playing/任何子状态 | SEEK | position valid | *(同状态)* | adapter.seek() |
| LoopCue | POSITION_UPDATE | position >= cue.end | *(同状态)* | seek(cue.start) |
| LoopRange | POSITION_UPDATE | position >= loopEnd | *(同状态)* | seek(loopStart) |

## 当前实现的问题（从 Statecharts 角度）

1. **隐式状态耦合**：`LoopCue` 状态依赖 SubtitleMachine 的 `loopCue` 字段。在 Statecharts 中，这应该显式建模为跨区域同步事件，而非通过父 widget 的 setState 隐式传播。

2. **状态枚举缺失**：当前 `PlayerState` 用 boolean (`playing`) 和条件字段 (`sourceLoopStart`) 编码状态，缺少显式的 `status` 枚举。这导致某些状态组合可能非法（如 `playing=true` 且 `mediaId=null`）。

3. **Seek 行为模糊**：`Paused` 状态下 SEEK 应保持暂停，但当前实现中 seek 后需手动检查 `playing`。Statecharts 应区分 "SeekAndPlay" 与 "SeekAndStay"。

4. **AudioTrack / SubtitleTrack 选择**：虽然状态数据已建模，但缺缺少从 `audioTracks` 列表中选择的显式转移事件——当前是直接 setter 调用，未作为状态机转移建模。

## 建议的改进

```dart
// 在 PlayerState 中增加显式状态枚举
enum PlaybackPhase { idle, opening, ready, failed }
enum PlayMode { normal, loopCue, loopRange }

class PlayerState {
  final PlaybackPhase phase;  // 替代隐式 null 检查
  final PlayMode mode;        // 替代分散的 loopCue/sourceLoopStart 字段
  // ...
}
```
