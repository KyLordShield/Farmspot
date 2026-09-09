@extends('layouts.app')

@section('title', 'Dashboard')

@section('content')

<div class="page-head">

    <div>
        <h1 class="page-title">Overview</h1>
        <div class="page-desc">FarmSpot Management Dashboard</div>
    </div>

    <div class="page-actions">
        <button class="btn btn-ghost">
            <i class="bi bi-download me-1"></i>
            Export Data
        </button>
    </div>

</div>

<div class="stat-grid">

    <div class="stat-card">
        <div class="stat-icon tint-green">
            <i class="bi bi-people"></i>
        </div>
        <div>
            <div class="stat-value">{{ $users }}</div>
            <div class="stat-label">Total Users</div>
        </div>
    </div>

    <div class="stat-card">
        <div class="stat-icon tint-slate">
            <i class="bi bi-person-badge"></i>
        </div>
        <div>
            <div class="stat-value">{{ $farmers }}</div>
            <div class="stat-label">Total Farmers</div>
        </div>
    </div>

    <div class="stat-card">
        <div class="stat-icon tint-amber">
            <i class="bi bi-basket"></i>
        </div>
        <div>
            <div class="stat-value">{{ $listings }}</div>
            <div class="stat-label">Active Listings</div>
        </div>
    </div>

    <div class="stat-card">
        <div class="stat-icon tint-red">
            <i class="bi bi-flag"></i>
        </div>
        <div>
            <div class="stat-value">{{ $reports }}</div>
            <div class="stat-label">New Reports</div>
        </div>
    </div>

</div>

<div class="row g-4">

    <!-- Top Crops -->
    <div class="col-lg-8">

        <div class="panel h-100">
            <div class="panel-header">
                <div>
                    <h5 class="panel-title">
                        <i class="bi bi-flower1"></i>
                        Top Crops This Week
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

    <!-- User Breakdown -->
    <div class="col-lg-4">

        <div class="panel h-100">
            <div class="panel-header">
                <div>
                    <h5 class="panel-title">
                        <i class="bi bi-people"></i>
                        User Breakdown
                    </h5>
                    <div class="panel-sub">Account mix today</div>
                </div>
            </div>
            <div class="panel-body">
                <div class="chart-box-sm">
                    <canvas id="userChart"></canvas>
                </div>

                <div class="kpi-grid">
                    <div class="kpi">
                        <div class="kpi-value">{{ $farmers }}</div>
                        <div class="kpi-label">Farm accounts</div>
                    </div>
                    <div class="kpi">
                        <div class="kpi-value">{{ $listings }}</div>
                        <div class="kpi-label">Live listings</div>
                    </div>
                    <div class="kpi">
                        <div class="kpi-value">0</div>
                        <div class="kpi-label">Searches today</div>
                    </div>
                    <div class="kpi">
                        <div class="kpi-value">0</div>
                        <div class="kpi-label">Contacts made</div>
                    </div>
                </div>

            </div>
        </div>

    </div>

</div>

<div class="panel mt-4">

    <div class="panel-header">
        <div>
            <h5 class="panel-title">
                <i class="bi bi-flag"></i>
                Recent Reports
            </h5>
            <div class="panel-sub">Latest moderation queue activity</div>
        </div>
    </div>

    <div class="table-responsive">
        <table class="data-table">

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
                    <td><span class="id-cell">{{ $report->RPT_ID }}</span></td>
                    <td class="cell-secondary">{{ optional($report->user)->USR_NAME ?? 'Unknown User' }}</td>
                    <td><span class="id-cell">{{ optional($report->listing)->LST_ID ?? 'Unknown Listing' }}</span></td>
                    <td class="cell-secondary">{{ $report->RPT_REASON }}</td>
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
                    <td class="cell-faint">{{ date('M d, Y', strtotime($report->RPT_CREATED_AT)) }}</td>
                </tr>

            @empty

                <tr>
                    <td colspan="6">
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
            backgroundColor: '#2b6d3c',
            borderRadius: 6
        }]
    },
    options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
            legend: {
                display: false
            }
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

if (document.getElementById('userChart')) {
    new Chart(document.getElementById('userChart'), {
        type: 'doughnut',
        data: {
            labels: ['Farmers', 'Buyers'],
            datasets: [{
                data: [@json($farmers), @json(max($users - $farmers, 0))],
                backgroundColor: ['#2b6d3c', '#d3dad6'],
                borderWidth: 0
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            cutout: '62%',
            plugins: {
                legend: {
                    position: 'bottom',
                    labels: {
                        boxWidth: 10,
                        boxHeight: 10,
                        usePointStyle: true,
                        pointStyle: 'circle',
                        font: { size: 11 }
                    }
                }
            }
        }
    });
}

</script>
@endpush