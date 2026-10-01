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

    /**
     * Messages a moderator has hidden after a report.
     *
     * Kept in the table rather than deleted so the action can be undone and the
     * conversation history stays auditable. Every query that serves messages to
     * the app must exclude these, which is why it is a scope rather than a
     * column check scattered around the controllers.
     */
    public function scopeVisible($query)
    {
        return $query->where('MSG_VISIBILITY', 'VISIBLE');
    }

    public function isHidden(): bool
    {
        return $this->MSG_VISIBILITY === 'HIDDEN';
    }

    public function conversation()
    {
        return $this->belongsTo(Conversation::class, 'CONV_ID', 'CONV_ID');
    }

    public function sender()
    {
        return $this->belongsTo(User::class, 'USR_ID', 'USR_ID');
    }
}
