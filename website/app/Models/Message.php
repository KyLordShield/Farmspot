<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Message extends Model
{
    protected $table = 'message';

    protected $primaryKey = 'MSG_ID';

    public $incrementing = false;

    protected $keyType = 'string';

    public $timestamps = false;

    protected $guarded = [];

    public function conversation()
    {
        return $this->belongsTo(Conversation::class, 'CONV_ID', 'CONV_ID');
    }

    public function sender()
    {
        return $this->belongsTo(User::class, 'USR_ID', 'USR_ID');
    }
}
