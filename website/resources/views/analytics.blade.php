@extends('layouts.app')

@section('title','System Analytics')

@section('content')

<div class="d-flex justify-content-between align-items-center mb-4">

    <div>

        <h2 class="fw-bold mb-0">
            System Analytics
        </h2>

        <small class="text-muted">
            Demand trends & system usage
        </small>

    </div>

    <div>

        <button class="btn btn-outline-success me-2">
            <i class="bi bi-download"></i>
            Export Data
        </button>

    </div>

</div>

<div class="row g-4">

    <!-- Top Crops -->

    <div class="col-lg-7">

        <div class="card shadow-sm border-0 rounded-4 h-100">

            <div class="card-body">

                <h6 class="fw-bold mb-3">

                    🌱 Top Searched Crops This Week

                </h6>

                <canvas id="cropChart" height="130"></canvas>

            </div>

        </div>

    </div>

    <!-- Seasonal Trends -->

    <div class="col-lg-5">

        <div class="card shadow-sm border-0 rounded-4 h-100">

            <div class="card-body">

                <h6 class="fw-bold mb-3">

                    📅 Seasonal Trends

                </h6>

                <table class="table table-borderless align-middle">

                    <thead>

                        <tr>

                            <th>Month</th>

                            <th>Trending Crop</th>

                            <th>Listings</th>

                        </tr>

                    </thead>

                    <tbody>

                        <tr>

                            <td>March</td>

                            <td class="text-muted">No data yet</td>

                            <td>0</td>

                        </tr>

                        <tr>

                            <td>June</td>

                            <td class="text-muted">No data yet</td>

                            <td>0</td>

                        </tr>

                        <tr>

                            <td>October</td>

                            <td class="text-muted">No data yet</td>

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

        <div class="card shadow-sm border-0 rounded-4">

            <div class="card-body">

                <h6 class="fw-bold mb-3">

                    📈 User Growth (This Month)

                </h6>

                <canvas id="growthChart" height="140"></canvas>

            </div>

        </div>

    </div>

    <!-- Summary -->

    <div class="col-lg-5">

        <div class="card shadow-sm border-0 rounded-4">

            <div class="card-body">

                <h6 class="fw-bold mb-3">

                    📦 System Summary

                </h6>

                <div class="row g-3">

                    <div class="col-6">

                        <div class="summary-card">

                            <h3>{{ $totalUsers }}</h3>

                            <small>Total Users</small>

                        </div>

                    </div>

                    <div class="col-6">

                        <div class="summary-card">

                            <h3>{{ $totalFarmers }}</h3>

                            <small>Active Farmers</small>

                        </div>

                    </div>

                    <div class="col-6">

                        <div class="summary-card">

                            <h3>{{ $totalListings }}</h3>

                            <small>Live Listings</small>

                        </div>

                    </div>

                    <div class="col-6">

                        <div class="summary-card">

                            <h3>{{ $totalBuyers }}</h3>

                            <small>Registered Buyers</small>

                        </div>

                    </div>

                    <div class="col-6">

                        <div class="summary-card">

                            <h3>0</h3>

                            <small>Searches Today</small>

                        </div>

                    </div>

                    <div class="col-6">

                        <div class="summary-card summary-danger">

                            <h3>{{ $totalReports }}</h3>

                            <small>Pending Reports</small>

                        </div>

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

new Chart(document.getElementById('cropChart'),{

type:'bar',

data:{

labels:cropLabels,

datasets:[{

data:cropValues,

backgroundColor:[
'#2E7D32',
'#388E3C',
'#43A047',
'#66BB6A',
'#81C784',
'#A5D6A7'
],

borderRadius:10

}]

},

options:{

plugins:{
legend:{display:false}
},

scales:{
y:{beginAtZero:true}
}

}

});

new Chart(document.getElementById('growthChart'),{

type:'bar',

data:{

labels:['Week 1','Week 2','Week 3','Week 4'],

datasets:[{

data:[0,0,0,0],

backgroundColor:[
'#C8E6C9',
'#81C784',
'#4CAF50',
'#2E7D32'
],

borderRadius:10

}]

},

options:{

plugins:{
legend:{display:false}
},

scales:{
y:{beginAtZero:true}
}

}

});

</script>

@endpush