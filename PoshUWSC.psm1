[System.Diagnostics.Process] $uwsc = $null
$ScriptPath = $MyInvocation.MyCommand.Path | Split-Path | Join-Path -ChildPath HTTPServer.uws
$port = 57913

<#
.SYNOPSIS
UWSC���N������
.DESCRIPTION
UWSC��҂��󂯏�Ԃɂ��AUWSC���W���[���̊֐��Q�𗘗p�ł���悤�ɂ���
.INPUTS
�Ȃ�
.OUTPUTS
�Ȃ�
.EXAMPLE
Start-Uwsc
#>
function Start-Uwsc
{
    [CmdletBinding()]
    param
    (
        # UWSC��HTTP�T�[�o�[���҂��󂯂Ɏg���|�[�g���w��
        [parameter(Mandatory=$false,Position=0)]
        [ValidateRange(1,[uint16]::MaxValue)]
        [uint16] $Port
    )
    if (! $(Test-Uwsc))
    {
        Write-Warning "UWSC�̃p�X���ݒ肳��Ă��܂���"
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
UWSC���I������
.DESCRIPTION
UWSC���W���[���̊e��֐�
.INPUTS
�Ȃ�
.OUTPUTS
�Ȃ�
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
UWSC�̃p�X���w�肷��
.DESCRIPTION
UWSC�̃p�X���O���[�o���ϐ� $UwscPath �ɃZ�b�g���܂�
.INPUTS
�Ȃ�
.OUTPUTS
�Ȃ�
.EXAMPLE
Set-UwscPath 'C:\Program Files (x86)\UWSC\UWSC.exe'
#>
function Set-UwscPath
{
    [CmdletBinding()]
    param
    (
        # uwsc.exe�̃p�X
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
UWSC�̉ғ��󋵂��m�F����
.DESCRIPTION
UWSC�̉ғ��󋵂��m�F����
.INPUTS
�Ȃ�
.OUTPUTS
�Ȃ�
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
UWSC�̊֐������s����
.DESCRIPTION
UWSC�̊֐������s����
.INPUTS
�Ȃ�
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
        # ���s����UWSC�̊֐���
        [parameter(Mandatory,Position=0)]
        [string] $Function,
        # �֐��ɓn������
        [parameter(Mandatory=$false,Position=1)]
        [string[]] $Arguments
    )
    if ($(Get-UwscState).State -ne 'Running')
    {
        Write-Warning 'UWSC����~���Ă��܂�'
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
�w�肵���^�C�g���̃E�B���h�EID���擾����
.DESCRIPTION
�w�肵���^�C�g���̃E�B���h�EID���擾����
UWSC��getid()
.INPUTS
�Ȃ�
.OUTPUTS
int
.EXAMPLE
$Id = Get-UwscWindowId '"������"'
#>
function Get-UwscWindowId
{
    [CmdletBinding()]
    param
    (
        # ID���擾����E�B���h�E�̃^�C�g��
        [parameter(Mandatory,Position=0)]
        [string] $Title
    )
    Invoke-UwscFunction -Function 'getid' -Arguments $Title | % {
        return $_.Value
    }

}

<#
.SYNOPSIS
�ΏۃE�B���h�E�̃X�e�[�^�X���擾����
.DESCRIPTION
�ΏۃE�B���h�E�̃X�e�[�^�X���擾����
UWSC��status()
.INPUTS
�Ȃ�
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
        # �E�B���h�E��ID
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
