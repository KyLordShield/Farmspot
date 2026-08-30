@extends('layouts.app')

@section('title', 'Report Details')

@section('content')

<div class="d-flex justify-content-between align-items-center mb-4">
    <div>
        <h2 class="fw-bold mb-0">Report Details</h2>
        <small class="text-muted">Report #{{ $report->RPT_ID }}</small>
    </div>
    <a href="{{ route('reports') }}" class="btn btn-outline-secondary">
        <i class="bi bi-arrow-left"></i> Back to Reports
    </a>
</div>

<div class="card shadow-sm border-0 rounded-4">
    <div class="card-header bg-success text-white">
        <h4 class="mb-0"><i class="bi bi-flag-fill"></i> Report #{{ $report->RPT_ID }}</h4>
    </div>
    <div class="card-body">
        <table class="table">

            <tr>
                <th>Reason</th>
                <td>{{ $report->RPT_REASON }}</td>
            </tr>

            <tr>
                <th>Status</th>
                <td>
                    @if($report->RPT_STATUS == 'New')
                        <span class="badge bg-danger">New</span>
                    @elseif($report->RPT_STATUS == 'Reviewing')
                        <span class="badge bg-warning text-dark">Reviewing</span>
                    @elseif($report->RPT_STATUS == 'Resolved')
                        <span class="badge bg-success">Resolved</span>
                    @else
                        <span class="badge bg-secondary">Dismissed</span>
                    @endif
                </td>
            </tr>

            <tr>
                <th>Submitted</th>
                <td>{{ \Carbon\Carbon::parse($report->RPT_CREATED_AT)->format('M d, Y h:i A') }}</td>
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
                <td>{{ $report->USR_ID }}</td>
            </tr>

            <tr>
                <th>Reported Listing</th>
                <td>{{ $report->listing?->LST_ID ?? '-' }}</td>
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

<div class="card shadow-sm border-0 rounded-4 mt-4">
    <div class="card-header bg-primary text-white">
        <h4 class="mb-0"><i class="bi bi-pencil-square"></i> Update Status</h4>
    </div>
    <div class="card-body">
        <form method="POST" action="{{ route('reports.updateStatus', $report->RPT_ID) }}">
            @csrf
            @method('PATCH')

            <div class="mb-3">
                <label for="status" class="form-label">Status</label>
                <select class="form-select" id="status" name="status" required>
                    <option value="New" {{ old('status', $report->RPT_STATUS) == 'New' ? 'selected' : '' }}>New</option>
                    <option value="Reviewing" {{ old('status', $report->RPT_STATUS) == 'Reviewing' ? 'selected' : '' }}>Reviewing</option>
                    <option value="Resolved" {{ old('status', $report->RPT_STATUS) == 'Resolved' ? 'selected' : '' }}>Resolved</option>
                    <option value="Dismissed" {{ old('status', $report->RPT_STATUS) == 'Dismissed' ? 'selected' : '' }}>Dismissed</option>
                </select>
            </div>

            <button type="submit" class="btn btn-primary">
                <i class="bi bi-check-lg"></i> Update Status
            </button>
        </form>
    </div>
</div>

@endsection