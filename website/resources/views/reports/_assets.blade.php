@push('styles')
    <link rel="stylesheet" href="{{ asset('css/listing-details.css') }}?v={{ filemtime(public_path('css/listing-details.css')) }}">
    <link rel="stylesheet" href="{{ asset('css/moderation.css') }}?v={{ filemtime(public_path('css/moderation.css')) }}">
@endpush
@push('scripts')
    <script src="{{ asset('js/moderation.js') }}?v={{ filemtime(public_path('js/moderation.js')) }}" defer></script>
@endpush
