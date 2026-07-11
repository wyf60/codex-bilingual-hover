param(
    [switch]$AllApps
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System.Runtime.InteropServices;
public static class CodexHoverDpi {
    [DllImport("user32.dll")]
    public static extern uint GetDpiForSystem();
}
"@

$dpiScale = [Math]::Max(1.0, [CodexHoverDpi]::GetDpiForSystem() / 96.0)

function Convert-Utf8([string]$Base64) {
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Base64))
}

$translations = @{
    "Computer Use" = (Convert-Utf8 "55S16ISR5o6n5Yi2")
    "Control Mac apps from ChatGPT" = (Convert-Utf8 "6YCa6L+HIENoYXRHUFQg5o6n5Yi2IE1hYyDlupTnlKg=")
    "Chrome" = (Convert-Utf8 "Q2hyb21lIOa1j+iniOWZqA==")
    "Control Chrome with ChatGPT" = (Convert-Utf8 "6YCa6L+HIENoYXRHUFQg5o6n5Yi2IENocm9tZQ==")
    "Spreadsheets" = (Convert-Utf8 "55S15a2Q6KGo5qC8")
    "Create and edit spreadsheet files" = (Convert-Utf8 "5Yib5bu65ZKM57yW6L6R55S15a2Q6KGo5qC85paH5Lu2")
    "Presentations" = (Convert-Utf8 "5ryU56S65paH56i/")
    "Create and edit presentations" = (Convert-Utf8 "5Yib5bu65ZKM57yW6L6R5ryU56S65paH56i/")
    "Data Analytics" = (Convert-Utf8 "5pWw5o2u5YiG5p6Q")
    "GitHub" = (Convert-Utf8 "R2l0SHViIOS7o+eggeWNj+S9nA==")
    "Triage PRs, issues, CI, and publish code" = (Convert-Utf8 "5YiG57G75aSE55CG5ouJ5Y+W6K+35rGC44CB6Zeu6aKY5ZKM5oyB57ut6ZuG5oiQ77yM5bm25Y+R5biD5Luj56CB")
    "Notion" = (Convert-Utf8 "Tm90aW9uIOefpeivhueuoeeQhg==")
    "Google Calendar" = (Convert-Utf8 "R29vZ2xlIOaXpeWOhg==")
    "Manage Google Calendar events" = (Convert-Utf8 "566h55CGIEdvb2dsZSDml6Xljobkuovku7Y=")
    "Productivity" = (Convert-Utf8 "55Sf5Lqn5Yqb")
    "Featured" = (Convert-Utf8 "57K+6YCJ")
    "Mac Computer Use lets ChatGPT use any app on your computer, including your web browsers and files you allow it to access. It may take screenshots or page content while working. You stay in control: you choose which apps to allow ChatGPT to access, you can stop actions at any time, and control whether we use screenshots for training." = (Convert-Utf8 "TWFjIOeJiCBDb21wdXRlciBVc2Ug5Y+v6K6pIENoYXRHUFQg5L2/55So5oKo55S16ISR5LiK55qE5Lu75L2V5bqU55So77yM5YyF5ous5oKo5YWB6K645YW26K6/6Zeu55qE572R6aG15rWP6KeI5Zmo5ZKM5paH5Lu244CC5bel5L2c5pyf6Ze077yM5a6D5Y+v6IO95Lya5oiq5Y+W5bGP5bmV5oiq5Zu+5oiW6K+75Y+W6aG16Z2i5YaF5a6544CC5o6n5Yi25p2D5aeL57uI5Zyo5oKo5omL5Lit77ya5oKo5Y+v5Lul6YCJ5oup5YWB6K64IENoYXRHUFQg6K6/6Zeu5ZOq5Lqb5bqU55So77yM6ZqP5pe25YGc5q2i5pON5L2c77yM5bm25o6n5Yi25oiR5Lus5piv5ZCm5L2/55So5oiq5Zu+6L+b6KGM6K6t57uD44CC")
}

function Normalize-EnglishText([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $text = [regex]::Replace($Value, "\s+", " ").Trim()
    if ($text.Length -lt 2 -or $text.Length -gt 1200) { return $null }
    if ($text -notmatch "[A-Za-z]") { return $null }
    if (@("codex", "chatgpt", "openai") -contains $text.ToLowerInvariant()) { return $null }
    return $text
}

function Test-SuppressedControl([System.Windows.Automation.AutomationElement]$Element) {
    $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
    $current = $Element
    for ($i = 0; $i -lt 8 -and $null -ne $current; $i++) {
        try { $controlType = $current.Current.ControlType } catch { return $true }
        if ($controlType -eq [System.Windows.Automation.ControlType]::Menu -or
            $controlType -eq [System.Windows.Automation.ControlType]::MenuBar -or
            $controlType -eq [System.Windows.Automation.ControlType]::MenuItem) {
            return $true
        }
        try { $current = $walker.GetParent($current) } catch { break }
    }
    return $false
}

function Test-PlausiblePluginTitle([string]$Value) {
    $text = Normalize-EnglishText $Value
    if ($null -eq $text -or $text.Length -gt 80) { return $false }
    if (($text -split "\s+").Count -gt 12) { return $false }

    # These are stable host labels, not plugin names. Never enumerate the plugin
    # catalog here: it changes continuously and may contain thousands of titles.
    $hostLabels = @(
        "chatgpt", "codex", "plugins", "skills", "plugin", "skill",
        "install", "install plugin", "try now", "add plugin", "back",
        "more", "settings", "create", "finder", "task actions",
        "new chat", "recent chats"
    )
    return $hostLabels -notcontains $text.ToLowerInvariant()
}

function Test-CodexProcess([int]$ProcessId) {
    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        return $process.ProcessName -match "^(ChatGPT|Codex)(\.|$)" -or
            $process.Path -match "\\(ChatGPT|Codex)(\\|\.exe)"
    } catch {
        return $false
    }
}

function Get-CandidateTarget(
    [System.Windows.Automation.AutomationElement]$Element,
    [System.Windows.Point]$Point
) {
    if (Test-SuppressedControl $Element) { return $null }
    try {
        $directName = [string]$Element.Current.Name
        $directType = $Element.Current.ControlType
        $interactiveTypes = @(
            [System.Windows.Automation.ControlType]::Button,
            [System.Windows.Automation.ControlType]::CheckBox,
            [System.Windows.Automation.ControlType]::RadioButton,
            [System.Windows.Automation.ControlType]::Tab,
            [System.Windows.Automation.ControlType]::TabItem,
            [System.Windows.Automation.ControlType]::ToolBar
        )
        if ($interactiveTypes -contains $directType -and $directName -match "[\u4e00-\u9fff]" -and
            $null -eq (Normalize-EnglishText $directName)) {
            return $null
        }
    } catch {}
    $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
    $roots = New-Object System.Collections.Generic.List[System.Windows.Automation.AutomationElement]
    $current = $Element
    for ($i = 0; $i -lt 6 -and $null -ne $current; $i++) {
        $roots.Add($current)
        $current = $walker.GetParent($current)
    }

    $matches = New-Object System.Collections.Generic.List[object]
    foreach ($root in $roots) {
        $stack = New-Object System.Collections.Stack
        $stack.Push([pscustomobject]@{
            Node = $root
            Depth = 0
            Frames = @()
        })
        $visited = 0
        while ($stack.Count -gt 0 -and $visited -lt 3500) {
            $entry = $stack.Pop()
            $node = [System.Windows.Automation.AutomationElement]$entry.Node
            $depth = [int]$entry.Depth
            $visited++

            try { $rect = $node.Current.BoundingRectangle } catch { continue }
            if (-not $rect.IsEmpty -and -not $rect.Contains($Point)) { continue }

            $frames = @($entry.Frames)
            if (-not $rect.IsEmpty) { $frames += $rect }

            $values = @()
            try { $values += $node.Current.Name } catch {}
            try { $values += $node.Current.HelpText } catch {}
            try {
                $valuePattern = $null
                if ($node.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$valuePattern)) {
                    $values += ([System.Windows.Automation.ValuePattern]$valuePattern).Current.Value
                }
            } catch {}

            $area = if ($rect.IsEmpty) { [double]::MaxValue } else { [Math]::Max(1, $rect.Width * $rect.Height) }
            $hoverRect = $null
            if (-not $rect.IsEmpty) {
                $rowFrames = @($frames | Where-Object {
                    $_.Width -ge [Math]::Max(80, $rect.Width) -and
                    $_.Height -ge [Math]::Max(32, $rect.Height) -and
                    $_.Width -le 760 -and
                    $_.Height -le 170
                } | Sort-Object @{ Expression = { $_.Width * $_.Height }; Descending = $true })
                if ($rowFrames.Count -gt 0) {
                    $hoverRect = $rowFrames[0]
                } else {
                    $hoverRect = [System.Windows.Rect]::new(
                        $rect.X - 14,
                        $rect.Y - 10,
                        $rect.Width + 28,
                        $rect.Height + 20
                    )
                }
            }
            foreach ($value in $values) {
                $text = Normalize-EnglishText ([string]$value)
                if ($null -ne $text -and $null -ne $hoverRect) {
                    $matches.Add([pscustomobject]@{
                        Text = $text
                        Area = $area
                        Rect = $rect
                        HoverRect = $hoverRect
                    })
                }
            }

            if ($depth -ge 24) { continue }
            try {
                $child = $walker.GetFirstChild($node)
                while ($null -ne $child) {
                    $stack.Push([pscustomobject]@{
                        Node = $child
                        Depth = $depth + 1
                        Frames = @($frames)
                    })
                    $child = $walker.GetNextSibling($child)
                }
            } catch {}
        }
    }

    return $matches |
        Sort-Object Area,
            @{ Expression = { $_.Text.Length } },
            @{ Expression = { $_.HoverRect.Width * $_.HoverRect.Height }; Descending = $true } |
        Select-Object -First 1
}

function Test-PluginSurfaceVisible([int]$ProcessId) {
    try {
        $condition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
            $ProcessId
        )
        $root = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst(
            [System.Windows.Automation.TreeScope]::Children,
            $condition
        )
        if ($null -eq $root) { return $false }
        try { $rootRect = $root.Current.BoundingRectangle } catch { $rootRect = [System.Windows.Rect]::Empty }

        $searchPluginsZh = Convert-Utf8 "5pCc57Si5o+S5Lu2"
        $browsePluginsZh = Convert-Utf8 "5rWP6KeI5o+S5Lu25oiW5oqA6IO9"
        $pluginsZh = Convert-Utf8 "5o+S5Lu2"
        $tryNowZh = Convert-Utf8 "56uL5Y2z6K+V55So"
        $installZh = Convert-Utf8 "5a6J6KOF"
        $installPluginZh = Convert-Utf8 "5a6J6KOF5o+S5Lu2"
        $taskActionsZh = Convert-Utf8 "5Lu75Yqh5pON5L2c"
        $newChatZh = Convert-Utf8 "5paw6IGK5aSp"
        $recentChatsZh = Convert-Utf8 "5pyA6L+R6IGK5aSp"
        $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
        $stack = New-Object System.Collections.Stack
        $stack.Push(@($root, 0))
        $visited = 0
        $hasDirectoryMarker = $false
        $hasDetailAction = $false
        $hasBlockedMarker = $false
        $hasCombinedBreadcrumb = $false
        $breadcrumbMarkers = New-Object System.Collections.Generic.List[object]
        $breadcrumbTitles = New-Object System.Collections.Generic.List[object]
        while ($stack.Count -gt 0 -and $visited -lt 6000) {
            $entry = $stack.Pop()
            $node = [System.Windows.Automation.AutomationElement]$entry[0]
            $depth = [int]$entry[1]
            $visited++

            $values = @()
            try { $rect = $node.Current.BoundingRectangle } catch { $rect = [System.Windows.Rect]::Empty }
            $localX = if ($rootRect.IsEmpty -or $rect.IsEmpty) { $rect.X } else { $rect.X - $rootRect.X }
            $localY = if ($rootRect.IsEmpty -or $rect.IsEmpty) { $rect.Y } else { $rect.Y - $rootRect.Y }
            try { $values += $node.Current.Name } catch {}
            try { $values += $node.Current.HelpText } catch {}
            foreach ($value in $values) {
                $valueText = [string]$value
                $canonicalValue = ([regex]::Replace($valueText.Trim(), "^[^\p{L}\p{N}]+", "")).Trim()
                $isDirectoryMarker = [string]$value -like "*Search plugins*" -or
                    [string]$value -like "*Browse plugins or skills*" -or
                    [string]$value -like "*$searchPluginsZh*" -or
                    [string]$value -like "*$browsePluginsZh*"
                $topActionThreshold = if ($rootRect.IsEmpty) {
                    600 * $dpiScale
                } else {
                    [Math]::Max(320 * $dpiScale, $rootRect.Width * 0.55)
                }
                $isTopAction = -not $rect.IsEmpty -and
                    $localY -ge 0 -and $localY -lt (380 * $dpiScale) -and
                    ($localX + ($rect.Width / 2)) -gt $topActionThreshold
                $isDetailAction = $isTopAction -and (
                    $canonicalValue -in @("Try now", "Install", "Install plugin", $tryNowZh, $installZh, $installPluginZh)
                )
                if ($isDirectoryMarker) { $hasDirectoryMarker = $true }
                if ($isDetailAction) { $hasDetailAction = $true }
                if ($valueText -like "*Task actions*" -or
                    $valueText -like "*New chat*" -or
                    $valueText -like "*Recent chats*" -or
                    $valueText -like "*$taskActionsZh*" -or
                    $valueText -like "*$newChatZh*" -or
                    $valueText -like "*$recentChatsZh*") {
                    $hasBlockedMarker = $true
                }
                if (-not $rect.IsEmpty -and $localY -ge 0 -and $localY -lt (160 * $dpiScale) -and
                    $rect.Height -gt 0 -and $rect.Height -le (64 * $dpiScale)) {
                    if ($canonicalValue -ieq "Plugins" -or $canonicalValue -eq $pluginsZh) {
                        $breadcrumbMarkers.Add($rect)
                    } elseif (Test-PlausiblePluginTitle $canonicalValue) {
                        $breadcrumbTitles.Add([pscustomobject]@{ Text = $canonicalValue; Rect = $rect })
                    }
                    if ($canonicalValue -like "Plugins *" -and
                        (Test-PlausiblePluginTitle $canonicalValue.Substring(8))) {
                        $hasCombinedBreadcrumb = $true
                    }
                    if ($canonicalValue -like "$pluginsZh *" -and
                        (Test-PlausiblePluginTitle $canonicalValue.Substring($pluginsZh.Length + 1))) {
                        $hasCombinedBreadcrumb = $true
                    }
                }
            }

            if ($depth -ge 18) { continue }
            try {
                $child = $walker.GetFirstChild($node)
                while ($null -ne $child) {
                    $stack.Push(@($child, $depth + 1))
                    $child = $walker.GetNextSibling($child)
                }
            } catch {}
        }
        if ($hasBlockedMarker) { return $false }
        if ($hasDirectoryMarker -or $hasDetailAction -or $hasCombinedBreadcrumb) { return $true }
        foreach ($marker in $breadcrumbMarkers) {
            foreach ($title in $breadcrumbTitles) {
                $titleRect = [System.Windows.Rect]$title.Rect
                if ([Math]::Abs(($marker.Y + ($marker.Height / 2)) - ($titleRect.Y + ($titleRect.Height / 2))) -le (18 * $dpiScale) -and
                    $titleRect.X -gt $marker.Right -and
                    ($titleRect.X - $marker.Right) -le (600 * $dpiScale)) {
                    return $true
                }
            }
        }
        return $false
    } catch {}
    return $false
}

$window = New-Object System.Windows.Window
$window.Title = "Codex Hover Translator"
$window.Width = 430
$window.Height = 64
$window.WindowStyle = [System.Windows.WindowStyle]::None
$window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.Topmost = $true
$window.ShowInTaskbar = $false
$window.ShowActivated = $false
$window.IsHitTestVisible = $false

$border = New-Object System.Windows.Controls.Border
$border.CornerRadius = [System.Windows.CornerRadius]::new(13)
$border.Padding = [System.Windows.Thickness]::new(14, 11, 14, 11)
$border.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(242, 32, 32, 36))
$border.BorderBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(70, 255, 255, 255))
$border.BorderThickness = [System.Windows.Thickness]::new(1)

$stackPanel = New-Object System.Windows.Controls.StackPanel
$translatedBlock = New-Object System.Windows.Controls.TextBlock
$translatedBlock.FontFamily = [System.Windows.Media.FontFamily]::new("Microsoft YaHei UI")
$translatedBlock.FontSize = 15
$translatedBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
$translatedBlock.Foreground = [System.Windows.Media.Brushes]::White
$translatedBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
$translatedBlock.MaxHeight = 132
$sourceBlock = New-Object System.Windows.Controls.TextBlock
$sourceBlock.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
$sourceBlock.FontSize = 11
$sourceBlock.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(185, 185, 192))
$sourceBlock.Margin = [System.Windows.Thickness]::new(0, 7, 0, 0)
$sourceBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
$sourceBlock.MaxHeight = 42
$stackPanel.Children.Add($translatedBlock) | Out-Null
$stackPanel.Children.Add($sourceBlock) | Out-Null
$border.Child = $stackPanel
$window.Content = $border

function Update-TooltipHeight {
    $available = [System.Windows.Size]::new($window.Width, [double]::PositiveInfinity)
    $border.Measure($available)
    $window.Height = [Math]::Min(200, [Math]::Max(58, [Math]::Ceiling($border.DesiredSize.Height)))
    $window.UpdateLayout()
}

$script:candidateText = ""
$script:candidateRect = $null
$script:activeText = ""
$script:activeRect = $null
$script:candidateSince = [DateTime]::MinValue
$script:pluginSurfaceVisible = $false
$script:nextPluginSurfaceCheck = [DateTime]::MinValue

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(50)
$timer.Add_Tick({
    $cursor = [System.Windows.Forms.Cursor]::Position
    $point = [System.Windows.Point]::new($cursor.X, $cursor.Y)
    try { $element = [System.Windows.Automation.AutomationElement]::FromPoint($point) } catch { $element = $null }
    if ($null -eq $element) {
        $window.Hide()
        $script:candidateText = ""
        $script:candidateRect = $null
        $script:activeText = ""
        $script:activeRect = $null
        return
    }

    if (Test-SuppressedControl $element) {
        $window.Hide()
        $script:candidateText = ""
        $script:candidateRect = $null
        $script:activeText = ""
        $script:activeRect = $null
        return
    }

    try { $processId = $element.Current.ProcessId } catch { $processId = 0 }
    if (-not $AllApps) {
        if (-not (Test-CodexProcess $processId)) {
            $window.Hide()
            $script:candidateText = ""
            $script:candidateRect = $null
            $script:activeText = ""
            $script:activeRect = $null
            return
        }

        if ([DateTime]::UtcNow -ge $script:nextPluginSurfaceCheck) {
            $script:pluginSurfaceVisible = Test-PluginSurfaceVisible $processId
            $script:nextPluginSurfaceCheck = [DateTime]::UtcNow.AddMilliseconds(400)
        }
        if (-not $script:pluginSurfaceVisible) {
            $window.Hide()
            $script:candidateText = ""
            $script:candidateRect = $null
            $script:activeText = ""
            $script:activeRect = $null
            return
        }
    }

    if ($null -ne $script:activeRect -and $script:activeRect.Contains($point)) {
        return
    }

    if ($null -ne $script:activeRect) {
        $window.Hide()
        $script:activeText = ""
        $script:activeRect = $null
    }

    $target = Get-CandidateTarget $element $point
    if ($null -eq $target -or [string]::IsNullOrWhiteSpace($target.Text)) {
        $window.Hide()
        $script:candidateText = ""
        $script:candidateRect = $null
        return
    }

    $text = [string]$target.Text
    $region = [System.Windows.Rect]$target.HoverRect
    if ($text -ne $script:candidateText -or $null -eq $script:candidateRect -or -not $script:candidateRect.Equals($region)) {
        $script:candidateText = $text
        $script:candidateRect = $region
        $script:candidateSince = [DateTime]::UtcNow
        return
    }

    if (([DateTime]::UtcNow - $script:candidateSince).TotalMilliseconds -lt 200) { return }
    if ($text -ne $script:activeText) {
        $script:activeText = $text
        $script:activeRect = $region
        $sourceBlock.Text = if ($text.Length -gt 260) { $text.Substring(0, 257) + "..." } else { $text }
        if ($translations.ContainsKey($text)) {
            $translatedBlock.Text = $translations[$text]
        } else {
            $translatedBlock.Text = Convert-Utf8 "5pyq5pS25b2V56a757q/57+76K+R"
        }
        Update-TooltipHeight
    }

    $cursorDipX = $cursor.X / $dpiScale
    $cursorDipY = $cursor.Y / $dpiScale
    $left = $cursorDipX + 18
    $top = $cursorDipY + 18
    $workArea = [System.Windows.SystemParameters]::WorkArea
    if ($left + $window.Width -gt $workArea.Right) { $left = $cursorDipX - $window.Width - 18 }
    if ($top + $window.Height -gt $workArea.Bottom) { $top = $cursorDipY - $window.Height - 18 }
    $window.Left = [Math]::Max($workArea.Left + 8, $left)
    $window.Top = [Math]::Max($workArea.Top + 8, $top)
    if (-not $window.IsVisible) { $window.Show() }
})

$timer.Start()
$window.Hide()
[System.Windows.Threading.Dispatcher]::Run()
