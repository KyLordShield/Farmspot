@if($profileUser?->USR_ID)
    <a href="{{ route('users.show', $profileUser->USR_ID) }}" class="ms-2 small text-nowrap" aria-label="View profile of {{ $profileUser->USR_NAME }}">View profile</a>
@endif
