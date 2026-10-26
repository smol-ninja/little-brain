<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/wordmark-dark.svg" />
  <img src="docs/wordmark-light.svg" width="320" alt="littlebrain" />
</picture>

littlebrain tracks active and unread Codex chats from the macOS menu bar. The counter shows finished unread chats out of all tracked chats. Opening a finished chat clears it. Chats are grouped into Ready for review and Running, with side chats nested beneath their main chat.

<img src="docs/screenshot.png" width="360" alt="Example chats showing recursive side chat nesting in littlebrain" />

*Example chats.*

## Setup

Requires macOS 26 or later, Codex, and Xcode with the macOS 27 SDK or later.

Ask Codex:

> Install littlebrain from https://github.com/smol-ninja/little-brain on my Mac. Clone the repo, run ./build.sh, copy little-brain.app into /Applications, and launch it.

Or build it yourself:

```sh
git clone https://github.com/smol-ninja/little-brain.git
cd little-brain
./build.sh
cp -R ../little-brain.app /Applications/
open /Applications/little-brain.app
```

Launch at login and the power button are at the bottom of the panel. littlebrain tracks local Codex chats only.
