#!/usr/bin/env bash
# Shared by the scripts that write text from a file or a model into Markdown.
# The model's text goes into Markdown as plain text: no HTML, no links, no
# images (a link or an image the job summary would load), one line, capped.
plain() {
  local text="${1//$'\n'/ }"
  # A bare & in a replacement is the matched text (bash 5.2): escaped.
  text="${text//&/\&amp;}"
  text="${text//</\&lt;}"
  text="${text//>/\&gt;}"
  text="${text//\[/\\[}"
  text="${text//\]/\\]}"
  # A | would end a table cell.
  text="${text//|/\\|}"
  printf '%s' "${text:0:600}"
}
