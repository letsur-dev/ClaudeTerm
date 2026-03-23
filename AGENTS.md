# ClaudeTerm

macOS native app. SwiftTerm 터미널 에뮬레이터 + NSTextView composer로 Claude CLI를 감싸는 하이브리드 앱.
한글 IME가 터미널 raw mode에서 깨지는 문제를 네이티브 입력으로 해결한다.

## Build & Run

```bash
cd ~/Projects/ClaudeTerm
swift build
swift run ClaudeTerm
# 또는 폴더 지정:
swift run ClaudeTerm ~/Projects/some-project
# macOS app bundle 생성:
./scripts/build-app.sh
open dist/ClaudeTerm.app
```

## Architecture

2파일 구조:
- `Sources/ClaudeTerm/main.swift` — AppDelegate, 세션 피커, WorkspaceWindowController
- `Sources/ClaudeTerm/WorkspaceView.swift` — 사이드바 + SwiftTerm 터미널 + NSTextView composer

데이터 흐름:
```
ComposerView → Enter → text + "\n" → PTY stdin → Claude CLI
Claude CLI stdout → PTY → SwiftTerm LocalProcessTerminalView → 화면
```

핵심: ConversationView 없음, ClaudeService 없음, PermissionServer 없음. CLI를 PTY로 직접 실행하고 SwiftTerm이 렌더링.

## Key Design Decisions

| 결정 | 이유 |
|------|------|
| SwiftTerm LocalProcessTerminalView | CLI TUI를 그대로 렌더링. xterm-256color 호환 |
| NSTextView composer | IME composition 이벤트 지원. 한글 조합 완벽 |
| PTY 직접 통신 | JSON stream 파싱 불필요. CLI 모든 기능이 그대로 동작 |
| 2파일 구조 | 최소 복잡도. Codex가 전체 컨텍스트를 한번에 파악 |

## Conventions

- Swift 6.2, macOS 13+
- `@MainActor` 사용
- NSLayoutConstraint 기반 레이아웃 (SwiftUI 아님)
- 디자인 토큰은 `private enum C`에 집중
- 모든 뷰는 코드로 생성 (xib/storyboard 없음)
