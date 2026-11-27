// Staging only, deliberately finite and independent of production admission.
export class StagingAdmission27 {
  active = 0;
  private minute = -1;
  private admissions = 0;
  constructor(readonly concurrent = 32, readonly perMinute = 20000) {
    if (!Number.isSafeInteger(concurrent) || concurrent < 1 || concurrent > 64 ||
        !Number.isSafeInteger(perMinute) || perMinute < 1 || perMinute > 100000) throw new Error('finite staging limits required');
  }
  enter(now = Date.now()) {
    const minute = Math.floor(now / 60000);
    if (minute !== this.minute) { this.minute = minute; this.admissions = 0; }
    if (this.active >= this.concurrent || this.admissions >= this.perMinute) return false;
    this.admissions++; this.active++; return true;
  }
  leave() { if (this.active < 1) throw new Error('unbalanced admission'); this.active--; }
}
