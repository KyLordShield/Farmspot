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

{{-- What is being reported, not just how much. A queue full of spam messages
     calls for a different response than one full of fake listings, and the
     status cards above cannot tell them apart. --}}
<div class="stat-grid">

    <div class="stat-card">
        <div class="stat-icon tint-green">
            <i class="bi bi-basket"></i>
        </div>
        <div>
            <div class="stat-value">{{ $typeCounts['LISTING'] ?? 0 }}</div>
            <div class="stat-label">Crop listings</div>
        </div>
    </div>

    <div class="stat-card">
        <div class="stat-icon tint-amber">
            <i class="bi bi-chat-dots"></i>
        </div>
        <div>
            <div class="stat-value">{{ $typeCounts['MESSAGE'] ?? 0 }}</div>
            <div class="stat-label">Messages</div>
        </div>
    </div>

    <div class="stat-card">
        <div class="stat-icon tint-slate">
            <i class="bi bi-person-badge"></i>
        </div>
        <div>
            <div class="stat-value">{{ ($typeCounts['FARMER'] ?? 0) + ($typeCounts['USER'] ?? 0) }}</div>
            <div class="stat-label">Farmers &amp; users</div>
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