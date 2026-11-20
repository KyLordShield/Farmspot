@if($value)
    @php $moment = \Carbon\Carbon::parse($value); @endphp
    <time datetime="{{ $moment->toAtomString() }}">{{ $moment->format('M j, Y · g:i A') }}</time>
    <span class="ld-relative">{{ $moment->diffForHumans() }}</span>
@else
    <em class="ld-muted">Not provided</em>
@endif
