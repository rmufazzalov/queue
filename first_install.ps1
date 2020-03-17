$new_comp_name = "" 
$WorkGroupName = "queue"

# Задаем какие ветки проектов должны качаться
$branch_printserver = "dev"
$branch_selectservice = "dev"
$branch_infoboard = "master"
$branch_mainboard = "master"
$branch_midiboardserver = "master"
$branch_startup = "testing2"

# Задаем политику выполнения скриптов (чтоб запускались все скрипты без подтверждения)
Set-ExecutionPolicy Unrestricted -Force

w32tm /config /syncfromflags:manual /manualpeerlist:#dnsip

$net = get-netconnectionprofile
set-netconnectionprofile -name $net.Name -NetworkCategory Private

## определяем ip-адрес текущей машинки
$networks = Get-wmiObject Win32_networkAdapterConfiguration | ?{$_.IPEnabled}
[array]$ips = $networks | %{ $_.ipaddress -match "*****"}
if ($ips.count -eq 1) {
    $ip = $ips[0]
}
else {
    $i = 1;$ok = $false;$message = ""
    foreach ($ip_temp in $ips){
        Write-Host "$i`: $ip_temp"
        $message += "$i`: $ip_temp`r`n"
        $i++}
    Write-Host "What is your ip?"
    $message += "`r`nWhat is your ip?"   
    Do{
        $ip_i = Read-Host -Prompt $message
        if ($ip_i -ge 1 -and $ip_i -le $ips.Count)
        {$ip = $ips[$ip_i-1];$ok = $true}
    } While ($ok -eq $false) 
}
$ip_v4=$ip
# установка choco
iex ((New-Object System.Net.WebClient).DownloadString('***'))

choco install -y sudo
choco install -y mfc-zabbix-agent

choco install -y TunableSSLValidator
Import-Module C:\ProgramData\chocolatey\lib\TunableSSLValidator
Disable-SSLChainValidation 
Invoke-WebRequest "***"
Add-SessionTrustedCertificate -LastFailed   

choco upgrade -y mfc-powershell

## Очищаем переменные среды
[Environment]::SetEnvironmentVariable("MPG123_MODDIR","C:\Program Files\mpg123\plugins","Machine")
[Environment]::SetEnvironmentVariable("MPG123_MODDIR",$null,"User")

$Env_path = [Environment]::GetEnvironmentVariable("PATH","User")
[System.Collections.ArrayList]$Env_path_arr = $Env_path -split (";")
[System.Collections.ArrayList]$Env_path_arr_edited  = $Env_path -split (";")
foreach ($Element in $Env_path_arr)
{
    if ($Element -like "*lanit*")
    {
        $Env_path_arr_edited.Remove($Element)
    }
}
$Env_path_ok = $Env_path_arr_edited -join (";")
[Environment]::SetEnvironmentVariable("PATH",$Env_path_ok,"User")

$Env_path = [Environment]::GetEnvironmentVariable("PATH","Machine")
[System.Collections.ArrayList]$Env_path_arr = $Env_path -split (";")
[System.Collections.ArrayList]$Env_path_arr_edited  = $Env_path -split (";")
foreach ($Element in $Env_path_arr)
{
    if ($Element -like "*lanit*")
    {
        $Env_path_arr_edited.Remove($Element)
    }
}
$Env_path_ok = $Env_path_arr_edited -join (";")
[Environment]::SetEnvironmentVariable("PATH",$Env_path_ok,"Machine")


# устанавливаем гит
choco install -y mfc-git

# переименовываем папки
Move-Item C:\qms C:\qms.old -Force -ErrorAction SilentlyContinue
Rename-Item -Path "C:\suolanit" -NewName "suolanit-" -Force -ErrorAction SilentlyContinue 
# создаем папку qms
$folder_qms = "C:\qms"
New-Item -Path $folder_qms -ItemType Directory -ErrorAction SilentlyContinue
# создаем папку git в папке qms
$folder_git = "C:\qms\git"
New-Item -Path $folder_git -ItemType Directory -ErrorAction SilentlyContinue
# меняем текущий рабочий каталог на C:\qms\git (гуглим команду cd, chdir)
cd $folder_git


$env:Path = [Environment]::GetEnvironmentVariable("PATH","Machine")

# клонируем проект стартап с указанным бранчем
git clone -q -b $branch_startup ***
certutil -addstore "Root" "C:\qms\git\startup\***.crt"
# считываем файл с конфигом ЭО и конвертируем из CSV
$config_all = Get-Content -Path C:\qms\git\startup\queue.conf | ConvertFrom-Csv -Delimiter (",")
## ищем в конфиге свой ip.
<#
    ВАЖНО!
    Если в конфиге нет строчки с ip-адресом текущей машинки - дальше делать нечего.
    Такое может возникнуть, если готовить комп ЭО не на месте.

    Проверка наличия или отсутствия ip-адреса в конфиге не предусмотрена в
    данной версии скрипта, поэтому проверьте сами ручками =)    
#>

foreach ($line in $config_all)
{
    if ($line.ip4 -eq $ip_v4)
    {
        $Dep_code = $line.code
        $Type = $line.type
        $Color = $line.color
        $Board = $line.infoboard
        $source = $line.source
        $pcname = $line.name
    }

}


if ($Type -eq "terminal")
{
    choco install -y mfc-terminal
    git clone -q -b $branch_printserver ***
    git clone -q -b $branch_selectservice ***
    git clone -q -b $branch_infoboard ***
    #git clone -q -b $Board ***

}
else
{ 
    choco install -y mfc-tv
    git clone -q -b $branch_mainboard ***
    git clone -q -b $branch_midiboardserver ***

}

### добавление новых пользователей
## поиск пользователей quser  qadmin, вдруг уже созданы такие!?
$workgroup = (Get-WmiObject Win32_ComputerSystem).domain
[adsi]$computer = "WinNT://$workgroup/$env:COMPUTERNAME"
$FL_qu_exist = $false
$FL_qa_exist = $false
$FL_qu_ok = $false
$users = $computer.children | where {$_.class -eq "user"}
foreach ($user in $users)
{
    if ($user.Name -eq "quser")
    {
        $FL_qu_exist = $true
    }
    if ($user.Name -eq "qadmin")
    {
        $FL_qa_exist = $true
    }
}
## Создание пользователя quser
if (!$FL_qu_exist)
{   # if quser does not exist
    try {
        $user = $computer.Create("User", "quser")
        $Secure_File_Path = "C:\qms\git\startup\first_install\userscred\quser"
        $Key = cat "C:\qms\git\startup\first_install\userscred\key"
        $Secure_Password = cat $Secure_File_Path |  ConvertTo-SecureString -Key $Key
        $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure_Password))
        #$password = ""
        $user.SetPassword($password)
        $user.Put("Description", "queue user")
        $flag = $user.userflags.value -bor 0x10040
        $user.Put("userflags", $flag)
        $user.setInfo()
        Write-Host "quser created" -ForegroundColor Magenta -BackgroundColor gray
        try {
            [adsi]$group = "WinNT://$workgroup/$env:COMPUTERNAME/Пользователи,group"
            $group.Add($user.Path)
            Write-Host "Group 'Пользователи' added." -ForegroundColor Magenta -BackgroundColor gray
            }
        catch {
            Write-Host "Group 'Пользователи' not found." -ForegroundColor red -BackgroundColor gray
            }
        try {
            [adsi]$group = "WinNT://$workgroup/$env:COMPUTERNAME/Users,group"
            $group.Add($user.Path)
            Write-Host "Group 'Users' added." -ForegroundColor Magenta -BackgroundColor gray
            }
        catch {
            Write-Host "Group 'Users' not found." -ForegroundColor red -BackgroundColor gray
            }
        $FL_qu_ok = $true
        }
    catch {
        Write-Host "quser creation error" -ForegroundColor red -BackgroundColor gray
        } 
}
else
{ # if quser is exist
    Write-Host "'quser' already exist" -ForegroundColor Magenta -BackgroundColor gray
}

## Создание пользователя qadmin, добавление прав админа.
if (!$FL_qa_exist)
{   # if qadmin does not exist
    try {
        $user = $computer.Create("User", "qadmin")
        $Secure_File_Path = "C:\qms\git\startup\first_install\userscred\qadmin"
        $Key = cat "C:\qms\git\startup\first_install\userscred\key"
        $Secure_Password = cat $Secure_File_Path |  ConvertTo-SecureString -Key $Key
        $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure_Password))
        #$password = ""
        $user.SetPassword($password)
        $user.Put("Description", "queue administrator")
        $flag = $user.userflags.value -bor 0x10040
        $user.Put("userflags", $flag)
        $user.setInfo()
        Write-Host "quser created" -ForegroundColor Magenta -BackgroundColor gray
        try {
            [adsi]$group = "WinNT://$workgroup/$env:COMPUTERNAME/Администраторы,group"
            $group.Add($user.Path)
            Write-Host "Group 'Администраторы' added." -ForegroundColor Magenta -BackgroundColor gray
            } 
        catch { 
            Write-Host "Group 'Администраторы' not found." -ForegroundColor red -BackgroundColor gray
            }
        try {
            [adsi]$group = "WinNT://$workgroup/$env:COMPUTERNAME/Administrators,group" 
            $group.Add($user.Path)
            Write-Host "Group 'Administrators' added." -ForegroundColor Magenta -BackgroundColor gray
            } 
         catch {
            Write-Host "Group 'Administrators' not found." -ForegroundColor red -BackgroundColor gray
            }  
        }
    catch {
        Write-Host "qadmin creation error" -ForegroundColor red -BackgroundColor gray
        }   
}
else
{ # if qadmin is exist
    Write-Host "'qadmin' already exist" -ForegroundColor Magenta -BackgroundColor gray
}

## настройка автовхода пользователя quser

if ($FL_qu_ok)
{
    try {
    $username = 'quser'
    $Secure_File_Path = "C:\qms\git\startup\first_install\userscred\quser"
    $Key = cat "C:\qms\git\startup\first_install\userscred\key"
    $Secure_Password = cat $Secure_File_Path |  ConvertTo-SecureString -Key $Key
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure_Password))
    $RegistryLocation = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Set-ItemProperty $RegistryLocation -Name 'AutoAdminLogon' -Value '1'
    Set-ItemProperty $RegistryLocation -Name 'DefaultUsername' -Value "$username"
    Set-ItemProperty $RegistryLocation -Name 'DefaultPassword' -Value "$password"
    }
    catch {
        Write-Host "Configuring winlogon error" -ForegroundColor red -BackgroundColor gray
    }
    Write-Host "Configuring winlogon OK" -ForegroundColor Magenta -BackgroundColor gray
}
else
{
    Write-Host "'quser' flag not true" -ForegroundColor red -BackgroundColor gray
}

## удаляем из папок автозагрузки все файлы
Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" | Remove-Item -Recurse -Force
Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup" | Remove-Item -Recurse -Force

## настройка задач планировщика. 
$login = "qadmin"
$Secure_File_Path = "C:\qms\git\startup\first_install\userscred\qadmin"
$Key = cat "C:\qms\git\startup\first_install\userscred\key"
$Secure_Password = cat $Secure_File_Path |  ConvertTo-SecureString -Key $Key
$password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure_Password))
schtasks /create /TN queue_first /XML C:\qms\git\startup\first_install\schtasks\queue_first.xml /RU $login /RP $password
schtasks /create /TN queue_second /XML C:\qms\git\startup\first_install\schtasks\queue_second.xml

if ($Type -eq "terminal")
{
$TimeSpan = New-TimeSpan -Minutes 180 # Время для повторения задачи
$status = New-ScheduledJobOption –RunElevated # повышенные привелегии
$file_start = "C:\qms\git\startup\chek_proc.ps1" # файла для задачи
$name_task = "Chec_proc" # имя задачи
Register-ScheduledJob -Name $name_task -FilePath $file_start -RunEvery $TimeSpan –ScheduledJobOption $status 
}
# указываю сервер активации
slmgr /skms ***

## отключение брандмауэра?
netsh advfirewall set allprofiles state off

# смена рабочей группы
Add-Computer -WorkGroupName $WorkGroupName

Rename-Computer -NewName $pcname 