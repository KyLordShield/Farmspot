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
        placeholder="Search by name, email or ID">

</div>
            </div>
<div class="col-md-3">

    <select class="form-select">

        <option>All Roles</option>
        <option>Admin</option>
        <option>Buyer</option>
        <option>Farmer</option>

    </select>

</div>

<div class="col-md-3">

    <select class="form-select">

        <option>All Status</option>
        <option>Active</option>
        <option>Pending</option>
        <option>Deactivated</option>

    </select>

</div>
        </div>

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

    <button class="btn btn-sm btn-warning">
        <i class="bi bi-pencil-fill"></i>
    </button>

    <button class="btn btn-sm btn-danger">
        <i class="bi bi-trash-fill"></i>
    </button>

</td>
                </tr>

            @empty

                <tr>

                    <td colspan="5" class="text-center text-muted">

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