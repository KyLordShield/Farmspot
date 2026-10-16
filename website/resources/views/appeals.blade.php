@extends('layouts.app')

@section('title', 'Appeals')

@section('content')

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

<div class="stat-grid">
    <div class="stat-card">
        <div class="stat-icon tint-amber">
            <i class="bi bi-shield-exclamation"></i>
        </div>
        <div>
            <div class="stat-value">{{ $counts['PENDING'] ?? 0 }}</div>
            <div class="stat-label">Pending</div>
        </div>
    </div>
    <div class="stat-card">
        <div class="stat-icon tint-green">
            <i class="bi bi-check-circle"></i>
        </div>
        <div>
            <div class="stat-value">{{ $counts['APPROVED'] ?? 0 }}</div>
            <div class="stat-label">Approved</div>
        </div>
    </div>
    <div class="stat-card">
        <div class="stat-icon tint-slate">
            <i class="bi bi-x-circle"></i>
        </div>
        <div>
            <div class="stat-value">{{ $counts['DENIED'] ?? 0 }}</div>
            <div class="stat-label">Denied</div>
        </div>
    </div>
</div>

<div class="panel">
    <form method="GET" action="{{ route('appeals') }}" class="filter-bar">
        <div class="filter-auto">
            <select name="status" class="form-select" onchange="this.form.submit()">
                <option value="">All Status</option>
                <option value="PENDING" {{ request('status') == 'PENDING' ? 'selected' : '' }}>Pending</option>
                <option value="APPROVED" {{ request('status') == 'APPROVED' ? 'selected' : '' }}>Approved</option>
                <option value="DENIED" {{ request('status') == 'DENIED' ? 'selected' : '' }}>Denied</option>
            </select>
        </div>
    </form>

    <div class="table-responsive">
        <table class="data-table">
            <thead>
                <tr>
                    <th>Appeal ID</th>
                    <th>Requester</th>
                    <th>Target</th>
                    <th>Reason Given</th>
                    <th>Status</th>
                    <th>Submitted</th>
                    <th>Decided</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
            @forelse($appeals as $appeal)
                <tr>
                    <td><span class="id-cell">{{ $appeal->RRQ_ID }}</span></td>
                    <td>{{ $appeal->user?->USR_NAME ?? '-' }}@if($appeal->user?->USR_EMAIL)<div class="cell-faint">{{ $appeal->user->USR_EMAIL }}</div>@endif</td>
                    <td>
                        <span class="badge badge-soft-neutral">{{ $appeal->RRQ_TARGET_TYPE }}</span>
                        <span class="id-cell ms-1">{{ $appeal->RRQ_TARGET_ID }}</span>
                        @if($appeal->RRQ_TARGET_TYPE === \App\Models\ReviewRequest::TARGET_LISTING && $appeal->listing?->farm?->FRM_NAME)
                            <div class="cell-faint">{{ $appeal->listing->farm->FRM_NAME }}</div>
                        @endif
                    </td>
                    <td class="cell-secondary">{{ \Illuminate\Support\Str::limit($appeal->RRQ_REASON, 60) }}</td>
                    <td>
                        @if($appeal->RRQ_STATUS === 'PENDING')<span class="badge badge-soft-warning">Pending</span>
                        @elseif($appeal->RRQ_STATUS === 'APPROVED')<span class="badge badge-soft-success">Approved</span>
                        @else<span class="badge badge-soft-neutral">Denied</span>@endif
                    </td>
                    <td class="cell-faint">{{ \Carbon\Carbon::parse($appeal->RRQ_CREATED_AT)->format('M d, Y h:i A') }}</td>
                    <td class="cell-faint">
                        @if($appeal->RRQ_DECIDED_AT)
                            {{ \Carbon\Carbon::parse($appeal->RRQ_DECIDED_AT)->format('M d, Y h:i A') }}
                            <div class="cell-faint">by {{ $appeal->decidedBy?->USR_NAME ?? 'an admin' }}</div>
                        @else
                            -
                        @endif
                    </td>
                    <td>
                        <div class="actions">
                            <a href="{{ route('appeals.show', $appeal->RRQ_ID) }}" class="btn-icon" title="View">
                                <i class="bi bi-eye"></i>
                            </a>
                        </div>
                    </td>
                </tr>
            @empty
                <tr>
                    <td colspan="8">
                        <div class="empty-state">
                            <i class="bi bi-shield-exclamation empty-icon"></i>
                            <p>No appeals found.</p>
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
