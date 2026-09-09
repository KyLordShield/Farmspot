@extends('layouts.app')

@section('title', 'Report Details')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">Report Details</h1>
        <div class="page-desc">Report #{{ $report->RPT_ID }}</div>
    </div>
    <div class="page-actions">
        <a href="{{ route('reports') }}" class="btn btn-ghost">
            <i class="bi bi-arrow-left me-1"></i> Back to Reports
        </a>
    </div>
</div>

<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-flag"></i>
            Report #{{ $report->RPT_ID }}
        </h5>
    </div>
    <div class="panel-body p-0">
        <table class="detail-table">

            <tr>
                <th>Reason</th>
                <td>{{ $report->RPT_REASON }}</td>
            </tr>

            <tr>
                <th>Status</th>
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
            </tr>

            <tr>
                <th>Submitted</th>
                <td class="cell-secondary">{{ \Carbon\Carbon::parse($report->RPT_CREATED_AT)->format('M d, Y h:i A') }}</td>
            </tr>

            <tr>
                <th>Reporter</th>
                <td>{{ $report->user?->USR_NAME ?? '-' }}</td>
            </tr>

            <tr>
                <th>Reporter Email</th>
                <td>{{ $report->user?->USR_EMAIL ?? '-' }}</td>
            </tr>

            <tr>
                <th>Reporter ID</th>
                <td><span class="id-cell">{{ $report->USR_ID }}</span></td>
            </tr>

            <tr>
                <th>Reported Listing</th>
                <td><span class="id-cell">{{ $report->listing?->LST_ID ?? '-' }}</span></td>
            </tr>

            <tr>
                <th>Crop</th>
                <td>{{ $report->listing?->category?->CAT_NAME ?? '-' }}</td>
            </tr>

            <tr>
                <th>Farm</th>
                <td>{{ $report->listing?->farm?->FRM_NAME ?? '-' }}</td>
            </tr>

            <tr>
                <th>Listing Owner</th>
                <td>{{ $report->listing?->farmer?->buyer?->user?->USR_NAME ?? '-' }}</td>
            </tr>

        </table>
    </div>
</div>

<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-pencil-square"></i>
            Update Status
        </h5>
    </div>
    <div class="panel-body">
        <form method="POST" action="{{ route('reports.updateStatus', $report->RPT_ID) }}" class="row g-3 align-items-end">
            @csrf
            @method('PATCH')

            <div class="col-md-4">
                <label for="status" class="form-label">Status</label>
                <select class="form-select" id="status" name="status" required>
                    <option value="New" {{ old('status', $report->RPT_STATUS) == 'New' ? 'selected' : '' }}>New</option>
                    <option value="Reviewing" {{ old('status', $report->RPT_STATUS) == 'Reviewing' ? 'selected' : '' }}>Reviewing</option>
                    <option value="Resolved" {{ old('status', $report->RPT_STATUS) == 'Resolved' ? 'selected' : '' }}>Resolved</option>
                    <option value="Dismissed" {{ old('status', $report->RPT_STATUS) == 'Dismissed' ? 'selected' : '' }}>Dismissed</option>
                </select>
            </div>

            <div class="col-auto">
                <button type="submit" class="btn btn-farm">
                    <i class="bi bi-check-lg me-1"></i> Update Status
                </button>
            </div>
        </form>
    </div>
</div>

@endsection