@if(filled($id))
    <button type="button" class="ld-copy" data-mod-copy="{{ $id }}" aria-label="Copy ID {{ $id }}">
        <span>{{ $id }}</span> <i class="bi bi-copy" aria-hidden="true"></i>
    </button>
@endif
