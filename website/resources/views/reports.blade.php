@extends('layouts.app')

@section('title', 'Reports')

@section('content')

<div class="d-flex justify-content-between align-items-center mb-4">

    <div>
        <h2 class="fw-bold mb-0">Reports</h2>
        <small class="text-muted">
            Moderator queue — reports submitted by users
        </small>
    </div>

</div>

@if(session('success'))
    <div class="alert alert-success alert-dismissible fade show" role="alert">
        {{ session('success') }}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
@endif

<div class="card shadow-sm border-0 rounded-4">

    <div class="card-body">

        <!-- Filters -->

        <form method="GET" action="{{ route('reports') }}" class="row mb-3">

            <div class="col-md-4">

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

                    <button class="btn btn-success" type="submit">
                        Search
                    </button>

                </div>

            </div>

            <div class="col-md-4">

                <select name="status" class="form-select" onchange="this.form.submit()">

                    <option value="">All Status</option>

                    <option value="New" {{ request('status') == 'New' ? 'selected' : '' }}>New</option>
                    <option value="Reviewing" {{ request('status') == 'Reviewing' ? 'selected' : '' }}>Reviewing</option>
                    <option value="Resolved" {{ request('status') == 'Resolved' ? 'selected' : '' }}>Resolved</option>
                    <option value="Dismissed" {{ request('status') == 'Dismissed' ? 'selected' : '' }}>Dismissed</option>

                </select>

            </div>

        </form>

        <!-- Summary Cards -->

        <div class="row mb-4">

            <div class="col-md-3">

                <div class="dashboard-card">

                    <div class="icon reports">
                        <i class="bi bi-flag-fill"></i>
                    </div>

                    <h2>{{ $reports->total() }}</h2>

                    <p>Total Reports</p>

                </div>

            </div>

            <div class="col-md-3">

                <div class="dashboard-card">

                    <div class="icon users">
                        <i class="bi bi-bell-fill"></i>
                    </div>

                    <h2>{{ $counts['New'] ?? 0 }}</h2>

                    <p class="text-danger">New</p>

                </div>

            </div>

            <div class="col-md-3">

                <div class="dashboard-card">

                    <div class="icon farmers">
                        <i class="bi bi-search"></i>
                    </div>

                    <h2>{{ $counts['Reviewing'] ?? 0 }}</h2>

                    <p class="text-warning">Reviewing</p>

                </div>

            </div>

            <div class="col-md-3">

                <div class="dashboard-card">

                    <div class="icon listings">
                        <i class="bi bi-check-circle-fill"></i>
                    </div>

                    <h2>{{ $counts['Resolved'] ?? 0 }}</h2>

                    <p class="text-success">Resolved</p>

                </div>

            </div>

        </div>

        <!-- Reports Table -->

        <div class="table-responsive">

            <table class="table table-hover align-middle">

                <thead class="table-light">

                    <tr>

                        <th>Report ID</th>
                        <th>Reporter</th>
                        <th>Reported Listing</th>
                        <th>Reason</th>
                        <th>Status</th>
                        <th>Date</th>
                        <th width="180">Actions</th>

                    </tr>

                </thead>

                <tbody>

                @forelse($reports as $report)

                    <tr>

                        <td>{{ $report->RPT_ID }}</td>

                        <td>{{ $report->user?->USR_NAME ?? '-' }}</td>

                        <td>{{ $report->listing?->LST_ID ?? '-' }}</td>

                        <td>{{ \Illuminate\Support\Str::limit($report->RPT_REASON, 60) }}</td>

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

                        <td>{{ \Carbon\Carbon::parse($report->RPT_CREATED_AT)->format('M d, Y h:i A') }}</td>

                        <td>

                            <a href="{{ route('reports.show', $report->RPT_ID) }}"
                               class="btn btn-sm btn-primary">
                                <i class="bi bi-eye-fill"></i>
                            </a>

                            <form method="POST" action="{{ route('reports.updateStatus', $report->RPT_ID) }}"
                                  class="d-inline">
                                @csrf
                                @method('PATCH')
                                <select name="status" class="form-select form-select-sm d-inline-block w-auto"
                                        onchange="this.form.submit()">
                                    <option value="New" {{ $report->RPT_STATUS == 'New' ? 'selected' : '' }}>New</option>
                                    <option value="Reviewing" {{ $report->RPT_STATUS == 'Reviewing' ? 'selected' : '' }}>Reviewing</option>
                                    <option value="Resolved" {{ $report->RPT_STATUS == 'Resolved' ? 'selected' : '' }}>Resolved</option>
                                    <option value="Dismissed" {{ $report->RPT_STATUS == 'Dismissed' ? 'selected' : '' }}>Dismissed</option>
                                </select>
                            </form>

                        </td>

                    </tr>

                @empty

                    <tr>

                        <td colspan="7" class="text-center text-muted py-5">

                            <i class="bi bi-flag display-5"></i>

                            <p class="mt-2">
                                No reports found.
                            </p>

                        </td>

                    </tr>

                @endforelse

                </tbody>

            </table>

        </div>

        <div class="mt-3">

            {{ $reports->links() }}

        </div>

    </div>

</div>

@endsection