@extends('layouts.app')

@section('title', 'User Details')

@section('content')

<div class="card shadow-sm border-0 rounded-4">

    <div class="card-header bg-success text-white">
        <h4>User Information</h4>
    </div>

    <div class="card-body">

        <table class="table">

            <tr>
                <th>User ID</th>
                <td>{{ $user->USR_ID }}</td>
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
                <td>{{ $user->USR_ROLE }}</td>
            </tr>

            <tr>
                <th>Status</th>
                <td>{{ $user->USR_STATUS }}</td>
            </tr>

            <tr>
                <th>Seller Mode</th>
                <td>{{ $user->USR_IS_SELLER ? 'Yes' : 'No' }}</td>
            </tr>

            <tr>
                <th>Registered</th>
                <td>{{ $user->USR_CREATED_AT }}</td>
            </tr>

        </table>

        <a href="{{ route('users') }}" class="btn btn-secondary">
            Back
        </a>

    </div>

</div>

@endsection