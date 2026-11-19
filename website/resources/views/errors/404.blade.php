<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>Page not found - FarmSpot</title>
    <link rel="icon" href="{{ asset('favicon.ico') }}">
    <style>
        * { box-sizing: border-box; }
        body { margin: 0; min-height: 100vh; min-height: 100svh; display: grid; place-items: center; padding: 24px; background: #f4f6f5; color: #20352a; font-family: system-ui, sans-serif; }
        main { width: 100%; max-width: 560px; text-align: center; }
        .brand { font-size: 22px; font-weight: 800; color: #1e4d2b; }
        .animation { width: min(100%, 380px); aspect-ratio: 950 / 847; margin: 12px auto; display: grid; place-items: center; }
        .fallback { font-size: 96px; font-weight: 800; color: #1e4d2b; }
        h1 { margin: 0 0 12px; font-size: clamp(26px, 5vw, 34px); }
        p { margin: 0 auto 28px; max-width: 400px; color: #59675f; line-height: 1.6; }
        a.button { display: inline-block; padding: 13px 24px; border-radius: 10px; background: #1e4d2b; color: white; font-weight: 600; text-decoration: none; }
        a.button:hover { background: #163c21; }
        a.button:focus-visible { outline: 3px solid #609c70; outline-offset: 4px; }
    </style>
</head>
<body>
    <main>
        <div class="brand">FarmSpot</div>
        <div id="not-found-animation" class="animation" aria-hidden="true"
             data-animation-url="{{ asset('animations/not_found_cat.json') }}">
            <span class="fallback">404</span>
        </div>
        <h1>Page not found</h1>
        <p>The page you are looking for may have been moved or is no longer available.</p>
        <a class="button" href="{{ route('dashboard') }}">Return to dashboard</a>
    </main>
    <script src="https://cdn.jsdelivr.net/npm/lottie-web@5.13.0/build/player/lottie_svg.min.js" defer></script>
    <script src="{{ asset('js/not-found.js') }}" defer></script>
</body>
</html>
