<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>{{ $document['title'] }} · Farmspot</title>
<style>body{margin:0;font:16px/1.65 system-ui,sans-serif;color:#213428;background:#f7faf7}main{max-width:760px;margin:30px auto;padding:24px;background:white;border-radius:12px}a{color:#1b6b2c}nav{display:flex;flex-wrap:wrap;gap:8px;margin-top:20px}nav a{background:#edf4ed;padding:6px 10px;border-radius:8px;text-decoration:none;font-size:14px}li{padding-left:5px;margin:10px 0;color:#3e4d43}h2{border-top:1px solid #e6ece5;padding-top:20px}.draft{padding:14px;background:#fff3cd;border-radius:8px}h1{line-height:1.2}h2{font-size:19px;margin-top:28px}.meta{color:#617069;font-size:14px}p{overflow-wrap:anywhere}@media(max-width:800px){main{margin:0;border-radius:0;padding:20px}}</style></head>
<body><main><a href="{{ route('login') }}">Farmspot</a><nav aria-label="Legal pages">@foreach($catalog['documents'] as $item)<a href="{{ route('legal.show', $item['id']) }}">{{ $item['title'] }}</a>@endforeach</nav>
<h1>{{ $document['title'] }}</h1><p class="meta">Version {{ $catalog['version'] }} · {{ $catalog['published'] ? 'Published' : 'Draft for review' }}</p>
@if(!$catalog['published'])<p class="draft">{{ $catalog['draft_notice'] }}</p>@endif
@foreach($document['sections'] as $section)<section><h2>{{ $section['heading'] }}</h2><p>{{ $section['text'] }}</p>@if(!empty($section['points']))<ul>@foreach($section['points'] as $point)<li>{{ $point }}</li>@endforeach</ul>@endif</section>@endforeach
@if($catalog['published'])<p>Operator: {{ $catalog['operator_name'] }}<br>{{ $catalog['contact_text'] ?? '' }}@if(!empty($catalog['contact_email']))<br><a href="mailto:{{ $catalog['contact_email'] }}">{{ $catalog['contact_email'] }}</a>@endif</p>@endif
</main></body></html>
