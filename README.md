# n8n AI Lead Qualifier

[![n8n](https://img.shields.io/badge/n8n-Workflow-EA4B71?style=for-the-badge&logo=n8n&logoColor=white)](https://n8n.io)
[![Gemini API](https://img.shields.io/badge/Gemini_API-8E75B2?style=for-the-badge&logo=google&logoColor=white)](https://ai.google.dev)
[![Airtable](https://img.shields.io/badge/Airtable-CRM-18BFFF?style=for-the-badge&logo=airtable&logoColor=white)](https://airtable.com)
[![Automation](https://img.shields.io/badge/Automation-BANT-0A7B3E?style=for-the-badge)](https://n8n.io)
[![Webhooks](https://img.shields.io/badge/Webhooks-POST-2088FF?style=for-the-badge)](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/)

An autonomous n8n workflow powered by **Google Gemini** that qualifies inbound leads with the **BANT** framework, scores them **1–10**, classifies them as `HOT` / `WARM` / `COLD` / `SPAM`, files every one of them in an **Airtable** CRM table, and routes the response immediately: a Telegram alert plus an email to sales, or an automatic polite decline.

## Business value

Sales teams burn hours on leads that will never buy: students, spam, "just curious", empty forms. This workflow closes the first filter **in seconds**, with no human in the loop.

| Problem | What the workflow does |
|---------|------------------------|
| An SDR reads every submission by hand | Gemini scores Budget, Authority, Need, and Timeline against one standard |
| A HOT lead waits until morning | Telegram alert and an email to the sales inbox the moment it arrives |
| Cold and junk requests eat calendar slots | Polite decline sent to the lead, no meeting booked |
| Different reps apply different criteria | One 1–10 scale and four categories, reproducible in the CRM |
| Lead history lives in a chat that scrolls away | Every scored lead is written to Airtable with its BANT breakdown and timestamp |
| Forms, ads, and landing pages are not integrated | A single `POST` webhook accepts any source (Tally, Webflow, ads, your own site) |

The outcome: your team only talks to `HOT` and `WARM`, nobody is left in silence, and `SPAM` never enters the pipeline.

## Architecture

```
                    ┌──────────────────────┐
                    │  Inbound lead        │
                    │  form / CRM / ads    │
                    └──────────┬───────────┘
                               │ POST JSON
                               ▼
                    ┌──────────────────────┐
                    │  n8n Webhook         │
                    │  /lead-qualifier     │
                    └──────────┬───────────┘
                               ▼
                    ┌──────────────────────┐
                    │  Prepare Lead Data   │
                    │  name, email, company│
                    │  budget, need, time  │
                    └──────────┬───────────┘
                               ▼
                    ┌──────────────────────┐
                    │  Google Gemini LLM   │
                    │  BANT system prompt  │
                    │  score 1–10          │
                    │  HOT|WARM|COLD|SPAM  │
                    └──────────┬───────────┘
                               ▼
                    ┌──────────────────────┐
                    │  Normalize Result    │
                    └──┬────────────────┬──┘
                       │                │
                       ▼                ▼
        ┌──────────────────────┐   ┌──────────────────────┐
        │  Airtable CRM        │   │  Switch by category  │
        │  one row per lead    │   └──┬───────────────┬───┘
        │  11 mapped columns   │      │               │
        └──────────────────────┘      │ HOT/WARM      │ COLD/SPAM
                                      ▼               ▼
                          ┌────────────────────┐  ┌─────────────────────┐
                          │ Telegram alert     │  │ Email: polite       │
                          │ + email to sales   │  │ rejection to lead   │
                          └─────────┬──────────┘  └──────────┬──────────┘
                                    │                        │
                                    └───────────┬────────────┘
                                                ▼
                                     ┌──────────────────────┐
                                     │ Respond to Webhook   │
                                     │ JSON qualification   │
                                     └──────────────────────┘
```

Airtable sits on its own branch rather than in the main chain, for two reasons. An n8n node replaces `$json` with its own output, so putting Airtable inline would feed the Airtable record — not the lead — into the Switch and every node after it. And a CRM problem (expired token, renamed column) should never be able to swallow a HOT lead alert: the node is set to `continueRegularOutput`, so the run carries on even if the write fails.

## Quick start

Roughly fifteen minutes from clone to a scored lead:

1. **Airtable** — create a base with a `Leads` table using the [columns below](#table-structure), then mint a personal access token with `data.records:write` and `schema.bases:read` on that base.
2. **Import** — in n8n, **Menu (☰) → Import from File** and pick `workflows/AI Lead Qualifier (BANT + Gemini).json`.
3. **Credentials** — map the four accounts n8n asks for: Gemini, Telegram, SMTP, Airtable.
4. **Variables** — in **Settings → Variables** add `TELEGRAM_CHAT_ID`, `SALES_EMAIL`, `FROM_EMAIL`, `AIRTABLE_BASE_ID`, `AIRTABLE_TABLE_NAME`. The workflow reads all of them through `$env`, so nothing personal is hard-coded in the file.
5. **Activate** — flip the **Active** toggle and copy the Production URL from the **Webhook** node.
6. **Verify** — run `.\scripts\send-test-lead.ps1 -Preset hot -Production`, which walks the whole chain and prints where it broke, if anywhere.

Missing a credential is not fatal while you set things up: deactivate the email nodes with `D`, and the Airtable node already runs in `continueRegularOutput` mode.

## Repository layout

```
n8n-ai-lead-qualifier/
├── workflows/
│   └── AI Lead Qualifier (BANT + Gemini).json   # ready-to-import n8n workflow
├── prompts/
│   └── system_prompt.md               # full BANT system prompt
├── scripts/
│   └── send-test-lead.ps1             # sends a test lead and verifies the whole chain
└── README.md
```

## Inside the workflow

| Node | Role |
|------|------|
| **Webhook** | Accepts `POST` with `name`, `email`, `company`, `budget`, `project_description`, `timeline`. Responds only after the AI step (`responseNode`). |
| **Prepare Lead Data** | Normalizes both webhook v2 bodies (`$json.body.*`) and flat payloads. Fills a missing `company` with the domain part of the email. |
| **BANT Qualifier** + **Google Gemini Chat Model** + **Structured Output Parser** | LLM scoring against BANT with a strict JSON contract. |
| **Normalize Result** | Reduces the Gemini output to `score`, `category`, `bant`, `reasoning`. |
| **Save Lead to Airtable** | Writes one row per scored lead into the CRM table. Runs on its own branch and never blocks the rest. |
| **Route by Category** | Switch with four branches: HOT, WARM, COLD, SPAM. |
| **Telegram Sales Alert** + **Email Sales Team** | Notifications for HOT and WARM. |
| **Email Polite Rejection** | Polite decline sent to the lead for COLD and SPAM. |
| **Respond to Webhook** | Returns the qualification JSON to the caller. |

Two rules keep this graph working, and both are easy to break when you edit it:

- **Never use `$json` after a node that talks to an external service.** The Telegram node outputs the Telegram API reply and the email node outputs the SMTP result, so the lead fields are gone downstream. `Email Sales Team` and `Respond to Webhook` therefore read `$('Normalize Result').first().json.*` explicitly.
- **Do not put a Merge node before the response.** A Switch fires exactly one branch, so a Merge waiting on a second input never runs and the caller gets an empty body. Both branches connect straight into `Respond to Webhook`.

If you have no SMTP credential yet, select each email node and press `D` to deactivate it. n8n passes data straight through a deactivated node, so the chain still completes and the webhook still answers.

## Prerequisites

- n8n **1.70+** (requires the LangChain nodes `chainLlm` and `lmChatGoogleGemini`)
- A Gemini API key from [Google AI Studio](https://aistudio.google.com/apikey)
- A Telegram bot ([@BotFather](https://t.me/BotFather)) and a `chat_id` (your user id or a group)
- SMTP (or Gmail) for outgoing email
- An Airtable base and a personal access token — see [Airtable integration](#airtable-integration)

Environment variables in n8n (**Settings → Variables**, or your container env):

| Variable | Purpose |
|----------|---------|
| `TELEGRAM_CHAT_ID` | Where HOT/WARM alerts are sent |
| `SALES_EMAIL` | Sales team inbox |
| `FROM_EMAIL` | Sender address for outgoing email |
| `AIRTABLE_BASE_ID` | Base that holds the leads table (`app…`) |
| `AIRTABLE_TABLE_NAME` | Table name or table id (`Leads` / `tbl…`) |

The Airtable token is **not** an environment variable: it lives in an n8n credential, so it stays encrypted at rest and never appears in an exported workflow.

## Airtable integration

Every scored lead becomes one row, so the sales team gets a searchable CRM instead of a Telegram feed that scrolls away. Because the node sits on its own branch, a broken token or a renamed column shows up as a failed node in **Executions** while alerts and the webhook reply keep working.

### Table structure

Create a base with one table (the workflow calls it `Leads` by default) and these fields:

| Column | Airtable type | Filled from |
|--------|---------------|-------------|
| `Lead Name` | Single line text | `name` from the payload |
| `Email` | Email | `email` from the payload |
| `Company` | Single line text | `company`, or the email domain when the form does not ask for it |
| `Budget` | Single line text | `budget` exactly as the lead phrased it (`$18,000 approved this quarter`) |
| `Authority` | Long text | Gemini's read on who this person is and whether they can sign |
| `Need` | Long text | `project_description` from the payload |
| `Timeline` | Single line text | `timeline` exactly as the lead phrased it |
| `BANT Score` | Number (integer, precision 0) | `1`–`10` total |
| `Category` | Single select — `HOT`, `WARM`, `COLD`, `SPAM` | The verdict that drives routing |
| `AI Summary` | Long text | Gemini's reasoning plus the recommended next step |
| `Created At` | Date (include time, ISO/GMT) | `qualified_at`, the moment scoring finished |

Two notes on the column choices. `Budget`, `Need` and `Timeline` keep the lead's own words because that is what a rep wants to read before a call, while `Authority` has no counterpart in the form and can only come from the model. And the brief asked for a single `BANT Score` column holding `HOT`/`WARM`/`COLD` — that is split into a numeric `BANT Score` and a `Category` select here, because sorting by "how hot" and filtering by category are different jobs and Airtable cannot do both from one field.

The node sends values with `typecast` enabled, so Airtable coerces the ISO timestamp into the date field and creates a missing select option instead of rejecting the write.

### Credentials and variables

1. In Airtable, open [Personal access tokens](https://airtable.com/create/tokens) and create a token with the `data.records:write` and `schema.bases:read` scopes, granted to the base you just created.
2. In n8n, add an **Airtable Personal Access Token** credential and paste it there.
3. In **Settings → Variables**, set `AIRTABLE_BASE_ID` (the `app…` id from the base URL) and `AIRTABLE_TABLE_NAME` (`Leads`, or the `tbl…` id).
4. Open **Save Lead to Airtable** once and pick your credential; the field mapping is already filled in.

Every lead is stored, `SPAM` included, which keeps an audit trail of what the filter rejected. If you would rather keep junk out of the CRM, move the node's input connection from **Normalize Result** to the `HOT` and `WARM` outputs of **Route by Category**.

## Importing the JSON into n8n and testing it

### 1. Import the workflow

1. Open n8n.
2. **Menu (☰) → Import from File** (or **Add workflow → ⋮ → Import**).
3. Select `workflows/AI Lead Qualifier (BANT + Gemini).json`.
4. Save the workflow. It is imported **disabled** (`active: false`).

### 2. Credentials

After the import, n8n asks you to map three accounts:

1. **Google Gemini API** (`googlePalmApi`) — paste the API key from AI Studio.
2. **Telegram Bot** (`telegramApi`) — the token from BotFather.
3. **SMTP Account** (`smtp`) — host, port, user, password (or a Gmail App Password).
4. **Airtable Personal Access Token** (`airtableTokenApi`) — the token created in [Airtable integration](#airtable-integration).

The **Google Gemini Chat Model** node defaults to `models/gemini-2.5-flash`; change `modelName` if your key exposes a different model.

In the **BANT Qualifier** node you can replace the system message with the full text from [`prompts/system_prompt.md`](prompts/system_prompt.md).

### 3. Get the webhook URL

1. Open the **Webhook** node and copy the **Production URL**  
   (it looks like `https://<your-n8n>/webhook/lead-qualifier`).
2. For manual debugging use the **Test URL** together with **Execute workflow** on the canvas. Do not use the Webhook node's own **Listen for test event** button for this: it runs the trigger only, captures the payload, and stops — the rest of the graph never executes and the caller gets an instant empty 200.
3. Flip the **Active** toggle — the Production URL only works while the workflow is active. Production runs are not animated on the canvas; they appear only in **Executions**.

### 4. Test with curl

```bash
curl -X POST "https://YOUR-N8N-HOST/webhook/lead-qualifier" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Olena Kovalenko",
    "email": "olena.kovalenko@brightforge.io",
    "company": "BrightForge",
    "budget": "$15000",
    "project_description": "We get 200 inbound demo requests per month from the website. Need an n8n + Gemini qualifier that scores BANT, pings sales on Slack/Telegram, and auto-declines junk. Must go live this month before the paid ads campaign.",
    "timeline": "This month, before 1 September"
  }'
```

Expect HTTP **200** and a JSON body with a `qualification` block (see the example below). In parallel, a row appears in Airtable, and a Telegram message plus an email to `SALES_EMAIL` arrive. `company` is optional — leave it out and the workflow stores `brightforge.io`, taken from the address.

Cold / spam scenario:

```bash
curl -X POST "https://YOUR-N8N-HOST/webhook/lead-qualifier" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "test",
    "email": "asdf@mailinator.com",
    "budget": "free",
    "project_description": "asdf lorem ipsum guest post crypto",
    "timeline": ""
  }'
```

Expect `category: "SPAM"` (or `COLD`) and a polite decline sent to that address.

### 5. Test with Postman

Postman has no dedicated "webhook" menu entry — you build a plain HTTP request:

1. Click **New** (top left) → **HTTP** (called **Request** in older versions). The **+** on the tab bar works too.
2. In the method dropdown, change `GET` to **POST**.
3. Paste the webhook URL into the address field.
4. Open the **Body** tab (below the address bar) → select the **raw** radio button → in the dropdown to its right, change `Text` to **JSON**.
5. Paste the payload from [the example below](#example-request-payload). Postman adds the `Content-Type: application/json` header for you.
6. Click **Send**.

The n8n **Executions** tab should show a run with the Switch taking the matching branch.

If you use the **Test URL**, click **Execute workflow** in the editor first, otherwise Postman gets `404 ... webhook is not registered`. The test URL accepts exactly one call per click; the production URL has no such limit.

### 6. Test without Postman

**The PowerShell script in this repo** is the fastest path. Point it at your instance once:

```powershell
$env:N8N_BASE_URL = 'https://your-instance.app.n8n.cloud'

# HOT lead to the test webhook, waiting for you to click Execute workflow
.\scripts\send-test-lead.ps1 -Wait

# other scenarios
.\scripts\send-test-lead.ps1 -Preset warm
.\scripts\send-test-lead.ps1 -Preset cold
.\scripts\send-test-lead.ps1 -Preset spam

# production URL (workflow must be Active), unlimited calls
.\scripts\send-test-lead.ps1 -Preset hot -Production
```

Instead of the environment variable you can pass `-BaseUrl https://your-instance.app.n8n.cloud` on every call.

Add three more variables and the script also confirms the row actually landed in the CRM, by querying Airtable for a record with that email created in the last two minutes:

```powershell
$env:AIRTABLE_PAT = 'patXXXXXXXXXXXXXX'
$env:AIRTABLE_BASE_ID = 'appXXXXXXXXXXXXXX'
$env:AIRTABLE_TABLE_NAME = 'Leads'

.\scripts\send-test-lead.ps1 -Preset hot -Production
```

The run then reports each link of the chain:

```
=== chain check ===
[ ok ] Webhook                HTTP 200 in 24s
[ ok ] Gemini analysis        HOT 10/10
[ ok ] Company captured       BrightForge Analytics
[ ok ] Airtable record        recA1B2C3D4E5F6G7 - Marta Ivanenko, Co-Founder at BrightForge Analytics
[ ok ] Airtable columns       all 11 fields written
[ .. ] Telegram alert         expect a HOT message in the sales chat
[ .. ] Email to sales         expect a lead summary at SALES_EMAIL
```

Without the Airtable variables that step is reported as `[skip]` rather than failing, and `-SkipAirtableCheck` turns it off explicitly. Telegram and email are marked `[ .. ]` because the script cannot read your inbox — it only tells you what should have arrived for the category the lead was given.

**With no HTTP request at all** — use pinned data in n8n. This is the most convenient loop for iterating on the prompt:

1. Open the **Webhook** node and send any request once (or click **Listen for test event** and send one).
2. In the node's **OUTPUT** panel, click the **Pin** (paperclip) icon.
3. **Execute workflow** now runs the whole chain on the pinned data — no curl, no Postman.
4. To change the test lead, click **Edit Output** on the pinned data and edit the JSON right inside n8n.

Remember to unpin before going live, otherwise the workflow keeps running on frozen data.

## Example request payload

```json
{
  "name": "Olena Kovalenko",
  "email": "olena.kovalenko@brightforge.io",
  "company": "BrightForge",
  "budget": "$15000",
  "project_description": "We get 200 inbound demo requests per month from the website. Need an n8n + Gemini qualifier that scores BANT, pings sales on Telegram, and auto-declines junk. Must go live this month before the paid ads campaign.",
  "timeline": "This month, before 1 September"
}
```

Only `email` is really required. Anything you omit is stored as an empty string and scored as a missing signal, except `company`, which falls back to the email domain.

## Example AI response (webhook output)

```json
{
  "ok": true,
  "lead": {
    "name": "Olena Kovalenko",
    "email": "olena.kovalenko@brightforge.io",
    "company": "BrightForge",
    "budget": "$15000",
    "timeline": "This month, before 1 September"
  },
  "qualification": {
    "score": 10,
    "category": "HOT",
    "bant": {
      "budget": {
        "score": 3,
        "comment": "Explicit $15k budget for an automation build."
      },
      "authority": {
        "score": 2,
        "comment": "Writes from a company domain with a complete professional identity."
      },
      "need": {
        "score": 3,
        "comment": "Concrete pain: 200 inbound demos/month and a clearly scoped n8n + Gemini qualifier."
      },
      "timeline": {
        "score": 2,
        "comment": "Hard deadline this month before the ads campaign (1 September)."
      }
    },
    "reasoning": "All four BANT pillars are present: funded budget, business email, a specific operational problem, and a dated go-live. This is a sales-ready inbound opportunity, not research or spam.",
    "recommended_action": "Call today, confirm decision-maker and stack, and send a scoped kickoff proposal this week.",
    "red_flags": [],
    "qualified_at": "2026-08-14T14:32:00.000Z"
  }
}
```

Gemini phrases its comments differently on every run; the field names and the `score` / `category` ranges stay stable thanks to the Structured Output Parser.

## BANT scale used in this project

| Category | Score | Workflow action |
|----------|-------|-----------------|
| **HOT** | 8–10 | Telegram alert plus an email to the sales team |
| **WARM** | 5–7 | Same alert, framed around a discovery call |
| **COLD** | 3–4 | Polite decline sent to the lead |
| **SPAM** | 1–2 | Same decline; no sales time is booked |

The detailed rubric (Budget 0–3, Authority 0–2, Need 0–3, Timeline 0–2) lives in [`prompts/system_prompt.md`](prompts/system_prompt.md).

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `404 ... webhook is not registered` | The test URL is armed for a single call. Click **Execute workflow**, then send. Or activate the workflow and use the production URL. |
| HTTP 200 with an empty body, returned in under two seconds | Either the **Webhook** node's **Respond** option is set to `Immediately`, or you started the run with **Listen for test event**, which executes the trigger only. Use `Using 'Respond to Webhook' Node` and **Execute workflow**. |
| HTTP 200 with an empty body after the AI has clearly run | The execution never reached **Respond to Webhook**. Two common causes: a failing node in the routed branch (usually email with missing SMTP — press `D` to deactivate it), or a **Merge** node placed before the response. A Switch only fires one branch, so a Merge waiting on a second input never runs. Wire every branch straight into **Respond to Webhook**. |
| Response is `{"ok":true,"lead":{},"qualification":{}}` | Something between the Switch and the response replaced the item — Telegram returns its API reply, the email node returns the SMTP result. Reference the source node explicitly (`$('Normalize Result').first().json.score`) instead of `$json.score` in **Respond to Webhook**. |
| Telegram arrives but the response is empty | Expected when SMTP is not configured: Telegram runs before `Email Sales Team`, which then fails and stops the chain. |
| `category` is always `COLD` | The model returned unparseable output, so `Normalize Result` fell back to the default. Check the **BANT Qualifier** output and keep the Structured Output Parser attached. |
| Airtable node fails with `NOT_FOUND` | `AIRTABLE_BASE_ID` or `AIRTABLE_TABLE_NAME` is unset in **Settings → Variables**, so the expression resolves to an empty string. The token also has to be granted access to that specific base. |
| Airtable node fails with `UNKNOWN_FIELD_NAME` | A column name in the table does not match the mapping exactly — the names are case and space sensitive, for example `BANT Score`, not `Bant score`. |
| Airtable row appears with an empty `Category` or `Created At` | The single select has no matching option, or the date field is text. Keep **typecast** enabled on the node and set `Created At` to a date field that includes time. |
| Alerts work but no Airtable row appears | Expected when the write fails: the node runs with `continueRegularOutput` so it cannot block notifications. Open the run in **Executions** and read the node's error. |

## Customization

- Change the HOT/WARM thresholds in the prompt, not in the Switch — the Switch only reads `category`.
- To stop emailing spam, delete the connection from the `SPAM` output to **Email Polite Rejection**.
- Swap SMTP for the **Gmail** node using the same `to` / `html` values.
- Swap Airtable for **Google Sheets**, **HubSpot** or **Postgres** by replacing that one node — it hangs off **Normalize Result**, so nothing else in the graph depends on it.
- To keep junk out of the CRM, move the Airtable node's input from **Normalize Result** to the `HOT` and `WARM` outputs of the Switch.
- The decline copy lives in the **Email Polite Rejection** node — translate it for your market.

## License

Use this template freely in your own automations. Never commit API keys, SMTP credentials, or Telegram tokens.
