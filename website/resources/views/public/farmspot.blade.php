<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="description" content="FarmSpot connects farmers and buyers. Explore Premium features, monthly pricing, payment terms, and customer support.">
    <title>FarmSpot · Farmers, produce, and better connections</title>
    <style>
        :root { color-scheme: light; --green: #1b6b2c; --ink: #173b25; --muted: #54665a; --paper: #f5f7f0; }
        * { box-sizing: border-box; }
        html { scroll-behavior: smooth; scroll-padding-top: 24px; }
        body { margin: 0; background: var(--paper); color: var(--ink); font: 17px/1.65 system-ui, sans-serif; }
        a { color: var(--green); text-underline-offset: 4px; }
        a:focus-visible { outline: 3px solid #c9922a; outline-offset: 5px; }
        .wrap { width: min(1120px, 90%); margin-inline: auto; }
        header { background: #fff; border-bottom: 1px solid #dce4d8; }
        header .wrap { display: flex; align-items: center; justify-content: space-between; gap: 24px; padding-block: 20px; }
        .brand { font-size: 25px; font-weight: 800; text-decoration: none; letter-spacing: -.8px; }
        nav { display: flex; flex-wrap: wrap; gap: 22px; font-size: 15px; }
        nav a { color: var(--ink); text-decoration: none; }
        .hero { display: grid; grid-template-columns: 1.1fr 1fr; min-height: 520px; }
        .hero-copy { padding: 64px 40px 64px 0; align-self: center; }
        .eyebrow { color: var(--green); font-size: 13px; font-weight: 800; letter-spacing: 2px; text-transform: uppercase; }
        h1 { font-size: clamp(38px, 5.4vw, 66px); line-height: 1.06; letter-spacing: -2px; margin: 20px 0 24px; }
        h2 { font-size: clamp(28px, 3vw, 40px); line-height: 1.15; letter-spacing: -1px; margin: 0 0 20px; }
        h3 { line-height: 1.3; margin: 0 0 12px; font-size: 20px; }
        p { margin: 0 0 18px; }
        .muted { color: var(--muted); }
        .hero-photo { width: 100%; height: 100%; min-height: 360px; object-fit: cover; }
        .button { display: inline-block; background: var(--green); color: white; padding: 12px 23px; border-radius: 6px; font-weight: 700; text-decoration: none; }
        .section { padding-block: 64px; border-top: 1px solid #dce4d8; }
        .intro { max-width: 700px; margin-bottom: 34px; }
        .features { display: grid; grid-template-columns: repeat(3, 1fr); gap: 30px; }
        .feature { border-top: 3px solid #bdd3a7; padding-top: 20px; }
        .number { display: block; color: var(--green); font-size: 13px; margin-bottom: 16px; font-weight: 700; }
        .premium { display: grid; grid-template-columns: 1fr 1fr; background: var(--ink); color: white; padding: 44px; gap: 50px; border-radius: 12px; }
        .premium .eyebrow { color: #e6ca81; }
        .price { font-size: 64px; font-weight: 800; letter-spacing: -2px; line-height: 1.1; margin: 20px 0 10px; }
        .premium ul { padding-left: 20px; margin: 0; }
        .premium li { padding-block: 8px; }
        .premium .muted { color: #d1ded3; }
        .details { display: grid; grid-template-columns: 1fr 1fr; gap: 60px; }
        .small { font-size: 14px; }
        address { font-style: normal; overflow-wrap: anywhere; }
        footer { background: #e9eee3; padding-block: 28px; font-size: 14px; }
        footer .wrap { display: flex; justify-content: space-between; gap: 20px; flex-wrap: wrap; }
        @media (max-width: 740px) {
            header .wrap { align-items: flex-start; flex-direction: column; gap: 12px; }
            nav { gap: 16px; }
            .hero, .features, .premium, .details { grid-template-columns: 1fr; }
            .hero-copy { padding: 44px 0 30px; }
            .hero-photo { height: 270px; min-height: 0; border-radius: 8px; }
            .section { padding-block: 42px; }
            .premium { padding: 28px; gap: 24px; }
            .details { gap: 32px; }
        }
        @media (prefers-reduced-motion: reduce) { html { scroll-behavior: auto; } }
    </style>
</head>
<body>
    <header>
        <div class="wrap">
            <a class="brand" href="{{ route('public.farmspot') }}">FarmSpot<span aria-hidden="true">.</span></a>
            <nav aria-label="Main navigation">
                <a href="#features">About the app</a>
                <a href="#premium">Premium</a>
                <a href="#contact">Contact</a>
            </nav>
        </div>
    </header>
    <main class="wrap">
        <section class="hero" aria-labelledby="welcome-title">
            <div class="hero-copy">
                <span class="eyebrow">Connecting farmers and buyers</span>
                <h1 id="welcome-title">Good produce starts with a connection.</h1>
                <p class="muted">Discover farms and available produce, talk to sellers, and plan what to source next with the FarmSpot mobile app.</p>
                <a class="button" href="#premium">Explore Premium</a>
            </div>
            <img class="hero-photo" src="{{ asset('images/login-farm.jpg') }}" alt="Hands gathering fresh vegetables in a garden" fetchpriority="high">
        </section>
        <section class="section" id="features" aria-labelledby="features-title">
            <div class="intro">
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
                <div>
                    <span class="eyebrow">FarmSpot Business</span>
                    <h2 id="premium-title">One month of Premium</h2>
                    <p class="price">₱{{ $price }}</p>
                    <p>PHP · one month of access per purchase</p>
                    <p class="muted">Renew manually from the Premium screen in the app. Your plan does not renew automatically.</p>
                </div>
                <div>
                    <ul>
                        <li>Buy requests for your sourcing needs</li>
                        <li>Saved farms and crop availability alerts</li>
                        <li>A weekly sourcing list</li>
                        <li>A Premium badge on your profile and buy requests</li>
                    </ul>
                    <p class="small muted" style="margin-top:24px">Premium activates after payment confirmation. Checkout currently uses PayMongo test mode. Live payments are being arranged. Produce purchases are agreed separately with sellers.</p>
                </div>
            </div>
        </section>
        <section class="section details">
            <article id="refunds" aria-labelledby="refunds-title">
                <h2 id="refunds-title">Payments &amp; refunds</h2>
                <p>{{ $catalog['refund_policy'] }}</p>
                <p class="muted">For payment assistance, contact us using the details on this page and include your payment reference. Keep passwords and one-time codes private.</p>
                <p><a href="{{ route('legal.show', 'terms') }}">Read the Terms of Service</a></p>
            </article>
            <article id="contact" aria-labelledby="contact-title">
                <h2 id="contact-title">Contact the operator</h2>
                <address>
                    <p><strong>{{ $business['business_name'] }}</strong><br>Operator of FarmSpot</p>
                    @if(filled($business['business_address']))
                        <p>{{ $business['business_address'] }}</p>
                    @endif
                    <p><a href="mailto:{{ $business['support_email'] }}">{{ $business['support_email'] }}</a><br>{{ $business['support_phone'] }}</p>
                </address>
                <p class="small muted">Our business sells fresh fruits through a physical fruit stand and operates FarmSpot to connect farmers and buyers.</p>
            </article>
        </section>
    </main>
    <footer>
        <div class="wrap">
            <span>FarmSpot · {{ $business['business_name'] }}</span>
            <nav aria-label="Policies">
                <a href="{{ route('legal.show', 'terms') }}">Terms</a>
                <a href="{{ route('legal.show', 'privacy') }}">Privacy</a>
                <a href="#refunds">Refunds &amp; cancellation</a>
            </nav>
        </div>
    </footer>
</body>
</html>
