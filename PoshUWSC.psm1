[System.Diagnostics.Process] $uwsc = $null
$ScriptPath = $MyInvocation.MyCommand.Path | Split-Path | Join-Path -ChildPath HTTPServer.uws
$port = 57913

<#
.SYNOPSIS
UWSCを起動する
.DESCRIPTION
UWSCを待ち受け状態にし、UWSCモジュールの関数群を利用できるようにする
.INPUTS
なし
.OUTPUTS
なし
.EXAMPLE
Start-Uwsc
#>
function Start-Uwsc
{
    [CmdletBinding()]
    param
    (
        # UWSCのHTTPサーバーが待ち受けに使うポートを指定
        [parameter(Mandatory=$false,Position=0)]
        [ValidateRange(1,[uint16]::MaxValue)]
        [uint16] $Port
    )
    if (! $(Test-Uwsc))
    {
        Write-Warning "UWSCのパスが設定されていません"
        return
    }
    if ($Port)
    {
        $script:port = $Port
    }
    $script:uwsc = Start-Process $UwscPath -ArgumentList $script:ScriptPath,$script:port -WindowStyle Hidden -PassThru
}

<#
.SYNOPSIS
UWSCを終了する
.DESCRIPTION
UWSCモジュールの各種関数
.INPUTS
なし
.OUTPUTS
なし
.EXAMPLE
Start-Uwsc
#>
function Stop-Uwsc
{
    [CmdletBinding()]
    param()
    send-command 'exit' | Out-Null
    $script:uwsc | Wait-Process
    return Get-UwscState
}

<#
.SYNOPSIS
UWSCのパスを指定する
.DESCRIPTION
UWSCのパスをグローバル変数 $UwscPath にセットします
.INPUTS
なし
.OUTPUTS
なし
.EXAMPLE
Set-UwscPath 'C:\Program Files (x86)\UWSC\UWSC.exe'
#>
function Set-UwscPath
{
    [CmdletBinding()]
    param
    (
        # uwsc.exeのパス
        [parameter(Mandatory,Position=0)]
        [string] $Path
    )
    Set-Variable -Name UwscPath -Value $Path -Scope global
}

function Test-Uwsc
{
    if (! $global:UwscPath)
    {
        return $false
    }
    return Test-Path $global:UwscPath -Include uwsc.exe
}

<#
.SYNOPSIS
UWSCの稼働状況を確認する
.DESCRIPTION
UWSCの稼働状況を確認する
.INPUTS
なし
.OUTPUTS
なし
.EXAMPLE
Get-UwscState
#>
function Get-UwscState
{
    [CmdletBinding()]
    param()
    $result = New-Object psobject -Property @{
        State = 'Not Started'
        StartTime = $null
        ExitTime  = $null
        ExitCode  = $null
        Pid       = $null
    }
    if ($script:uwsc)
    {
        $result.StartTime = $script:uwsc.StartTime
        $result.Pid       = $script:uwsc.Id
        if ($script:uwsc.ExitCode -eq $null)
        {
            $result.State = 'Running'
        }
        else
        {
            $result.State = 'Stopped'
            $result.ExitCode = $script:uwsc.ExitCode
            $result.ExitTime = $script:uwsc.ExitTime
        }
    }
    return $result | select State,Pid,StartTime,ExitTime,ExitCode
}

<#
.SYNOPSIS
UWSCの関数を実行する
.DESCRIPTION
UWSCの関数を実行する
.INPUTS
なし
.OUTPUTS
[string]
.EXAMPLE
Invoke-UwscFunction -Function clkitem -Arguments $Id,'OK'
#>
function Invoke-UwscFunction
{
    [CmdletBinding()]
    param
    (
        # 実行するUWSCの関数名
        [parameter(Mandatory,Position=0)]
        [string] $Function,
        # 関数に渡す引数
        [parameter(Mandatory=$false,Position=1)]
        [string[]] $Arguments
    )
    if ($(Get-UwscState).State -ne 'Running')
    {
        Write-Warning 'UWSCが停止しています'
        return
    }
    $command = $Function
    if ($Arguments)
    {
        $command += "`r`n$($Arguments -join "`r`n")"
    }
    $response = send-command $command
    $arr = $response -split $([char] 9)
    return New-Object psobject -Property @{
        Error    = $arr[0]
        Variable = $arr[1]
        Value    = $arr[2]
    } | Select Variable,Value,Error
}

<#
.SYNOPSIS
指定したタイトルのウィンドウIDを取得する
.DESCRIPTION
指定したタイトルのウィンドウIDを取得する
UWSCのgetid()
.INPUTS
なし
.OUTPUTS
int
.EXAMPLE
$Id = Get-UwscWindowId '"メモ帳"'
#>
function Get-UwscWindowId
{
    [CmdletBinding()]
    param
    (
        # IDを取得するウィンドウのタイトル
        [parameter(Mandatory,Position=0)]
        [string] $Title
    )
    Invoke-UwscFunction -Function 'getid' -Arguments $Title | % {
        return $_.Value
    }

}

<#
.SYNOPSIS
対象ウィンドウのステータスを取得する
.DESCRIPTION
対象ウィンドウのステータスを取得する
UWSCのstatus()
.INPUTS
なし
.OUTPUTS
psobject
.EXAMPLE
Get-UwscWindowStatus $Id
#>
function Get-UwscWindowStatus
{
    [CmdletBinding()]
    param
    (
        # ウィンドウのID
        [parameter(Mandatory,Position=0)]
        [string] $Id
    )
    $result = New-Object psobject
    Invoke-UwscFunction -Function 'GetAllStatus' -Arguments $Id | % {
        $_.Value -split $([char] 5) | ? {$_} | % {
            $Status = $_ -split $([char] 4)
            $result | Add-Member -MemberType NoteProperty -Name $Status[0] -Value $Status[1]
        }
    }
    return $result
}


function send-command
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory,Position=0)]
        [string] $Command
    )
    $Body = [System.Text.Encoding]::Default.GetBytes($Command)
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:$($script:port)" -Method Post -Body $Body
    return [System.Text.Encoding]::Default.GetString($response.RawContentStream.ToArray())
}

Export-ModuleMember -Function *-Uwsc*
