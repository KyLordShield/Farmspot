@extends('layouts.app')

@section('title', 'Dashboard')

@section('content')

<div class="page-head">

    <div>
        <h1 class="page-title">Dashboard</h1>
        <div class="page-desc">{{ now()->format('l, F j, Y') }} · Your personal workspace</div>
    </div>

    <div class="page-actions">
        @if($plannerReady)
            <button type="button" class="btn btn-farm" id="dashAddEvent">
                <i class="bi bi-calendar-plus me-1"></i>
                Add Event
            </button>
        @endif
    </div>

</div>

@if(session('success'))
    <div class="alert alert-success alert-dismissible fade show" role="alert">
        {{ session('success') }}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
@endif
@if(session('error'))
    <div class="alert alert-danger alert-dismissible fade show" role="alert">
        {{ session('error') }}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
@endif

<div class="stat-grid">

    <a class="stat-card" href="{{ route('users') }}">
        <div class="stat-icon tint-green">
            <i class="bi bi-people"></i>
        </div>
        <div>
            <div class="stat-value">{{ $users }}</div>
            <div class="stat-label">Total Users</div>
        </div>
    </a>

    <a class="stat-card" href="{{ route('users') }}">
        <div class="stat-icon tint-slate">
            <i class="bi bi-person-badge"></i>
        </div>
        <div>
            <div class="stat-value">{{ $farmers }}</div>
            <div class="stat-label">Total Farmers</div>
        </div>
    </a>

    <a class="stat-card" href="{{ route('listings') }}">
        <div class="stat-icon tint-amber">
            <i class="bi bi-basket"></i>
        </div>
        <div>
            <div class="stat-value">{{ $listings }}</div>
            <div class="stat-label">Active Listings</div>
        </div>
    </a>

    <a class="stat-card" href="{{ route('reports', ['status' => 'New']) }}">
        <div class="stat-icon tint-red">
            <i class="bi bi-flag"></i>
        </div>
        <div>
            <div class="stat-value">{{ $reports }}</div>
            <div class="stat-label">New Reports</div>
        </div>
    </a>

</div>

<div class="row g-4">

    <!-- Calendar -->
    <div class="col-lg-8">

        <div class="panel">

            <div class="panel-header">
                <div>
                    <h5 class="panel-title">
                        <i class="bi bi-calendar3"></i>
                        Calendar
                    </h5>
                    <div class="panel-sub">Your events and live FarmSpot tasks</div>
                </div>
                <div class="cal-nav">
                    <button type="button" class="btn-icon" id="calPrev" aria-label="Previous month">
                        <i class="bi bi-chevron-left"></i>
                    </button>
                    <span class="cal-label" id="calLabel" aria-live="polite"></span>
                    <button type="button" class="btn-icon" id="calNext" aria-label="Next month">
                        <i class="bi bi-chevron-right"></i>
                    </button>
                    <button type="button" class="btn-icon" id="calToday" aria-label="Go to today" title="Today">
                        <i class="bi bi-bullseye"></i>
                    </button>
                </div>
            </div>

            <div class="panel-body">

                @if($plannerReady)
                    <form method="POST" action="{{ route('planner.store') }}" id="eventForm" class="event-form" hidden data-auto-spinner>
                        @csrf
                        <input type="hidden" name="APL_TYPE" value="EVENT">

                        <div class="row g-2">
                            <div class="col-md-6">
                                <input type="text" name="APL_TITLE" class="form-control form-control-sm"
                                       placeholder="Event title" maxlength="150" required>
                            </div>
                            <div class="col-md-6">
                                <input type="datetime-local" name="APL_DATETIME" id="eventDate"
                                       class="form-control form-control-sm" required>
                            </div>
                            <div class="col-12">
                                <input type="text" name="APL_BODY" class="form-control form-control-sm"
                                       placeholder="Details (optional)" maxlength="2000">
                            </div>
                            <div class="col-12 d-flex gap-2">
                                <button type="submit" class="btn btn-farm btn-sm">
                                    <i class="bi bi-plus-lg me-1"></i> Save Event
                                </button>
                                <button type="button" class="btn btn-ghost btn-sm" id="eventCancel">Cancel</button>
                            </div>
                        </div>
                    </form>
                @endif

                <div class="cal-legend">
                    <span><i class="cal-dot dot-event"></i> Event</span>
                    <span><i class="cal-dot dot-note"></i> Reminder</span>
                    <span><i class="cal-dot dot-task"></i> Task</span>
                </div>

                <div class="cal-grid" id="calGrid"></div>

                <div class="cal-detail" id="calDetail"></div>

            </div>

        </div>

    </div>

    <!-- Weather + notes -->
    <div class="col-lg-4">

        <!-- Weather -->
        <div class="panel">

            <div class="panel-header">
                <div>
                    <h5 class="panel-title">
                        <i class="bi bi-cloud-sun"></i>
                        Weather
                    </h5>
                    <div class="panel-sub">{{ $weather['label'] ?? config('farmspot.weather.label') }}</div>
                </div>
            </div>

            <div class="panel-body">

                @if($weather && !empty($weather['current']))

                    <div class="weather-current">
                        <img src="{{ asset('images/weather/'.$weather['current']['icon'].'.svg') }}"
                             alt="{{ $weather['current']['condition'] }}"
                             class="weather-current-icon" width="48" height="48">
                        <div>
                            <div class="weather-temp">
                                {{ $weather['current']['temperature'] }}<span class="weather-unit">&deg;C</span>
                            </div>
                            <div class="weather-condition">{{ $weather['current']['condition'] }}</div>
                        </div>
                    </div>

                    <div class="weather-meta">
                        <span title="Feels like">
                            <i class="bi bi-thermometer-half"></i>
                            Feels {{ $weather['current']['apparent'] ?? '—' }}&deg;
                        </span>
                        <span title="Humidity">
                            <i class="bi bi-droplet"></i>
                            {{ $weather['current']['humidity'] ?? '—' }}%
                        </span>
                        <span title="Wind speed">
                            <i class="bi bi-wind"></i>
                            {{ $weather['current']['wind'] ?? '—' }} km/h
                        </span>
                    </div>

                    @if(!empty($weather['daily']))
                        <div class="weather-forecast">
                            @foreach($weather['daily'] as $day)
                                <div class="weather-day">
                                    <span class="weather-day-name">{{ $day['label'] }}</span>
                                    <img src="{{ asset('images/weather/'.$day['icon'].'.svg') }}"
                                         alt="{{ $day['condition'] }}"
                                         title="{{ $day['condition'] }}"
                                         class="weather-day-icon" width="28" height="28">
                                    <span class="weather-day-temp">
                                        {{ $day['max'] }}&deg;<small>{{ $day['min'] }}&deg;</small>
                                    </span>
                                    @if($day['rain'] !== null)
                                        <span class="weather-day-rain">
                                            <i class="bi bi-droplet-half"></i> {{ $day['rain'] }}%
                                        </span>
                                    @endif
                                </div>
                            @endforeach
                        </div>
                    @endif

                @else

                    {{-- The server could not reach Open-Meteo. Its free, keyless
                         endpoint rate-limits by IP, and Render egresses from a
                         shared cloud IP, so the server's share of that quota is
                         out of our hands. The browser is not on that IP, so let
                         it fetch the same public API directly; the empty state
                         below stays if that fails too. --}}
                    <div class="weather-live" id="weatherLive"
                         data-endpoint="{{ config('farmspot.weather.endpoint') }}"
                         data-lat="{{ config('farmspot.weather.latitude') }}"
                         data-lng="{{ config('farmspot.weather.longitude') }}"
                         data-tz="{{ config('farmspot.weather.timezone') }}"
                         data-days="{{ (int) config('farmspot.weather.days') }}"
                         data-icon-base="{{ asset('images/weather') }}">

                        <div class="empty-state">
                            <i class="bi bi-cloud-slash empty-icon"></i>
                            <p>Forecast unavailable right now.</p>
                        </div>

                    </div>

                @endif

            </div>

        </div>

        <div class="panel">

            <div class="panel-header">
                <div>
                    <h5 class="panel-title">
                        <i class="bi bi-journal-check"></i>
                        Notes &amp; Reminders
                    </h5>
                    <div class="panel-sub">Private to you</div>
                </div>
            </div>

            <div class="panel-body">

                @if($plannerReady)
                    <form method="POST" action="{{ route('planner.store') }}" class="note-add" data-auto-spinner>
                        @csrf
                        <input type="hidden" name="APL_TYPE" value="NOTE">

                        <input type="text" name="APL_TITLE" class="form-control form-control-sm"
                               placeholder="Add a note or to-do..." maxlength="150" required>

                        <div class="note-add-row">
                            <input type="date" name="APL_DATETIME" class="form-control form-control-sm"
                                   aria-label="Due date (optional)" title="Optional due date">
                            <button type="submit" class="btn btn-farm btn-sm" aria-label="Add note">
                                <i class="bi bi-plus-lg"></i>
                            </button>
                        </div>
                    </form>
                @endif

                @if(!$plannerReady)

                    <div class="empty-state">
                        <i class="bi bi-tools empty-icon"></i>
                        <p>Your planner is unavailable until the database is migrated.</p>
                    </div>

                @elseif($notes->isEmpty())

                    <div class="empty-state">
                        <i class="bi bi-journal-text empty-icon"></i>
                        <p>No notes yet. Add your first reminder above.</p>
                    </div>

                @else

                    @php($notePages = $notes->chunk(3))

                    <div class="note-viewport">
                        <div class="note-track" id="noteTrack">
                            @foreach($notePages as $page)
                                <ul class="note-page">
                                    @foreach($page as $note)
                                        <li class="note-item {{ $note->APL_IS_DONE ? 'is-done' : '' }}">

                                            <form method="POST" action="{{ route('planner.toggle', $note->APL_ID) }}" class="note-toggle-form">
                                                @csrf
                                                @method('PATCH')
                                                <input type="checkbox" class="note-check"
                                                       onchange="this.form.requestSubmit()"
                                                       {{ $note->APL_IS_DONE ? 'checked' : '' }}
                                                       aria-label="Mark &quot;{{ $note->APL_TITLE }}&quot; done">
                                            </form>

                                            <div class="note-main">
                                                <div class="note-title">{{ $note->APL_TITLE }}</div>

                                                @if($note->APL_DATETIME)
                                                    <span class="note-due {{ $note->isOverdue() ? 'overdue' : '' }}">
                                                        <i class="bi bi-clock"></i>
                                                        {{ $note->APL_DATETIME->format('M j, Y') }}{{ $note->isOverdue() ? ' · overdue' : '' }}
                                                    </span>
                                                @endif
                                            </div>

                                            <form method="POST" action="{{ route('planner.destroy', $note->APL_ID) }}"
                                                  data-confirm-title="Delete this note?"
                                                  data-confirm-text="It will be removed from your planner."
                                                  data-confirm-tone="danger">
                                                @csrf
                                                @method('DELETE')
                                                <button type="submit" class="btn-icon danger" aria-label="Delete note">
                                                    <i class="bi bi-trash"></i>
                                                </button>
                                            </form>

                                        </li>
                                    @endforeach
                                </ul>
                            @endforeach
                        </div>
                    </div>

                    @if($notePages->count() > 1)
                        <div class="note-pager">
                            <button type="button" class="btn-icon" id="notePrev" aria-label="Previous notes">
                                <i class="bi bi-chevron-left"></i>
                            </button>
                            <span class="note-page-label" id="notePageLabel" aria-live="polite">1 / {{ $notePages->count() }}</span>
                            <button type="button" class="btn-icon" id="noteNext" aria-label="Next notes">
                                <i class="bi bi-chevron-right"></i>
                            </button>
                        </div>
                    @endif

                @endif

            </div>

        </div>

    </div>

</div>

<div class="row g-4">

    <!-- Needs attention -->
    <div class="col-lg-4">

        <div class="panel h-100">

            <div class="panel-header">
                <div>
                    <h5 class="panel-title">
                        <i class="bi bi-exclamation-circle"></i>
                        Needs Your Attention
                    </h5>
                    <div class="panel-sub">Live queues right now</div>
                </div>
            </div>

            <div class="panel-body p-0">

                <a class="attention-item" href="{{ route('reports') }}">
                    <span class="attention-count {{ $newReports ? 'is-active' : '' }}">{{ $newReports }}</span>
                    <span class="attention-label">
                        <strong>New reports</strong>
                        <small>Waiting to be triaged</small>
                    </span>
                    <i class="bi bi-chevron-right"></i>
                </a>

                <a class="attention-item" href="{{ route('reports.flagged') }}">
                    <span class="attention-count {{ $flaggedTargets ? 'is-active' : '' }}">{{ $flaggedTargets }}</span>
                    <span class="attention-label">
                        <strong>Mass-report alerts</strong>
                        <small>Targets flagged by many reporters</small>
                    </span>
                    <i class="bi bi-chevron-right"></i>
                </a>

                <a class="attention-item" href="{{ route('seller-requests') }}">
                    <span class="attention-count {{ $pendingSellerRequests ? 'is-active' : '' }}">{{ $pendingSellerRequests }}</span>
                    <span class="attention-label">
                        <strong>Seller requests</strong>
                        <small>Farms awaiting review</small>
                    </span>
                    <i class="bi bi-chevron-right"></i>
                </a>

                <a class="attention-item" href="{{ route('appeals') }}">
                    <span class="attention-count {{ $pendingAppeals ? 'is-active' : '' }}">{{ $pendingAppeals }}</span>
                    <span class="attention-label">
                        <strong>Appeals</strong>
                        <small>Re-evaluations awaiting a decision</small>
                    </span>
                    <i class="bi bi-chevron-right"></i>
                </a>

            </div>

        </div>

    </div>

    <!-- Quick actions -->
    <div class="col-lg-4">

        <div class="panel h-100">

            <div class="panel-header">
                <div>
                    <h5 class="panel-title">
                        <i class="bi bi-lightning-charge"></i>
                        Quick Actions
                    </h5>
                    <div class="panel-sub">Jump straight to common tasks</div>
                </div>
            </div>

            <div class="panel-body">

                <div class="quick-grid">
                    <a class="quick-btn" href="{{ route('reports') }}">
                        <i class="bi bi-flag"></i><span>Reports</span>
                    </a>
                    <a class="quick-btn" href="{{ route('seller-requests') }}">
                        <i class="bi bi-person-check"></i><span>Requests</span>
                    </a>
                    <a class="quick-btn" href="{{ route('appeals') }}">
                        <i class="bi bi-shield-exclamation"></i><span>Appeals</span>
                    </a>
                    <a class="quick-btn" href="{{ route('users') }}">
                        <i class="bi bi-people"></i><span>Users</span>
                    </a>
                    <a class="quick-btn" href="{{ route('listings') }}">
                        <i class="bi bi-basket"></i><span>Listings</span>
                    </a>
                    <a class="quick-btn" href="{{ route('analytics') }}">
                        <i class="bi bi-bar-chart"></i><span>Analytics</span>
                    </a>
                </div>

            </div>

        </div>

    </div>

    <!-- My recent activity -->
    <div class="col-lg-4">

        <div class="panel h-100">

            <div class="panel-header">
                <div>
                    <h5 class="panel-title">
                        <i class="bi bi-clock-history"></i>
                        My Recent Activity
                    </h5>
                    <div class="panel-sub">Your latest recorded decisions</div>
                </div>
            </div>

            <div class="panel-body">

                @forelse($recentActivity as $log)

                    <div class="activity-item">
                        <span class="activity-icon">
                            <i class="bi bi-check2-circle"></i>
                        </span>
                        <div>
                            <div class="activity-text">{{ $log->AUD_DETAILS ?? $log->AUD_ACTION }}</div>
                            <div class="activity-time">
                                {{ \Carbon\Carbon::parse($log->AUD_CREATED_AT)->diffForHumans() }}
                            </div>
                        </div>
                    </div>

                @empty

                    <div class="empty-state">
                        <i class="bi bi-clock-history empty-icon"></i>
                        <p>No recorded activity yet.</p>
                    </div>

                @endforelse

            </div>

        </div>

    </div>

</div>

<div class="panel">

    <div class="panel-header">
        <div>
            <h5 class="panel-title">
                <i class="bi bi-flag"></i>
                Recent Reports
            </h5>
            <div class="panel-sub">Latest moderation queue activity</div>
        </div>
    </div>

    <div class="table-responsive">
        <table class="data-table">

            <thead>
                <tr>
                    <th>Report ID</th>
                    <th>Reporter</th>
                    <th>Listing</th>
                    <th>Reason</th>
                    <th>Status</th>
                    <th>Date</th>
                </tr>
            </thead>

            <tbody>

            @forelse($recentReports as $report)

                <tr>
                    <td><span class="id-cell">{{ $report->RPT_ID }}</span></td>
                    <td class="cell-secondary">{{ optional($report->user)->USR_NAME ?? 'Unknown User' }}</td>
                    <td><span class="id-cell">{{ optional($report->listing)->LST_ID ?? 'Unknown Listing' }}</span></td>
                    <td class="cell-secondary">{{ $report->RPT_REASON }}</td>
                    <td>
                        @if($report->RPT_STATUS == 'New')
                            <span class="badge badge-soft-danger">New</span>
                        @elseif($report->RPT_STATUS == 'Reviewing')
                            <span class="badge badge-soft-warning">Reviewing</span>
                        @elseif($report->RPT_STATUS == 'Resolved')
                            <span class="badge badge-soft-success">Resolved</span>
                        @else
                            <span class="badge badge-soft-neutral">Dismissed</span>
                        @endif
                    </td>
                    <td class="cell-faint">{{ date('M d, Y', strtotime($report->RPT_CREATED_AT)) }}</td>
                </tr>

            @empty

                <tr>
                    <td colspan="6">
                        <div class="empty-state">
                            <i class="bi bi-flag empty-icon"></i>
                            <p>No reports found.</p>
                        </div>
                    </td>
                </tr>

            @endforelse

            </tbody>

        </table>
    </div>

</div>

@endsection

@push('scripts')
<script>
(function () {
    'use strict';

    var items = @json($calendarItems);

    var byDate = {};
    items.forEach(function (item) {
        (byDate[item.date] = byDate[item.date] || []).push(item);
    });

    var grid = document.getElementById('calGrid');
    var label = document.getElementById('calLabel');
    var detail = document.getElementById('calDetail');

    if (!grid) {
        return;
    }

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
</script>
@endpush
