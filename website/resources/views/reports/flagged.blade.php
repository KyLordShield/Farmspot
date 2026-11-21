@extends('layouts.app')

@section('title', 'Mass Report Alerts')

@include('partials._admin-refresh')

@section('content')
<div class="admin-refresh admin-refresh-queue">
<div class="page-head">
    <div>
        <nav class="admin-refresh-crumb" aria-label="Breadcrumb">
            <a href="{{ route('reports') }}">Reports</a><span aria-hidden="true">/</span><span aria-current="page">Mass-report alerts</span>
        </nav>
        <h1 class="page-title">Mass Report Alerts</h1>
        <div class="page-desc">
            Accounts and items reported by multiple people that need review
        </div>
    </div>
    <div class="page-actions">
        <a href="{{ route('reports') }}" class="btn btn-ghost">
            <i class="bi bi-arrow-left me-1"></i> Back to Reports
        </a>
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

{{-- One row per target, not per report. This is the whole reason the page
     exists: a flat list of ten rows about the same account hides the fact that
     it is one account. --}}
<div class="admin-report-notice" role="note">
    <i class="bi bi-info-circle" aria-hidden="true"></i>
    <div>An alert appears after <strong>{{ $threshold }} different people</strong> report the same account or item.
        <strong>Read the reports before taking action.</strong></div>
</div>

@forelse($alerts as $alert)

    <div class="panel">
        <div class="panel-body">
            <div class="d-flex align-items-start justify-content-between flex-wrap gap-3">

                <div class="d-flex align-items-start gap-3">
                    <div class="stat-icon tint-red" style="flex: 0 0 auto;">
                        <i class="bi bi-{{ $alert['icon'] }}"></i>
                    </div>
                    <div>
                        <div class="d-flex align-items-center gap-2 flex-wrap">
                            <h5 class="mb-0">
                                @if($alert['url'])
                                    <a href="{{ $alert['url'] }}" class="text-decoration-none">
                                        {{ $alert['name'] }}
                                        <i class="bi bi-box-arrow-up-right small"></i>
                                    </a>
                                @else
                                    {{ $alert['name'] }}
                                @endif
                            </h5>
                            <span class="badge badge-soft-neutral">{{ $alert['type_label'] }}</span>
                            <span class="id-cell">{{ $alert['id'] }}</span>
                        </div>
                        <div class="cell-secondary mt-1">{{ $alert['subtitle'] }}</div>
                        <div class="cell-faint mt-1">
                            First report {{ \Carbon\Carbon::parse($alert['first_at'])->format('M d, Y h:i A') }}
                            · Latest {{ \Carbon\Carbon::parse($alert['last_at'])->format('M d, Y h:i A') }}
                        </div>
                    </div>
                </div>

                <div class="d-flex align-items-center gap-3 flex-wrap">
                    <div class="text-center">
                        <div class="stat-value" style="color: var(--bs-danger, #b02a37);">{{ $alert['reporter_count'] }}</div>
                        <div class="stat-label">Reporter{{ $alert['reporter_count'] == 1 ? '' : 's' }}</div>
                    </div>
                    <div class="text-center">
                        <div class="stat-value">{{ $alert['open_count'] }}</div>
                        <div class="stat-label">Open report{{ $alert['open_count'] == 1 ? '' : 's' }}</div>
                    </div>
                    <a href="{{ route('reports.flaggedTarget', [$alert['type'], $alert['id']]) }}"
                       class="btn btn-farm">
                        <i class="bi bi-people me-1"></i> Review reporters
                    </a>
                </div>

            </div>
        </div>
    </div>

@empty

    <div class="panel">
        <div class="panel-body">
            <div class="empty-state">
                <i class="bi bi-shield-check empty-icon"></i>
                <p>No mass-report alerts. Nothing has reached {{ $threshold }} distinct reporters.</p>
            </div>
        </div>
    </div>

@endforelse
</div>
@endsection
