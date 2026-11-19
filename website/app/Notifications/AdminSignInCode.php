<?php

namespace App\Notifications;

use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class AdminSignInCode extends Notification
{
    public function __construct(public readonly string $code, public readonly string $reference) {}

    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject('Your FarmSpot admin sign-in code ('.$this->reference.')')
            ->line('Your sign-in code is '.$this->code.'.')
            ->line('Sign-in reference: '.$this->reference.'. Use this code on the FarmSpot screen showing the same reference.')
            ->line('The code expires within five minutes.')
            ->line('If you did not try to sign in, you can ignore this email.');
    }
}
