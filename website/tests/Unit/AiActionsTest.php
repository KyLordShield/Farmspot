<?php

namespace Tests\Unit;

use App\Models\User;
use App\Support\AiActions;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * The action resolver is the contract between the assistant and the app's
 * navigation. These tests pin the wording-to-screen mapping so a prompt tweak
 * or a new phrase cannot silently send someone to the wrong place.
 */
class AiActionsTest extends TestCase
{
    private function seller(): User
    {
        return new User(['USR_IS_SELLER' => 1]);
    }

    private function buyer(): User
    {
        return new User(['USR_IS_SELLER' => 0]);
    }

    public function test_seller_onboarding_points_at_the_profile_setup(): void
    {
        $actions = AiActions::forMessage($this->buyer(), 'How do I become a seller?');

        $this->assertSame('start_farm_setup', $actions[0]['id']);
        $this->assertSame('profile', $actions[0]['screen']);
    }

    public function test_a_seller_onboarding_points_at_my_farm(): void
    {
        $actions = AiActions::forMessage($this->seller(), 'How do I set up?');

        $this->assertSame('open_my_farm', $actions[0]['id']);
        $this->assertSame('my_farm', $actions[0]['screen']);
    }

    public function test_a_short_setup_question_still_offers_the_entry(): void
    {
        $actions = AiActions::forMessage($this->buyer(), 'how to setup');

        $this->assertSame('start_farm_setup', $actions[0]['id']);
        $this->assertSame('profile', $actions[0]['screen']);
    }

    public function test_a_sellers_farm_question_opens_my_farm(): void
    {
        $actions = AiActions::forMessage($this->seller(), 'What is my farm status?');

        $this->assertSame('open_my_farm', $actions[0]['id']);
        $this->assertSame('my_farm', $actions[0]['screen']);
    }

    public function test_a_buyers_farm_question_becomes_the_setup_entry(): void
    {
        $actions = AiActions::forMessage($this->buyer(), 'Why is my farm pending?');

        $this->assertSame('start_farm_setup', $actions[0]['id']);
        $this->assertSame('profile', $actions[0]['screen']);
    }

    #[DataProvider('commonQuestions')]
    public function test_common_questions_map_to_their_screen(
        string $question,
        string $screen
    ): void {
        $actions = AiActions::forMessage($this->buyer(), $question);

        $this->assertNotEmpty($actions, "No action for '{$question}'");
        $this->assertSame($screen, $actions[0]['screen']);
    }

    public static function commonQuestions(): array
    {
        return [
            'messaging' => ['How do I message a seller?', 'messages'],
            'map' => ['Where is the map?', 'map'],
            'alerts' => ['Where are my notifications?', 'notifications'],
            'account' => ['How do I change my profile photo?', 'profile'],
            'home' => ['How do I get back home?', 'home'],
        ];
    }

    public function test_the_crop_from_a_tool_call_becomes_the_search_query(): void
    {
        $actions = AiActions::forMessage(
            $this->buyer(),
            'Where can I buy tomatoes?',
            [['name' => 'search_marketplace', 'arguments' => ['crop' => '  tomatoes ']]]
        );

        $this->assertSame('search_crop', $actions[0]['screen']);
        $this->assertSame('tomatoes', $actions[0]['params']['query']);
        $this->assertStringContainsString('tomatoes', $actions[0]['label']);
    }

    public function test_the_farm_or_seller_from_a_tool_call_becomes_a_search(): void
    {
        $actions = AiActions::forMessage(
            $this->buyer(),
            "Where is Lolo's Farm?",
            [['name' => 'search_farms', 'arguments' => ['query' => "  Lolo's Farm "]]]
        );

        $this->assertSame('search_farms', $actions[0]['id']);
        $this->assertSame('search', $actions[0]['screen']);
        $this->assertSame("Lolo's Farm", $actions[0]['params']['query']);
    }

    public function test_an_empty_question_produces_no_action(): void
    {
        $this->assertSame([], AiActions::forMessage($this->buyer(), '   '));
    }

    public function test_no_phrase_match_produces_no_action(): void
    {
        $this->assertSame(
            [],
            AiActions::forMessage($this->buyer(), 'When should I plant pechay?')
        );
    }
}
