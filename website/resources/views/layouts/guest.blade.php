<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>@yield('title', 'FarmSpot Admin')</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background-color: #f4f6f5;
        }
        .guest-wrapper {
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 2rem;
        }
        .guest-card {
            width: 100%;
            max-width: 420px;
            background: #ffffff;
            border-radius: 10px;
            padding: 2.5rem;
            box-shadow: 0 4px 20px rgba(0,0,0,0.06);
        }
        .guest-brand {
            text-align: center;
            margin-bottom: 1.5rem;
            color: #1e4d2b;
            font-weight: 700;
            font-size: 1.25rem;
        }
        .btn-farmspot {
            background-color: #1e4d2b;
            color: #ffffff;
            font-weight: 600;
            border: none;
        }
        .btn-farmspot:hover {
            background-color: #16351e;
            color: #ffffff;
        }
    </style>
</head>
<body>

<div class="guest-wrapper">
    <div class="guest-card">
        <div class="guest-brand">FarmSpot Admin</div>
        @yield('content')
    </div>
</div>

</body>
</html>