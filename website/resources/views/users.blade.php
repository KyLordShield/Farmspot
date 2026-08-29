@extends('layouts.app')

@section('title', 'Users')

@section('content')

<div class="d-flex justify-content-between align-items-center mb-4">

    <div>
        <h2 class="fw-bold mb-0">Users</h2>
        <small class="text-muted">
            Manage all registered users
        </small>
    </div>

    <a href="{{ route('users.create') }}" class="btn btn-success">
        <i class="bi bi-person-plus-fill"></i> Add User
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

        <!-- Search & Filters -->
        <form method="GET" action="{{ route('users') }}" class="row mb-3">

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
        placeholder="Search by name, email or ID">

    <button class="btn btn-success" type="submit">
        Search
    </button>

</div>
            </div>
<div class="col-md-3">

    <select name="role" class="form-select" onchange="this.form.submit()">

        <option value="">All Roles</option>
        <option value="ADMIN" {{ request('role') == 'ADMIN' ? 'selected' : '' }}>Admin</option>
        <option value="GENERAL_USER" {{ request('role') == 'GENERAL_USER' ? 'selected' : '' }}>General User</option>

    </select>

</div>

<div class="col-md-3">

    <select name="status" class="form-select" onchange="this.form.submit()">

        <option value="">All Status</option>
        <option value="ACTIVE" {{ request('status') == 'ACTIVE' ? 'selected' : '' }}>Active</option>
        <option value="PENDING_VERIFICATION" {{ request('status') == 'PENDING_VERIFICATION' ? 'selected' : '' }}>Pending Verification</option>
        <option value="DEACTIVATED" {{ request('status') == 'DEACTIVATED' ? 'selected' : '' }}>Deactivated</option>

    </select>

</div>
        </form>

        <div class="row mb-4">

    <div class="col-md-4">
        <div class="dashboard-card">
            <div class="icon users">
                <i class="bi bi-people-fill"></i>
            </div>

            <h2>{{ $users->total() }}</h2>
            <p>Total Registered Users</p>
        </div>
    </div>

    <div class="col-md-4">
        <div class="dashboard-card">
            <div class="icon farmers">
                <i class="bi bi-person-check-fill"></i>
            </div>

            <h2>{{ $users->where('USR_STATUS','ACTIVE')->count() }}</h2>
            <p>Active Users</p>
        </div>
    </div>

    <div class="col-md-4">
        <div class="dashboard-card">
            <div class="icon reports">
                <i class="bi bi-person-x-fill"></i>
            </div>

            <h2>{{ $users->where('USR_STATUS','DEACTIVATED')->count() }}</h2>
            <p>Deactivated</p>
        </div>
    </div>

</div>

        <!-- Users Table -->
         <div class="table-responsive">

        <table class="table table-hover align-middle">

            <thead class="table-light">

                <tr>

                    <th>ID</th>
                    <th>Name</th>
                    <th>Email</th>
                    <th>Role</th>
                    <th>Status</th>
                    <th width="170">Actions</th>
                </tr>
            </thead>

</div>
            <tbody>

            @forelse($users as $user)

                <tr>

                    <td>{{ $user->USR_ID }}</td>

                    <td>{{ $user->USR_NAME }}</td>

                    <td>{{ $user->USR_EMAIL }}</td>

                    <td>

                        @if($user->USR_ROLE == 'ADMIN')

                            <span class="badge bg-danger">
                                Admin
                            </span>

                        @elseif($user->USR_ROLE == 'FARMER')

                            <span class="badge bg-success">
                                Farmer
                            </span>

                        @else

                            <span class="badge bg-primary">
                                Buyer
                            </span>

                        @endif

                    </td>

                    <td>

                        @if($user->USR_STATUS == 'ACTIVE')

                            <span class="badge bg-success">
                                Active
                            </span>

                        @else

                            <span class="badge bg-secondary">
                                {{ $user->USR_STATUS }}
                            </span>

                        @endif

                    </td>

                    <td>

    <a href="{{ route('users.show', $user->USR_ID) }}"
       class="btn btn-sm btn-primary">
        <i class="bi bi-eye-fill"></i>
    </a>

    <a href="{{ route('users.edit', $user->USR_ID) }}"
       class="btn btn-sm btn-warning">
        <i class="bi bi-pencil-fill"></i>
    </a>

    <form method="POST" action="{{ route('users.destroy', $user->USR_ID) }}"
          class="d-inline"
          onsubmit="return confirm('Are you sure you want to deactivate this user?');">
        @csrf
        @method('DELETE')
        <button type="submit" class="btn btn-sm btn-danger" title="Deactivate">
            <i class="bi bi-trash-fill"></i>
        </button>
    </form>

</td>
                </tr>

            @empty

                <tr>

                    <td colspan="6" class="text-center text-muted">

                        No users found.

                    </td>

                </tr>

            @endforelse

            </tbody>

        </table>

        <div class="mt-3">

            {{ $users->links() }}

        </div>

    </div>

</div>

@endsection