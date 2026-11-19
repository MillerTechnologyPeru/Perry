---
title: Compatibility
---

# Compatibility

Each app's level is the level of its newest report. Every report comes from
a merged pull request, which the Last tested column links to.

<ul class="level-list">
{%- for level in site.data.levels %}
  <li><span class="badge level-{{ level.level }}"><span class="badge-number">{{ level.level }}</span>{{ level.name }}</span> {{ level.description }}</li>
{%- endfor %}
</ul>

{% assign platforms = "ios:iOS,macos:macOS,catalyst:Mac Catalyst" | split: "," -%}
{%- assign apps = site.apps | sort_natural: "name" -%}
{%- for pair in platforms -%}
{%- assign parts = pair | split: ":" -%}
{%- assign platform_apps = apps | where: "platform", parts[0] -%}
{%- if platform_apps.size > 0 %}
<h2 id="{{ parts[0] }}">{{ parts[1] }}</h2>

<div class="table-wrap">
<table class="app-table">
  <thead>
    <tr>
      <th>Name</th>
      <th>Kind</th>
      <th>Architectures</th>
      <th>Level</th>
      <th>Last tested</th>
      <th>Notes</th>
      <th>Screenshot</th>
    </tr>
  </thead>
  <tbody>
  {%- for app in platform_apps %}
    {%- assign current = app.reports | last -%}
    {%- assign level = site.data.levels | where: "level", current.level | first -%}
    {%- assign archs = "" | split: "" -%}
    {%- for report in app.reports -%}
      {%- if report.arch -%}{%- assign archs = archs | push: report.arch -%}{%- endif -%}
    {%- endfor -%}
    {%- assign shot = current.screenshots | first %}
    <tr>
      <td><a href="{{ app.url | relative_url }}">{{ app.name | escape }}</a></td>
      <td>{{ app.kind | capitalize }}</td>
      <td>{{ archs | uniq | join: ", " }}</td>
      <td><span class="badge level-{{ current.level }}"><span class="badge-number">{{ current.level }}</span>{{ level.name }}</span></td>
      <td class="nowrap">{{ current.date | date: "%Y-%m-%d" }}<br><a href="https://github.com/MillerTechnologyPeru/Perry/pull/{{ current.pr }}">#{{ current.pr }}</a></td>
      <td class="notes">{{ current.notes | escape }}</td>
      <td>{% if shot %}<a href="{{ app.url | relative_url }}"><img src="{{ shot.url }}" alt="{{ shot.caption | escape }}" width="160" loading="lazy"></a>{% endif %}</td>
    </tr>
  {%- endfor %}
  </tbody>
</table>
</div>
{%- endif -%}
{%- endfor %}
