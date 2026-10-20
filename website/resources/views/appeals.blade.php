@extends('layouts.app')

@section('title', 'Appeals')

@section('content')

@php
    $activeStatus = request('status');
    $totalAppeals = $counts->sum();
@endphp

<div class="page-head">
    <div>
        <h1 class="page-title">Appeals</h1>
        <div class="page-desc">Re-evaluation requests from sellers whose listings or accounts were taken down by an admin.</div>
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

{{-- Each card is both a number and a filter, so the overview doubles as the
     queue's quick navigation. The active card is highlighted to keep the
     current filter obvious while scanning the list. --}}
<div class="stat-grid">

    <a href="{{ route('appeals') }}"
       class="stat-card {{ $activeStatus ? '' : 'is-active' }}"
       title="Show every appeal">
        <div class="stat-icon tint-slate">
            <i class="bi bi-collection"></i>
        </div>
        <div>
            <div class="stat-value">{{ $totalAppeals }}</div>
            <div class="stat-label">All appeals</div>
        </div>
    </a>

    <a href="{{ route('appeals', ['status' => 'PENDING']) }}"
       class="stat-card {{ $activeStatus === 'PENDING' ? 'is-active' : '' }}"
       title="Show pending appeals">
        <div class="stat-icon tint-amber">
            <i class="bi bi-shield-exclamation"></i>
        </div>
        <div>
            <div class="stat-value">{{ $counts['PENDING'] ?? 0 }}</div>
            <div class="stat-label">Pending</div>
        </div>
    </a>

    <a href="{{ route('appeals', ['status' => 'APPROVED']) }}"
       class="stat-card {{ $activeStatus === 'APPROVED' ? 'is-active' : '' }}"
       title="Show approved appeals">
        <div class="stat-icon tint-green">
            <i class="bi bi-check-circle"></i>
        </div>
        <div>
            <div class="stat-value">{{ $counts['APPROVED'] ?? 0 }}</div>
            <div class="stat-label">Approved</div>
        </div>
    </a>

    <a href="{{ route('appeals', ['status' => 'DENIED']) }}"
       class="stat-card {{ $activeStatus === 'DENIED' ? 'is-active' : '' }}"
       title="Show denied appeals">
        <div class="stat-icon tint-red">
            <i class="bi bi-x-circle"></i>
        </div>
        <div>
            <div class="stat-value">{{ $counts['DENIED'] ?? 0 }}</div>
            <div class="stat-label">Denied</div>
        </div>
    </a>

</div>

<div class="panel">
    <form method="GET" action="{{ route('appeals') }}" class="filter-bar">
        <div class="filter-auto">
            <select name="status" class="form-select" onchange="this.form.submit()" aria-label="Filter appeals by status">
                <option value="">All statuses</option>
                <option value="PENDING" {{ $activeStatus === 'PENDING' ? 'selected' : '' }}>Pending</option>
                <option value="APPROVED" {{ $activeStatus === 'APPROVED' ? 'selected' : '' }}>Approved</option>
                <option value="DENIED" {{ $activeStatus === 'DENIED' ? 'selected' : '' }}>Denied</option>
            </select>
        </div>
        <div class="ms-auto cell-faint d-flex align-items-center gap-1">
            <i class="bi bi-sort-down"></i>
            <span>Newest first</span>
        </div>
    </form>

    <div class="table-responsive">
        <table class="data-table">
            <thead>
                <tr>
                    <th>Appeal ID</th>
                    <th>Requester</th>
                    <th>Target</th>
                    <th>Status</th>
                    <th>Submitted</th>
                    <th>Decided</th>
                    <th class="text-end">Actions</th>
                </tr>
            </thead>
            <tbody>
            @forelse($appeals as $appeal)
                @php
                    $isListing = $appeal->RRQ_TARGET_TYPE === \App\Models\ReviewRequest::TARGET_LISTING;
                    $targetName = $isListing
                        ? $appeal->listing?->farm?->FRM_NAME
                        : $appeal->account?->USR_NAME;
                @endphp
                <tr>
                    <td>
                        <a href="{{ route('appeals.show', $appeal->RRQ_ID) }}" class="id-cell text-decoration-none">
                            {{ $appeal->RRQ_ID }}
                        </a>
                    </td>
                    <td>
                        {{ $appeal->user?->USR_NAME ?? '-' }}
                        @if($appeal->user?->USR_EMAIL)
                            <div class="cell-faint">{{ $appeal->user->USR_EMAIL }}</div>
                        @endif
                    </td>
                    <td>
                        <span class="badge badge-soft-neutral">{{ $isListing ? 'Crop listing' : 'User account' }}</span>
                        <span class="id-cell ms-1">{{ $appeal->RRQ_TARGET_ID }}</span>
                        @if($targetName)
                            <div class="cell-faint">{{ $targetName }}</div>
                        @endif
                    </td>
                    <td>
                        @if($appeal->RRQ_STATUS === 'PENDING')<span class="badge badge-soft-warning">Pending</span>
                        @elseif($appeal->RRQ_STATUS === 'APPROVED')<span class="badge badge-soft-success">Approved</span>
                        @else<span class="badge badge-soft-neutral">Denied</span>@endif
                    </td>
                    <td class="cell-faint">{{ \Carbon\Carbon::parse($appeal->RRQ_CREATED_AT)->timezone(config('farmspot.display_timezone'))->format('M d, Y h:i A') }}</td>
                    <td class="cell-faint">
                        @if($appeal->RRQ_DECIDED_AT)
                            {{ \Carbon\Carbon::parse($appeal->RRQ_DECIDED_AT)->timezone(config('farmspot.display_timezone'))->format('M d, Y h:i A') }}
                            <div class="cell-faint">by {{ $appeal->decidedBy?->USR_NAME ?? 'an admin' }}</div>
                        @else
                            -
                        @endif
                    </td>
                    <td class="text-end">
                        <div class="actions justify-content-end">
                            <a href="{{ route('appeals.show', $appeal->RRQ_ID) }}" class="btn btn-ghost btn-sm">
                                <i class="bi bi-eye me-1"></i> View
                            </a>
                        </div>
                    </td>
                </tr>
            @empty
                <tr>
                    <td colspan="7">
                        <div class="empty-state">
                            <i class="bi bi-shield-exclamation empty-icon"></i>
                            <p>No appeals match this filter.</p>
                        </div>
                    </td>
                </tr>
            @endforelse
            </tbody>
        </table>
    </div>

    <div class="panel-body pt-0 pb-3">
        {{ $appeals->links() }}
    </div>
</div>

@endsection
