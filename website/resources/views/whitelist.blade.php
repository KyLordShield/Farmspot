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

    <a href="{{ route('whitelist.create') }}" class="btn btn-success">
        <i class="bi bi-plus-circle-fill"></i> Add Number
    </a>

</div>

@if(session('success'))
    <div class="alert alert-success alert-dismissible fade show" role="alert">
        {{ session('success') }}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
@endif

<div class="card shadow-sm border-0 rounded-4">

<div class="card-body">

<form method="GET" action="{{ route('whitelist') }}" class="row mb-3">

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
placeholder="Search mobile number">

<button class="btn btn-success" type="submit">
Search
</button>

</div>

</div>

<div class="col-md-3">

<select name="status" class="form-select" onchange="this.form.submit()">

<option value="">All Status</option>

<option value="Active" {{ request('status') == 'Active' ? 'selected' : '' }}>Active</option>

<option value="Inactive" {{ request('status') == 'Inactive' ? 'selected' : '' }}>Inactive</option>

</select>

</div>

</form>

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

<div class="col-md-4">

<div class="dashboard-card">

<div class="icon farmers">

<i class="bi bi-check-lg"></i>

</div>

<h2>{{ $whitelists->where('WLST_IS_ACTIVE', 1)->count() }}</h2>

<p>Active</p>

</div>

</div>

<div class="col-md-4">

<div class="dashboard-card">

<div class="icon reports">

<i class="bi bi-slash-circle"></i>

</div>

<h2>{{ $whitelists->where('WLST_IS_ACTIVE', 0)->count() }}</h2>

<p>Inactive</p>

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

<th>Deactivated By</th>

<th width="190">Actions</th>

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

<td>{{ $whitelist->addedBy?->USR_NAME ?? '-' }}</td>

<td>{{ $whitelist->deactivatedBy?->USR_NAME ?? '—' }}</td>

<td>

<a href="{{ route('whitelist.show', $whitelist->WLST_ID) }}"
   class="btn btn-sm btn-primary">
    <i class="bi bi-eye-fill"></i>
</a>

@if($whitelist->WLST_IS_ACTIVE)

    <form method="POST" action="{{ route('whitelist.toggle', $whitelist->WLST_ID) }}"
          class="d-inline"
          onsubmit="return confirm('Are you sure you want to deactivate this number?');">
        @csrf
        @method('PATCH')
        <button type="submit" class="btn btn-sm btn-danger" title="Deactivate">
            <i class="bi bi-slash-circle"></i> Deactivate
        </button>
    </form>

@else

    <form method="POST" action="{{ route('whitelist.toggle', $whitelist->WLST_ID) }}"
          class="d-inline">
        @csrf
        @method('PATCH')
        <button type="submit" class="btn btn-sm btn-success" title="Reactivate">
            <i class="bi bi-check-circle"></i> Reactivate
        </button>
    </form>

@endif

</td>

</tr>

@empty

<tr>

<td colspan="7" class="text-center py-5">

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