<?php

namespace App\Support;

use App\Models\User;

/**
 * Turns the user's own question into at most one navigation button.
 *
 * This is deliberately not the model's job. A model that can invent a screen
 * name will eventually invent one that does not exist, and the app would then
 * have to either faith-follow it or awkwardly explain that the assistant was
 * wrong. Instead the server maps a small, reviewed set of intents to screens
 * the app actually has, and the mobile client ignores anything outside its own
 * allowlist as a second line of defence.
 *
 * The search query is the one value taken from a tool call: when the model has
 * already looked up "pechay" or "Lolo's Farm", the reply can carry a button
 * straight to those results instead of making the user retype the word.
 */
class AiActions
{
    /**
     * @param  array<int, array{name: string, arguments: array}>  $calls
     * @return array<int, array{id: string, label: string, screen: string, params: object|array}>
     */
    public static function forMessage(?User $user, string $latest, array $calls = []): array
    {
        // Punctuation becomes a space so "become a seller?" still matches the
        // phrase "become a seller". Letters and digits survive, including
        // Bisaya/Tagalog accents; only separators are normalised.
        $text = ' '.preg_replace(
            '/[^\p{L}\p{N}]+/u',
            ' ',
            mb_strtolower(trim($latest))
        ).' ';
        $text = (string) preg_replace('/\s+/u', ' ', $text);
        if (trim($text) === '') {
            return [];
        }

        $seller = $user?->isFarmer() ?? false;

        // 1. Becoming a seller / setting a farm up. A seller who already has a
        //    farm is sent to My Farm (where "Add Farm" lives); a buyer is sent
        //    to the Profile entry that starts setup.
        if (self::mentions($text, [
            'become a seller',
            'be a seller',
            'seller mode',
            'seller account',
            'seller registration',
            'register as a seller',
            'set up',
            'setup',
            'getting started',
            'get started',
            'set up a farm',
            'set up my farm',
            'setup my farm',
            'farm setup',
            'create a farm',
            'start a farm',
            'add a farm',
            'add farm',
            'start selling',
            'how to sell',
            'set farm location',
            'set my farm location',
            'change farm location',
            'update farm location',
            'my farm location',
        ])) {
            return $seller
                ? [self::action('open_my_farm', 'Open My Farm', 'my_farm')]
                : [self::action('start_farm_setup', 'Start farm setup', 'profile')];
        }

        // 2. The seller's own farm and produce. A buyer asking the same question
        //    is really asking how to start, so they get the setup entry instead.
        if (self::mentions($text, [
            'my farm',
            'farm status',
            'farm approved',
            'farm rejected',
            'farm pending',
            'my listing',
            'my listings',
            'my produce',
            'list produce',
            'list my produce',
            'sell produce',
            'sell my produce',
            'add a crop',
            'add crop',
            'who contacted me',
            'buyer contacted',
        ])) {
            return $seller
                ? [self::action('open_my_farm', 'Open My Farm', 'my_farm')]
                : [self::action('start_farm_setup', 'Start farm setup', 'profile')];
        }

        // 3. Talking to the other side of a deal.
        if (self::mentions($text, [
            'message',
            'messages',
            'chat',
            'inbox',
            'contact seller',
            'contact the seller',
            'reply to',
        ])) {
            return [self::action('open_messages', 'Open Messages', 'messages')];
        }

        // 4. Alerts.
        if (self::mentions($text, [
            'notification',
            'notifications',
            'alert',
            'alerts',
            'bell icon',
        ])) {
            return [self::action('open_notifications', 'Open Notifications', 'notifications')];
        }

        // 5. Finding a farm or a place.
        if (self::mentions($text, [
            'map',
            'near me',
            'nearby',
            'navigate',
            'navigation',
            'directions',
            'how far',
            'farm location',
        ])) {
            return [self::action('open_map', 'Open Map', 'map')];
        }

        // 6. The account behind every screen.
        if (self::mentions($text, [
            'profile',
            'account',
            'my name',
            'change photo',
            'settings',
            'support',
            'log out',
            'logout',
        ])) {
            return [self::action('open_profile', 'Open Profile', 'profile')];
        }

        // 7. A farm or crop the model already looked up in this turn. The
        //    button reuses the same search the model ran, including the exact
        //    crop/name it typed, so the results screen opens pre-filled.
        $search = self::searchAction($calls);
        if ($search !== null) {
            return [$search];
        }

        // 8. The front door, for browsing questions that named nothing specific.
        if (self::mentions($text, [
            'home',
            'feed',
            'browse',
            'marketplace',
            'search',
        ])) {
            return [self::action('open_home', 'Go to Home', 'home')];
        }

        return [];
    }

    /**
     * Whole-phrase matching. The surrounding spaces stop "message" from firing
     * on "messages" and "map" from firing on "mapagmahal".
     */
    private static function mentions(string $text, array $needles): bool
    {
        foreach ($needles as $needle) {
            if (str_contains($text, ' '.$needle.' ')) {
                return true;
            }
        }

        return false;
    }

    /**
     * The search from the last marketplace/farm lookup in this turn.
     *
     * Cleaned and truncated because it is used in a button label and as the
     * query the app sends to its results screen.
     */
    private static function searchAction(array $calls): ?array
    {
        foreach (array_reverse($calls) as $call) {
            $name = (string) ($call['name'] ?? '');

            $raw = match ($name) {
                'search_farms' => data_get($call, 'arguments.query'),
                'search_marketplace' => data_get($call, 'arguments.crop'),
                default => null,
            };

            if (! is_string($raw)) {
                continue;
            }

            $query = trim((string) preg_replace('/\s+/u', ' ', $raw));
            if ($query === '') {
                continue;
            }
            $query = mb_substr($query, 0, 60);

            // A farm/seller search opens the combined results screen; a crop
            // search keeps the crop-results screen the app already has.
            return $name === 'search_farms'
                ? self::action(
                    'search_farms',
                    'Show results for '.$query,
                    'search',
                    ['query' => $query]
                )
                : self::action(
                    'search_crop',
                    'View '.$query.' listings',
                    'search_crop',
                    ['query' => $query]
                );
        }

        return null;
    }

    private static function action(
        string $id,
        string $label,
        string $screen,
        array $params = []
    ): array {
        return [
            'id' => $id,
            'label' => $label,
            'screen' => $screen,
            // cast, not [], so an empty params encodes as {} and the client can
            // treat it as a map without a special case.
            'params' => $params === [] ? (object) [] : $params,
        ];
    }
}
