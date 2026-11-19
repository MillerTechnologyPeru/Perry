---
title: Perry
---

# Perry

Run iOS and macOS apps on Linux, natively.

Perry loads prebuilt Mach-O binaries into a Linux process and binds their
imports to Linux shared libraries ("providers") that implement Apple's
libraries and frameworks behind the Darwin ABI. There is no CPU emulation
and no Darwin kernel layer: an app's own code runs on the host CPU, and
everything it calls is ordinary Linux code, mostly written in Swift.

## What runs

| Mach-O binary | Linux host | Loader | Notes |
| --- | --- | --- | --- |
| arm64 iOS and macOS | arm64 | `perry` | C, Objective-C, C++, Swift and SwiftUI |
| armv7 and armv6 iOS | arm64 with AArch32 at EL0 | `perry32` | C, Objective-C and C++; iOS 2 through 10; no Swift |
| x86_64 macOS | x86_64 | `perry` | AppKit apps and games |
| i386 macOS | x86_64 | `perry32` | Cocoa, Carbon and QuickTime era apps and games |

## Apps tested so far

{% assign report_count = 0 -%}
{%- for app in site.apps -%}
  {%- assign report_count = report_count | plus: app.reports.size -%}
{%- endfor -%}
{{ site.apps.size }} apps and games have {{ report_count }} reports, each from a merged pull request.
An app's level is the level of its newest report.

<div class="table-wrap">
<table>
  <thead>
    <tr><th>Level</th><th>Apps</th></tr>
  </thead>
  <tbody>
  {%- for level in site.data.levels %}
    {%- assign count = 0 -%}
    {%- for app in site.apps -%}
      {%- assign current = app.reports | last -%}
      {%- if current.level == level.level -%}{%- assign count = count | plus: 1 -%}{%- endif -%}
    {%- endfor %}
    <tr>
      <td><span class="badge level-{{ level.level }}"><span class="badge-number">{{ level.level }}</span>{{ level.name }}</span></td>
      <td>{{ count }}</td>
    </tr>
  {%- endfor %}
  </tbody>
</table>
</div>

See [the compatibility table]({{ '/compatibility/' | relative_url }}) for every app,
or [the repository on GitHub]({{ site.repository_url }}) for Perry itself.
To add a report, read [Contributing]({{ '/contributing/' | relative_url }}).
