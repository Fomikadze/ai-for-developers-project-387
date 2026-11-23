import { expect, type APIRequestContext, type Page } from '@playwright/test';

const ZONE = 'Asia/Almaty';

const timeKey = (iso: string) =>
  new Intl.DateTimeFormat('en-GB', {
    timeZone: ZONE,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(new Date(iso));

export interface PickedSlot {
  /** Начало слота, ISO UTC. */
  start: string;
  /** Время `HH:mm` по Asia/Almaty. */
  time: string;
}

/**
 * Берёт случайный день, где слот на `time` (`HH:mm` по Asia/Almaty) ещё свободен.
 * Бэкенд живёт между прогонами, поэтому «первый слот» занят после первого же запуска.
 * Каждый тест использует своё время суток, так параллельные тесты не борются за один слот.
 */
export async function pickFreeSlot(
  request: APIRequestContext,
  typeId: string,
  time: string,
): Promise<PickedSlot> {
  const response = await request.get(`/api/meeting-types/${typeId}/slots`);
  expect(response.ok()).toBeTruthy();
  const free = ((await response.json()) as { start: string }[]).map((slot) => slot.start);
  const candidates = free.filter((start) => timeKey(start) === time);
  expect(candidates, `нет свободных слотов на ${time}`).not.toHaveLength(0);
  const start = candidates[Math.floor(Math.random() * candidates.length)];
  return { start, time };
}

/**
 * Выбирает день слота в календаре. Окно записи может переходить на следующий месяц,
 * поэтому день ищется по дате, а если его нет на текущей странице — листаем вперёд.
 */
export async function openDay(page: Page, slot: PickedSlot, lng = 'ru'): Promise<void> {
  const date = new Intl.DateTimeFormat(lng, {
    timeZone: ZONE,
    day: 'numeric',
    month: 'long',
  }).format(new Date(slot.start));
  const day = page.getByRole('button', { name: new RegExp(`^${date}, `) });
  const nextMonth = page.getByRole('button', { name: /^(Следующий месяц|Next month)$/ });
  await expect(nextMonth).toBeVisible();
  if ((await day.count()) === 0) {
    await nextMonth.click();
  }
  await day.click();
}
