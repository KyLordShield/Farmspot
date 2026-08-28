@extends('layouts.app')

@section('title', 'Reports')

@section('content')

<div class="d-flex justify-content-between align-items-center mb-4">

    <div>
        <h2 class="fw-bold mb-0">Reports</h2>
        <small class="text-muted">
            Manage user reports
        </small>
    </div>

</div>

<div class="card shadow-sm border-0 rounded-4">

    <div class="card-body">

        <!-- Search -->

        <div class="row mb-3">

            <div class="col-md-4">

                <div class="input-group">

                    <span class="input-group-text">
                        <i class="bi bi-search"></i>
                    </span>

                    <input
                        type="text"
                        class="form-control"
                        placeholder="Search reports">

                </div>

            </div>

            <div class="col-md-4">

                <select class="form-select">

                    <option>All Status</option>
                    <option>New</option>
                    <option>Reviewing</option>
                    <option>Resolved</option>
                    <option>Dismissed</option>

                </select>

            </div>

        </div>

        <!-- Summary Card -->

        <div class="row mb-4">

            <div class="col-md-4">

                <div class="dashboard-card">

                    <div class="icon reports">
                        <i class="bi bi-flag-fill"></i>
                    </div>

                    <h2>{{ $reports->total() }}</h2>

                    <p>Total Reports</p>

                </div>

            </div>

        </div>

        <!-- Reports Table -->

        <div class="table-responsive">

            <table class="table table-hover align-middle">

                <thead class="table-light">

                    <tr>

                        <th>Report ID</th>
                        <th>Listing ID</th>
                        <th>User ID</th>
                        <th>Reason</th>
                        <th>Status</th>
                        <th>Date</th>
                        <th width="170">Actions</th>

                    </tr>

                </thead>

                <tbody>

                @forelse($reports as $report)

                    <tr>

                        <td>{{ $report->RPT_ID }}</td>

                        <td>{{ $report->LST_ID }}</td>

                        <td>{{ $report->USR_ID }}</td>

                        <td>{{ $report->RPT_REASON }}</td>

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

                        <td>{{ $report->RPT_CREATED_AT }}</td>

                        <td>

                            <button class="btn btn-sm btn-primary">
                                <i class="bi bi-eye-fill"></i>
                            </button>

                            <button class="btn btn-sm btn-warning">
                                <i class="bi bi-pencil-fill"></i>
                            </button>

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