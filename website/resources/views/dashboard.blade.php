@extends('layouts.app')

@section('title', 'Dashboard')

@section('content')

<div class="d-flex justify-content-between align-items-center mb-4">

    <div>
        <h2 class="fw-bold mb-0">Overview</h2>
        <small class="text-muted">
            FarmSpot Management Dashboard
        </small>
    </div>

    <button class="btn btn-success">
        <i class="bi bi-download"></i>
        Export Data
    </button>

</div>


<div class="row g-4">

    <!-- Users -->

    <div class="col-lg-3 col-md-6">

        <div class="dashboard-card">

            <div class="icon users">

                <i class="bi bi-people-fill"></i>

            </div>

            <h2>{{ $users }}</h2>

            <p>Total Users</p>

        </div>

    </div>


    <!-- Farmers -->

    <div class="col-lg-3 col-md-6">

        <div class="dashboard-card">

            <div class="icon farmers">

                <i class="bi bi-person-badge-fill"></i>

            </div>

            <h2>{{ $farmers }}</h2>

            <p>Total Farmers</p>

        </div>

    </div>


    <!-- Listings -->

    <div class="col-lg-3 col-md-6">

        <div class="dashboard-card">

            <div class="icon listings">

                <i class="bi bi-basket-fill"></i>

            </div>

            <h2>{{ $listings }}</h2>

            <p>Active Listings</p>

        </div>

    </div>


    <!-- Reports -->

    <div class="col-lg-3 col-md-6">

        <div class="dashboard-card">

            <div class="icon reports">

                <i class="bi bi-flag-fill"></i>

            </div>

            <h2>{{ $reports }}</h2>

            <p>New Reports</p>

        </div>

    </div>

</div>
<div class="row mt-4">

    <!-- Top Crops -->
    <div class="col-lg-8">

        <div class="card shadow-sm border-0 rounded-4">

            <div class="card-body">

                <h5 class="fw-bold mb-3">
                    🌱 Top Crops This Week
                </h5>

                <canvas id="cropChart" height="120"></canvas>

            </div>

        </div>

    </div>

    <!-- Empty for now (Pie Chart goes here next) -->
    <div class="col-lg-4">

    <div class="card shadow-sm border-0 rounded-4">

        <div class="card-body">

            <h5 class="fw-bold mb-3">
                👥 User Breakdown
            </h5>

            <!-- Pie Chart -->
            <canvas id="userChart" height="180"></canvas>

            <!-- Statistics -->
            <div class="row mt-4">

                <div class="col-6 mb-3">
                    <div class="mini-card">
                        <h4>{{ $farmers }}</h4>
                        <small>Active Farms</small>
                    </div>
                </div>

                <div class="col-6 mb-3">
                    <div class="mini-card">
                        <h4>{{ $listings }}</h4>
                        <small>Live Listings</small>
                    </div>
                </div>

                <div class="col-6">
                    <div class="mini-card">
                        <h4>0</h4>
                        <small>Searches Today</small>
                    </div>
                </div>

                <div class="col-6">
                    <div class="mini-card">
                        <h4>0</h4>
                        <small>Contacts Made</small>
                    </div>
                </div>

            </div>

        </div>

    </div>

</div>

<div class="card shadow-sm border-0 rounded-4 mt-4">

    <div class="card-header bg-white">
        <h5 class="fw-bold mb-0">
            🚩 Recent Reports
        </h5>
    </div>

    <div class="card-body">

        <table class="table table-hover align-middle">

            <thead>

                <tr>

                    <th>Report ID</th>

                    <th>Reporter</th>

                    <th>Listing</th>

                    <th>Reason</th>

                    <th>Status</th>

                    <th>Date</th>

                </tr>

            </thead>

            <tbody>

            @forelse($recentReports as $report)

                <tr>

                    <td>{{ $report->RPT_ID }}</td>

                    <td>{{ optional($report->user)->USR_NAME ?? 'Unknown User' }}</td>

                    <td>{{ optional($report->listing)->LST_ID ?? 'Unknown Listing' }}</td>

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

                    <td>{{ date('M d, Y', strtotime($report->RPT_CREATED_AT)) }}</td>

                </tr>

            @empty

                <tr>

                    <td colspan="6" class="text-center text-muted">
                        No reports found.
                    </td>

                </tr>

            @endforelse

            </tbody>

        </table>

    </div>

</div>
</div>

@endsection

@push('scripts')
<script>

const labels = @json($cropStats->pluck('CAT_NAME'));
const values = @json($cropStats->pluck('total'));



new Chart(document.getElementById('cropChart'), {
    type: 'bar',
    data: {
        labels: labels,
        datasets: [{
            label: 'Listings',
            data: values,
            backgroundColor: '#4CAF50',
            borderRadius: 10
        }]
    },
    options: {
        responsive: true,
        plugins: {
            legend: {
                display: false
            }
        },
        scales: {
            y: {
                beginAtZero: true
            }
        }
    }
});

</script>
@endpush