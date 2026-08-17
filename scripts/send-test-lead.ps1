<#
.SYNOPSIS
    Sends a test lead to the n8n AI Lead Qualifier webhook and verifies the full chain.

.DESCRIPTION
    Walks the whole path the workflow is supposed to take:

        Webhook -> Gemini BANT analysis -> Airtable record -> Telegram alert / email reply

    The webhook and the AI verdict are checked from the HTTP response. The Airtable
    record is checked over the Airtable REST API when a token, base and table are
    available; otherwise that step is reported as skipped instead of failing.
    Telegram and email cannot be verified from here, so the script prints exactly
    what should have arrived for the category the lead was given.

.EXAMPLE
    $env:N8N_BASE_URL = 'https://your-instance.app.n8n.cloud'
    .\scripts\send-test-lead.ps1
    Sends the HOT preset to the test webhook.

.EXAMPLE
    $env:AIRTABLE_PAT = 'patXXXXXXXXXXXXXX'
    $env:AIRTABLE_BASE_ID = 'appXXXXXXXXXXXXXX'
    $env:AIRTABLE_TABLE_NAME = 'Leads'
    .\scripts\send-test-lead.ps1 -Preset hot -Production
    Full end-to-end run, including a lookup of the record that was just created.

.EXAMPLE
    .\scripts\send-test-lead.ps1 -Preset spam -BaseUrl https://your-instance.app.n8n.cloud
    Sends a junk lead to check the polite-rejection branch.

.EXAMPLE
    .\scripts\send-test-lead.ps1 -Wait
    Retries every 5s for 2 minutes, so you can click "Execute workflow" after starting it.
#>
[CmdletBinding()]
param(
    [ValidateSet('hot', 'warm', 'cold', 'spam')]
    [string]$Preset = 'hot',

    # Your n8n host. Set $env:N8N_BASE_URL once instead of passing it every time.
    [string]$BaseUrl = $(if ($env:N8N_BASE_URL) { $env:N8N_BASE_URL } else { 'https://YOUR-N8N-HOST' }),

    [string]$Path = 'lead-qualifier',

    # Use the production webhook (requires the workflow toggle to be Active).
    [switch]$Production,

    # Keep retrying while the test webhook is not armed yet.
    [switch]$Wait,

    [string]$AirtablePat = $env:AIRTABLE_PAT,

    [string]$AirtableBaseId = $env:AIRTABLE_BASE_ID,

    [string]$AirtableTable = $env:AIRTABLE_TABLE_NAME,

    [switch]$SkipAirtableCheck
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($BaseUrl -like '*YOUR-N8N-HOST*') {
    throw 'Point the script at your instance: pass -BaseUrl https://your-instance.app.n8n.cloud, or set $env:N8N_BASE_URL.'
}

function Write-Step {
    param(
        [string]$Name,
        [ValidateSet('ok', 'fail', 'skip', 'info')]
        [string]$State,
        [string]$Detail
    )

    $marker, $color = switch ($State) {
        'ok'   { '[ ok ]', 'Green' }
        'fail' { '[fail]', 'Red' }
        'skip' { '[skip]', 'DarkGray' }
        'info' { '[ .. ]', 'Cyan' }
    }

    Write-Host ("{0} {1,-22} {2}" -f $marker, $Name, $Detail) -ForegroundColor $color
}

$payloads = @{
    hot  = [ordered]@{
        name                = 'Marta Ivanenko, Co-Founder at BrightForge Analytics'
        email               = 'marta.ivanenko@brightforge-analytics.com'
        company             = 'BrightForge Analytics'
        budget              = '$18,000 approved for this quarter'
        project_description = 'B2B SaaS, 40 people. Our site form brings ~250 demo requests per month and two SDRs cannot keep up, so good leads wait 48h. We need n8n + Gemini to score BANT, push HOT leads to our sales Telegram instantly, and auto-decline junk. I am the decision maker and can sign this week.'
        timeline            = 'Kickoff next Monday, live before the ads campaign on 1 September'
    }
    warm = [ordered]@{
        name                = 'Dmytro Serhiienko'
        email               = 'd.serhiienko@nordwave-logistics.com'
        company             = 'Nordwave Logistics'
        budget              = 'Not fixed yet, probably a couple of thousand dollars'
        project_description = 'We want to automate how sales handles incoming requests. Not sure yet what exactly we need, but the manual work is getting heavy.'
        timeline            = 'Sometime this quarter'
    }
    cold = [ordered]@{
        name                = 'Ihor'
        email               = 'ihor.student@gmail.com'
        company             = ''
        budget              = 'Looking for the cheapest option'
        project_description = 'Curious how AI automation works, maybe for a future idea.'
        timeline            = 'No rush'
    }
    spam = [ordered]@{
        name                = 'seo growth partner'
        email               = 'promo@mailinator.com'
        company             = ''
        budget              = 'free'
        project_description = 'Hi, I can rank your website #1 on Google and place guest posts on 500 crypto blogs. Interested in a partnership?'
        timeline            = ''
    }
}

$lead = $payloads[$Preset]
$segment = if ($Production) { 'webhook' } else { 'webhook-test' }
$url = "$($BaseUrl.TrimEnd('/'))/$segment/$Path"
$body = $lead | ConvertTo-Json -Depth 5
$sentAt = (Get-Date).ToUniversalTime()

Write-Host "POST $url" -ForegroundColor Cyan
Write-Host "Preset: $Preset" -ForegroundColor Cyan
Write-Host $body
Write-Host ""

$attempts = if ($Wait) { 24 } else { 1 }
$response = $null

for ($i = 1; $i -le $attempts; $i++) {
    try {
        $response = Invoke-WebRequest -Uri $url -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing -TimeoutSec 180
        break
    }
    catch {
        $code = $_.Exception.Response.StatusCode.value__

        if ($code -eq 404 -and -not $Production) {
            if ($i -lt $attempts) {
                Write-Host "attempt $i - test webhook not armed, click 'Execute workflow' in n8n..." -ForegroundColor DarkGray
                Start-Sleep -Seconds 5
                continue
            }

            Write-Step 'Webhook' 'fail' '404 - the test webhook is not registered'
            Write-Host "Test URLs work for exactly one call after you click 'Execute workflow' on the canvas." -ForegroundColor Red
            Write-Host 'Tip: rerun with -Wait, then click the button.' -ForegroundColor Red
            return
        }

        Write-Step 'Webhook' 'fail' "HTTP $code"
        if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message }
        else { Write-Host $_.Exception.Message }
        return
    }
}

Write-Host "=== chain check ===" -ForegroundColor White
Write-Step 'Webhook' 'ok' "HTTP $($response.StatusCode) in $([int]((Get-Date).ToUniversalTime() - $sentAt).TotalSeconds)s"

$parsed = $null
if ([string]::IsNullOrWhiteSpace($response.Content)) {
    Write-Step 'Gemini analysis' 'fail' 'empty response body'
    Write-Host "The run never reached 'Respond to Webhook'. Open Executions in n8n: a node in the routed branch failed," -ForegroundColor Yellow
    Write-Host 'or the node still reads $json instead of $(''Normalize Result'').first().json.' -ForegroundColor Yellow
}
else {
    try { $parsed = $response.Content | ConvertFrom-Json } catch { }

    if ($null -eq $parsed -or $null -eq $parsed.qualification.category) {
        Write-Step 'Gemini analysis' 'fail' 'response is not the expected qualification JSON'
        Write-Host $response.Content
    }
    else {
        $q = $parsed.qualification
        Write-Step 'Gemini analysis' 'ok' "$($q.category) $($q.score)/10"
        Write-Step 'Company captured' $(if ($parsed.lead.company) { 'ok' } else { 'skip' }) "$($parsed.lead.company)"
    }
}

$category = if ($parsed) { $parsed.qualification.category } else { $null }

if ($SkipAirtableCheck) {
    Write-Step 'Airtable record' 'skip' 'disabled with -SkipAirtableCheck'
}
elseif (-not $AirtablePat -or -not $AirtableBaseId -or -not $AirtableTable) {
    Write-Step 'Airtable record' 'skip' 'set AIRTABLE_PAT, AIRTABLE_BASE_ID and AIRTABLE_TABLE_NAME to verify'
}
else {
    $filter = "{Email}='$($lead.email)'"
    $query = 'pageSize=10&filterByFormula=' + [uri]::EscapeDataString($filter)
    $listUrl = "https://api.airtable.com/v0/$AirtableBaseId/$([uri]::EscapeDataString($AirtableTable))?$query"
    $headers = @{ Authorization = "Bearer $AirtablePat" }
    $record = $null

    # The Airtable branch runs alongside the reply, so the record can land a moment later.
    for ($i = 1; $i -le 4; $i++) {
        try {
            $result = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get -TimeoutSec 30
            $record = $result.records |
                Where-Object {
                    $created = $null
                    [datetime]::TryParse($_.fields.'Created At', [ref]$created) -and
                    $created.ToUniversalTime() -ge $sentAt.AddMinutes(-2)
                } |
                Select-Object -First 1

            if ($record) { break }
            Start-Sleep -Seconds 3
        }
        catch {
            $code = $_.Exception.Response.StatusCode.value__
            Write-Step 'Airtable record' 'fail' "Airtable API returned HTTP $code"
            if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message }
            $record = 'error'
            break
        }
    }

    if ($record -eq 'error') { }
    elseif ($null -eq $record) {
        Write-Step 'Airtable record' 'fail' "no record for $($lead.email) created in the last 2 minutes"
        Write-Host "Open the 'Save Lead to Airtable' node in Executions. Common causes: the PAT lacks data.records:write," -ForegroundColor Yellow
        Write-Host 'AIRTABLE_BASE_ID / AIRTABLE_TABLE_NAME are unset in n8n, or a column name does not match the table.' -ForegroundColor Yellow
    }
    else {
        Write-Step 'Airtable record' 'ok' "$($record.id) - $($record.fields.'Lead Name')"

        $expected = @('Lead Name', 'Email', 'Company', 'Budget', 'Authority', 'Need', 'Timeline', 'BANT Score', 'Category', 'AI Summary', 'Created At')
        $missing = $expected | Where-Object { -not $record.fields.PSObject.Properties.Name.Contains($_) }

        if ($missing) { Write-Step 'Airtable columns' 'fail' "empty or missing: $($missing -join ', ')" }
        else { Write-Step 'Airtable columns' 'ok' 'all 11 fields written' }

        if ($category -and $record.fields.Category -ne $category) {
            Write-Step 'Airtable category' 'fail' "record says $($record.fields.Category), response says $category"
        }
    }
}

switch ($category) {
    { $_ -in 'HOT', 'WARM' } {
        Write-Step 'Telegram alert' 'info' "expect a $_ message in the sales chat"
        Write-Step 'Email to sales' 'info' 'expect a lead summary at SALES_EMAIL'
    }
    { $_ -in 'COLD', 'SPAM' } {
        Write-Step 'Polite rejection' 'info' "expect a decline sent to $($lead.email)"
    }
    default {
        Write-Step 'Notifications' 'skip' 'unknown category, nothing to expect'
    }
}

if ($parsed) {
    Write-Host ""
    Write-Host '=== response ===' -ForegroundColor White
    $parsed | ConvertTo-Json -Depth 10
}
