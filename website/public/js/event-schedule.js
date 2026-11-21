(function () {
    'use strict';

    function todayInManila(now) {
        var parts = {};
        new Intl.DateTimeFormat('en', {
            timeZone: 'Asia/Manila', year: 'numeric', month: '2-digit', day: '2-digit'
        }).formatToParts(now || new Date()).forEach(function (part) { parts[part.type] = part.value; });
        return parts.year + '-' + parts.month + '-' + parts.day;
    }

    function addDays(day, count) {
        var date = new Date(day + 'T00:00:00Z');
        date.setUTCDate(date.getUTCDate() + count);
        return date.toISOString().slice(0, 10);
    }

    function combine(day, time) {
        return /^\d{4}-\d{2}-\d{2}$/.test(day) && /^([01]\d|2[0-3]):[0-5]\d$/.test(time)
            ? day + 'T' + time : '';
    }

    function init(doc) {
        var form = doc.getElementById('eventForm');
        var input = doc.getElementById('eventDate');
        var controls = doc.getElementById('eventSchedule');
        var day = doc.getElementById('eventDay');
        var time = doc.getElementById('eventTime');
        var preview = doc.getElementById('eventSchedulePreview');
        var fallback = doc.getElementById('eventDateFallback');
        if (!form || !input || !controls || !day || !time || !preview || !fallback) return;

        var dateChoices = controls.querySelectorAll('[data-event-day]');
        var timeChoices = controls.querySelectorAll('[data-event-time]');
        function paint() {
            var today = todayInManila();
            day.min = today;
            dateChoices.forEach(function (button) {
                button.setAttribute('aria-pressed', String(day.value === addDays(today, Number(button.dataset.eventDay))));
            });
            timeChoices.forEach(function (button) {
                button.setAttribute('aria-pressed', String(time.value === button.dataset.eventTime));
            });
            var value = combine(day.value, time.value);
            var date = new Date(value + ':00+08:00');
            preview.textContent = value && !Number.isNaN(date.getTime())
                ? new Intl.DateTimeFormat('en-PH', {
                    timeZone: 'Asia/Manila', weekday: 'short', month: 'short', day: 'numeric',
                    year: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true
                }).format(date) + ' · Philippine time'
                : 'Choose a date and time for your event.';
        }
        function sync() {
            input.value = combine(day.value, time.value);
            paint();
        }
        function read() {
            var parts = input.value.split('T');
            day.value = parts[0] || todayInManila();
            time.value = parts[1] ? parts[1].slice(0, 5) : '09:00';
            paint();
        }
        dateChoices.forEach(function (button) {
            button.addEventListener('click', function () {
                day.value = addDays(todayInManila(), Number(button.dataset.eventDay));
                sync();
            });
        });
        timeChoices.forEach(function (button) {
            button.addEventListener('click', function () {
                time.value = button.dataset.eventTime;
                sync();
            });
        });
        day.addEventListener('change', sync);
        time.addEventListener('change', sync);
        input.addEventListener('change', read);
        form.addEventListener('submit', sync);
        read();
        input.type = 'hidden';
        input.required = false;
        fallback.hidden = true;
        day.required = time.required = true;
        controls.hidden = false;
    }

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = { todayInManila: todayInManila, addDays: addDays, combine: combine, init: init };
    }
    if (typeof document !== 'undefined') init(document);
})();
