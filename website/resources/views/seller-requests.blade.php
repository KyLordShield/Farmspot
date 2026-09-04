@extends('layouts.app')

@section('title','Seller Requests')

@section('content')

<div class="d-flex justify-content-between align-items-center mb-4">

    <div>

        <h2 class="fw-bold mb-0">
            Seller Requests
        </h2>

        <small class="text-muted">
            Review pending farm submissions
        </small>

    </div>

</div>

@if(session('success'))
    <div class="alert alert-success alert-dismissible fade show" role="alert">
        {{ session('success') }}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
@endif

@if(session('error'))
    <div class="alert alert-danger alert-dismissible fade show" role="alert">
        {{ session('error') }}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
@endif

<div class="card shadow-sm border-0 rounded-4">

<div class="card-body">

<form method="GET" action="{{ route('seller-requests') }}" class="row mb-3">

<div class="col-md-5">

<div class="input-group">

<span class="input-group-text">
<i class="bi bi-search"></i>
</span>

<input
type="text"
name="search"
value="{{ request('search') }}"
class="form-control"
placeholder="Search farm or owner name">

<button class="btn btn-success" type="submit">
Search
</button>

</div>

</div>

</form>

<div class="row mb-4">

<div class="col-md-4">

<div class="dashboard-card">

<div class="icon users">

<i class="bi bi-hourglass-split"></i>

</div>

<h2>{{ $sellerRequests->total() }}</h2>

<p>Pending Requests</p>

</div>

</div>

</div>

<div class="table-responsive">

<table class="table table-hover align-middle">

<thead class="table-light">

<tr>

<th>Farm Name</th>

<th>Owner Name</th>

<th>Mobile Number</th>

<th>Barangay</th>

<th>Submitted At</th>

<th width="120">Actions</th>

</tr>

</thead>

<tbody>

@forelse($sellerRequests as $farm)

<tr>

<td>{{ $farm->FRM_NAME }}</td>

<td>{{ $farm->farmer?->buyer?->user?->USR_NAME ?? '-' }}</td>

<td>{{ $farm->farmer?->buyer?->user?->USR_MOBILE_NUMBER ?? '-' }}</td>

<td>{{ $farm->FRM_BARANGAY }}</td>

<td>{{ \Carbon\Carbon::parse($farm->FRM_CREATED_AT)->format('M d, Y h:i A') }}</td>

<td>

<a href="{{ route('seller-requests.show', $farm->FRM_ID) }}"
   class="btn btn-sm btn-primary" title="View">
    <i class="bi bi-eye-fill"></i>
</a>

</td>

</tr>

@empty

<tr>

<td colspan="6" class="text-center py-5">

<i class="bi bi-hourglass-split display-5 text-secondary"></i>

<p class="mt-3">

No pending seller requests found.

</p>

</td>

</tr>

@endforelse

</tbody>

</table>

</div>

<div class="mt-3">

{{ $sellerRequests->links() }}

</div>

</div>

</div>

@endsection
