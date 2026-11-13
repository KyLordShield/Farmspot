<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $document['title'] }} · FarmSpot</title>
    <link rel="stylesheet" href="{{ asset('css/farmspot-public.css') }}?v=2">
</head>
<body>
    <header>
        <div class="wrap">
            <a class="brand" href="{{ route('public.home') }}"><img src="{{ asset('images/logo.png') }}" width="64" height="64" alt=""><span>FarmSpot<span class="brand-dot" aria-hidden="true">.</span></span></a>
            <nav aria-label="Main navigation">
                <a href="{{ route('public.farmspot') }}#features">About the app</a>
                <a href="{{ route('public.farmspot') }}#premium">Premium</a>
                <a class="nav-contact" href="{{ route('public.farmspot') }}#contact">Get in touch <span aria-hidden="true">↗</span></a>
            </nav>
        </div>
    </header>
    <main class="wrap legal-main">
        <p class="eyebrow">FarmSpot policies</p>
        <h1>{{ $document['title'] }}</h1>
        <p class="meta">Version {{ $catalog['version'] }} · {{ $catalog['published'] ? 'Published' : 'Draft for review' }}</p>
        <nav class="legal-nav" aria-label="Legal pages">
            @foreach($catalog['documents'] as $item)
                <a href="{{ route('legal.show', $item['id']) }}" @if($item['id'] === $document['id']) aria-current="page" @endif>{{ $item['title'] }}</a>
            @endforeach
        </nav>
        @if(!$catalog['published'])
            <p class="draft">{{ $catalog['draft_notice'] }}</p>
        @endif
        @foreach($document['sections'] as $section)
            <section>
                <h2>{{ $section['heading'] }}</h2>
                <p>{{ $section['text'] }}</p>
                @if(!empty($section['points']))
                    <ul>@foreach($section['points'] as $point)<li>{{ $point }}</li>@endforeach</ul>
                @endif
            </section>
        @endforeach
        @if($catalog['published'])
            <section>
                <h2>Operator &amp; contact</h2>
                <p>{{ $catalog['operator_name'] }}<br>{{ $catalog['contact_text'] ?? '' }}</p>
                @if(!empty($catalog['contact_email']))
                    <p><a href="mailto:{{ $catalog['contact_email'] }}">{{ $catalog['contact_email'] }}</a></p>
                @endif
                <p><a href="{{ route('public.farmspot') }}#contact">FarmSpot customer support</a></p>
            </section>
        @endif
    </main>
    <footer>
        <div class="wrap">
            <div><a class="footer-brand" href="{{ route('public.home') }}">FarmSpot.</a><p>Connecting farmers and buyers</p></div>
            <nav aria-label="Policies">
                <a href="{{ route('legal.show', 'terms') }}">Terms</a>
                <a href="{{ route('legal.show', 'privacy') }}">Privacy</a>
                <a href="{{ route('public.farmspot') }}#refunds">Refunds &amp; cancellation</a>
            </nav>
        </div>
    </footer>
</body>
</html>
