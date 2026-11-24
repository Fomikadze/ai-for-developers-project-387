# Инструменты: mise, git-хуки, daemons, CI, smoke-тест

## mise

Версии инструментов (JDK, Node, pnpm, hk, pitchfork и инструменты проверок) и задачи проекта лежат в `mise.toml`. Это единственное место, где задаются версии: CI ставит их через `jdx/mise-action` и запускает те же задачи, что и локально.

- `mise install` ставит инструменты, `mise tasks` показывает задачи.
- `mise run check` — полная проверка, ровно то, что выполняет CI: `lint`, `lint:repo`, `lint:links`, `lint:commits`, `contract:check`, `test`, `security`, `api:breaking`, затем `coverage:diff`, `smoke` и `e2e:run`. Нужны сеть и свободные порты 8080 и 5173.
- `mise run local-check` — быстрая версия для работы без сети и серверов: `lint`, `lint:repo`, `test`, `security`, `api:breaking`, затем `coverage:diff`.
- Задачи `lint:*` и `test:*` для `backend`, `frontend` и `typespec` пропускаются с сообщением, пока нет `gradlew` или `package.json`.
- Основные задачи: `mise run lint`, `mise run test`, `mise run sdk`, `mise run backend:run`, `mise run frontend:dev`, `mise run e2e`, `mise run e2e:run`, `mise run smoke`.
- `mise run e2e` только запускает Playwright и ждёт уже поднятые серверы (`mise daemons start`). `mise run e2e:run` сам поднимает daemons, ставит браузер Chromium, гоняет тесты и останавливает серверы; её вызывают `check` и CI. В `local-check` она не входит.

## Git-хуки (hk)

hk ставится через mise, конфигурация — `hk.pkl` в корне. Хуки вызывают те же задачи mise, что и CI:

| Хук | Что запускает |
| --- | --- |
| `pre-commit` | линтеры `backend`, `frontend`, `contract`, `workflows`, `schemas`, `docker`, `markdown`, `typos`; `security:secrets:staged` |
| `commit-msg` | `commitlint` |
| `pre-push` | `test:backend`, `test:frontend`, `api:breaking`, `security:deps` |
| `check` (вручную: `hk check`) | то же, что `pre-commit` |

- Шаг с `glob` запускается, только если в изменениях есть подходящие файлы (`backend/**`, `*.md`, `Dockerfile*` и т. д.). Typos, поиск секретов и проверка зависимостей запускаются всегда.
- Установка хуков один раз после клонирования: `mise run hooks:install` (`hk install --mise`).
- Новая проверка добавляется как задача mise, а в `hk.pkl` — шаг, который её вызывает. Команды проверок в `hk.pkl` не дублируются.

## Проверки качества

| Инструмент | Задача mise | Что проверяет | Конфигурация |
| --- | --- | --- | --- |
| jactionlint (с shellcheck) | `lint:workflows` | корректность и безопасность workflow GitHub Actions, профиль `default`, `--strict-exit` | `.github/jactionlint.yaml` |
| check-jsonschema | `lint:schemas` | workflow, `renovate.json` и конфигурация release-please по официальным схемам | — |
| hadolint | `lint:docker` | все `Dockerfile*` в репозитории | — |
| rumdl | `lint:markdown` | Markdown | `.rumdl.toml` |
| typos | `lint:typos` | опечатки в коде и документации (английский) | — |
| lychee | `lint:links` | битые ссылки и якоря в Markdown, нужна сеть | — |
| commitlint | `lint:commits`, хук `commit-msg` | сообщения коммитов | `commitlint.config.mjs` |
| betterleaks | `security:secrets`, `security:secrets:staged` | секреты в истории git и в проиндексированных изменениях | — |
| OSV-Scanner | `security:deps` | известные уязвимости в зависимостях по lock-файлам | — |
| tsp compile + git diff | `contract:check` | закоммиченный `typespec/openapi.yaml` совпадает с результатом генерации из `typespec/main.tsp`; сравнивает с проиндексированным файлом, поэтому падает, если `openapi.yaml` правили руками или забыли перегенерировать и добавить в коммит | — |
| oasdiff | `api:breaking` | ломающие изменения `typespec/openapi.yaml` относительно `origin/main`; новый код ошибки — предупреждение, а не ошибка | `scripts/api-breaking.sh`, уровни правил в `scripts/oasdiff-severity-levels.txt` |
| diff-cover | `coverage:diff` | покрытие изменённых строк, порог 80% | `scripts/coverage-diff.sh` |
| release-please | — | релизный PR, `CHANGELOG.md` и теги | `release-please-config.json`, `.release-please-manifest.json`, `.github/workflows/release-please.yml` |
| Renovate | — | обновления зависимостей и версий в `mise.toml` через PR | `renovate.json` |

Группы: `mise run lint:repo` (workflows, schemas, docker, markdown, typos), `mise run security` (секреты и зависимости).

- Коммиты пишутся по Conventional Commits: `тип(область): описание`. Типы: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`. Заголовок до 100 символов, без точки в конце.
- `api:breaking` и `coverage:diff` пропускают проверку, пока нет `openapi.yaml` в `origin/main` или отчётов о покрытии. Отчёты ожидаются в Cobertura: `backend/build/reports/kover/report.xml` (Kover) и `frontend/coverage/cobertura-coverage.xml` (Vitest).
- `security:deps` не падает, пока в репозитории нет lock-файлов.
- Renovate работает как GitHub App: его нужно установить в репозиторий на GitHub. CLI Renovate через mise не ставится: установка `npm:renovate@44.194.0` блокируется проверкой цепочки поставок mise (у зависимости `@yarnpkg/libzip@3.2.2` нет provenance), поэтому `renovate.json` проверяется только по схеме.
- detekt, ArchUnit и stylelint подключаются не через mise, а как зависимости проектов (см. [stack.md](stack.md)).

## Daemons (фоновые серверы разработки)

Серверы разработки описаны в `[daemons]` в `mise.toml` и управляются pitchfork. Для этого в `[settings]` включено `experimental = true`, а версия pitchfork зафиксирована в `[tools]`.

| Daemon | Задача | Готов, когда |
| --- | --- | --- |
| `backend` | `backend:run` | открыт порт 8080 |
| `frontend` | `frontend:dev` | открыт порт 5173; стартует после `backend` |

Группа `default` = `backend` + `frontend`.

- `mise daemons start` — запустить оба и дождаться готовности; `mise daemons start backend` — только бэкенд.
- `mise daemons stop` — остановить; `mise daemons restart` — перезапустить.
- `mise daemons ls` / `mise daemons status` — состояние; `mise daemons logs backend` — вывод.
- Агент запускает серверы только через daemons, а не фоновым `./gradlew run &` или `pnpm dev &`.

## Релизы

Релизы выпускает release-please (GitHub Action `googleapis/release-please-action`, workflow `.github/workflows/release-please.yml`).

- После каждого пуша в `main` action по Conventional Commits с прошлого релиза поддерживает открытый **релизный PR** с заголовком `chore(main): release X.Y.Z`. В нём следующая версия, дописанный `CHANGELOG.md` и обновлённый `.release-please-manifest.json`.
- Мёрж релизного PR ставит тег `vX.Y.Z` и создаёт GitHub Release с тем же текстом. Сборки и публикации артефактов после релиза пока нет: событие релиза станет точкой подключения Docker позже.
- Конфигурация — `release-please-config.json` и `.release-please-manifest.json` в корне. Схему конфигурации проверяет `lint:schemas` по локальной копии `schemas/release-please-config.schema.json` (версия release-please v17.11.2, чтобы проверка работала без сети; при обновлении release-please копию надо заменить вручную). Версия одна на всё приложение (тип пакета `simple`, корень репозитория), версия API в `typespec/main.tsp` с ней не связана. Отсчёт идёт с `bootstrap-sha` (последний коммит `main` до переноса приложения, `ec5db83`): релизы `0.1.0`–`0.3.0` и их теги остались в первом проекте (см. [previous-project.md](previous-project.md)), `CHANGELOG.md` начат здесь заново. Номер первого релиза здесь задаёт `initial-version` (`0.4.0`): без него release-please для первого релиза берёт `1.0.0`, независимо от манифеста. Если сдвинуть `bootstrap-sha` на коммит без `feat` и `fix` после него, релизный PR не откроется: release-please пропускает историю без пользовательских изменений. После мёржа первого релизного PR `bootstrap-sha` можно удалить.
- Влияние коммитов на версию: `feat` повышает минорную, `fix`, `perf` и `revert` — патчевую версию. Ломающее изменение (`!` после типа или `BREAKING CHANGE:` в теле) до `1.0.0` тоже повышает минорную (`bump-minor-pre-major`). В ченджлог попадают секции «Возможности» (`feat`), «Исправления» (`fix`), «Производительность» (`perf`), «Откаты» (`revert`); остальные типы скрыты.
- `CHANGELOG.md` исключён из `lint:markdown` (формат генератора) и из `lint:typos` (`_typos.toml`: хеши коммитов в ссылках дают ложные срабатывания).
- `lint:links` пропускает ссылки `compare/vA...vB` (`lychee.toml`): release-please пишет их в `CHANGELOG.md` до создания тега `vB`, и в релизном PR они отдают 404.
- В настройках репозитория должна быть включена опция «Allow GitHub Actions to create and approve pull requests» (Settings → Actions → General), иначе релизный PR не создастся.
- Токен — встроенный `GITHUB_TOKEN` с правами `contents: write` и `pull-requests: write`. Ограничение: PR, созданный этим токеном, не запускает другие workflow, поэтому `check.yml` на релизном PR не стартует. Пока это приемлемо, релизный PR меняет только ченджлог и манифест. Если проверки понадобятся, нужен токен GitHub App или PAT в секретах репозитория — отдельное решение владельца.

## CI

- `hexlet-check.yml` — автоматические тесты Хекслета, не трогаем и не меняем.
- `.github/workflows/check.yml` — один job: `mise run install`, затем `mise run check`. Запускается на push в `main` и на pull request, полная история git нужна для `lint:commits`, `api:breaking`, `coverage:diff` и поиска секретов.
- Задачи `lint:*`, `test:*` и `mise run install` пропускают `backend`, `frontend` и `typespec`, пока нет `gradlew` или `package.json`.
- В `frontend/` и `typespec/` должен быть закоммичен `pnpm-lock.yaml`. Скрипты во `frontend/package.json`: `lint`, `format:check`, `typecheck`, `generate`, `test`, `dev`.
- Actions закрепляются полным SHA, исходная версия пишется в комментарии (`# v7.0.1`).
- Исключения jactionlint пишутся только в `ignores` файла `.github/jactionlint.yaml` с правилом, путём, причиной и датой `expires`. Сейчас одно: `dangerous-triggers` для `claudecode.yml`, пересмотр до 2027-02-24. После этой даты проверка падает (`expired-ignore`), лишнее исключение тоже ошибка (`unused-ignore`). Файл `hexlet-check.yml` помечен как автогенерируемый, поэтому jactionlint не применяет к нему правила групп `policy` и `style` (поведение `skip-policy`). Остальные проверки для него работают.

### Claude Code по комментариям

`.github/workflows/claudecode.yml` запускает [Claude Code Action](https://code.claude.com/docs/en/github-actions) по комментарию с `@claude` в issue или PR.

- Запуск разрешён людям с ролью OWNER, MEMBER или COLLABORATOR, право записи action проверяет сам. На PR из форка job завершается ошибкой до запуска агента.
- Модель `claude-opus-5-5`, провайдер Anthropic по подписке: секрет `CLAUDE_CODE_OAUTH_TOKEN` и установленный Claude GitHub App. Токен из `claude setup-token` действует год.
- `GITHUB_TOKEN` только читает, `id-token: write` нужен для обмена на токен App. Права самого App шире: он может пушить ветки.
- До 60 ходов, таймаут 30 минут. По `issue_comment` GitHub берёт workflow из `main`: правка лимита в другой ветке не действует, а Re-run старого запуска использует прежний лимит, нужен новый комментарий.
- Запуски по одной задаче идут по очереди (`concurrency` на уровне job), чужие комментарии без доступа в очередь не попадают.

### Автотриаж новых обращений

`.github/workflows/issue-triage.yml` запускается на `issues: [opened]`. Фильтр по автору и меткам стоит в `if` задачи `analyze`, готовые тикеты он пропускает.

- `analyze` — агент с инструментами `Read`, `Glob`, `Grep` и токеном только на чтение (`contents`, `issues`). Токен Claude GitHub App не запрашивается (`id-token` нет). Обращение передаётся файлом `.triage/issue.json`, ответ приходит по JSON-схеме. До 20 ходов, таймаут 10 минут.
- `apply` — `scripts/triage-apply.sh` без агента, единственный с правом `issues: write`, таймаут 5 минут. Проверяет ответ по белому списку значений, заново читает состояние issue (если его уже разобрали или закрыли, ничего не меняет), пишет комментарий и ставит метки.
- Запуски по одному issue идут по очереди. Комментарии и метки от `GITHUB_TOKEN` другие workflow не запускают.
- Обращения людей без доступа к репозиторию не разбираются: чужой текст не должен запускать агента и тратить подписку.

### Независимое авторевью PR

`.github/workflows/pr-review.yml` запускается на `pull_request: [opened, synchronize, reopened, ready_for_review]`. Фильтр в `if` задачи `review`: PR из этого репозитория, не черновик, автор — человек.

- Права на уровне workflow пустые (`permissions: {}`), каждый job получает только нужное.
- `review` — агент с инструментами `Read`, `Glob`, `Grep` и токеном только на чтение (`contents`, `pull-requests`). Токен Claude GitHub App не запрашивается (`id-token` нет). Описание PR, diff и `REVIEW.md` базовой ветки передаются файлами в `.review/`, ответ приходит по JSON-схеме, в которой поля формата замечания обязательны. До 40 ходов, таймаут 20 минут.
- `publish` — `scripts/pr-review-publish.sh` без агента, единственный с правом `pull-requests: write`, таймаут 5 минут. Проверяет ответ (все поля, строка как `42` или `42-48`, важность из белого списка), заново читает PR (если он закрыт или в нём новый коммит, ничего не публикует) и создаёт или обновляет один комментарий с маркером `<!-- pr-review -->`.
- `concurrency` на уровне workflow с `cancel-in-progress: true`: новый push в PR отменяет устаревшее ревью вместе с публикацией.
- `pull_request`, а не `pull_request_target`: код PR выполняется без секретов базовой ветки, поэтому исключение в `.github/jactionlint.yaml` не нужно. PR из форков секрет не получают и пропускаются.
- Скрипт публикации берётся из ветки PR. Это допустимо, потому что `publish` идёт только после `review`, то есть для веток этого репозитория, куда автор и так может пушить.

## Docker

Корневой `Dockerfile` собирает один образ в три стадии: фронтенд (pnpm, SDK генерируется из `typespec/openapi.yaml`), бэкенд (`./gradlew :presentation:installDist`) и рантайм на `eclipse-temurin:21-jre`. Бэкенд отдаёт API и собранный фронтенд из каталога `STATIC_DIR` (в образе `/app/static`, любой неизвестный путь возвращает `index.html`). Без `STATIC_DIR` статика не раздаётся, поэтому разработка и тесты не меняются. Процесс работает от пользователя `10001`, порт — `8080` (переменная `PORT`).

```bash
docker compose up --build   # приложение на http://localhost:8080
```

Образ собирают проверка Хекслета (`hexlet-check`) и `docker compose`. Dockerfile проверяет `lint:docker` (hadolint).

## Smoke-тест

`scripts/smoke.sh` запускает бэкенд (`./gradlew run` в `backend/`, порт 8080) и ждёт ответ `200` от `GET /api/health` (до 120 с). Входит в `mise run check`, отдельно запускается как `mise run smoke`. Переменные: `APP_CMD`, `APP_DIR`, `SMOKE_URL`, `TIMEOUT`. Gradle запускается на JDK из `mise.toml` (Temurin 21), поэтому вызывайте его через `mise run` или `mise x -- ./gradlew`.
