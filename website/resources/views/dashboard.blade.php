@extends('layouts.app')

@section('title', 'Dashboard')

@include('partials._admin-refresh')

@section('content')
<div class="admin-refresh">
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
                    <form method="POST" action="{{ route('planner.store') }}" id="eventForm" class="event-form" @if(old('APL_TYPE') !== 'EVENT') hidden @endif data-auto-spinner>
                        @csrf
                        <input type="hidden" name="APL_TYPE" value="EVENT">

                        <div class="row g-2">
                            <div class="col-12">
                                <label for="eventTitle" class="form-label">Event title</label>
                                <input type="text" name="APL_TITLE" id="eventTitle" class="form-control"
                                       placeholder="Event title" maxlength="150" value="{{ old('APL_TYPE') === 'EVENT' ? old('APL_TITLE') : '' }}" required>
                            </div>
                            <div class="col-12">
                                <div id="eventDateFallback">
                                <label for="eventDate" class="form-label">Date and time (Philippine time)</label>
                                <input type="datetime-local" name="APL_DATETIME" id="eventDate"
                                       class="form-control form-control-sm @error('APL_DATETIME') is-invalid @enderror"
                                       min="{{ now('Asia/Manila')->format('Y-m-d') }}T00:00"
                                       value="{{ old('APL_TYPE') === 'EVENT' ? old('APL_DATETIME') : '' }}" required>
                                </div>
                                <fieldset id="eventSchedule" class="event-schedule" hidden>
                                    <legend class="visually-hidden">Event date and time</legend>
                                    <div class="event-schedule-field">
                                        <label for="eventDay"><i class="bi bi-calendar3" aria-hidden="true"></i> Date</label>
                                        <input type="date" id="eventDay" class="form-control" min="{{ now('Asia/Manila')->toDateString() }}">
                                        <div class="event-quick-choices" aria-label="Quick dates">
                                            <button type="button" class="event-choice" data-event-day="0" aria-pressed="false">Today</button>
                                            <button type="button" class="event-choice" data-event-day="1" aria-pressed="false">Tomorrow</button>
                                            <button type="button" class="event-choice" data-event-day="7" aria-pressed="false">In a week</button>
                                        </div>
                                    </div>
                                    <div class="event-schedule-field">
                                        <label for="eventTime"><i class="bi bi-clock" aria-hidden="true"></i> Time</label>
                                        <input type="time" id="eventTime" class="form-control" step="60">
                                        <div class="event-quick-choices" aria-label="Quick times">
                                            <button type="button" class="event-choice" data-event-time="09:00" aria-pressed="false">9:00 AM</button>
                                            <button type="button" class="event-choice" data-event-time="13:00" aria-pressed="false">1:00 PM</button>
                                            <button type="button" class="event-choice" data-event-time="15:00" aria-pressed="false">3:00 PM</button>
                                        </div>
                                    </div>
                                    <p class="event-schedule-preview" id="eventSchedulePreview" role="status" aria-live="polite"></p>
                                </fieldset>
                                @error('APL_DATETIME')
                                    <div class="text-danger small mt-2">{{ $message }}</div>
                                @enderror
                            </div>
                            <div class="col-12">
                                <input type="text" name="APL_BODY" class="form-control form-control-sm"
                                       placeholder="Details (optional)" maxlength="2000" value="{{ old('APL_TYPE') === 'EVENT' ? old('APL_BODY') : '' }}">
                            </div>
                            <div class="col-12">
                                <label class="form-check">
                                    <input type="checkbox" name="APL_NOTIFY_FARMERS" value="1" class="form-check-input" @checked(old('APL_TYPE') !== 'EVENT' || old('APL_NOTIFY_FARMERS') === '1')>
                                    <span class="form-check-label">Notify farmers about this event</span>
                                </label>
                                <small class="text-muted">Times are Philippine time. Farmers receive one announcement, delivered in background batches. Uncheck for a private event.</small>
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

                <div class="cal-grid" id="calGrid" data-calendar-items="{{ json_encode($calendarItems) }}"></div>

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
                                                       data-submit-on-change="requestSubmit"
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
</div>
@endsection

@push('scripts')
<script src="{{ asset('js/event-schedule.js') }}?v={{ filemtime(public_path('js/event-schedule.js')) }}"></script>
<script src="{{ asset('js/dashboard.js') }}?v={{ filemtime(public_path('js/dashboard.js')) }}"></script>
@endpush
