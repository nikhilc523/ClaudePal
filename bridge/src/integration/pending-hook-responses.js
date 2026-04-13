export class PendingHookResponses {
  constructor() {
    this.waiters = new Map();
  }

  waitForDecision(decisionId, timeoutMs) {
    return new Promise((resolve) => {
      const entry = {
        resolve,
        timeoutId: setTimeout(() => {
          this.remove(decisionId, entry);
          resolve({
            type: "timeout"
          });
        }, timeoutMs)
      };

      const currentEntries = this.waiters.get(decisionId) ?? [];
      currentEntries.push(entry);
      this.waiters.set(decisionId, currentEntries);
    });
  }

  resolve(decisionId, payload) {
    const entries = this.waiters.get(decisionId) ?? [];

    for (const entry of entries) {
      clearTimeout(entry.timeoutId);
      entry.resolve({
        type: "resolved",
        payload
      });
    }

    this.waiters.delete(decisionId);
  }

  remove(decisionId, entry) {
    const entries = this.waiters.get(decisionId) ?? [];
    const nextEntries = entries.filter((candidate) => candidate !== entry);

    if (nextEntries.length === 0) {
      this.waiters.delete(decisionId);
      return;
    }

    this.waiters.set(decisionId, nextEntries);
  }

  close() {
    for (const [decisionId, entries] of this.waiters.entries()) {
      for (const entry of entries) {
        clearTimeout(entry.timeoutId);
        entry.resolve({
          type: "closed"
        });
      }

      this.waiters.delete(decisionId);
    }
  }
}
