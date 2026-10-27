@extends('layouts.app')

@section('title','System Analytics')

@push('styles')
<style>
    .analytics-monthly-table {
        max-height: 290px;
        overflow: auto;
    }
    .analytics-monthly-table thead th {
        position: sticky;
        top: 0;
        z-index: 1;
    }
</style>
@endpush

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">System Analytics</h1>
        <div class="page-desc">Demand trends &amp; system usage · Updated {{ $asOf }}</div>
    </div>
</div>

<div class="row g-4">

    <!-- Top Crops -->
    <div class="col-lg-7">

        <div class="panel">
            <div class="panel-header">
                <div>
                    <h5 class="panel-title">
                        <i class="bi bi-flower1"></i>
                        Top Searches This Week
                    </h5>
                    <div class="panel-sub">Recorded searches from signed-in users · {{ $weekLabel }}</div>
                </div>
            </div>
            <div class="panel-body">
                @if($topSearches->isEmpty())
                <p class="cell-secondary">No searches recorded this week yet.</p>
                @endif
                <div class="chart-box">
                    <canvas id="cropChart" role="img" aria-label="Bar chart of most recorded searches this week"></canvas>
                </div>
            </div>
        </div>

    </div>

    <!-- Monthly Listing Trends -->
    <div class="col-lg-5">

        <div class="panel">
            <div class="panel-header">
                <div>
                    <h5 class="panel-title">
                        <i class="bi bi-calendar3"></i>
                        Monthly Listing Trends
                    </h5>
                    <div class="panel-sub">Top crop by new listings each month · last 12 months</div>
                </div>
            </div>
            <div class="panel-body p-0 analytics-monthly-table">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>Month</th>
                            <th>Most-listed Crop</th>
                            <th>Crop / Total</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach($monthlyTrends as $trend)
                        <tr>
                            <td class="cell-secondary">{{ $trend['month'] }}</td>
                            <td>{{ $trend['crop'] ?? 'No listings' }}</td>
                            <td>{{ $trend['top_count'] }} / {{ $trend['total'] }}</td>
                        </tr>
                        @endforeach
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
                        User Growth ({{ $monthLabel }})
                    </h5>
                    <div class="panel-sub">New registrations in 7-day groups; current group is month-to-date</div>
                </div>
            </div>
            <div class="panel-body">
                <div class="chart-box-sm">
                    <canvas id="growthChart" role="img" aria-label="Bar chart of user growth this month"></canvas>
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
                        <div class="kpi-label">Visible Listings</div>
                    </div>
                    <div class="kpi">
                        <div class="kpi-value">{{ $totalBuyers }}</div>
                        <div class="kpi-label">Registered Buyers</div>
                    </div>
                    <div class="kpi">
                        <div class="kpi-value">{{ $searchesToday }}</div>
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

// JSON encoding keeps search terms safe even when they contain quotes or HTML.
const cropLabels = {{ Illuminate\Support\Js::from($topSearches->pluck('keyword')->values()) }};
const cropValues = {{ Illuminate\Support\Js::from($topSearches->pluck('total')->map(fn ($count) => (int) $count)->values()) }};
const growthLabels = {{ Illuminate\Support\Js::from($growthLabels) }};
const growthValues = {{ Illuminate\Support\Js::from($growthValues) }};

new Chart(document.getElementById('cropChart'), {
    type: 'bar',
    data: {
        labels: cropLabels,
        datasets: [{
            data: cropValues,
            backgroundColor: ['#1b6b2c', '#3d9347', '#6fcf6f', '#a9d8b4', '#c8e6d0', '#e2efe6'],
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
                ticks: { precision: 0 },
                grid: { color: '#eef1f0' }
            }
        }
    }
});

new Chart(document.getElementById('growthChart'), {
    type: 'bar',
    data: {
        labels: growthLabels,
        datasets: [{
            data: growthValues,
            backgroundColor: ['#e2efe6', '#c8e6d0', '#6fcf6f', '#1b6b2c'],
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
                ticks: { precision: 0 },
                grid: { color: '#eef1f0' }
            }
        }
    }
});

</script>

@endpush
