@extends('layouts.app')

@section('title', 'Appeal Details')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">Appeal Details</h1>
        <div class="page-desc">Appeal #{{ $appeal->RRQ_ID }}</div>
    </div>
    <div class="page-actions">
        <a href="{{ route('appeals') }}" class="btn btn-ghost">
            <i class="bi bi-arrow-left me-1"></i> Back to Appeals
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

<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-shield-exclamation"></i>
            Appeal #{{ $appeal->RRQ_ID }}
        </h5>
    </div>
    <div class="panel-body p-0">
        <table class="detail-table">
            <tr>
                <th>Target</th>
                <td>
                    <span class="badge badge-soft-neutral">{{ $appeal->RRQ_TARGET_TYPE }}</span>
                    <span class="id-cell ms-2">{{ $appeal->RRQ_TARGET_ID }}</span>
                </td>
            </tr>
            <tr>
                <th>Status</th>
                <td>
                    @if($appeal->RRQ_STATUS === 'PENDING')<span class="badge badge-soft-warning">Pending</span>
                    @elseif($appeal->RRQ_STATUS === 'APPROVED')<span class="badge badge-soft-success">Approved</span>
                    @else<span class="badge badge-soft-neutral">Denied</span>@endif
                </td>
            </tr>
            <tr>
                <th>Requester</th>
                <td>
                    {{ $appeal->user?->USR_NAME ?? '-' }}
                    @if($appeal->user?->USR_EMAIL)
                        <div class="cell-secondary">{{ $appeal->user->USR_EMAIL }}</div>
                    @endif
                    <span class="id-cell ms-2">{{ $appeal->USR_ID }}</span>
                </td>
            </tr>
            <tr>
                <th>Reason given</th>
                <td style="white-space: pre-wrap;">{{ $appeal->RRQ_REASON ?? '-' }}</td>
            </tr>
            <tr>
                <th>Submitted</th>
                <td class="cell-secondary">{{ \Carbon\Carbon::parse($appeal->RRQ_CREATED_AT)->format('M d, Y h:i A') }}</td>
            </tr>
            <tr>
                <th>Decided</th>
                <td class="cell-secondary">
                    @if($appeal->RRQ_DECIDED_AT)
                        {{ \Carbon\Carbon::parse($appeal->RRQ_DECIDED_AT)->format('M d, Y h:i A') }}
                        @if($appeal->decidedBy?->USR_NAME)
                            <div class="cell-faint">by {{ $appeal->decidedBy->USR_NAME }}</div>
                        @endif
                    @else
                        -
                    @endif
                </td>
            </tr>
            @if($appeal->RRQ_ADMIN_NOTE)
                <tr>
                    <th>Admin note</th>
                    <td style="white-space: pre-wrap;">{{ $appeal->RRQ_ADMIN_NOTE }}</td>
                </tr>
            @endif
        </table>
    </div>
</div>

@if($appeal->RRQ_TARGET_TYPE === \App\Models\ReviewRequest::TARGET_LISTING)
    <div class="panel">
        <div class="panel-header">
            <h5 class="panel-title">
                <i class="bi bi-basket"></i>
                Listing Details
            </h5>
        </div>
        <div class="panel-body p-0">
            <table class="detail-table">
                <tr>
                    <th>Listing ID</th>
                    <td><span class="id-cell">{{ $appeal->listing?->LST_ID ?? $appeal->RRQ_TARGET_ID }}</span></td>
                </tr>
                <tr>
                    <th>Farm</th>
                    <td>{{ $appeal->listing?->farm?->FRM_NAME ?? '-' }}</td>
                </tr>
                <tr>
                    <th>Status</th>
                    <td>{{ $appeal->listing?->LST_STATUS ?? '-' }}</td>
                </tr>
                <tr>
                    <th>Availability</th>
                    <td>{{ $appeal->listing?->LST_AVAILABILITY ?? '-' }}</td>
                </tr>
                <tr>
                    <th>Takedown reason</th>
                    <td class="cell-secondary" style="white-space: pre-wrap;">{{ $appeal->listing?->LST_TAKEDOWN_REASON ?? '-' }}</td>
                </tr>
            </table>
        </div>
    </div>
@else
    <div class="panel">
        <div class="panel-header">
            <h5 class="panel-title">
                <i class="bi bi-person-badge"></i>
                Account Details
            </h5>
        </div>
        <div class="panel-body p-0">
            <table class="detail-table">
                <tr>
                    <th>Name</th>
                    <td>{{ $appeal->account?->USR_NAME ?? '-' }}</td>
                </tr>
                <tr>
                    <th>Email</th>
                    <td>{{ $appeal->account?->USR_EMAIL ?? '-' }}</td>
                </tr>
                <tr>
                    <th>Status</th>
                    <td>{{ $appeal->account?->USR_STATUS ?? '-' }}</td>
                </tr>
                <tr>
                    <th>Takedown reason</th>
                    <td class="cell-secondary" style="white-space: pre-wrap;">{{ $appeal->account?->USR_TAKEDOWN_REASON ?? '-' }}</td>
                </tr>
            </table>
        </div>
    </div>
@endif

@if($appeal->isPending())
    <div class="panel">
        <div class="panel-header">
            <h5 class="panel-title">
                <i class="bi bi-gear"></i>
                Decide Appeal
            </h5>
        </div>
        <div class="panel-body">
            <form method="POST" action="{{ route('appeals.approve', $appeal->RRQ_ID) }}" class="mb-4" data-auto-spinner>
                @csrf
                <div class="row g-3 align-items-end">
                    <div class="col-md-6">
                        <label class="form-label" for="note-approve">Admin note (optional)</label>
                        <input type="text" class="form-control" id="note-approve" name="note" maxlength="500" placeholder="Note shown to the requester or for audit trail">
                    </div>
                    <div class="col-auto">
                        <button type="submit" class="btn btn-success">
                            <i class="bi bi-check-lg me-1"></i> Approve &amp; Restore
                        </button>
                    </div>
                </div>
            </form>

            <form method="POST" action="{{ route('appeals.deny', $appeal->RRQ_ID) }}" data-auto-spinner>
                @csrf
                <div class="row g-3 align-items-end">
                    <div class="col-md-6">
                        <label class="form-label" for="note-deny">Admin note (optional)</label>
                        <input type="text" class="form-control" id="note-deny" name="note" maxlength="500" placeholder="Reason to keep decision in place">
                    </div>
                    <div class="col-auto">
                        <button type="submit" class="btn btn-farm" data-confirm-title="Deny appeal?" data-confirm-text="This keeps the takedown in place. The decision is final until a new takedown occurs." data-confirm-tone="danger">
                            <i class="bi bi-x-lg me-1"></i> Deny
                        </button>
                    </div>
                </div>
            </form>
        </div>
    </div>
@endif

@endsection
