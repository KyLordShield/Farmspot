<div class="mod-feedback" data-mod-feedback>
    <div role="status" data-mod-copy-feedback></div>
    @foreach(['success', 'error'] as $tone)
        @if(session($tone))
            <div class="mod-toast mod-toast-{{ $tone }}" role="{{ $tone === 'error' ? 'alert' : 'status' }}">
                {{ session($tone) }}<button type="button" class="btn-close" aria-label="Dismiss notification" data-mod-dismiss></button>
            </div>
        @endif
    @endforeach
    @if($errors->any())
        <div class="mod-toast mod-toast-error" role="alert">
            <ul class="mb-0">@foreach($errors->all() as $error)<li>{{ $error }}</li>@endforeach</ul>
            <button type="button" class="btn-close" aria-label="Dismiss validation errors" data-mod-dismiss></button>
        </div>
    @endif
</div>
