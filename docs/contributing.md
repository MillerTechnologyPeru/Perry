---
title: Contributing
---

# Adding a compatibility report

Every app has one Markdown file in
[`docs/_apps`]({{ site.repository_url }}/tree/master/docs/_apps), named
after the app: its name in lowercase ASCII with hyphens, such as
`cut-the-rope-2.md`. Each report in it comes from a merged pull request.
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
platform: ios            # ios | macos | catalyst
kind: app                # app | game
developer: Hulu          # only if a PR states it or it is unambiguous
reports:
  - pr: 216
    date: 2026-11-19     # the PR's merge date
    perry: "e9a46074"    # the merge commit, 8 characters, always quoted
    arch: arm64          # arm64 | armv7 | armv6 | x86_64 | i386
    app_version: "8.1"   # only if the PR states it, always quoted
    host: Lenovo Duet 3  # only if the PR states it
    level: 2
    source: title        # title | body | screenshot: what the level rests on
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
- `name`, `platform`, `kind` and `reports` are required, and each report
  needs `pr`, `date`, `perry`, `level`, `source` and `notes`. Leave out a
  field the pull request does not state; never guess a version, device or
  result.
- `notes` is one or two plain sentences in the present tense saying how
  far the app gets and what is known to be wrong.
- Don't add `layout`, `title` or `permalink`; the site's settings supply
  them.

### Quoting

- `perry` and `app_version` are always quoted, so YAML never reads a commit
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
- Level 5 needs an explicit statement in the pull request.
- A screenshot may raise the level only to what it plainly shows.
- For iOS apps `arch` is `arm64` unless the pull request says `armv7` or
  `armv6`. For Mac apps leave it out unless the pull request states it.

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
