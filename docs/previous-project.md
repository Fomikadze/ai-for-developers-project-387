# Исходный проект: спецификация и решения

Приложение перенесено из репозитория [Fomikadze/ai-for-developers-project-386](https://github.com/Fomikadze/ai-for-developers-project-386) (коммит [`147120b`](https://github.com/Fomikadze/ai-for-developers-project-386/tree/147120b), версия `0.3.0`). Файлы перенесены снимком, история коммитов, тикеты и PR остались там.

Новые тикеты заводятся только в трекере этого репозитория (см. [agents/issue-tracker.md](agents/issue-tracker.md)). Старые тикеты читаются по полным ссылкам: короткий `#N` здесь означает тикет нового репозитория.

## Спецификация

| Тикет | Что в нём |
| --- | --- |
| [386#6](https://github.com/Fomikadze/ai-for-developers-project-386/issues/6) | карта: проектирование брони, сводка решений |
| [386#18](https://github.com/Fomikadze/ai-for-developers-project-386/issues/18) | исходная спецификация: запись на звонок, бэкенд, фронтенд и e2e |
| [386#57](https://github.com/Fomikadze/ai-for-developers-project-386/issues/57) | спецификация доработки по приёмке: деплой, ADR, правила агента |

Действующее поведение описано в [requirements.md](requirements.md), [schedule.md](schedule.md) и [api.md](api.md).

## Решения

| Тикет | Решение |
| --- | --- |
| [386#7](https://github.com/Fomikadze/ai-for-developers-project-386/issues/7) | базовые правила брони, расписания и данных API |
| [386#8](https://github.com/Fomikadze/ai-for-developers-project-386/issues/8) | исследование: проверка имени и email ([отчёт](../research/guest-name-email-validation.md)) |
| [386#9](https://github.com/Fomikadze/ai-for-developers-project-386/issues/9) | исследование: TypeSpec и hey-api ([отчёт](../research/typespec-hey-api.md)) |
| [386#10](https://github.com/Fomikadze/ai-for-developers-project-386/issues/10) | правила проверки имени и email гостя |
| [386#11](https://github.com/Fomikadze/ai-for-developers-project-386/issues/11) | чтение типа встречи по id и детали ошибки валидации |
| [386#12](https://github.com/Fomikadze/ai-for-developers-project-386/issues/12) | контракт TypeSpec для типов встреч, слотов и броней |
| [386#14](https://github.com/Fomikadze/ai-for-developers-project-386/issues/14) | добавление кода ошибки в `api:breaking` |
| [386#16](https://github.com/Fomikadze/ai-for-developers-project-386/issues/16) | примеры ошибочных ответов в контракте |
| [386#59](https://github.com/Fomikadze/ai-for-developers-project-386/issues/59) | ADR [0001](adr/0001-in-memory-storage-with-mutex.md), [0002](adr/0002-ktor-without-server-generator.md), [0003](adr/0003-utc-instants-owner-timezone.md) |
| [386#67](https://github.com/Fomikadze/ai-for-developers-project-386/issues/67), [386#68](https://github.com/Fomikadze/ai-for-developers-project-386/issues/68) | одно правило пересечения интервалов и нейтральный `TimeRange` |

Словарь предметной области — [GLOSSARY.md](../GLOSSARY.md).

## Релизы

Версии `0.1.0`–`0.3.0` и их описание — в [CHANGELOG.md первого проекта](https://github.com/Fomikadze/ai-for-developers-project-386/blob/main/CHANGELOG.md). Записи о новых релизах release-please добавляет в [CHANGELOG.md](../CHANGELOG.md) этого репозитория.
