<?php

namespace App\Http\Controllers;

use App\Models\User;

class UserController extends Controller
{
    public function index()
    {
        $users = User::orderBy('USR_CREATED_AT', 'desc')
                     ->paginate(10);

        return view('users', compact('users'));
    }

public function show($id)
{
    $user = User::where('USR_ID', $id)->firstOrFail();

    return view('users.show', compact('user'));
}
}