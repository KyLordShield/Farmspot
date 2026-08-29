<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
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

        $validated = $request->validate([
            'USR_NAME' => ['required', 'string', 'max:255'],
            'USR_EMAIL' => [
                'required', 'email', 'max:255',
                Rule::unique('user', 'USR_EMAIL')->ignore($user->USR_ID, 'USR_ID'),
            ],
            'USR_MOBILE_NUMBER' => ['required', 'string', 'max:20'],
            'USR_ROLE' => ['required', 'in:GENERAL_USER,ADMIN'],
            'USR_STATUS' => ['required', 'in:ACTIVE,PENDING_VERIFICATION,DEACTIVATED'],
        ]);

        $user->update([
            'USR_NAME' => $validated['USR_NAME'],
            'USR_EMAIL' => $validated['USR_EMAIL'],
            'USR_MOBILE_NUMBER' => $validated['USR_MOBILE_NUMBER'],
            'USR_ROLE' => $validated['USR_ROLE'],
            'USR_STATUS' => $validated['USR_STATUS'],
        ]);

        return redirect()->route('users')->with('success', 'User updated successfully.');
    }

    public function destroy($id)
    {
        $user = User::where('USR_ID', $id)->firstOrFail();

        $user->USR_STATUS = 'DEACTIVATED';
        $user->save();

        return redirect()->route('users')->with('success', 'User deactivated successfully.');
    }
}