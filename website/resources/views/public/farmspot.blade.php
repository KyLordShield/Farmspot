<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="description" content="FarmSpot connects farmers and buyers. Explore Premium features, monthly pricing, payment terms, and customer support.">
    <title>FarmSpot · Farmers, produce, and better connections</title>
    <link rel="stylesheet" href="{{ asset('css/farmspot-public.css') }}?v=2">
</head>
<body>
    <header>
        <div class="wrap">
            <a class="brand" href="{{ route('public.home') }}"><img src="{{ asset('images/logo.png') }}" width="64" height="64" alt=""><span>FarmSpot<span class="brand-dot" aria-hidden="true">.</span></span></a>
            <nav aria-label="Main navigation">
                <a href="#features">About the app</a>
                <a href="#premium">Premium</a>
                <a class="nav-contact" href="#contact">Get in touch <span aria-hidden="true">↗</span></a>
            </nav>
        </div>
    </header>
    <main class="wrap">
        <section class="hero" aria-labelledby="welcome-title">
            <div class="hero-copy">
                <span class="eyebrow">Connecting farmers and buyers</span>
                <h1 id="welcome-title">Closer to farms.<br><span>Closer to fresh.</span></h1>
                <p class="muted">Discover farms and available produce, talk to sellers, and plan what to source next with the FarmSpot mobile app.</p>
                <div class="hero-actions"><a class="button" href="#premium">Explore Premium <span aria-hidden="true">→</span></a><a class="text-link" href="#features">How FarmSpot works</a></div>
                <p class="hero-caption">Discover produce. Connect directly. Plan your sourcing.</p>
            </div>
            <div class="hero-visual">
                <img class="hero-photo" src="{{ asset('images/login-farm.jpg') }}" alt="Hands gathering fresh vegetables in a garden" fetchpriority="high">
                <div class="photo-caption"><span class="caption-mark" aria-hidden="true">✦</span><div><strong>Rooted in local connections</strong><span>For the people who grow and source produce.</span></div></div>
            </div>
        </section>
        <section class="section" id="features" aria-labelledby="features-title">
            <div class="intro">
                <p class="eyebrow">A better way to source</p>
                <h2 id="features-title">Find a farm. Start a conversation.</h2>
                <p class="muted">FarmSpot helps buyers discover produce and connect directly with farmers. Confirm availability, quantities, prices, and pickup or delivery arrangements with the seller.</p>
            </div>
            <div class="features">
                <article class="feature"><span class="number">01 / DISCOVER</span><h3>Explore farms and crops</h3><p class="muted">Browse farm locations and crop listings to see what sellers have posted.</p></article>
                <article class="feature"><span class="number">02 / CONNECT</span><h3>Talk to the seller</h3><p class="muted">Use messages to ask questions and discuss your purchase directly.</p></article>
                <article class="feature"><span class="number">03 / PLAN</span><h3>Source with Premium</h3><p class="muted">Post buy requests, save farms, and receive crop alerts to support your sourcing.</p></article>
            </div>
        </section>
        <section class="section" id="premium" aria-labelledby="premium-title">
            <div class="premium">
                <div class="plan-overview">
                    <span class="eyebrow">FarmSpot Business</span>
                    <h2 id="premium-title">One month of Premium</h2>
                    <p class="price">₱{{ $price }}<span> / month</span></p>
                    <p class="price-description">PHP · one month of access per purchase</p>
                    <p class="muted">Renew manually from the Premium screen in the app. Your plan does not renew automatically.</p>
                </div>
                <div class="plan-features">
                    <h3>Built for your next sourcing day</h3>
                    <ul>
                        <li>Buy requests for your sourcing needs</li>
                        <li>Saved farms and crop availability alerts</li>
                        <li>A weekly sourcing list</li>
                        <li>A Premium badge on your profile and buy requests</li>
                    </ul>
                    <div class="payment-note"><span class="payment-label">Payment information</span><p>Premium activates after payment confirmation. Checkout currently uses PayMongo test mode. Live payments are being arranged. Produce purchases are agreed separately with sellers.</p></div>
                </div>
            </div>
        </section>
        <section class="section details">
            <article id="refunds" aria-labelledby="refunds-title">
                <p class="eyebrow">Clear payment terms</p>
                <h2 id="refunds-title">Payments &amp; refunds</h2>
                <p>{{ $catalog['refund_policy'] }}</p>
                <p class="muted">For payment assistance, contact us using the details on this page and include your payment reference. Keep passwords and one-time codes private.</p>
                <p><a href="{{ route('legal.show', 'terms') }}">Read the Terms of Service</a></p>
            </article>
            <article id="contact" aria-labelledby="contact-title">
                <p class="eyebrow">We’re here to help</p>
                <h2 id="contact-title">Let’s stay connected.</h2>
                <address>
                    <p><strong>{{ $business['business_name'] }}</strong><br>Operator of FarmSpot</p>
                    @if(filled($business['business_address']))
                        <p>{{ $business['business_address'] }}</p>
                    @endif
                    <p class="contact-method"><span>Email support</span><a href="mailto:{{ $business['support_email'] }}">{{ $business['support_email'] }}</a></p>
                    <p class="contact-method"><span>Customer service</span><a href="tel:{{ preg_replace('/[^+0-9]/', '', $business['support_phone']) }}">{{ $business['support_phone'] }}</a></p>
                </address>
                <p class="small muted">Our business sells fresh fruits through a physical fruit stand and operates FarmSpot to connect farmers and buyers.</p>
            </article>
        </section>
    </main>
    <footer>
        <div class="wrap">
            <div><a class="footer-brand" href="{{ route('public.home') }}">FarmSpot.</a><p>Operated by {{ $business['business_name'] }}</p></div>
            <nav aria-label="Policies">
                <a href="{{ route('legal.show', 'terms') }}">Terms</a>
                <a href="{{ route('legal.show', 'privacy') }}">Privacy</a>
                <a href="#refunds">Refunds &amp; cancellation</a>
            </nav>
        </div>
    </footer>
</body>
</html>
