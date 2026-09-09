@extends('layouts.app')

@section('title', 'Reports')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">Reports</h1>
        <div class="page-desc">Moderator queue — reports submitted by users</div>
    </div>
</div>

@if(session('success'))
    <div class="alert alert-success alert-dismissible fade show" role="alert">
        {{ session('success') }}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
@endif

<div class="stat-grid">

    <div class="stat-card">
        <div class="stat-icon tint-red">
            <i class="bi bi-flag"></i>
        </div>
        <div>
            <div class="stat-value">{{ $reports->total() }}</div>
            <div class="stat-label">Total reports</div>
        </div>
    </div>

    <div class="stat-card">
        <div class="stat-icon tint-amber">
            <i class="bi bi-bell"></i>
        </div>
        <div>
            <div class="stat-value">{{ $counts['New'] ?? 0 }}</div>
            <div class="stat-label">New</div>
        </div>
    </div>

    <div class="stat-card">
        <div class="stat-icon tint-slate">
            <i class="bi bi-search"></i>
        </div>
        <div>
            <div class="stat-value">{{ $counts['Reviewing'] ?? 0 }}</div>
            <div class="stat-label">Reviewing</div>
        </div>
    </div>

    <div class="stat-card">
        <div class="stat-icon tint-green">
            <i class="bi bi-check-circle"></i>
        </div>
        <div>
            <div class="stat-value">{{ $counts['Resolved'] ?? 0 }}</div>
            <div class="stat-label">Resolved</div>
        </div>
    </div>

</div>

<div class="panel">

    <!-- Filters -->
    <form method="GET" action="{{ route('reports') }}" class="filter-bar">

        <div class="filter-grow">
            <div class="input-group">
                <span class="input-group-text">
                    <i class="bi bi-search"></i>
                </span>
                <input
                    type="text"
                    name="search"
                    value="{{ request('search') }}"
                    class="form-control"
                    placeholder="Search by reason, reporter or listing">
                <button class="btn btn-farm" type="submit">
                    Search
                </button>
            </div>
        </div>

        <div class="filter-auto">
            <select name="status" class="form-select" onchange="this.form.submit()">
                <option value="">All Status</option>
                <option value="New" {{ request('status') == 'New' ? 'selected' : '' }}>New</option>
                <option value="Reviewing" {{ request('status') == 'Reviewing' ? 'selected' : '' }}>Reviewing</option>
                <option value="Resolved" {{ request('status') == 'Resolved' ? 'selected' : '' }}>Resolved</option>
                <option value="Dismissed" {{ request('status') == 'Dismissed' ? 'selected' : '' }}>Dismissed</option>
            </select>
        </div>

    </form>

    <div class="table-responsive">
        <table class="data-table">

            <thead>
                <tr>
                    <th>Report ID</th>
                    <th>Reporter</th>
                    <th>Reported Listing</th>
                    <th>Reason</th>
                    <th>Status</th>
                    <th>Date</th>
                    <th>Actions</th>
                </tr>
            </thead>

            <tbody>

            @forelse($reports as $report)

                <tr>
                    <td><span class="id-cell">{{ $report->RPT_ID }}</span></td>
                    <td class="cell-secondary">{{ $report->user?->USR_NAME ?? '-' }}</td>
                    <td><span class="id-cell">{{ $report->listing?->LST_ID ?? '-' }}</span></td>
                    <td class="cell-secondary">{{ \Illuminate\Support\Str::limit($report->RPT_REASON, 60) }}</td>
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
                    <td class="cell-faint">{{ \Carbon\Carbon::parse($report->RPT_CREATED_AT)->format('M d, Y h:i A') }}</td>
                    <td>
                        <div class="actions">
                            <a href="{{ route('reports.show', $report->RPT_ID) }}"
                               class="btn-icon" title="View">
                                <i class="bi bi-eye"></i>
                            </a>

                            <form method="POST" action="{{ route('reports.updateStatus', $report->RPT_ID) }}"
                                  class="d-inline">
                                @csrf
                                @method('PATCH')
                                <select name="status" class="form-select form-select-sm"
                                        style="width: 128px;"
                                        onchange="this.form.submit()" title="Update status">
                                    <option value="New" {{ $report->RPT_STATUS == 'New' ? 'selected' : '' }}>New</option>
                                    <option value="Reviewing" {{ $report->RPT_STATUS == 'Reviewing' ? 'selected' : '' }}>Reviewing</option>
                                    <option value="Resolved" {{ $report->RPT_STATUS == 'Resolved' ? 'selected' : '' }}>Resolved</option>
                                    <option value="Dismissed" {{ $report->RPT_STATUS == 'Dismissed' ? 'selected' : '' }}>Dismissed</option>
                                </select>
                            </form>
                        </div>
                    </td>
                </tr>

            @empty

                <tr>
                    <td colspan="7">
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

    <div class="panel-body pt-0 pb-3">
        {{ $reports->links() }}
    </div>

</div>

@endsection