#!/usr/bin/env bash
# Публикует результат авторевью (pr-review.yml): проверяет ответ агента по формату
# замечания из REVIEW.md и пишет или обновляет один комментарий в PR.
# Переменные: GH_TOKEN, GITHUB_REPOSITORY, PR_NUMBER, HEAD_SHA, REVIEW_RESULT.
set -euo pipefail

marker='<!-- pr-review -->'

# Ответ агента недоверенный: каждое замечание обязано содержать все поля формата.
if ! jq -e '
  (.summary | type == "string" and length > 0) and
  (.findings | type == "array" and all(
    ([.file, .rule, .condition, .consequence] | all(type == "string" and length > 0)) and
    (.line | type == "string" and test("^[1-9][0-9]*(-[1-9][0-9]*)?$")) and
    (.severity | IN("blocker", "major", "minor"))
  ))
' <<<"$REVIEW_RESULT" >/dev/null; then
  echo "::error::Ответ агента не прошёл проверку формата замечания"
  exit 1
fi

# Пока агент работал, в PR могли запушить: ревью старого коммита не публикуем.
pr="$(gh pr view "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --json state,headRefOid)"
if ! jq -e --arg sha "$HEAD_SHA" '.state == "OPEN" and .headRefOid == $sha' <<<"$pr" >/dev/null; then
  echo "PR закрыт или в нём новый коммит, ревью устарело"
  exit 0
fi

body="$(jq -r --arg marker "$marker" --arg sha "$HEAD_SHA" '
  def esc: gsub("\\|"; "\\|") | gsub("\n"; " ");
  def sev: {blocker: "🔴 blocker", major: "🟠 major", minor: "🟡 minor"}[.];
  [
    $marker,
    "### Авторевью по REVIEW.md",
    "",
    "> Сгенерировано ИИ для коммита `\($sha[0:7])`. Ревью рекомендательное и не блокирует мерж.",
    "",
    .summary,
    "",
    if (.findings | length) == 0 then
      "Замечаний по правилам `REVIEW.md` нет."
    else
      "| Важность | Файл и строка | Правило | Условия ошибки | Последствие |",
      "| --- | --- | --- | --- | --- |",
      (.findings | sort_by({blocker: 0, major: 1, minor: 2}[.severity]) | .[] |
        "| \(.severity | sev) | `\(.file | esc):\(.line)` | \(.rule | esc) | \(.condition | esc) | \(.consequence | esc) |")
    end
  ] | join("\n")
' <<<"$REVIEW_RESULT")"

comment_id="$(gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" \
  --jq ".[] | select(.user.login == \"github-actions[bot]\" and (.body | startswith(\"$marker\"))) | .id" |
  head -n 1)"

if [ -n "$comment_id" ]; then
  gh api --method PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$comment_id" -f body="$body" >/dev/null
else
  gh pr comment "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --body "$body"
fi
