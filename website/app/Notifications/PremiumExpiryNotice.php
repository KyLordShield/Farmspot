<?php

namespace App\Notifications;

use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class PremiumExpiryNotice extends Notification
{
    public function __construct(
        public string $title,
        public string $body,
    ) {
    }

    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $sender = trim((string) config('mail.from.name'));

        return (new MailMessage)
            ->from(config('mail.from.address'), $sender === '' || $sender === 'Laravel' ? 'FarmSpot' : $sender)
            ->subject('FarmSpot: '.$this->title)
            ->greeting('Hi '.($notifiable->USR_NAME ?: 'there').',')
            ->line($this->body)
            ->line('Premium does not renew automatically. Open the Premium screen in FarmSpot to renew when you are ready.');
    }
}
