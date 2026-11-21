@extends('layouts.app')
@section('title', 'Reports')
@include('reports._assets')

@section('content')
@php
    $filtered = request()->filled('search') || request()->filled('type') || request()->filled('status')
        || request()->filled('flagged') || request()->filled('reporter');
    $cards = [
        ['Total reports', $totalReports, route('reports'), !$filtered, false],
        ['Mass reported', $flaggedTargetCount, route('reports.flagged'), false, true],
        ['Resolved', $counts['Resolved'] ?? 0, route('reports', ['status' => 'Resolved']), request('status') === 'Resolved', false],
        ['New', $counts['New'] ?? 0, route('reports', ['status' => 'New']), request('status') === 'New', false],
    ];
    $rows = $reports->getCollection()->groupBy(fn ($report) => $report->RPT_FLAGGED_AT
        ? $report->RPT_TARGET_TYPE.':'.$report->RPT_TARGET_ID
        : 'report:'.$report->RPT_ID);
@endphp
<div class="listing-details mod-page">
    <header class="ld-header">
        <div class="ld-title"><h1>Reports</h1></div>
        <a class="ld-button" href="{{ route('reports.flagged') }}">Mass-report alerts</a>
    </header>
    @include('reports._feedback')

    <nav class="mod-stats" aria-label="Report overview">
        @foreach($cards as [$label, $count, $href, $active, $massAlert])
            <a class="ld-card mod-stat" href="{{ $href }}" @if($active) aria-current="true" @endif>
                <strong>{{ $count }}</strong>
                <span>{{ $label }}</span>
                @if($massAlert)
                    @if($count > 0)
                        <span class="mod-stat-warning"><i class="bi bi-exclamation-triangle-fill" aria-hidden="true"></i> Needs review</span>
                    @else
                        <span class="mod-stat-note">No active alerts</span>
                    @endif
                @endif
            </a>
        @endforeach
    </nav>

    <section class="ld-card mod-queue" aria-label="Reports queue">
        <form method="GET" action="{{ route('reports') }}" class="mod-toolbar">
            <div class="input-group">
                <span class="input-group-text"><i class="bi bi-search" aria-hidden="true"></i></span>
                <input type="search" name="search" value="{{ request('search') }}" class="form-control"
                       aria-label="Search reports" placeholder="Search reports">
                <button class="ld-button ld-primary" type="submit">Search</button>
            </div>
            <select name="type" class="form-select" aria-label="Report type" data-mod-filter>
                <option value="">All types</option>
                @foreach(['LISTING' => 'Crop listing', 'MESSAGE' => 'Message', 'FARMER' => 'Farmer / seller', 'USER' => 'User'] as $type => $label)
                    <option value="{{ $type }}" @selected(request('type') === $type)>{{ $label }}</option>
                @endforeach
            </select>
            <select name="status" class="form-select" aria-label="Report status" data-mod-filter>
                <option value="">All statuses</option>
                @foreach(['New', 'Reviewing', 'Resolved', 'Dismissed'] as $status)
                    <option @selected(request('status') === $status)>{{ $status }}</option>
                @endforeach
            </select>
            <label class="form-check form-switch mod-toggle">
                <input class="form-check-input" type="checkbox" name="flagged" value="1" role="switch"
                       data-mod-filter @checked(request()->filled('flagged'))>
                Mass reported only
            </label>
            @if(request()->filled('reporter'))
                <input type="hidden" name="reporter" value="{{ request('reporter') }}">
                @if(request()->filled('except'))
                    <input type="hidden" name="except" value="{{ request('except') }}">
                @endif
                <span class="ld-muted">Reporter @include('reports._id', ['id' => request('reporter')])</span>
            @endif
            @if($filtered)
                <a class="mod-link" href="{{ route('reports') }}">Clear filters</a>
            @endif
        </form>

        <div class="mod-table-scroll" tabindex="0" role="region" aria-label="Report results">
            <table class="mod-table">
                <thead>
                    <tr>
                        @foreach(['Report ID', 'Reported', 'Reason', 'Reporter', 'Status', 'Date', 'Actions'] as $column)
                            <th scope="col">{{ $column }}</th>
                        @endforeach
                    </tr>
                </thead>
                @forelse($rows as $group)
                    @php
                        $first = $group->first();
                        $groupId = 'report-group-'.$loop->index;
                    @endphp
                    @if($first->RPT_FLAGGED_AT)
                        <tbody>
                            <tr class="mod-group">
                                <td colspan="7">
                                    <button type="button" class="mod-disclosure" data-mod-group="{{ $groupId }}"
                                            aria-controls="{{ $groupId }}" aria-expanded="true">
                                        <i class="bi bi-chevron-down" aria-hidden="true"></i>
                                        <strong>{{ $first->targetLabel() ?: $first->RPT_TARGET_ID }}</strong>
                                        <span>{{ $group->count() }} {{ Str::plural('report', $group->count()) }} on this page · {{ $group->map->reasonLabel()->unique()->count() === 1 ? $first->reasonLabel() : 'Multiple reasons' }}</span>
                                    </button>
                                    <a class="mod-link" href="{{ route('reports.flaggedTarget', [$first->RPT_TARGET_TYPE, $first->RPT_TARGET_ID]) }}">All reporters</a>
                                </td>
                            </tr>
                        </tbody>
                    @endif
                    <tbody id="{{ $groupId }}">
                        @foreach($group as $report)
                            @include('reports._queue-row')
                        @endforeach
                    </tbody>
                @empty
                    <tbody><tr><td colspan="7" class="mod-empty">
                        <i class="bi bi-flag" aria-hidden="true"></i>
                        <p>{{ $filtered ? 'No reports match these filters.' : 'There are no reports to review yet.' }}</p>
                        @if($filtered)<a class="mod-link" href="{{ route('reports') }}">Clear filters</a>@endif
                    </td></tr></tbody>
                @endforelse
            </table>
        </div>
        @if($reports->hasPages())
            <div class="mod-pagination">{{ $reports->links() }}</div>
        @endif
    </section>
</div>
@endsection
