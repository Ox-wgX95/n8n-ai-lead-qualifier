<#
.SYNOPSIS
    Sends a test lead to the n8n AI Lead Qualifier webhook.

.EXAMPLE
    $env:N8N_BASE_URL = 'https://your-instance.app.n8n.cloud'
    .\scripts\send-test-lead.ps1
    Sends the HOT preset to the test webhook.

.EXAMPLE
    .\scripts\send-test-lead.ps1 -Preset spam -BaseUrl https://your-instance.app.n8n.cloud
    Sends a junk lead to check the polite-rejection branch.

.EXAMPLE
    .\scripts\send-test-lead.ps1 -Preset hot -Production
    Hits /webhook/ instead of /webhook-test/ (workflow must be Active).

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
    [switch]$Wait
)

$ErrorActionPreference = 'Stop'

if ($BaseUrl -like '*YOUR-N8N-HOST*') {
    throw 'Point the script at your instance: pass -BaseUrl https://your-instance.app.n8n.cloud, or set $env:N8N_BASE_URL.'
}

$payloads = @{
    hot  = [ordered]@{
        name                = 'Marta Ivanenko, Co-Founder at BrightForge Analytics'
        email               = 'marta.ivanenko@brightforge-analytics.com'
        budget              = '$18,000 approved for this quarter'
        project_description = 'B2B SaaS, 40 people. Our site form brings ~250 demo requests per month and two SDRs cannot keep up, so good leads wait 48h. We need n8n + Gemini to score BANT, push HOT leads to our sales Telegram instantly, and auto-decline junk. I am the decision maker and can sign this week.'
        timeline            = 'Kickoff next Monday, live before the ads campaign on 1 September'
    }
    warm = [ordered]@{
        name                = 'Dmytro Serhiienko'
        email               = 'd.serhiienko@nordwave-logistics.com'
        budget              = 'Not fixed yet, probably a couple of thousand dollars'
        project_description = 'We want to automate how sales handles incoming requests. Not sure yet what exactly we need, but the manual work is getting heavy.'
        timeline            = 'Sometime this quarter'
    }
    cold = [ordered]@{
        name                = 'Ihor'
        email               = 'ihor.student@gmail.com'
        budget              = 'Looking for the cheapest option'
        project_description = 'Curious how AI automation works, maybe for a future idea.'
        timeline            = 'No rush'
    }
    spam = [ordered]@{
        name                = 'seo growth partner'
        email               = 'promo@mailinator.com'
        budget              = 'free'
        project_description = 'Hi, I can rank your website #1 on Google and place guest posts on 500 crypto blogs. Interested in a partnership?'
        timeline            = ''
    }
}

$segment = if ($Production) { 'webhook' } else { 'webhook-test' }
$url = "$($BaseUrl.TrimEnd('/'))/$segment/$Path"
$body = $payloads[$Preset] | ConvertTo-Json -Depth 5

Write-Host "POST $url" -ForegroundColor Cyan
Write-Host "Preset: $Preset" -ForegroundColor Cyan
Write-Host $body

$attempts = if ($Wait) { 24 } else { 1 }

for ($i = 1; $i -le $attempts; $i++) {
    try {
        $response = Invoke-WebRequest -Uri $url -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing -TimeoutSec 180

        Write-Host ""
        Write-Host "STATUS $($response.StatusCode)" -ForegroundColor Green

        if ([string]::IsNullOrWhiteSpace($response.Content)) {
            Write-Host "Empty response body." -ForegroundColor Yellow
            Write-Host "The workflow started, but nothing reached the 'Respond to Webhook' node." -ForegroundColor Yellow
            Write-Host "Check Executions in n8n: a node in the routed branch (usually email/SMTP) probably failed." -ForegroundColor Yellow
        }
        else {
            try { $response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 10 }
            catch { $response.Content }
        }
        return
    }
    catch {
        $code = $_.Exception.Response.StatusCode.value__

        if ($code -eq 404 -and -not $Production) {
            if ($i -lt $attempts) {
                Write-Host "attempt $i - test webhook not armed, click 'Execute workflow' in n8n..." -ForegroundColor DarkGray
                Start-Sleep -Seconds 5
                continue
            }

            Write-Host ""
            Write-Host "404 - the test webhook is not registered." -ForegroundColor Red
            Write-Host "Test URLs work for exactly one call after you click 'Execute workflow' on the canvas." -ForegroundColor Red
            Write-Host "Tip: rerun with -Wait, then click the button." -ForegroundColor Red
            return
        }

        Write-Host ""
        Write-Host "FAILED with status $code" -ForegroundColor Red
        if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message }
        else { Write-Host $_.Exception.Message }
        return
    }
}
