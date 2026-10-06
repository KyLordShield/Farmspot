<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <title>@hasSection('title')@yield('title') · FarmSpot Admin@else FarmSpot Admin@endif</title>

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

    {{-- Page-specific stylesheets. Two stacks rather than one because a partial
         that pushes into 'scripts' for JS would otherwise have to push its CSS
         there too, which works and is exactly as clear as it sounds. --}}
    @stack('styles')
</head>

<body>

<div class="wrapper">

    <!-- Sidebar -->
    <aside class="sidebar" id="appSidebar">

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

            {{-- Sits after Reports rather than before Users: both are moderation
                 queues, and keeping them adjacent means an admin working a
                 flagged item can move straight to the review it produced. --}}
            <li>
                <a href="{{ route('reviews') }}">
                    <i class="bi bi-star"></i>
                    Reviews
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
            <form method="POST" action="{{ route('logout') }}"
                  data-confirm-title="Log out?"
                  data-confirm-text="You will be returned to the sign-in page.">
                @csrf
                <button type="submit" class="btn-logout">
                    <i class="bi bi-box-arrow-right"></i>
                    Logout
                </button>
            </form>
        </div>

    </aside>

    <!-- Tap-away layer behind the off-canvas sidebar on small screens -->
    <div class="sidebar-overlay" id="sidebarOverlay" aria-hidden="true"></div>

    <!-- Mobile topbar: hamburger + branding. Hidden on large screens. -->
    <header class="topbar">
        <button type="button"
                class="topbar-toggle"
                id="sidebarToggle"
                aria-label="Toggle navigation"
                aria-expanded="false"
                aria-controls="appSidebar">
            <i class="bi bi-list"></i>
        </button>
        <span class="topbar-brand">
            <i class="bi bi-flower1 me-1"></i> FarmSpot Admin
        </span>
    </header>

    <!-- Main Content -->

    <div class="main-area">

        <main class="content">

            @yield('content')

        </main>

    </div>

</div>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>

<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>

<script src="{{ asset('js/global.js') }}"></script>

{{-- SweetAlert2 for confirmations and toasts. Pinned to an exact version so a
     future CDN release cannot change the behaviour of the helper below. --}}
<script src="https://cdn.jsdelivr.net/npm/sweetalert2@11.14.5/dist/sweetalert2.all.min.js"></script>

<script src="{{ asset('js/admin-alerts.js') }}"></script>

@stack('scripts')

</body>
</html>