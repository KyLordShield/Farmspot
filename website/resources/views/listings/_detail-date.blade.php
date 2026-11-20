@if($value)
    <time datetime="{{ $value->format($withTime ? DATE_ATOM : 'Y-m-d') }}">{{ $value->format($withTime ? 'M j, Y · g:i A' : 'M j, Y') }}</time>
    <span class="ld-relative">{{ $relative($value) }}</span>
@elseif(isset($missing))
    <span class="ld-muted">{{ $missing }}</span>
@else
    <em class="ld-muted">Not provided</em>
@endif
