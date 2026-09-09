@extends('layouts.app')

@section('title','System Analytics')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">System Analytics</h1>
        <div class="page-desc">Demand trends &amp; system usage</div>
    </div>
    <div class="page-actions">
        <button class="btn btn-ghost">
            <i class="bi bi-download me-1"></i>
            Export Data
        </button>
    </div>
</div>

<div class="row g-4">

    <!-- Top Crops -->
    <div class="col-lg-7">

        <div class="panel h-100">
            <div class="panel-header">
                <div>
                    <h5 class="panel-title">
                        <i class="bi bi-flower1"></i>
                        Top Searched Crops This Week
                    </h5>
                    <div class="panel-sub">Listings per category</div>
                </div>
            </div>
            <div class="panel-body">
                <div class="chart-box">
                    <canvas id="cropChart"></canvas>
                </div>
            </div>
        </div>

    </div>

    <!-- Seasonal Trends -->
    <div class="col-lg-5">

        <div class="panel h-100">
            <div class="panel-header">
                <div>
                    <h5 class="panel-title">
                        <i class="bi bi-calendar3"></i>
                        Seasonal Trends
                    </h5>
                    <div class="panel-sub">Expected peak months vs. data</div>
                </div>
            </div>
            <div class="panel-body p-0">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>Month</th>
                            <th>Trending Crop</th>
                            <th>Listings</th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr>
                            <td class="cell-secondary">March</td>
                            <td class="cell-faint">No data yet</td>
                            <td>0</td>
                        </tr>
                        <tr>
                            <td class="cell-secondary">June</td>
                            <td class="cell-faint">No data yet</td>
                            <td>0</td>
                        </tr>
                        <tr>
                            <td class="cell-secondary">October</td>
                            <td class="cell-faint">No data yet</td>
                            <td>0</td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>

    </div>

</div>

<div class="row g-4 mt-1">

    <!-- User Growth -->
    <div class="col-lg-7">

        <div class="panel">
            <div class="panel-header">
                <div>
                    <h5 class="panel-title">
                        <i class="bi bi-graph-up"></i>
                        User Growth (This Month)
                    </h5>
                    <div class="panel-sub">New registrations per week</div>
                </div>
            </div>
            <div class="panel-body">
                <div class="chart-box-sm">
                    <canvas id="growthChart"></canvas>
                </div>
            </div>
        </div>

    </div>

    <!-- Summary -->
    <div class="col-lg-5">

        <div class="panel">
            <div class="panel-header">
                <div>
                    <h5 class="panel-title">
                        <i class="bi bi-box-seam"></i>
                        System Summary
                    </h5>
                    <div class="panel-sub">Key metrics at a glance</div>
                </div>
            </div>
            <div class="panel-body">
                <div class="kpi-grid">
                    <div class="kpi">
                        <div class="kpi-value">{{ $totalUsers }}</div>
                        <div class="kpi-label">Total Users</div>
                    </div>
                    <div class="kpi">
                        <div class="kpi-value">{{ $totalFarmers }}</div>
                        <div class="kpi-label">Active Farmers</div>
                    </div>
                    <div class="kpi">
                        <div class="kpi-value">{{ $totalListings }}</div>
                        <div class="kpi-label">Live Listings</div>
                    </div>
                    <div class="kpi">
                        <div class="kpi-value">{{ $totalBuyers }}</div>
                        <div class="kpi-label">Registered Buyers</div>
                    </div>
                    <div class="kpi">
                        <div class="kpi-value">0</div>
                        <div class="kpi-label">Searches Today</div>
                    </div>
                    <div class="kpi">
                        <div class="kpi-value text-danger">{{ $totalReports }}</div>
                        <div class="kpi-label">Pending Reports</div>
                    </div>
                </div>
            </div>
        </div>

    </div>

</div>

@endsection

@push('scripts')

<script>

const cropLabels = [
@foreach($cropStats as $crop)
"{{ $crop->CAT_NAME }}",
@endforeach
];

const cropValues = [
@foreach($cropStats as $crop)
{{ $crop->total }},
@endforeach
];

new Chart(document.getElementById('cropChart'), {
    type: 'bar',
    data: {
        labels: cropLabels,
        datasets: [{
            data: cropValues,
            backgroundColor: ['#2b6d3c', '#4f8a60', '#87ad93', '#a9c3b3', '#c8d9cf', '#e2ebe5'],
            borderRadius: 6
        }]
    },
    options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
            legend: { display: false }
        },
        scales: {
            x: {
                grid: { display: false }
            },
            y: {
                beginAtZero: true,
                grid: { color: '#eef1f0' }
            }
        }
    }
});

new Chart(document.getElementById('growthChart'), {
    type: 'bar',
    data: {
        labels: ['Week 1', 'Week 2', 'Week 3', 'Week 4'],
        datasets: [{
            data: [0, 0, 0, 0],
            backgroundColor: ['#e2ebe5', '#c8d9cf', '#87ad93', '#2b6d3c'],
            borderRadius: 6
        }]
    },
    options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
            legend: { display: false }
        },
        scales: {
            x: {
                grid: { display: false }
            },
            y: {
                beginAtZero: true,
                grid: { color: '#eef1f0' }
            }
        }
    }
});

</script>

@endpush