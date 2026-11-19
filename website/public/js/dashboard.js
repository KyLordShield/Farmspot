(function () {
    'use strict';

    var grid = document.getElementById('calGrid');
    if (!grid) {
        return;
    }

    var items = JSON.parse(grid.dataset.calendarItems);

    var byDate = {};
    items.forEach(function (item) {
        (byDate[item.date] = byDate[item.date] || []).push(item);
    });

    var label = document.getElementById('calLabel');
    var detail = document.getElementById('calDetail');

    function pad(n) {
        return (n < 10 ? '0' : '') + n;
    }

    function key(date) {
        return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate());
    }

    function escapeHtml(value) {
        return String(value === null || value === undefined ? '' : value)
            .replace(/[&<>"']/g, function (ch) { return '&#' + ch.charCodeAt(0) + ';'; });
    }

    var today = new Date();
    var todayKey = key(today);
    var view = new Date(today.getFullYear(), today.getMonth(), 1);
    var selected = todayKey;

    function renderGrid() {
        label.textContent = view.toLocaleString(undefined, { month: 'long', year: 'numeric' });

        var firstDay = new Date(view.getFullYear(), view.getMonth(), 1).getDay();
        var daysInMonth = new Date(view.getFullYear(), view.getMonth() + 1, 0).getDate();

        var html = '';

        ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].forEach(function (dow) {
            html += '<div class="cal-dow">' + dow + '</div>';
        });

        for (var blank = 0; blank < firstDay; blank++) {
            html += '<div class="cal-day is-empty"></div>';
        }

        for (var day = 1; day <= daysInMonth; day++) {
            var dayKey = view.getFullYear() + '-' + pad(view.getMonth() + 1) + '-' + pad(day);
            var dayItems = byDate[dayKey] || [];

            var classes = 'cal-day';
            if (dayKey === todayKey) { classes += ' is-today'; }
            if (dayKey === selected) { classes += ' is-selected'; }

            var types = {};
            dayItems.forEach(function (item) { types[item.type] = true; });

            var dots = '';
            ['event', 'note', 'task'].forEach(function (type) {
                if (types[type]) {
                    dots += '<span class="cal-dot dot-' + type + '"></span>';
                }
            });

            html += '<button type="button" class="' + classes + '" data-date="' + dayKey + '">'
                + '<span class="cal-daynum">' + day + '</span>'
                + '<span class="cal-dots">' + dots + '</span>'
                + '</button>';
        }

        grid.innerHTML = html;

        grid.querySelectorAll('.cal-day[data-date]').forEach(function (cell) {
            cell.addEventListener('click', function () {
                selected = cell.getAttribute('data-date');
                renderGrid();
            });
        });
    }

    function renderDetail() {
        var dayItems = byDate[selected] || [];
        var heading = new Date(selected + 'T00:00:00').toLocaleDateString(undefined, {
            weekday: 'long', month: 'long', day: 'numeric'
        });

        var html = '<div class="cal-detail-head">' + escapeHtml(heading) + '</div>';

        if (dayItems.length === 0) {
            html += '<div class="cal-detail-empty">Nothing planned for this day.</div>';
            detail.innerHTML = html;
            return;
        }

        dayItems.forEach(function (item) {
            var tag = item.type.charAt(0).toUpperCase() + item.type.slice(1);
            var inner = '<span class="cal-chip cal-chip-' + item.type + '">' + tag + '</span>'
                + '<span class="cal-chip-title">' + escapeHtml(item.title) + '</span>';

            if (item.url) {
                html += '<a class="cal-detail-item" href="' + item.url + '">' + inner
                    + '<i class="bi bi-arrow-right"></i></a>';
            } else {
                html += '<div class="cal-detail-item">' + inner + '</div>';
            }
        });

        detail.innerHTML = html;
    }

    function render() {
        renderGrid();
        renderDetail();
    }

    document.getElementById('calPrev').addEventListener('click', function () {
        view = new Date(view.getFullYear(), view.getMonth() - 1, 1);
        render();
    });

    document.getElementById('calNext').addEventListener('click', function () {
        view = new Date(view.getFullYear(), view.getMonth() + 1, 1);
        render();
    });

    var todayBtn = document.getElementById('calToday');
    if (todayBtn) {
        todayBtn.addEventListener('click', function () {
            view = new Date(today.getFullYear(), today.getMonth(), 1);
            selected = todayKey;
            render();
        });
    }

    var eventForm = document.getElementById('eventForm');
    var addBtn = document.getElementById('dashAddEvent');
    var cancelBtn = document.getElementById('eventCancel');
    var dateInput = document.getElementById('eventDate');

    function showEventForm(show) {
        if (!eventForm) {
            return;
        }
        eventForm.hidden = !show;
        if (show) {
            if (dateInput && !dateInput.value) {
                dateInput.value = selected + 'T09:00';
            }
            var titleInput = eventForm.querySelector('input[name="APL_TITLE"]');
            if (titleInput) {
                titleInput.focus();
            }
        }
    }

    if (addBtn) {
        addBtn.addEventListener('click', function () { showEventForm(eventForm.hidden); });
    }
    if (cancelBtn) {
        cancelBtn.addEventListener('click', function () { showEventForm(false); });
    }

    render();
})();

(function () {
    'use strict';

    var track = document.getElementById('noteTrack');
    var prev = document.getElementById('notePrev');
    var next = document.getElementById('noteNext');
    var label = document.getElementById('notePageLabel');

    if (!track || !prev || !next) {
        return;
    }

    var total = track.querySelectorAll('.note-page').length;
    var index = 0;

    function render() {
        track.style.transform = 'translateX(' + (-index * 100) + '%)';
        if (label) {
            label.textContent = (index + 1) + ' / ' + total;
        }
        prev.disabled = index === 0;
        next.disabled = index === total - 1;
    }

    prev.addEventListener('click', function () {
        if (index > 0) { index--; render(); }
    });
    next.addEventListener('click', function () {
        if (index < total - 1) { index++; render(); }
    });

    render();
})();

(function () {
    'use strict';

    // Server-side forecast first; this only runs when the server could not get
    // one. See the comment on #weatherLive: the browser sits on the admin's own
    // connection, which is not inside the shared cloud quota that Open-Meteo
    // throttles. The markup is rebuilt by hand because this is the one path the
    // server did not render.
    var root = document.getElementById('weatherLive');

    if (!root) {
        return;
    }

    function iconFor(code, isDay) {
        var d = isDay ? 'day' : 'night';

        if (code === 0 || code === 1) { return 'clear-' + d; }
        if (code === 2) { return 'partly-cloudy-' + d; }
        if (code === 3) { return 'overcast-' + d; }
        if (code === 45 || code === 48) { return 'fog-' + d; }
        if (code === 51 || code === 53 || code === 55) { return 'drizzle'; }
        if ([56, 57, 66, 67].indexOf(code) >= 0) { return 'sleet'; }
        if (code === 61 || code === 63 || code === 65) { return 'rain'; }
        if ([71, 73, 75, 77].indexOf(code) >= 0) { return 'snow'; }
        if (code === 80 || code === 81 || code === 82) { return 'partly-cloudy-' + d + '-rain'; }
        if (code === 85 || code === 86) { return 'snow'; }
        if (code === 95) { return 'thunderstorms-' + d; }
        if (code === 96 || code === 99) { return 'thunderstorms-' + d + '-rain'; }

        return 'cloudy';
    }

    function conditionFor(code) {
        if (code === 0) { return 'Clear sky'; }
        if (code === 1) { return 'Mainly clear'; }
        if (code === 2) { return 'Partly cloudy'; }
        if (code === 3) { return 'Overcast'; }
        if ([45, 48].indexOf(code) >= 0) { return 'Fog'; }
        if ([51, 53, 55].indexOf(code) >= 0) { return 'Drizzle'; }
        if ([56, 57, 66, 67].indexOf(code) >= 0) { return 'Freezing rain'; }
        if ([61, 63, 65].indexOf(code) >= 0) { return 'Rain'; }
        if ([71, 73, 75, 77].indexOf(code) >= 0) { return 'Snow'; }
        if ([80, 81, 82].indexOf(code) >= 0) { return 'Rain showers'; }
        if ([85, 86].indexOf(code) >= 0) { return 'Snow showers'; }
        if ([95, 96, 99].indexOf(code) >= 0) { return 'Thunderstorm'; }

        return 'Unknown';
    }

    function round(value) {
        return (value === null || value === undefined || isNaN(value)) ? null : Math.round(value);
    }

    function esc(value) {
        return String(value === null || value === undefined ? '' : value)
            .replace(/[&<>"']/g, function (ch) { return '&#' + ch.charCodeAt(0) + ';'; });
    }

    function num(value, suffix) {
        var rounded = round(value);

        return rounded === null ? '&mdash;' : rounded + (suffix || '');
    }

    function render(data) {
        var current = data.current;
        var daily = data.daily;
        var code = parseInt(current.weather_code || 0, 10);
        var isDay = parseInt(current.is_day === null || current.is_day === undefined ? 1 : current.is_day, 10) === 1;
        var condition = conditionFor(code);

        var html = '<div class="weather-current">'
            + '<img src="' + root.getAttribute('data-icon-base') + '/' + iconFor(code, isDay) + '.svg"'
            + ' alt="' + esc(condition) + '" class="weather-current-icon" width="48" height="48">'
            + '<div>'
            + '<div class="weather-temp">' + num(current.temperature_2m) + '<span class="weather-unit">&deg;C</span></div>'
            + '<div class="weather-condition">' + esc(condition) + '</div>'
            + '</div>'
            + '</div>';

        html += '<div class="weather-meta">'
            + '<span title="Feels like"><i class="bi bi-thermometer-half"></i> Feels ' + num(current.apparent_temperature) + '&deg;</span>'
            + '<span title="Humidity"><i class="bi bi-droplet"></i> ' + num(current.relative_humidity_2m, '%') + '</span>'
            + '<span title="Wind speed"><i class="bi bi-wind"></i> ' + num(current.wind_speed_10m, ' km/h') + '</span>'
            + '</div>';

        var times = daily.time || [];
        var codes = daily.weather_code || [];
        var maxes = daily.temperature_2m_max || [];
        var mins = daily.temperature_2m_min || [];
        var rain = daily.precipitation_probability_max || [];

        if (times.length) {
            html += '<div class="weather-forecast">';

            times.forEach(function (date, index) {
                var dayCondition = conditionFor(parseInt(codes[index] || 0, 10));

                html += '<div class="weather-day">'
                    + '<span class="weather-day-name">'
                    + esc(new Date(date + 'T00:00:00').toLocaleString(undefined, { weekday: 'short' }))
                    + '</span>'
                    + '<img src="' + root.getAttribute('data-icon-base') + '/' + iconFor(parseInt(codes[index] || 0, 10), true) + '.svg"'
                    + ' alt="' + esc(dayCondition) + '" title="' + esc(dayCondition) + '" class="weather-day-icon" width="28" height="28">'
                    + '<span class="weather-day-temp">' + num(maxes[index]) + '&deg;<small>' + num(mins[index]) + '&deg;</small></span>';

                if (rain[index] !== null && rain[index] !== undefined) {
                    html += '<span class="weather-day-rain"><i class="bi bi-droplet-half"></i> ' + parseInt(rain[index], 10) + '%</span>';
                }

                html += '</div>';
            });

            html += '</div>';
        }

        return html;
    }

    var params = [
        'latitude=' + encodeURIComponent(root.getAttribute('data-lat')),
        'longitude=' + encodeURIComponent(root.getAttribute('data-lng')),
        'timezone=' + encodeURIComponent(root.getAttribute('data-tz')),
        'current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m,is_day',
        'daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
        'forecast_days=' + encodeURIComponent(root.getAttribute('data-days')),
        'wind_speed_unit=kmh',
    ];

    fetch(root.getAttribute('data-endpoint') + '?' + params.join('&'), { headers: { Accept: 'application/json' } })
        .then(function (response) {
            if (!response.ok) {
                throw new Error('HTTP ' + response.status);
            }

            return response.json();
        })
        .then(function (data) {
            if (data && data.current && data.daily) {
                root.innerHTML = render(data);
            }
        })
        .catch(function () {
            // Leave the server-rendered empty state in place.
        });
})();
