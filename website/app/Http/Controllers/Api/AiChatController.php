<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Support\AiTools;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * The FarmSpot in-app assistant.
 *
 * A thin pass-through to Groq's OpenAI-compatible chat completions endpoint,
 * plus the small tool loop that lets the model read the caller's own FarmSpot
 * data. The provider key comes from config (GROQ_API_KEY) and is never
 * returned to, or even reachable by, the mobile app.
 *
 * Three constraints shape the design, all of them coming from the free tier:
 *
 *  1. Only the last MAX_TURNS messages are forwarded. The client keeps its
 *     history short, but the server enforces its own bound too rather than
 *     trusting whatever a caller sends. This is what keeps each request inside
 *     the free per-minute and per-day token budgets.
 *  2. Tool calling costs a second round trip, so MAX_TOOL_ROUNDS caps the loop.
 *     A tool result also has to fit the same budget as the conversation.
 *  3. Every failure mode returns a readable message. The assistant is additive
 *     to the app, never load-bearing, so a missing key, a throttled provider or
 *     a dropped connection must surface as "try again shortly" rather than
 *     taking the rest of the app down with it.
 */
class AiChatController extends Controller
{
    /** Messages forwarded to the provider: the recent tail of the conversation. */
    private const MAX_TURNS = 8;

    /** Hard input cap, so one pasted paragraph cannot blow the token budget. */
    private const MAX_MESSAGE_CHARS = 1000;

    /** Upper bound on the reply, to keep answers short and cheap. */
    private const MAX_REPLY_TOKENS = 500;

    /**
     * How many times the model may call tools before we make it answer.
     *
     * One round is enough for every real question. The cap exists so a model
     * that gets stuck retrying a tool cannot loop and burn the day's budget.
     */
    private const MAX_TOOL_ROUNDS = 2;

    private const TIMEOUT_SECONDS = 30;

    private const TEMPERATURE = 0.4;

    /**
     * The system prompt carries three jobs that the code cannot enforce:
     * focus (this is a help desk for the app), scope (do not stray), and tone
     * (the people asking are often stuck, and some are looking at a rejected
     * farm, so the wording matters as much as the facts).
     *
     * The app's own navigation is deliberately NOT in here. It lives in the
     * get_app_guide tool instead, so it is only paid for when a how-to question
     * is asked rather than on every request.
     */
    private const SYSTEM_PROMPT = <<<'PROMPT'
You are the FarmSpot assistant. FarmSpot is a marketplace in the Philippines
where farmers sell produce and buyers find and contact them.

WHICH MESSAGE YOU ANSWER
Answer the message the user just sent. If the newest message changes the
subject, follow it to the new subject. Never carry on answering an earlier
question in the same thread.

WHAT YOU ARE FOR — answer these three:
1. Helping people use FarmSpot: listing produce, searching, messaging a seller,
   seller setup, farm approval, and where a feature lives.
2. Questions about the user's own account, farm, listings or activity. Use the
   tools every time. Never guess at their data, never describe another user's.
3. Farming questions: growing, pests, planting schedules, harvesting,
   post-harvest handling and general produce knowledge.

OUT OF SCOPE — do not answer
Politics, medical or legal advice, programming, schoolwork, general news, and
requests for your own opinions on unrelated matters. Reply in one short
sentence that you cover FarmSpot and farming, then offer what you can help
with. Do not lecture, and do not list everything you cannot do.

MENUS AND BUTTONS
For any "how do I", "where do I find" or "what does this button do" question,
call get_app_guide and answer only with the tab and button names it returns.
Never invent a screen, tab or button name, and never tell people to use the
phone back button to move between sections. If the answer is not in the guide,
say you are not sure and point them to Contact Support in Profile.

HOW TO ANSWER
- Be warm and patient. People ask because they are stuck, unsure or worried.
- If the user sounds frustrated, stuck or worried, open with ONE short
  sentence that acknowledges it, then give the steps. Otherwise lead with the
  steps directly and do not pad the answer with pleasantries.
- Never imply a rejected or pending item is the user's fault, and never guess
  why something was rejected. Check their farm status, and if it is rejected
  point them to Contact Support.
- Give concrete directions ("Profile, then the Become a Seller switch")
  rather than general encouragement.
- Do not claim a task is done on the app's behalf. If an action needs the user
  to tap something, say so.
- One account can own SEVERAL farms, and each has its own approval status,
  location, listings and stats. When a seller says "my farm" and they own more
  than one, ask which farm they mean instead of assuming there is only one.
  Never add one farm's numbers to another's.
- If you do not know, say so plainly and suggest who to ask.

LANGUAGE - this rule is strict, follow it every time
Judge the user's most recent message, then reply in the language this table
names:
- English in, English out. Always.
- Tagalog in, Bisaya out.
- Bisaya or Cebuano in, Bisaya out.
So Tagalog and Bisaya both get a Bisaya answer, and an English question never
gets a Filipino answer. Judge a short question by the words it really uses, so
"magkano?" is Bisaya and "how much?" is English. Write the Bisaya in everyday
Filipino words instead of translating English ones word for word.

FORMAT - plain text, laid out as steps
Your reply is shown as plain text in a chat bubble. Markdown is not rendered,
so any marker you type shows up literally and looks broken. Never use ** or __
for bold, * or _ for italics, ` for code, # for headings, - for bullets, or
[text](url) for links.

Shape the answer so it can be read at a glance, not as one solid paragraph:
- How-to answers are a numbered list, one step per line: "1. Open Profile."
  "2. Turn on Become a Seller."
- Say one short sentence first, then the steps.
- One line per step. No step runs past a single sentence.
- No nested lists, no sub-points, no paragraphs of more than two sentences.
- A yes/no or single-fact question still gets a short one or two line answer,
  not a list.

HOW TO SOUND
Write like a helpful person on a chat, not a page from a manual. Short
sentences, everyday words, no jargon. Skip filler such as "Great question!",
"Certainly!" or "I hope this helps", and do not restate the question back
before answering it.

NEVER INVENT
No prices, buyer contact details, farm locations, policies or approval
outcomes unless a tool result or the user just told you. You have no live
weather feed, so if asked for weather, say you cannot check it. For who has
produce in stock, use search_marketplace. A farmer who acts on a made-up price
loses money.
PROMPT;

    /**
     * POST /api/ai/chat
     *
     * Body: { "messages": [{ "role": "user"|"assistant", "content": "..." }] }
     * Reply: { "reply": "...", "model": "...", "tools_used": ["..."] }
     */
    public function chat(Request $request)
    {
        $validated = $request->validate([
            'messages' => ['required', 'array', 'min:1', 'max:20'],
            'messages.*.role' => ['required', 'string', 'in:user,assistant'],
            'messages.*.content' => ['required', 'string', 'max:'.self::MAX_MESSAGE_CHARS],
        ]);

        $key = config('services.groq.key');
        if (blank($key)) {
            return $this->unavailable(
                'The assistant is not set up yet. Please add a GROQ_API_KEY to the server .env file.'
            );
        }

        $model = config('services.groq.model');
        $tools = new AiTools($request->user());

        // Everything below the system prompt accumulates: the conversation
        // window, then any assistant tool call and its result per round.
        $messages = array_merge(
            [['role' => 'system', 'content' => self::SYSTEM_PROMPT]],
            $this->window($validated['messages'])
        );

        $used = [];
        $reply = null;

        for ($round = 0; $round <= self::MAX_TOOL_ROUNDS; $round++) {
            $upstream = $this->callProvider($key, $model, $messages);

            if ($upstream['failed']) {
                return $upstream['response'];
            }

            $choice = data_get($upstream['body'], 'choices.0');
            $toolCalls = data_get($choice, 'message.tool_calls') ?: [];

            if (empty($toolCalls) || $round === self::MAX_TOOL_ROUNDS) {
                // Either it answered, or it ran out of budget and we take
                // whatever text it managed to produce.
                $reply = data_get($choice, 'message.content');
                break;
            }

            $messages[] = [
                'role' => 'assistant',
                'content' => data_get($choice, 'message.content') ?? '',
                'tool_calls' => $toolCalls,
            ];

            foreach ($toolCalls as $call) {
                $name = data_get($call, 'function.name');
                $used[] = $name;

                $messages[] = [
                    'role' => 'tool',
                    'tool_call_id' => data_get($call, 'id'),
                    // Json-encodable result, handed straight to the model.
                    'content' => json_encode(
                        $this->runTool($tools, (string) $name, $call)
                    ),
                ];
            }
        }

        if (blank($reply)) {
            return $this->unavailable('The assistant did not return an answer. Please try again.');
        }

        return response()->json([
            'reply' => trim((string) $reply),
            'model' => $model,
            'tools_used' => array_values(array_unique($used)),
        ]);
    }

    /**
     * Runs one tool call, defensively.
     *
     * The arguments come from the model, so they are treated as untrusted: a
     * tool we do not recognise, or one called with garbage, gets a note back
     * so the model can recover on the next turn instead of the request 500ing.
     */
    private function runTool(AiTools $tools, string $name, array $call): array
    {
        if (!in_array($name, AiTools::names(), true)) {
            return ['error' => "Unknown tool '$name'."];
        }

        $raw = data_get($call, 'function.arguments');
        $arguments = is_array($raw) ? $raw : (json_decode((string) $raw, true) ?: []);

        if (!is_array($arguments)) {
            $arguments = [];
        }

        return $tools->run($name, $arguments);
    }

    /**
     * One provider call, with the failure modes already translated into
     * responses this controller can hand straight back.
     *
     * @return array{failed: bool, response?: \Illuminate\Http\Response, body?: array}
     */
    private function callProvider(string $key, string $model, array $messages): array
    {
        try {
            $upstream = Http::withToken($key)
                ->acceptJson()
                ->timeout(self::TIMEOUT_SECONDS)
                ->post(rtrim((string) config('services.groq.base_url'), '/').'/chat/completions', [
                    'model' => $model,
                    'messages' => $messages,
                    'tools' => AiTools::schemas(),
                    'tool_choice' => 'auto',
                    'max_tokens' => self::MAX_REPLY_TOKENS,
                    'temperature' => self::TEMPERATURE,
                ]);
        } catch (\Throwable $e) {
            Log::warning('AI assistant could not reach the provider.', [
                'error' => $e->getMessage(),
            ]);

            return [
                'failed' => true,
                'response' => $this->unavailable('The assistant could not be reached. Please try again shortly.'),
            ];
        }

        if ($upstream->status() === 429) {
            // The free tier is a shared budget; a throttle is expected, not a bug.
            return [
                'failed' => true,
                'response' => response()->json([
                    'message' => 'The assistant is busy right now. Please try again in a moment.',
                ], 429),
            ];
        }

        if ($upstream->status() === 401 || $upstream->status() === 403) {
            // Key present but not accepted. Log the status, never the key.
            Log::warning('AI assistant rejected the provider credentials.', [
                'status' => $upstream->status(),
            ]);

            return [
                'failed' => true,
                'response' => $this->unavailable('The assistant credentials were rejected. Please check GROQ_API_KEY.'),
            ];
        }

        if ($upstream->failed()) {
            Log::warning('AI assistant provider error.', [
                'status' => $upstream->status(),
            ]);

            return [
                'failed' => true,
                'response' => $this->unavailable('The assistant is having trouble right now. Please try again shortly.'),
            ];
        }

        return ['failed' => false, 'body' => $upstream->json() ?: []];
    }

    /**
     * Keeps only the most recent MAX_TURNS messages.
     *
     * The window is taken from the end because recency is what carries the
     * conversation; older turns are the ones that quietly inflate every
     * subsequent request.
     */
    private function window(array $messages): array
    {
        $recent = array_slice($messages, -self::MAX_TURNS);

        return array_values(array_map(
            fn ($message) => [
                'role' => $message['role'],
                'content' => trim($message['content']),
            ],
            $recent
        ));
    }

    /**
     * 503 is deliberate. It signals "this optional feature is switched off",
     * which is accurate, and it keeps the mobile client's error branch honest
     * instead of pretending an upstream 500 happened.
     */
    private function unavailable(string $message)
    {
        return response()->json(['message' => $message], 503);
    }
}
