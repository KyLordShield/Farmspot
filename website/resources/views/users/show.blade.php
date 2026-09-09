@extends('layouts.app')

@section('title', 'User Details')

@section('content')

<div class="page-head">
    <div>
        <h1 class="page-title">User Details</h1>
        <div class="page-desc">{{ $user->USR_ID }} · {{ $user->USR_NAME }}</div>
    </div>
    <div class="page-actions">
        <a href="{{ route('users') }}" class="btn btn-ghost">
            <i class="bi bi-arrow-left me-1"></i> Back to Users
        </a>
        <a href="{{ route('users.edit', $user->USR_ID) }}" class="btn btn-farm">
            <i class="bi bi-pencil me-1"></i> Edit User
        </a>
    </div>
</div>

<div class="panel">
    <div class="panel-header">
        <h5 class="panel-title">
            <i class="bi bi-person"></i>
            User Information
        </h5>
    </div>
    <div class="panel-body p-0">
        <table class="detail-table">

            <tr>
                <th>User ID</th>
                <td><span class="id-cell">{{ $user->USR_ID }}</span></td>
            </tr>

            <tr>
                <th>Name</th>
                <td>{{ $user->USR_NAME }}</td>
            </tr>

            <tr>
                <th>Email</th>
                <td>{{ $user->USR_EMAIL }}</td>
            </tr>

            <tr>
                <th>Mobile</th>
                <td>{{ $user->USR_MOBILE_NUMBER }}</td>
            </tr>

            <tr>
                <th>Role</th>
                <td>
                    @if($user->USR_ROLE == 'ADMIN')
                        <span class="badge badge-soft-danger">Admin</span>
                    @elseif($user->USR_ROLE == 'FARMER')
                        <span class="badge badge-soft-success">Farmer</span>
                    @else
                        <span class="badge badge-soft-neutral">Buyer</span>
                    @endif
                </td>
            </tr>

            <tr>
                <th>Status</th>
                <td>
                    @if($user->USR_STATUS == 'ACTIVE')
                        <span class="badge badge-soft-success">Active</span>
                    @else
                        <span class="badge badge-soft-neutral">{{ $user->USR_STATUS }}</span>
                    @endif
                </td>
            </tr>

            <tr>
                <th>Seller Mode</th>
                <td>{{ $user->USR_IS_SELLER ? 'Yes' : 'No' }}</td>
            </tr>

            <tr>
                <th>Registered</th>
                <td class="cell-secondary">{{ $user->USR_CREATED_AT }}</td>
            </tr>

        </table>
    </div>
</div>

@endsection