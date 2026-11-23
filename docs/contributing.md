---
title: Contributing
---

# Adding a compatibility report

Every app has one Markdown file in
[`docs/_apps`]({{ site.repository_url }}/tree/master/docs/_apps), named by
its Darwin platform and bundle identifier:
`docs/_apps/<platform>/<bundle id>.md`, such as
`docs/_apps/ios/com.hulu.plus.md`. The platform and bundle ID together are
the app's identifier, since an iOS app and a Mac app can share a bundle ID.
Read the bundle ID from the app's `Info.plist` (`CFBundleIdentifier`). Each
report in the file comes from a merged pull request.
To add a report, open a pull request that changes Perry and adds or edits
the app's file in the same branch, or send a pull request with the file
alone that links the pull request it reports on.

## The file format

Structured data goes in YAML front matter; anything longer goes in the
Markdown body. GitHub shows the front matter as a table when the file is
opened, so the file reads well there too.

```markdown
---
name: Hulu
bundle_id: "com.hulu.plus"  # CFBundleIdentifier, always quoted
platform: ios            # ios | macos | maccatalyst, the folder it is in
kind: app                # app | game
developer: Hulu          # only if a PR states it or it is unambiguous
tags: [Swift, ObjC]      # languages and engines; see the list below
reports:
  - pr: 216
    date: 2026-11-19     # the PR's merge date
    perry: "e9a46074"    # the merge commit, 8 characters, always quoted
    platform: ios        # the same as the app's platform
    cpu: arm64           # ios: arm64 | armv7 | armv6; macos: arm64 | x86_64 | i386 | ppc; maccatalyst: arm64 | x86_64
    app_version: "8.1"   # only if the PR states it, always quoted
    hardware: Lenovo Duet 3  # the machine it ran on
    resolution: "1170x2532"  # the size it drew at, if stated: "WxH" pixels, or "WxH@S" points at a scale
    graphics: Metal      # the graphics API this run drew with, if known
    fps: 60              # games only: the frame rate in play, or a range such as "45-52"
    env:                 # environment variables it ran with, if any
      - "PERRY_OS_VERSION=18.0"
    args:                # options passed to perry before the app, if any
      - "--report"
    os: Debian sid       # the operating system that machine ran
    packaging: Packaging/ios/com.hulu.plus/linux  # the launcher folder it ran with, if any
    level: 2
    source: title        # title | body | screenshot | maintainer: what the level rests on
    notes: Reaches the Welcome screen.
    screenshots:
      - url: https://github.com/user-attachments/assets/00000000-0000-0000-0000-000000000000
        caption: Welcome screen
---

Optional notes in Markdown: known problems, the `PERRY_*` settings the app
needs, what was worked around. Leave the body empty if the PRs say nothing
more than the reports do.
```

- Reports are in date order, oldest first. An app's level is its newest
  report's level.
- A report from the maintainer's own test, rather than a pull request,
  leaves out `pr`, sets `source: maintainer`, and gives the tested commit
  as `perry` and the test's date as `date`.
- An app can be listed before anyone has tested it: leave `reports` out
  and the site shows it as not tested yet.
- `name`, `bundle_id`, `platform` and `kind` are required, and each
  report needs `pr` (except a maintainer's test), `date`, `perry`, `platform`, `cpu`, `hardware`,
  `os`, `level`, `source` and `notes`. Leave out `app_version` when the pull
  request does not state it; never guess a version or a result.
- `cpu` is the slice of the binary that ran, and `hardware` the machine it
  ran on, such as Lenovo Duet 3, Retroid Pocket 5 or Dell OptiPlex 7020;
  `os` is the operating system it ran, such as Debian 13, Debian sid or
  ROCKNIX.
  Perry runs code natively, so an arm64 machine runs arm64 slices and an
  x86 machine runs x86_64 or i386 ones, and a 32-bit PowerPC machine ppc
  ones.
- `tags` names the languages and engines the app is built with: Swift,
  ObjC, C++, Unity, Unreal, SpriteKit, SceneKit, Cocos2D (cocos2d-iphone,
  Objective-C), Cocos2D-X (C++), SexyAppFramework, Mono, XNA, Lua and
  Kotlin. Add a tag only when the app's bundle or its pull request shows
  it.
- `graphics` is the graphics API that run drew with: OpenGL, OpenGL ES 1,
  OpenGL ES 2, OpenGL ES 3 or Metal. It belongs to the report, not the app:
  older builds of a game may use OpenGL ES where newer ones use Metal, and
  a game that supports both runs on OpenGL ES when Metal is turned off
  (`PERRY_METAL=0`, listed in `env`).
- `fps` is for games: the frame rate the pull request measured while
  playing, or the menu's if play wasn't reached. A range is quoted, as
  `"45-52"`.
- `resolution` is the screen size the app drew at, when the pull request
  states it: `"1920x1080"` in pixels, or `"390x844@3"` in points at a
  scale, as `PERRY_UIKIT_SCREEN` takes it. It is always quoted.
- `env` lists the environment variables the app ran with, each as a
  quoted `"NAME=value"`, and `args` the options passed to `perry`. Give
  them when the pull request says the app needs them or was tested with
  them, so someone else can run it the same way.
- `packaging` is the folder in [Packaging](https://github.com/MillerTechnologyPeru/Perry/tree/master/Packaging)
  holding the launcher, desktop entry or port script the app ran with,
  such as `Packaging/macos/com.popcap.Bejeweled3/portmaster`. The app page
  links to it.
- `notes` is one or two plain sentences in the present tense saying how
  far the app gets and what is known to be wrong.
- Don't add `layout`, `title` or `permalink`; the site's settings supply
  them.

### Quoting

- `bundle_id`, `perry` and `app_version` are always quoted, so YAML never reads a commit
  such as `12345678` or a version such as `6.30` as a number.
- A value containing `: ` or starting with a quote, `#`, `[`, `{`, `*`,
  `&`, `!`, `|`, `>`, `@` or a backtick is quoted.

## Levels

| Level | Name | Assign when the PR says |
| --- | --- | --- |
| 1 | Loads | starts, then stops or crashes; "launch crash", "start-up", "toward" |
| 2 | First screen | splash, welcome, sign-in, login, launcher, loading screen, title screen, bot check |
| 3 | Main content, major issues | past sign-in or into a menu or game, with stated problems or no claim of being usable; "bring up", "initial support" |
| 4 | Usable | "playable", "play", "runs" with main content shown and only small issues named |
| 5 | Complete | the PR states that everything tested works |

- Use the lowest level the evidence supports. A title that only says
  "Run X" with no milestone is level 3, `source: title`.
- Level 5 needs an explicit statement in the pull request, or the
  maintainer's review of the app, recorded as `source: maintainer`.
- A screenshot may raise the level only to what it plainly shows.
- For iOS apps `cpu` is `arm64` unless the pull request says `armv7` or
  `armv6`.

## Screenshots

Screenshots are never stored in this repository. Attach the image to the
pull request on GitHub, then copy its URL into `screenshots` exactly as it
appears there. Only these forms are accepted:

- `https://github.com/user-attachments/assets/<uuid>`
- `https://github.com/MillerTechnologyPeru/Perry/assets/<id>/<uuid>`
- `https://user-images.githubusercontent.com/<id>/<name>`

The image must load without signing in to GitHub. Don't link an image that
shows an email address, account name, real name, street address, phone
number, precise location, device serial or message content. Keep at most
three per report, and give each a `caption` of a few plain words.

## Checking and building locally

The check script needs only Ruby's standard library:

```sh
ruby Scripts/compatibility-check.rb
```

It names the file and the problem when a report is malformed, and prints
the number of apps and reports when all is well.

To build and preview the site, with Ruby and Bundler installed:

```sh
cd docs
bundle install
bundle exec jekyll serve
```

Then open <http://localhost:4000/Perry/>.
