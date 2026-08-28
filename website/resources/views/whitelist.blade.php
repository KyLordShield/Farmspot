@extends('layouts.app')

@section('title','Whitelist')

@section('content')

<div class="d-flex justify-content-between align-items-center mb-4">

    <div>

        <h2 class="fw-bold mb-0">
            Whitelist
        </h2>

        <small class="text-muted">
            Manage approved mobile numbers
        </small>

    </div>

</div>

<div class="card shadow-sm border-0 rounded-4">

<div class="card-body">

<div class="row mb-3">

<div class="col-md-5">

<div class="input-group">

<span class="input-group-text">
<i class="bi bi-search"></i>
</span>

<input
class="form-control"
placeholder="Search mobile number">

</div>

</div>

<div class="col-md-3">

<select class="form-select">

<option>All Status</option>

<option>Active</option>

<option>Inactive</option>

</select>

</div>

</div>

<div class="row mb-4">

<div class="col-md-4">

<div class="dashboard-card">

<div class="icon users">

<i class="bi bi-check-circle-fill"></i>

</div>

<h2>{{ $whitelists->total() }}</h2>

<p>Total Numbers</p>

</div>

</div>

</div>

<div class="table-responsive">

<table class="table table-hover align-middle">

<thead class="table-light">

<tr>

<th>ID</th>

<th>Mobile Number</th>

<th>Status</th>

<th>Added At</th>

<th>Added By</th>

<th width="170">Actions</th>

</tr>

</thead>

<tbody>

@forelse($whitelists as $whitelist)

<tr>

<td>{{ $whitelist->WLST_ID }}</td>

<td>{{ $whitelist->WLST_MOBILE_NUMBER }}</td>

<td>

@if($whitelist->WLST_IS_ACTIVE)

<span class="badge bg-success">

Active

</span>

@else

<span class="badge bg-danger">

Inactive

</span>

@endif

</td>

<td>{{ $whitelist->WLST_ADDED_AT }}</td>

<td>{{ $whitelist->USR_ADDED_ID }}</td>

<td>

<button class="btn btn-primary btn-sm">

<i class="bi bi-eye-fill"></i>

</button>

<button class="btn btn-warning btn-sm">

<i class="bi bi-pencil-fill"></i>

</button>

</td>

</tr>

@empty

<tr>

<td colspan="6" class="text-center py-5">

<i class="bi bi-check-circle display-5 text-secondary"></i>

<p class="mt-3">

No whitelist records found.

</p>

</td>

</tr>

@endforelse

</tbody>

</table>

</div>

<div class="mt-3">

{{ $whitelists->links() }}

</div>

</div>

</div>

@endsection