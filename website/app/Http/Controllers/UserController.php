<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Services\ModerationService;
use App\Services\NotificationService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;

class UserController extends Controller
{
    public function index(Request $request)
    {
        $users = User::query()
            ->when($request->filled('search'), function ($query) use ($request) {
                $query->where(function ($q) use ($request) {
                    $q->where('USR_NAME', 'like', '%' . $request->search . '%')
                      ->orWhere('USR_EMAIL', 'like', '%' . $request->search . '%')
                      ->orWhere('USR_ID', 'like', '%' . $request->search . '%');
                });
            })
            ->when($request->filled('role'), function ($query) use ($request) {
                $query->where('USR_ROLE', $request->role);
            })
            ->when($request->filled('status'), function ($query) use ($request) {
                $query->where('USR_STATUS', $request->status);
            })
            ->orderBy('USR_CREATED_AT', 'desc')
            ->paginate(10)
            ->withQueryString();

        return view('users', compact('users'));
    }

    public function show($id)
    {
        $user = User::where('USR_ID', $id)->firstOrFail();

        return view('users.show', compact('user'));
    }

    public function create()
    {
        return view('users.create');
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'USR_NAME' => ['required', 'string', 'max:255'],
            'USR_EMAIL' => ['required', 'email', 'max:255', 'unique:user,USR_EMAIL'],
            'USR_PASSWORD' => ['required', 'confirmed', Password::defaults()],
            'USR_MOBILE_NUMBER' => ['required', 'string', 'max:20'],
        ]);

        do {
            $id = strtoupper(Str::random(6));
        } while (User::where('USR_ID', $id)->exists());

        User::create([
            'USR_ID' => $id,
            'USR_NAME' => $validated['USR_NAME'],
            'USR_EMAIL' => $validated['USR_EMAIL'],
            'USR_PASSWORD' => Hash::make($validated['USR_PASSWORD']),
            'USR_MOBILE_NUMBER' => $validated['USR_MOBILE_NUMBER'],
            'USR_ROLE' => 'GENERAL_USER',
            'USR_IS_SELLER' => 0,
            'USR_STATUS' => 'ACTIVE',
            'USR_CREATED_AT' => now(),
        ]);

        return redirect()->route('users')->with('success', 'User created successfully.');
    }

    public function edit($id)
    {
        $user = User::where('USR_ID', $id)->firstOrFail();

        return view('users.edit', compact('user'));
    }

    public function update(Request $request, $id)
    {
        $user = User::where('USR_ID', $id)->firstOrFail();

        // Read before the update. Without this the "did the status actually
        // change" test below is impossible, because $user->update() has already
        // overwritten the old value by the time anything looks at it — and a
        // form that re-saves an unchanged user would then "suspend" them every
        // single time an admin fixed a typo in their email.
        $previousStatus = $user->USR_STATUS;

        $validated = $request->validate([
            'USR_NAME' => ['required', 'string', 'max:255'],
            'USR_EMAIL' => [
                'required', 'email', 'max:255',
                Rule::unique('user', 'USR_EMAIL')->ignore($user->USR_ID, 'USR_ID'),
            ],
            'USR_MOBILE_NUMBER' => ['required', 'string', 'max:20'],
            'USR_ROLE' => ['required', 'in:GENERAL_USER,ADMIN'],
            'USR_STATUS' => ['required', 'in:ACTIVE,PENDING_VERIFICATION,DEACTIVATED'],
            // A deactivation from this panel is a takedown: the owner gets a
            // reason they can read at the refused login and a re-evaluation they
            // can request, exactly like one that arrives through the reports
            // queue. Required only when the save is actually deactivating, so
            // fixing a typo in a name never demands a reason.
            'USR_TAKEDOWN_REASON' => ['nullable', 'string', 'max:500', 'required_if:USR_STATUS,DEACTIVATED'],
        ]);

        $newStatus = $validated['USR_STATUS'];

        $user->update([
            'USR_NAME' => $validated['USR_NAME'],
            'USR_EMAIL' => $validated['USR_EMAIL'],
            'USR_MOBILE_NUMBER' => $validated['USR_MOBILE_NUMBER'],
            'USR_ROLE' => $validated['USR_ROLE'],
            'USR_STATUS' => $newStatus,
        ]);

        if ($newStatus === 'DEACTIVATED') {
            $user->update([
                'USR_TAKEDOWN_REASON' => $validated['USR_TAKEDOWN_REASON'],
                'USR_TAKEDOWN_AT' => now(),
                'USR_HIDDEN_BY_TAKEDOWN' => true,
            ]);
            $user->tokens()->delete();
        } elseif ($previousStatus === 'DEACTIVATED' && $newStatus === 'ACTIVE') {
            // Reinstating from this panel is the same act as approving an
            // appeal, so it goes through the same service: the takedown markers
            // are cleared and only the listings the takedown hid come back.
            // Sharing the code keeps the two doors from drifting apart.
            app(ModerationService::class)->restoreAccount($user);
        }

        $this->notifyStatusChange($user, $previousStatus, $newStatus);

        return redirect()->route('users')->with('success', 'User updated successfully.');
    }

    public function destroy(Request $request, $id)
    {
        $user = User::where('USR_ID', $id)->firstOrFail();

        // Same rule as the edit form: the quick deactivate button collects a
        // reason in its confirm dialog and posts it as a hidden field, so a
        // one-click deactivation is still an appealable takedown.
        $validated = $request->validate([
            'USR_TAKEDOWN_REASON' => ['required', 'string', 'max:500'],
        ]);

        $previousStatus = $user->USR_STATUS;

        $user->update([
            'USR_STATUS' => 'DEACTIVATED',
            'USR_TAKEDOWN_REASON' => $validated['USR_TAKEDOWN_REASON'],
            'USR_TAKEDOWN_AT' => now(),
            'USR_HIDDEN_BY_TAKEDOWN' => true,
        ]);

        // If a user is being deactivated, they must not stay signed in on any
        // device. Setting USR_STATUS alone blocks the next login, but tokens
        // issued before this call would still work — which is the exact reason
        // the report action also revokes them.
        $user->tokens()->delete();

        $this->notifyStatusChange($user, $previousStatus, 'DEACTIVATED');

        return redirect()->route('users')->with('success', 'User deactivated successfully.');
    }

    /**
     * Tell a user their account status actually changed.
     *
     * Three rules, all of them about not sending something misleading:
     *
     *  - Only a real transition counts. Both admin actions here are forms or
     *    buttons that get clicked repeatedly, and a user must not be told they
     *    were suspended by a save that never suspended them.
     *  - Only DEACTIVATED and the way back out of it. A move to
     *    PENDING_VERIFICATION is a routine admin correction with nothing the
     *    user needs to act on.
     *  - Never an admin. An admin's access is managed by another admin out of
     *    band, and mailing them "Please contact your Association Secretary"
     *    would send an authority figure to the authority figures.
     *
     * The inbox row is written even though the tokens were just revoked: that
     * row is the durable record, and it is what the user reads when they next
     * sign in to find out what happened.
     */
    private function notifyStatusChange(User $user, string $previousStatus, string $newStatus): void
    {
        if ($previousStatus === $newStatus) {
            return;
        }

        if ($user->USR_ROLE === 'ADMIN') {
            return;
        }

        if ($newStatus === 'DEACTIVATED') {
            $type = 'ACCOUNT_SUSPENDED';
            $title = 'Your account was deactivated';
            // When the deactivation carries a reason it is an appealable
            // takedown, so the message points at the re-evaluation instead of
            // sending the person to the Association first.
            $body = $user->USR_TAKEDOWN_REASON !== null
                ? 'Reason: '.$user->USR_TAKEDOWN_REASON.' You can request a re-evaluation from the login screen.'
                : 'Please contact your Association Secretary for help.';
        } elseif ($previousStatus === 'DEACTIVATED' && $newStatus === 'ACTIVE') {
            $type = 'ACCOUNT_REACTIVATED';
            $title = 'Your account is active again';
            $body = 'You can use FarmSpot normally again.';
        } else {
            return;
        }

        try {
            app(NotificationService::class)->notify($user->USR_ID, $type, $title, $body);
        } catch (\Throwable $e) {
            // The status change is already saved. A user who is genuinely
            // suspended but never told is a much smaller problem than an admin
            // action that fails because a notification table hiccupped.
            Log::warning('[notifications] account status notification failed', [
                'usr_id' => $user->USR_ID,
                'type' => $type,
                'message' => $e->getMessage(),
            ]);
        }
    }
}