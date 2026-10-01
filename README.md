# GitHubBar

A macOS menu bar app for keeping an eye on GitHub: notifications, pull requests, review requests — or anything else you can express as a GitHub search. Styled after [Primer](https://primer.style/).

## Features

- **Configurable tabs.** Each tab has a title, an [Octicon](https://primer.style/octicons/), a query and an attention rule.
  - **Search tabs** use the same syntax as the github.com search bar (`is:pr is:open review-requested:@me`). All search tabs are fetched in a single GraphQL request.
  - **Notification tabs** filter your unread notifications locally (`reason:mention,team_mention -repo:owner/noisy`). All notification tabs share one conditional REST request.
- **Presets** for the common cases: Inbox, Mentions, Review requests, My pull requests, Failing CI, Ready to merge, Assigned to me…
- **Menu bar icon** turns orange when a tab needs attention — either because it has items, or because new items appeared since you last looked.
- Pull request rows show state, CI status and review decision — notification rows too.
- Mark notifications as **read** or **done** (hover a row, or use the footer to clear a whole tab).
- Optional **macOS notifications** per tab when new items appear.
- **Snooze** the menu bar highlight (and notifications) for an hour, four hours or until tomorrow.
- **Keyboard shortcuts** inside the popover (press `?`), plus a configurable global shortcut to open it.
- **Export / import** tab setups as JSON to share them.
- Token stored in the Keychain.

## Building

Requires macOS 14+, Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen
open GitHubBar.xcodeproj
```

The Xcode project, `Info.plist` and entitlements are generated from `project.yml` and not checked in.

## Token

Create a **classic** personal access token with the `repo` and `notifications` scopes:
<https://github.com/settings/tokens/new?scopes=repo,notifications&description=GitHubBar>

Fine-grained tokens work for search tabs, but GitHub doesn't let them read notifications.

## Notification query syntax

| Qualifier | Example |
|---|---|
| `reason:` | `reason:review_requested`, `reason:mention,team_mention` |
| `type:` | `type:PullRequest`, `type:pr`, `type:Issue`, `type:Release`, `type:ci` |
| `repo:` | `repo:owner/name` |
| `org:` | `org:owner` |
| `state:` | `state:open`, `-state:merged,closed` (`open` includes drafts) |
| `is:` | `is:unread` |
| text | words match the notification title |

Terms are combined with AND, comma-separated values with OR, and a leading `-` excludes. See [notification reasons](https://docs.github.com/en/rest/activity/notifications#about-notification-reasons).

## Keyboard shortcuts

| Keys | Action |
|---|---|
| `⌘1`–`⌘9`, `←` `→` | Switch tab |
| `J` / `↓`, `K` / `↑` | Next / previous item |
| `O` / `↩` | Open in browser |
| `E` | Mark notification as done |
| `⇧I` | Mark notification as read |
| `⌘R` | Refresh |
| `?` | Show shortcuts |
| `Esc` | Close the popover |

The global "Open GitHubBar" shortcut is set in Settings → Account (uses [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)).

## Octicons

Icons are bundled from [`@primer/octicons`](https://github.com/primer/octicons) (MIT). To add icons, edit the list in `scripts/update-octicons.sh` and run it (requires Node).
The app icon is rendered from the `mark-github` Octicon by `swift scripts/make-app-icon.swift`.

## Project layout

```
GitHubBar/
  App/        App entry point (MenuBarExtra + Settings)
  Core/       GitHub client (REST + GraphQL), Keychain, notification filter
  Models/     Tab configuration, presets, feed items
  Store/      AppState: polling, results, attention logic, persistence
  UI/         Popover, rows, settings
  UI/Primer/  Primer color tokens, Octicons, Primer-style components
```
