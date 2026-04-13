import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import path from 'node:path';

export class StatsStore {
  #filePath;
  #timeZone;
  #data;
  #loadPromise;
  #writeQueue;

  constructor({ filePath, timeZone }) {
    this.#filePath = filePath;
    this.#timeZone = timeZone;
    this.#data = {
      version: 1,
      updatedAt: null,
      daily: {}
    };
    this.#writeQueue = Promise.resolve();
    this.#loadPromise = this.#load();
  }

  async ready() {
    await this.#loadPromise;
  }

  async increment(type) {
    await this.#loadPromise;

    const today = this.#getDateString(0);
    const row =
      this.#data.daily[today] ||
      (this.#data.daily[today] = {
        date: today,
        playing_count: 0,
        playback_info_count: 0
      });

    if (type === 'playing') {
      row.playing_count += 1;
    } else if (type === 'playback_info') {
      row.playback_info_count += 1;
    }

    this.#data.updatedAt = new Date().toISOString();
    await this.#persist();
  }

  async getStats({ dailyWindow, totalWindow }) {
    await this.#loadPromise;

    const rows = Object.values(this.#data.daily).sort((left, right) => right.date.localeCompare(left.date));
    const totalCutoff = this.#getDateString(-(totalWindow - 1));

    const totals = rows.reduce(
      (accumulator, row) => {
        if (row.date >= totalCutoff) {
          accumulator.playing += row.playing_count;
          accumulator.playbackInfo += row.playback_info_count;
        }

        return accumulator;
      },
      { playing: 0, playbackInfo: 0 }
    );

    return {
      dailyStats: rows.slice(0, dailyWindow),
      total: totals,
      lastUpdated: new Date().toLocaleString('zh-CN', { timeZone: this.#timeZone })
    };
  }

  async #load() {
    await mkdir(path.dirname(this.#filePath), { recursive: true });

    try {
      const raw = await readFile(this.#filePath, 'utf8');
      const parsed = JSON.parse(raw);

      if (parsed && typeof parsed === 'object' && parsed.daily && typeof parsed.daily === 'object') {
        this.#data = {
          version: parsed.version || 1,
          updatedAt: parsed.updatedAt || null,
          daily: parsed.daily
        };
      }
    } catch (error) {
      if (error.code !== 'ENOENT') {
        throw error;
      }
    }
  }

  async #persist() {
    const payload = JSON.stringify(this.#data, null, 2);
    const tempFile = `${this.#filePath}.tmp`;
    const writeOperation = async () => {
      await mkdir(path.dirname(this.#filePath), { recursive: true });
      await writeFile(tempFile, payload, 'utf8');
      await rename(tempFile, this.#filePath);
    };

    this.#writeQueue = this.#writeQueue.catch(() => undefined).then(writeOperation);

    await this.#writeQueue;
  }

  #getDateString(dayOffset) {
    const currentDate = this.#getCurrentDateParts();
    const baseline = new Date(Date.UTC(currentDate.year, currentDate.month - 1, currentDate.day));
    baseline.setUTCDate(baseline.getUTCDate() + dayOffset);
    return baseline.toISOString().slice(0, 10);
  }

  #getCurrentDateParts() {
    const formatter = new Intl.DateTimeFormat('en-CA', {
      timeZone: this.#timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit'
    });

    const parts = formatter.formatToParts(new Date());
    const lookup = Object.fromEntries(parts.map((part) => [part.type, part.value]));

    return {
      year: Number.parseInt(lookup.year, 10),
      month: Number.parseInt(lookup.month, 10),
      day: Number.parseInt(lookup.day, 10)
    };
  }
}
