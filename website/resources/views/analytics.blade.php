@extends('layouts.app')
@section('title', 'System Analytics')
@include('partials._admin-refresh')

@push('styles')
    <link rel="stylesheet" href="{{ asset('css/analytics.css') }}?v={{ filemtime(public_path('css/analytics.css')) }}">
@endpush

@section('content')
@php
    $metrics = [
        ['Total Users', $totalUsers, 'people', 'All user accounts, including administrators and inactive accounts.'],
        ['Active Farmers', $totalFarmers, 'basket', 'Active seller accounts with an approved farm. Farmers can also be registered buyers.'],
        ['Registered Buyers', $totalBuyers, 'person-check', 'Registered buyer profiles, including those belonging to farmers.'],
        ['Visible Listings', $totalListings, 'grid', 'Active listings shown in the public feed, including expired listings with a freshness notice.'],
        ['Searches Today', $searchesToday, 'search', 'Recorded searches with a nonblank keyword since midnight in Manila.'],
        ['Pending Reports', $totalReports, 'flag', 'Reports awaiting a decision, including New and Reviewing.'],
    ];
    $growthTotal = array_sum($growthValues);
@endphp

<div class="admin-refresh analytics-page">
    <header class="page-head analytics-header">
        <div>
            <h1 class="page-title">System Analytics</h1>
            <p class="analytics-muted">Search demand, registrations, and listing activity</p>
            <div class="analytics-muted">
                Updated <time id="analytics-updated" datetime="{{ $asOf->toAtomString() }}">{{ $asOf->format('M j, Y, g:i A') }} PHT</time>
                <span id="analytics-age"></span>
            </div>
        </div>
        <form class="analytics-controls" method="GET" action="{{ route('analytics') }}">
            <label for="analytics-range" class="visually-hidden">Top Searches date range</label>
            <select id="analytics-range" name="range" class="form-select" aria-describedby="analytics-range-scope">
                @foreach(['week' => 'This week', 'today' => 'Today', '7' => 'Last 7 days', '30' => 'Last 30 days', 'custom' => 'Custom'] as $value => $label)
                    <option value="{{ $value }}" @selected(old('range', $range) === $value)>{{ $label }}</option>
                @endforeach
            </select>
            <fieldset id="analytics-custom" class="analytics-custom">
                <legend class="visually-hidden">Custom Top Searches dates</legend>
                <label>From <input class="form-control" name="from" type="date" value="{{ old('from', $filters['from'] ?? '') }}"></label>
                <label>To <input class="form-control" name="to" type="date" value="{{ old('to', $filters['to'] ?? '') }}"></label>
            </fieldset>
            <button type="submit" class="btn btn-ghost"><i class="bi bi-arrow-clockwise" aria-hidden="true"></i> Refresh</button>
            <button type="submit" name="export" value="csv" class="btn btn-farm"><i class="bi bi-download" aria-hidden="true"></i> Export CSV</button>
            <small class="analytics-muted" id="analytics-range-scope">Date range applies to Top Searches.</small>
        </form>
    </header>

    @if($errors->any())
        <div class="alert alert-danger" role="alert">{{ $errors->first() }}</div>
    @endif

    <section class="analytics-kpis" aria-label="System summary">
        @foreach($metrics as [$label, $value, $icon, $note])
            <article @class(['analytics-card', 'analytics-kpi', 'analytics-kpi-alert' => $label === 'Pending Reports' && $value > 0])>
                <span @class(['analytics-icon', 'analytics-icon-neutral' => $label === 'Pending Reports' && !$value])><i class="bi bi-{{ $icon }}" aria-hidden="true"></i></span>
                <strong>{{ number_format($value) }}</strong>
                @if($label === 'Pending Reports')
                    <a class="analytics-kpi-label" href="{{ route('reports') }}">{{ $label }}</a>
                @else
                    <span class="analytics-kpi-label">{{ $label }}</span>
                @endif
                <details class="analytics-metric-note">
                    <summary aria-label="About {{ $label }}">About</summary>
                    <p>{{ $note }}</p>
                </details>
            </article>
        @endforeach
    </section>

    <div class="analytics-grid">
        <section class="analytics-card analytics-searches" aria-labelledby="analytics-search-title">
            <header class="analytics-card-head">
                <span class="analytics-icon"><i class="bi bi-search" aria-hidden="true"></i></span>
                <div>
                    <h2 id="analytics-search-title">Top Searches</h2>
                    <p>Recorded searches from signed-in users · {{ $weekLabel }}</p>
                </div>
            </header>
            @if($topSearches->isEmpty())
                <p class="analytics-empty">{{ $range === 'week' ? 'No searches recorded this week yet.' : 'No searches recorded for this date range.' }}</p>
            @else
                <div class="analytics-chart analytics-chart-search" data-chart-area hidden>
                    <div class="analytics-skeleton" aria-hidden="true"></div>
                    <canvas id="cropChart" aria-hidden="true"
                            data-labels="{{ $topSearches->pluck('keyword')->values()->toJson() }}"
                            data-values="{{ $topSearches->pluck('total')->map(fn ($count) => (int) $count)->values()->toJson() }}"></canvas>
                </div>
                <details class="analytics-data" open>
                    <summary>Chart data</summary>
                    <table class="analytics-table"><thead><tr><th scope="col">Search term</th><th scope="col">Searches</th></tr></thead>
                        <tbody>@foreach($topSearches as $item)<tr><th scope="row">{{ $item->keyword }}</th><td>{{ number_format($item->total) }}</td></tr>@endforeach</tbody>
                    </table>
                </details>
                @if($allSearches->isNotEmpty())
                    <details class="analytics-data" open>
                        <summary>All search terms</summary>
                        <table class="analytics-table"><thead><tr><th scope="col">Search term</th><th scope="col">Searches</th></tr></thead>
                            <tbody>@foreach($allSearches as $item)<tr><th scope="row">{{ $item->keyword }}</th><td>{{ number_format($item->total) }}</td></tr>@endforeach</tbody>
                        </table>
                    </details>
                @else
                    <a class="analytics-link" href="{{ route('analytics', $filters + ['all' => 1]) }}#analytics-search-title">View all search terms</a>
                @endif
            @endif
        </section>

        <section class="analytics-card analytics-growth" aria-labelledby="analytics-growth-title">
            <header class="analytics-card-head">
                <span class="analytics-icon"><i class="bi bi-graph-up" aria-hidden="true"></i></span>
                <div>
                    <h2 id="analytics-growth-title">User Growth</h2>
                    <p>New registrations by seven-day period · {{ $monthLabel }}</p>
                </div>
            </header>
            <p class="analytics-growth-total"><strong>{{ number_format($growthTotal) }}</strong> {{ Str::plural('new user', $growthTotal) }} this month</p>
            @if(!$growthTotal)
                <p class="analytics-empty">No new registrations this month yet.</p>
            @else
                <div class="analytics-chart" data-chart-area hidden>
                    <div class="analytics-skeleton" aria-hidden="true"></div>
                    <canvas id="growthChart" aria-hidden="true" data-labels="{{ json_encode($growthLabels) }}" data-values="{{ json_encode($growthValues) }}"></canvas>
                </div>
            @endif
            <details class="analytics-data" open>
                <summary>Chart data</summary>
                <table class="analytics-table"><thead><tr><th scope="col">Period</th><th scope="col">New users</th></tr></thead>
                    <tbody>@foreach($growthLabels as $index => $label)<tr><th scope="row">{{ $label }}{{ $loop->last ? ' · so far' : '' }}</th><td>{{ number_format($growthValues[$index]) }}</td></tr>@endforeach</tbody>
                </table>
            </details>
        </section>

        <section class="analytics-card analytics-monthly" aria-labelledby="analytics-monthly-title">
            <header class="analytics-card-head">
                <span class="analytics-icon"><i class="bi bi-calendar3" aria-hidden="true"></i></span>
                <div><h2 id="analytics-monthly-title">Monthly Listing Trends</h2><p>Activity over the last 12 months, including the current month</p></div>
            </header>
            <div class="analytics-table-region" tabindex="0" role="region" aria-label="Monthly listing trends table">
                <table class="analytics-table analytics-trends">
                    <thead><tr>
                        <th scope="col">Month</th><th scope="col">Most-listed crop</th>
                        <th scope="col">Top crop listings</th><th scope="col">Total listings</th>
                        <th scope="col" title="Share of the month's listings belonging to the most-listed crop">Top crop share</th>
                    </tr></thead>
                    <tbody>
                        @foreach($monthlyTrends as $trend)
                            <tr @class(['analytics-current' => $loop->last])>
                                <th scope="row">{{ $trend['month'] }} @if($loop->last)<small class="analytics-muted">so far</small>@endif</th>
                                <td>{{ $trend['crop'] ?? 'No listings' }}</td>
                                <td>{{ number_format($trend['top_count']) }}</td>
                                <td>{{ number_format($trend['total']) }}</td>
                                <td title="Share of the month's listings belonging to the most-listed crop">
                                    @if($trend['total'])
                                        <meter min="0" max="{{ $trend['total'] }}" value="{{ $trend['top_count'] }}" aria-label="Top crop share in {{ $trend['month'] }}"></meter>
                                        {{ number_format($trend['top_count']) }} of {{ number_format($trend['total']) }}
                                    @else
                                        <span class="analytics-muted">—</span>
                                    @endif
                                </td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
        </section>
    </div>
</div>
@endsection

@push('scripts')
    <script src="{{ asset('js/analytics.js') }}?v={{ filemtime(public_path('js/analytics.js')) }}" defer></script>
@endpush
