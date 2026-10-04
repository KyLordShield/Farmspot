<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <title>@yield('title','FarmSpot')</title>

    <link rel="icon" href="{{ asset('favicon.ico') }}" sizes="any">
    <link rel="icon" type="image/png" sizes="32x32" href="{{ asset('favicon-32x32.png') }}">
    <link rel="icon" type="image/png" sizes="16x16" href="{{ asset('favicon-16x16.png') }}">
    <link rel="apple-touch-icon" sizes="180x180" href="{{ asset('apple-touch-icon.png') }}">
    <link rel="manifest" href="{{ asset('site.webmanifest') }}">
    <meta name="theme-color" content="#0f4a1c">

    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">

    <link rel="stylesheet"
          href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">

    <link rel="stylesheet" href="{{ asset('css/style.css') }}">
</head>

<body>

<div class="wrapper">

    <!-- Sidebar -->
    <aside class="sidebar">

        <div class="brand">
            <div class="brand-mark">
                <img src="{{ asset('images/logo.png') }}" alt="FarmSpot">
            </div>
            <div>
                <span class="brand-name">FarmSpot</span>
                <span class="brand-sub">Admin</span>
            </div>
        </div>

        <div class="admin-profile">

            <div class="avatar">
                {{ strtoupper(substr(Auth::user()->USR_NAME, 0, 2)) }}
            </div>

            <div class="admin-meta">
                <h6>{{ Auth::user()->USR_NAME }}</h6>
                <small>Administrator</small>
            </div>

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
                <a href="{{ route('seller-requests') }}">
                    <i class="bi bi-person-check"></i>
                    Seller Requests
                </a>
            </li>

            <li>
                <a href="{{ route('analytics') }}">
                    <i class="bi bi-bar-chart"></i>
                    Analytics
                </a>
            </li>

        </ul>

        <div class="sidebar-footer">
            <form method="POST" action="{{ route('logout') }}">
                @csrf
                <button type="submit" class="btn-logout">
                    <i class="bi bi-box-arrow-right"></i>
                    Logout
                </button>
            </form>
        </div>

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