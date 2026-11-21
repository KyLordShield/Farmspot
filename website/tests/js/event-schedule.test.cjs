const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const context = { module: { exports: {} }, Intl, Date };
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../../public/js/event-schedule.js'), 'utf8'), context);
const schedule = context.module.exports;

test('quick dates respect Philippine midnight and month/year boundaries', () => {
    assert.equal(schedule.todayInManila(new Date('2026-11-21T16:01:00Z')), '2026-11-22');
    assert.equal(schedule.addDays('2026-12-31', 1), '2027-01-01');
    assert.equal(schedule.addDays('2028-02-28', 1), '2028-02-29');
    assert.equal(schedule.combine('2027-01-01', '13:00'), '2027-01-01T13:00');
    assert.equal(schedule.combine('', '09:00'), '');
    assert.equal(schedule.combine('2027-01-01', '25:00'), '');
});

test('quick choices and custom edits submit the exact visible schedule', () => {
    function element(extra = {}) {
        return Object.assign({ value: '', listeners: {}, attrs: {}, hidden: false,
            addEventListener(type, callback) { this.listeners[type] = callback; },
            setAttribute(key, value) { this.attrs[key] = value; },
        }, extra);
    }
    const dates = [0, 1, 7].map(n => element({ dataset: { eventDay: String(n) } }));
    const times = ['09:00', '13:00', '15:00'].map(time => element({ dataset: { eventTime: time } }));
    const elements = {
        eventForm: element(), eventDate: element({ value: '2030-01-05T10:45' }),
        eventDay: element(), eventTime: element(), eventSchedulePreview: element(),
        eventDateFallback: element(),
        eventSchedule: element({ querySelectorAll: selector => selector.includes('day') ? dates : times }),
    };
    schedule.init({ getElementById: id => elements[id] });
    assert.equal(elements.eventDate.type, 'hidden');
    assert.equal(elements.eventDateFallback.hidden, true);
    assert.equal(elements.eventSchedule.hidden, false);
    assert.equal(elements.eventDay.value, '2030-01-05');
    assert.equal(elements.eventTime.value, '10:45');
    assert.match(elements.eventSchedulePreview.textContent, /Philippine time/);
    dates[1].listeners.click();
    times[1].listeners.click();
    const tomorrow = schedule.addDays(schedule.todayInManila(), 1);
    assert.equal(elements.eventDate.value, tomorrow + 'T13:00');
    assert.equal(dates[1].attrs['aria-pressed'], 'true');
    assert.equal(times[1].attrs['aria-pressed'], 'true');
    elements.eventTime.value = '14:17';
    elements.eventTime.listeners.change();
    assert.equal(elements.eventDate.value, tomorrow + 'T14:17');
    assert.equal(times[1].attrs['aria-pressed'], 'false');
    elements.eventDate.value = '2031-04-07T16:30';
    elements.eventDate.listeners.change();
    assert.equal(elements.eventDay.value, '2031-04-07');
    assert.equal(elements.eventTime.value, '16:30');
    elements.eventDay.value = '';
    elements.eventForm.listeners.submit();
    assert.equal(elements.eventDate.value, '');
    assert.match(elements.eventSchedulePreview.textContent, /Choose a date/);
});
