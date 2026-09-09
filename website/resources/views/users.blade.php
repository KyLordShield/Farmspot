@extends('layouts.app')

@section('title', 'Users')

@section('content')

<div class="page-head">

    <div>
        <h1 class="page-title">Users</h1>
        <div class="page-desc">Manage all registered users</div>
    </div>

    <div class="page-actions">
        <a href="{{ route('users.create') }}" class="btn btn-farm">
            <i class="bi bi-person-plus me-1"></i> Add User
        </a>
    </div>

</div>

@if(session('success'))
    <div class="alert alert-success alert-dismissible fade show" role="alert">
        {{ session('success') }}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
@endif

<div class="stat-grid">

    <div class="stat-card">
        <div class="stat-icon tint-green">
            <i class="bi bi-people"></i>
        </div>
        <div>
            <div class="stat-value">{{ $users->total() }}</div>
            <div class="stat-label">Total registered users</div>
        </div>
    </div>

    <div class="stat-card">
        <div class="stat-icon tint-amber">
            <i class="bi bi-person-check"></i>
        </div>
        <div>
            <div class="stat-value">{{ $users->where('USR_STATUS','ACTIVE')->count() }}</div>
            <div class="stat-label">Active users</div>
        </div>
    </div>

    <div class="stat-card">
        <div class="stat-icon tint-red">
            <i class="bi bi-person-x"></i>
        </div>
        <div>
            <div class="stat-value">{{ $users->where('USR_STATUS','DEACTIVATED')->count() }}</div>
            <div class="stat-label">Deactivated</div>
        </div>
    </div>

</div>

<div class="panel">

    <!-- Search & Filters -->
    <form method="GET" action="{{ route('users') }}" class="filter-bar">

        <div class="filter-grow">
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
                <button class="btn btn-farm" type="submit">
                    Search
                </button>
            </div>
        </div>

        <div class="filter-auto">
            <select name="role" class="form-select" onchange="this.form.submit()">
                <option value="">All Roles</option>
                <option value="ADMIN" {{ request('role') == 'ADMIN' ? 'selected' : '' }}>Admin</option>
                <option value="GENERAL_USER" {{ request('role') == 'GENERAL_USER' ? 'selected' : '' }}>General User</option>
            </select>
        </div>

        <div class="filter-auto">
            <select name="status" class="form-select" onchange="this.form.submit()">
                <option value="">All Status</option>
                <option value="ACTIVE" {{ request('status') == 'ACTIVE' ? 'selected' : '' }}>Active</option>
                <option value="PENDING_VERIFICATION" {{ request('status') == 'PENDING_VERIFICATION' ? 'selected' : '' }}>Pending Verification</option>
                <option value="DEACTIVATED" {{ request('status') == 'DEACTIVATED' ? 'selected' : '' }}>Deactivated</option>
            </select>
        </div>

    </form>

    <div class="table-responsive">
        <table class="data-table">

            <thead>
                <tr>
                    <th>ID</th>
                    <th>Name</th>
                    <th>Email</th>
                    <th>Role</th>
                    <th>Status</th>
                    <th>Actions</th>
                </tr>
            </thead>

            <tbody>

            @forelse($users as $user)

                <tr>
                    <td><span class="id-cell">{{ $user->USR_ID }}</span></td>
                    <td>{{ $user->USR_NAME }}</td>
                    <td class="cell-secondary">{{ $user->USR_EMAIL }}</td>
                    <td>
                        @if($user->USR_ROLE == 'ADMIN')
                            <span class="badge badge-soft-danger">Admin</span>
                        @elseif($user->USR_ROLE == 'FARMER')
                            <span class="badge badge-soft-success">Farmer</span>
                        @else
                            <span class="badge badge-soft-neutral">Buyer</span>
                        @endif
                    </td>
                    <td>
                        @if($user->USR_STATUS == 'ACTIVE')
                            <span class="badge badge-soft-success">Active</span>
                        @else
                            <span class="badge badge-soft-neutral">{{ $user->USR_STATUS }}</span>
                        @endif
                    </td>
                    <td>
                        <div class="actions">
                            <a href="{{ route('users.show', $user->USR_ID) }}"
                               class="btn-icon" title="View">
                                <i class="bi bi-eye"></i>
                            </a>

                            <a href="{{ route('users.edit', $user->USR_ID) }}"
                               class="btn-icon" title="Edit">
                                <i class="bi bi-pencil"></i>
                            </a>

                            <form method="POST" action="{{ route('users.destroy', $user->USR_ID) }}"
                                  class="d-inline"
                                  onsubmit="return confirm('Are you sure you want to deactivate this user?');">
                                @csrf
                                @method('DELETE')
                                <button type="submit" class="btn-icon danger" title="Deactivate">
                                    <i class="bi bi-trash"></i>
                                </button>
                            </form>
                        </div>
                    </td>
                </tr>

            @empty

                <tr>
                    <td colspan="6">
                        <div class="empty-state">
                            <i class="bi bi-people empty-icon"></i>
                            <p>No users found.</p>
                        </div>
                    </td>
                </tr>

            @endforelse

            </tbody>

        </table>
    </div>

    <div class="panel-body pt-0 pb-3">
        {{ $users->links() }}
    </div>

</div>

@endsection