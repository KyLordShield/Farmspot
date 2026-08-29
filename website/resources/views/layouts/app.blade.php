<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <title>@yield('title','FarmSpot')</title>

    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">

    <link rel="stylesheet"
          href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">

    <link rel="stylesheet" href="{{ asset('css/style.css') }}">
</head>

<body>

<div class="wrapper">

    <!-- Sidebar -->
    <aside class="sidebar">

        <div class="logo">
            🌱 <strong>FarmSpot</strong>
            <small>ADMIN DASHBOARD</small>
        </div>

        <div class="admin-profile">

    <div class="avatar">

          {{ isset($associationOfficer) && $associationOfficer ? strtoupper(substr($associationOfficer->USR_NAME,0,2)) : 'AA' }}
    </div>

    <div>

        <h6>

          {{ isset($associationOfficer) && $associationOfficer ? $associationOfficer->USR_NAME : 'No Admin Yet' }}

        </h6>

        <small>Association Officer</small>

    </div>

    <form method="POST" action="{{ route('logout') }}" class="px-3 mb-3">
    @csrf
    <button type="submit" class="btn btn-sm btn-outline-light w-100">
        <i class="bi bi-box-arrow-right"></i>
        Logout
    </button>
    </form>

</div>  

        <ul class="menu">

            <li>
                <a href="{{ route('dashboard') }}">
                    <i class="bi bi-speedometer2"></i>
                    Dashboard
                </a>
            </li>

            <li>
                <a href="{{ route('users') }}">
                    <i class="bi bi-people"></i>
                    Users
                </a>
            </li>

            <li>
                <a href="{{ route('listings') }}">
                    <i class="bi bi-basket"></i>
                    Listings
                </a>
            </li>

            <li>
                <a href="{{ route('reports') }}">
                    <i class="bi bi-flag"></i>
                    Reports
                </a>
            </li>

            <li>
                <a href="{{ route('whitelist') }}">
                    <i class="bi bi-check-circle"></i>
                    Whitelist
                </a>
            </li>

            <li>
                <a href="{{ route('analytics') }}">
                    <i class="bi bi-bar-chart"></i>
                    Analytics
                </a>
            </li>

        </ul>

    </aside>

    <!-- Main Content -->

    <main class="content">

        @yield('content')

    </main>

</div>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>

<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>

@stack('scripts')

</body>
</html>