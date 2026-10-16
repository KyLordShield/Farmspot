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

{{-- The mass-report signal is now the clickable "Mass reported" card in the
     overview below, so this no longer needs a banner of its own at the top.
     Clicking the card opens the same grouped alert list the banner linked to. --}}

<div class="stat-grid">

    {{-- Each card doubles as the filter its number describes, so the overview
         is also the queue's quick filter. Total is the unfiltered view, which
         is what the queue shows by default. --}}
    <a href="{{ route('reports') }}" class="stat-card" title="Show every report">
        <div class="stat-icon tint-slate">
            <i class="bi bi-flag"></i>
        </div>
        <div>
            <div class="stat-value">{{ $totalReports }}</div>
            <div class="stat-label">Total reports</div>
        </div>
    </a>

    {{-- Always rendered, so the grid keeps the same four cards no matter the
         state of the queue. Zero simply means no target has reached the
         threshold yet. --}}
    <a href="{{ route('reports.flagged') }}" class="stat-card" title="Review mass-report alerts">
        <div class="stat-icon tint-amber">
            <i class="bi bi-exclamation-triangle-fill"></i>
        </div>
        <div>
            <div class="stat-value">{{ $flaggedTargetCount ?? 0 }}</div>
            <div class="stat-label">Mass reported</div>
        </div>
    </a>

    <a href="{{ route('reports', ['status' => 'Resolved']) }}" class="stat-card" title="Show resolved reports">
        <div class="stat-icon tint-green">
            <i class="bi bi-check-circle"></i>
        </div>
        <div>
            <div class="stat-value">{{ $counts['Resolved'] ?? 0 }}</div>
            <div class="stat-label">Resolved</div>
        </div>
    </a>

    <a href="{{ route('reports', ['status' => 'New']) }}" class="stat-card" title="Show new reports">
        <div class="stat-icon tint-red">
            <i class="bi bi-bell"></i>
        </div>
        <div>
            <div class="stat-value">{{ $counts['New'] ?? 0 }}</div>
            <div class="stat-label">New</div>
        </div>
    </a>

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
                    placeholder="Search reason, details, reporter or reported id">
                <button class="btn btn-farm" type="submit">
                    Search
                </button>
            </div>
        </div>

        <div class="filter-auto">
            <select name="type" class="form-select" onchange="this.form.submit()">
                <option value="">All Types</option>
                <option value="LISTING" {{ request('type') == 'LISTING' ? 'selected' : '' }}>Crop listing</option>
                <option value="MESSAGE" {{ request('type') == 'MESSAGE' ? 'selected' : '' }}>Message</option>
                <option value="FARMER" {{ request('type') == 'FARMER' ? 'selected' : '' }}>Farmer / seller</option>
                <option value="USER" {{ request('type') == 'USER' ? 'selected' : '' }}>User</option>
            </select>
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
                    <th>Type</th>
                    <th>Reported</th>
                    <th>Reporter</th>
                    <th>Reason</th>
                    <th>Status</th>
                    <th>Date</th>
                    <th>Action Taken</th>
                    <th>Actions</th>
                </tr>
            </thead>

            <tbody>

            @forelse($reports as $report)

                <tr>
                    <td><span class="id-cell">{{ $report->RPT_ID }}</span></td>
                    <td>
                        @php
                            $typeLabels = [
                                'LISTING' => 'Crop listing',
                                'MESSAGE' => 'Message',
                                'FARMER' => 'Farmer',
                                'USER' => 'User',
                            ];
                        @endphp
                        <span class="badge badge-soft-neutral">{{ $typeLabels[$report->RPT_TARGET_TYPE] ?? $report->RPT_TARGET_TYPE }}</span>
                    </td>
                    <td class="cell-secondary">
                        {{ $report->targetLabel() ?? '-' }}
                    </td>
                    <td class="cell-secondary">{{ $report->user?->USR_NAME ?? '-' }}</td>
                    <td class="cell-secondary">{{ \Illuminate\Support\Str::limit($report->reasonLabel(), 60) }}</td>
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
                        {{-- Only while the report is still open. Once it is
                             Resolved or Dismissed the flag has done its job. --}}
                        @if($report->RPT_FLAGGED_AT && in_array($report->RPT_STATUS, ['New', 'Reviewing'], true))
                            <span class="badge badge-soft-danger" title="Mass-report threshold reached">
                                <i class="bi bi-exclamation-triangle-fill"></i> Flagged
                            </span>
                        @endif
                    </td>
                    <td class="cell-faint">{{ \Carbon\Carbon::parse($report->RPT_CREATED_AT)->format('M d, Y h:i A') }}</td>
                    <td>
                        {{-- Whether anything was actually done, visible from the
                             list. A status of "Resolved" on its own does not
                             tell a moderator whether the listing came down or
                             the report was simply closed. --}}
                        @php $live = $report->live_actions_count; @endphp
                        @if($live > 0)
                            <span class="badge badge-soft-danger">
                                <i class="bi bi-shield-fill-exclamation"></i>
                                {{ $live }} action{{ $live > 1 ? 's' : '' }} in force
                            </span>
                        @else
                            <span class="cell-faint">-</span>
                        @endif
                    </td>
                    <td>
                        <div class="actions">
                            <a href="{{ route('reports.show', $report->RPT_ID) }}"
                               class="btn-icon" title="View">
                                <i class="bi bi-eye"></i>
                            </a>

                            <form method="POST" action="{{ route('reports.updateStatus', $report->RPT_ID) }}"
                                  class="d-inline"
                                  data-confirm-select-label="report status">
                                @csrf
                                @method('PATCH')
                                <select name="status" class="form-select form-select-sm"
                                        style="width: 128px;"
                                        data-confirm-select title="Update status">
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
                    <td colspan="8">
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