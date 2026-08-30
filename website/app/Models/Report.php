<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Report extends Model
{
    protected $table = 'report';

    protected $primaryKey = 'RPT_ID';

    public $timestamps = false;

    protected $fillable = ['RPT_STATUS'];

    public function user()
    {
        return $this->belongsTo(User::class, 'USR_ID', 'USR_ID');
    }

    public function listing()
    {
        return $this->belongsTo(Listing::class, 'LST_ID', 'LST_ID');
    }
}