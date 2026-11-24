#!/usr/bin/env bash
# Сверяет решение агента (calendar-audit.yml) с отчётом и публикует находки в Issues.
# Ключ находки — «проверка/вид сбоя» из отчёта, а не текст агента: повтор ищется среди
# открытых и закрытых Issues, созданных этим воркфлоу.
# Переменные: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA, RUN_URL, REPORT, AUDIT_DECISION.
set -euo pipefail

fail() {
  echo "::error::$1"
  exit 1
}

summary() { echo "$1" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"; }

# Отчёт должен относиться к этому коммиту и быть согласован сам с собой.
jq -e --arg sha "$GITHUB_SHA" '
  .commit == $sha and (.checks | type == "array" and length > 0) and
  (.checks | all((.id | test("^[a-z0-9-]+$")) and (.kind | test("^[a-z0-9-]+$")) and .ok == (.kind == "ok"))) and
  ((.checks | map(.id)) as $ids | ($ids | unique | length) == ($ids | length)) and
  .failed == ([.checks[] | select(.ok | not)] | length)
' "$REPORT" >/dev/null || fail "Отчёт повреждён или собран для другого коммита"

# Ответ агента недоверенный: сначала форма, затем сверка с отчётом.
jq -e '
  (.verdict | IN("ok", "problems")) and (.summary | type == "string" and length > 0) and
  (.findings | type == "array" and all(
    (.checks | type == "array" and length > 0 and all(type == "string")) and
    (.severity | IN("blocker", "major", "minor")) and
    ([.title, .analysis, .recommendation] | all(type == "string" and length > 0))))
' <<<"$AUDIT_DECISION" >/dev/null || fail "Ответ агента не прошёл проверку формата"

# Каждая проваленная проверка указана ровно в одной находке, прошедших и выдуманных нет.
jq -e --slurpfile report "$REPORT" '
  ([$report[0].checks[] | select(.ok | not) | .id] | sort) as $failed |
  ([.findings[].checks[]] | sort) == $failed and
  .verdict == (if $failed == [] then "ok" else "problems" end)
' <<<"$AUDIT_DECISION" >/dev/null || fail "Решение агента расходится с отчётом"

if [ "$(jq .failed "$REPORT")" -eq 0 ]; then
  summary "Calendar audit: все проверки пройдены, Issue не нужен"
  exit 0
fi

# Список, а не поиск: индекс поиска отстаёт. Чужие issue не в счёт, маркер в них можно подделать.
issues="$(gh api --paginate "repos/$GITHUB_REPOSITORY/issues?state=all&per_page=100" |
  jq -s '[.[][] | select(.pull_request == null and .user.login == "github-actions[bot]")
    | {number, state, keys: [(.body // "") | scan("<!-- calendar-audit: ([a-z0-9-]+/[a-z0-9-]+) -->") | .[0]]}]')"

plan="$(jq -c --slurpfile report "$REPORT" --argjson issues "$issues" '
  ($report[0].checks | map({key: .id, value: .}) | from_entries) as $checks |
  .findings[] | . as $finding |
  [.checks[] | $checks[.] | . + {key: "\(.id)/\(.kind)"} | . as $c
    | . + {known: [$issues[] | select(.keys | index($c.key)) | "#\(.number) (\(.state))"]}] as $all |
  $finding + {new: [$all[] | select(.known == [])], known: [$all[] | select(.known != [])]}
' <<<"$AUDIT_DECISION")"

while IFS= read -r finding; do
  while IFS= read -r line; do
    [ -z "$line" ] || summary "$line"
  done < <(jq -r '.known[] | "Уже есть: `\(.key)` в \(.known | join(", "))"' <<<"$finding")
  [ "$(jq '.new | length' <<<"$finding")" -gt 0 ] || continue

  title="$(jq -r '"Calendar audit: " + (.title | gsub("\\s+"; " ") | gsub("@"; "@​") | .[0:120])' <<<"$finding")"
  # Проверки берутся из отчёта, тексты агента обезврежены и ограничены по длине.
  body="$(jq -r --arg sha "$GITHUB_SHA" --arg url "$RUN_URL" '
    def clean: gsub("\\s+"; " ") | gsub("@"; "@​") | gsub("<"; "&lt;") | .[0:1500];
    def cell: gsub("\\|"; "\\|") | gsub("\n"; " ");
    ["> *Создано автоматически: Calendar audit, анализ выполнен ИИ.*", "",
     "**Коммит:** \($sha)", "**Прогон и отчёт:** \($url)", "**Важность:** `\(.severity)`", "",
     "| Проверка | Запрос | Ожидалось | Сбой |", "| --- | --- | --- | --- |"]
    + (.new | map("| `\(.id)` | `\(.path | cell)` | \(.expected | cell) | `\(.kind)` |"))
    + ["", "## Анализ", "", (.analysis | clean), "", "## Что сделать", "", (.recommendation | clean), ""]
    + (.new | map("<!-- calendar-audit: \(.key) -->"))
    | join("\n")' <<<"$finding")"
  created="$(gh issue create --repo "$GITHUB_REPOSITORY" --title "$title" --body "$body" \
    --label bug --label needs-triage </dev/null)"
  summary "Создано: $created"
done <<<"$plan"
