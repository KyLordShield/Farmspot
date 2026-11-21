<?php

namespace App\Notifications;

use Illuminate\Notifications\Messages\MailMessage;

class AdminPasswordResetCode extends AdminSignInCode
{
    public function toMail(object $notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject('Your FarmSpot password reset code ('.$this->reference.')')
            ->line('Your password reset code is '.$this->code.'.')
            ->line('Reference: '.$this->reference.'. Enter it only on your FarmSpot admin profile.')
            ->line('This code expires in five minutes and cannot be used to sign in.')
            ->line('If you did not request a password reset, do not share this code.');
    }
}
