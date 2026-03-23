<p align="center">
  <h1 align="center">ClaudeTerm</h1>
  <p align="center">Claude Code를 위한 네이티브 macOS 터미널</p>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-6.2-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

<p align="center">
  한국어 | <a href="../README.md">English</a>
</p>

<p align="center">
  <img src="screenshot.png" alt="ClaudeTerm 스크린샷" width="800">
</p>

> Claude Code CLI를 네이티브 macOS 앱으로 감싸서, 한글 입력이 완벽하게 동작하는 터미널입니다.

## 왜 ClaudeTerm인가요?

Claude Code CLI는 터미널 raw mode에서 동작하기 때문에 한글 조합이 깨집니다. 글자가 씹히거나, 조합 중에 사라지거나, IME가 정상적으로 동작하지 않는 문제가 있습니다.

ClaudeTerm은 입력을 네이티브 NSTextView로 받아서 이 문제를 해결합니다. CLI 자체는 그대로 사용하고, PTY로 직접 연결한 뒤 SwiftTerm이 렌더링하는 구조입니다.

## 빠른 시작

```bash
brew install tmux
git clone https://github.com/jinu/ClaudeTerm.git
cd ClaudeTerm && ./scripts/build-app.sh
open dist/ClaudeTerm.app
```

바로 실행하고 싶다면 이렇게 하면 됩니다: `swift run ClaudeTerm ~/Projects/my-project`

## 기능

| 기능 | 설명 |
|------|------|
| 한글/CJK IME | NSTextView 기반 네이티브 입력으로 한글, 일본어, 중국어 조합이 완벽하게 동작합니다 |
| 파일 사이드바 | 파일을 클릭하면 `@파일명`이 입력창에 삽입됩니다. 더블클릭하면 미리보기를 할 수 있습니다 |
| 세션 유지 | tmux 세션을 사용하기 때문에 앱을 재시작해도 대화가 유지됩니다 |
| 폰트 매칭 | Terminal.app이나 iTerm2에서 사용 중인 폰트를 자동으로 감지하여 적용합니다 |
| 입력 히스토리 | 위/아래 화살표로 이전에 보낸 메시지를 다시 불러올 수 있습니다 |
| 터미널 단축키 | Ctrl+C, Escape, Tab, Option+드래그 복사 등을 지원합니다 |

## 설치하기 전에 필요한 것

- macOS 13 이상
- [tmux](https://github.com/tmux/tmux) — `brew install tmux`로 설치할 수 있습니다
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) — `npm install -g @anthropic-ai/claude-code`로 설치할 수 있습니다

## 설치

<details>
<summary><strong>소스에서 빌드하기 (권장)</strong></summary>

```bash
git clone https://github.com/jinu/ClaudeTerm.git
cd ClaudeTerm
./scripts/build-app.sh
cp -r dist/ClaudeTerm.app /Applications/
```

</details>

<details>
<summary><strong>Swift Package Manager로 실행하기</strong></summary>

```bash
git clone https://github.com/jinu/ClaudeTerm.git
cd ClaudeTerm
swift run ClaudeTerm [경로]
```

</details>

## 사용법

| 키 | 동작 |
|----|------|
| Enter | 메시지 전송 |
| Shift+Enter | 줄바꿈 |
| 위/아래 | 입력 히스토리 탐색 |
| Ctrl+C | 실행 중단 |
| Option+드래그 | 터미널 텍스트 선택 및 복사 |
| Cmd+N | 새 워크스페이스 열기 |
| Cmd+O | 폴더 열기 |

**사이드바:** 파일을 한 번 클릭하면 `@파일명`이 입력창에 삽입됩니다. 더블클릭하면 Quick Look으로 미리볼 수 있습니다.

## 동작 원리

```
Composer (NSTextView) → Enter → PTY stdin → Claude CLI (tmux 안에서 실행)
Claude CLI stdout → PTY → SwiftTerm (xterm-256color) → 화면
```

네이티브 컴포저가 IME 조합을 처리하고, 나머지는 PTY를 통해 실제 CLI로 바로 전달됩니다. JSON 파싱이나 API 프록시 같은 중간 레이어는 없습니다.

## 기여

기여는 언제나 환영합니다. 변경하고 싶은 내용이 있다면 먼저 이슈를 열어주세요.

## 라이선스

MIT
