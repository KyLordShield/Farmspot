<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Admin Login — FarmSpot</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        }
        .login-wrapper {
            min-height: 100vh;
            display: flex;
        }
        .brand-panel {
            background-color: #1e4d2b;
            color: #ffffff;
            flex: 1;
            display: flex;
            flex-direction: column;
            justify-content: center;
            padding: 4rem;
        }
        .brand-panel h1 {
            font-weight: 700;
            font-size: 2rem;
            letter-spacing: 0.5px;
        }
        .brand-panel .subtitle {
            color: #cfe3d6;
            font-size: 0.95rem;
            letter-spacing: 1px;
            text-transform: uppercase;
        }
        .brand-panel p.description {
            color: #d7e8dc;
            margin-top: 1.5rem;
            max-width: 380px;
            line-height: 1.6;
        }
        .form-panel {
            flex: 1;
            display: flex;
            align-items: center;
            justify-content: center;
            background-color: #f4f6f5;
            padding: 2rem;
        }
        .login-card {
            width: 100%;
            max-width: 400px;
        }
        .login-card h2 {
            font-weight: 700;
            color: #1e293b;
            margin-bottom: 0.25rem;
        }
        .login-card .subtext {
            color: #64748b;
            font-size: 0.9rem;
            margin-bottom: 2rem;
        }
        .form-label {
            font-weight: 600;
            font-size: 0.85rem;
            color: #334155;
        }
        .input-group-text {
            background-color: #ffffff;
            border-right: none;
            color: #1e4d2b;
        }
        .form-control {
            border-left: none;
        }
        .form-control:focus {
            box-shadow: none;
            border-color: #86efac;
        }
        .input-group:focus-within .input-group-text {
            border-color: #86efac;
        }
        .btn-login {
            background-color: #1e4d2b;
            color: #ffffff;
            font-weight: 600;
            padding: 0.65rem;
            border: none;
        }
        .btn-login:hover {
            background-color: #16351e;
            color: #ffffff;
        }
        .footer-note {
            font-size: 0.8rem;
            color: #94a3b8;
            text-align: center;
            margin-top: 2rem;
        }
        @media (max-width: 767px) {
            .brand-panel { display: none; }
        }
    </style>
</head>
<body>

<div class="login-wrapper">

    <!-- Left Brand Panel -->
    <div class="brand-panel">
        <div class="subtitle">FarmSpot</div>
        <h1>Association Administrator Portal</h1>
        <p class="description">
            Geolocation-based produce vendor locator and real-time availability tracking system.
            Sign in to manage users, listings, and reports.
        </p>
    </div>

    <!-- Right Form Panel -->
    <div class="form-panel">
        <div class="login-card">

            <h2>Sign In</h2>
            <p class="subtext">Enter your administrator credentials to continue.</p>

            @if (session('status'))
                <div class="alert alert-success py-2">{{ session('status') }}</div>
            @endif

            <form method="POST" action="{{ route('login') }}">
                @csrf

                <!-- Email -->
                <div class="mb-3">
                    <label for="email" class="form-label">Email Address</label>
                    <div class="input-group">
                        <span class="input-group-text"><i class="bi bi-envelope"></i></span>
                        <input id="email" type="email" name="email"
                               class="form-control @error('email') is-invalid @enderror"
                               value="{{ old('email') }}"
                               required autofocus autocomplete="username">
                    </div>
                    @error('email')
                        <div class="text-danger small mt-1">{{ $message }}</div>
                    @enderror
                </div>

                <!-- Password -->
                <div class="mb-3">
                    <label for="password" class="form-label">Password</label>
                    <div class="input-group">
                        <span class="input-group-text"><i class="bi bi-lock"></i></span>
                        <input id="password" type="password" name="password"
                               class="form-control @error('password') is-invalid @enderror"
                               required autocomplete="current-password">
                    </div>
                    @error('password')
                        <div class="text-danger small mt-1">{{ $message }}</div>
                    @enderror
                </div>

                <!-- Remember + Forgot -->
                <div class="d-flex justify-content-between align-items-center mb-4">
                    <div class="form-check">
                        <input class="form-check-input" type="checkbox" name="remember" id="remember_me">
                        <label class="form-check-label small" for="remember_me">
                            Remember me
                        </label>
                    </div>
                    @if (Route::has('password.request'))
                        <a href="{{ route('password.request') }}" class="small text-decoration-none" style="color:#1e4d2b;">
                            Forgot password?
                        </a>
                    @endif
                </div>

                <button type="submit" class="btn btn-login w-100">
                    Sign In
                </button>
            </form>

            <p class="footer-note">
                Authorized personnel only. All access attempts are logged.
            </p>

        </div>
    </div>

</div>

</body>
</html>