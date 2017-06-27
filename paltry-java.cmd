@echo off
title Paltry Java

set SSH_REPOS=" "
set HTTPS_REPOS="https://github.com/jitpack/maven-simple.git"
set MAVEN_SERVER_IDS=" "
set ECLIPSE_FORMATTER_PATH=" "

set TMP_SCRIPT="%TMP%\%~n0.ps1"
for /f "delims=:" %%a in ('findstr -n "^___" %0') do set "Line=%%a"
(for /f "skip=%Line% tokens=* eol=_" %%a in ('type %0') do echo(%%a) > %TMP_SCRIPT%

powershell -ExecutionPolicy RemoteSigned -File %TMP_SCRIPT% ^
  -SshRepos "%SSH_REPOS%" -HttpsRepos "%HTTPS_REPOS%" -MavenServerIds "%MAVEN_SERVER_IDS%" ^
  -EclipseFormatterPath "%ECLIPSE_FORMATTER_PATH%"
exit

___SCRIPT___
Param(
  [string]$SshRepos,
  [string]$HttpsRepos,
  [string]$MavenServerIds,
  [string]$EclipseFormatterPath
)
Set-PSDebug -Trace 0
Add-Type -Assembly "System.IO.Compression.FileSystem"
$CurrentFolder = $PWD
$UserProfile = $Env:USERPROFILE
$DownloadsFolder = "$UserProfile\Downloads"
$TempFolder = "$UserProfile\Temp"
$ToolsFolder = "$CurrentFolder\tools"
$EclipseWorkspace = "$CurrentFolder\workspace"
$MavenUserFolder = "$UserProfile\.m2"
$MavenSettings = "$MavenUserFolder\settings.xml"
$MavenSecuritySettings = "$MavenUserFolder\settings-security.xml"
$MavenRepo = "$MavenUserFolder\repository"
$EclipseFormatterFullPath = "$CurrentFolder\$EclipseFormatterPath"
$WebClient = New-Object System.Net.WebClient
$WebClient.Headers.Add("User-Agent", "PowerShell")
$Online = Test-Connection -ComputerName 8.8.8.8 -Quiet -ErrorAction Ignore
New-Item -ItemType Directory -Force -Path $DownloadsFolder | Out-Null
New-Item -ItemType Directory -Force -Path $TempFolder | Out-Null
New-Item -ItemType Directory -Force -Path $ToolsFolder | Out-Null

Function Out-File-Force($Path) {
  Process {
    if(Test-Path $path) {
      Out-File -Force -FilePath $Path -InputObject $_
    } else {
      New-Item -Force -Path $Path -Value $_ -Type File | Out-Null
    }
  }
}

Function Log-Info($Message) {
  Write-Host -ForegroundColor "Green" $Message
}
Function Log-Warn($Message) {
  Write-Host -ForegroundColor "Yellow" $Message
}

Function Require-Online {
  if(!$Online) {
    $ErrorMessage = "Required files not downloaded and you are offline"
    (New-Object -ComObject Wscript.Shell).Popup($ErrorMessage, 0, "ERROR!", 16)
    exit 1
  }
}

Function InstallTool($Name, $Url, $Prefix) {
  if($Online) {
    $ToolFile = $Url.Split("/") | Select-Object -Last 1
    $ToolFolder = [io.path]::GetFileNameWithoutExtension($ToolFile)
    if(!($ToolFolder.Contains("."))) {
      $Url = [System.Net.WebRequest]::Create($Url).GetResponse().ResponseUri.AbsoluteUri
      $ToolFile = $Url.Split("/") | Select-Object -Last 1
      $ToolFolder = [io.path]::GetFileNameWithoutExtension($ToolFile)
    }
    $DownloadedFile = "$DownloadsFolder\$ToolFile"
    $ExtractedFolder = "$TempFolder\$Name"
    $InstalledFolder = "$ToolsFolder\$ToolFolder"
  } else {
    $InstalledFolder = Get-ChildItem $ToolsFolder -Filter $Prefix |
      Sort-Object Name -Descending | Select-Object -First 1 | %{ $_.FullName }
    if(!$InstalledFolder) {
      Require-Online
    }
  }
  if(!(Test-Path $InstalledFolder)) {
    if(!(Test-Path $DownloadedFile)) {
      Require-Online
      Log-Info "Downloading $Name..."
      $WebClient.DownloadFile($Url, $DownloadedFile)
    }
    Log-Info "Extracting $Name..."
    Remove-Item -Recurse -ErrorAction Ignore $ExtractedFolder
    [System.IO.Compression.ZipFile]::ExtractToDirectory($DownloadedFile, $ExtractedFolder)
    $ExtractedContents = Get-ChildItem $ExtractedFolder
    if($ExtractedContents.Length -eq 1 -And $ExtractedContents[0].PSIsContainer) {
      Move-Item $ExtractedContents[0].FullName $InstalledFolder
      Remove-Item $ExtractedFolder
    } else {
      Move-Item $ExtractedFolder $InstalledFolder
    }
  }

  $ToolBinFolder = Get-ChildItem -Recurse "$InstalledFolder" -Include @("*.exe", "*.cmd") |
    Sort-Object FullName | Select-Object -First 1 | %{ $_.Directory.FullName }
  $Env:Path = "$ToolBinFolder;$Env:Path"
}

Function InstallGit {
  $GitReleaseApiUrl = "https://api.github.com/repos/git-for-windows/git/releases/latest"
  if($Online) {
    $MinGitRelease = $WebClient.DownloadString($GitReleaseApiUrl) | ConvertFrom-Json |
      Select -Expand assets | Where-Object { $_.name -Match "MinGit.*64-bit.zip" }
  }
  $MinGitUrl = $MinGitRelease.browser_download_url
  InstallTool -Name "Git" -Url $MinGitUrl -Prefix MinGit*
}

Function CloneRepos {
  if((Test-Path "$UserProfile\.ssh") -And $SshRepos) {
      $SshRepos.Split(",") | %{ [PSCustomObject]@{
        Url = $_;
        Name = $_.Split("/") | Select -Last 1 | %{ $_.Replace(".git", "") }
      } } | %{
        if(!(Test-Path "$CurrentFolder\$($_.Name)")) {
        Require-Online
        Log-Info "Cloning $($_.Name)..."
        git clone $_.Url $_.Name
      }
    }
  }
  $HttpsRepos.Split(",") | %{ [PSCustomObject]@{
    Url = $_;
    Name = $_.Split("/") | Select -Last 1 | %{ $_.Replace(".git", "") }
  } } | %{
    if(!(Test-Path "$CurrentFolder\$($_.Name)")) {
    Require-Online
    Log-Info "Cloning $($_.Name)..."
    git clone $_.Url $_.Name
    }
  }
}

Function Install7Zip {
  $7ZipUrl = "http://www.7-zip.org/a/7z1604-x64.msi"
  $7ZipFile = $7ZipUrl.Split("/") | Select-Object -Last 1
  $7ZipFolder = [io.path]::GetFileNameWithoutExtension($7ZipFile)
  $7ZipInstallerFile = "$DownloadsFolder\$7ZipFile"
  $7ZipInstallerFolder = "$TempFolder\$7ZipFolder"
  $7ZipInstalledFolder = "$ToolsFolder\$7ZipFolder"
  if(!(Test-Path $7ZipInstalledFolder)) {
    if(!(Test-Path $7ZipInstallerFile)) {
      Require-Online
      Log-Info "Downloading 7-Zip..."
      $WebClient.DownloadFile($7ZipUrl, $7ZipInstallerFile)
    }
    Log-Info "Extracting 7-Zip..."
    msiexec /a "$7ZipInstallerFile" TARGETDIR="$7ZipInstallerFolder" /qn | Out-Null
    Move-Item "$7ZipInstallerFolder\Files\7-Zip" $7ZipInstalledFolder -Force
    Remove-Item -Recurse -Force -ErrorAction Ignore $7ZipInstallerFolder
  }
  $Env:Path = "$7ZipInstalledFolder;$Env:Path"
}

Function InstallJdk {
  if($Online) {
    $JdkUrl = $WebClient.DownloadString("https://www.oracle.com/technetwork/java/javase/downloads/jdk8-downloads-2133151.html") |
      %{ ([regex]'http.+-windows-x64.exe').Matches($_) | %{ $_.Value } }
    $JceUrl = "http://download.oracle.com/otn-pub/java/jce/8/jce_policy-8.zip"
    $JdkFile = $JdkUrl.Split("/") | Select-Object -Last 1
    $JdkFolder = [io.path]::GetFileNameWithoutExtension($JdkFile)
    $JdkInstallerFile = "$DownloadsFolder\$JdkFile"
    $JceFile = "$DownloadsFolder\jce_policy-8.zip"
    $JdkInstallerFolder = "$TempFolder\$JdkFolder"
    $JdkInstalledFolder = "$ToolsFolder\$JdkFolder"
    if(!(Test-Path $JdkInstalledFolder)) {
      if(!(Test-Path $JdkInstallerFile)) {
        Require-Online
        Log-Info "Downloading JDK..."
        $WebClient.Headers.Set("Cookie", "oraclelicense=accept-securebackup-cookie")
        $WebClient.DownloadFile($JdkUrl, $JdkInstallerFile)
        $WebClient.DownloadFile($JceUrl, $JceFile)
        $WebClient.Headers.Remove("Cookie")
      }
      Log-Info "Extracting JDK..."
      Remove-Item -Recurse -Force -ErrorAction Ignore $JdkInstallerFolder
      7z x "$JdkInstallerFile" -o"$JdkInstallerFolder" | Out-Null
      $ToolsZipArchive = Get-ChildItem -Recurse -Path $JdkInstallerFolder |
        Sort Length -Descending | Select-Object -First 1 | %{ $_.FullName }
      7z x "$ToolsZipArchive" -o"$JdkInstallerFolder" | Out-Null
      7z x "$JdkInstallerFolder\tools.zip" -o"$JdkInstalledFolder" | Out-Null
      $Unpack200 = "$JdkInstalledFolder\bin\unpack200"
      Get-ChildItem -Recurse -Include *.pack -Path $JdkInstalledFolder |
        %{ &$Unpack200 -r "$_" "$($_.Directory)\$([io.path]::GetFileNameWithoutExtension($_)).jar" }
      7z x "$JceFile" -o"$JdkInstallerFolder" | Out-Null
      Get-ChildItem -Path "$JdkInstallerFolder\UnlimitedJCEPolicyJDK8" -Filter *.jar |
        Move-Item -Force -Destination "$JdkInstalledFolder\jre\lib\security"
      Remove-Item -Recurse -Force -ErrorAction Ignore $JdkInstallerFolder
    }
  } else {
    $JdkInstalledFolder = Get-ChildItem $ToolsFolder -Filter jdk* |
      Sort-Object Name -Descending | Select-Object -First 1 | %{ $_.FullName }
    if(!$JdkInstalledFolder) {
      Require-Online
    }
  }
  
  $Env:JAVA_HOME = "$JdkInstalledFolder"
  $Env:Path = "$JdkInstalledFolder\bin;$Env:Path"
}

Function InstallMaven {
  if($Online) {
    $MavenDownloadUrl = Invoke-WebRequest -Uri "https://maven.apache.org/download.cgi" |
      %{ $_.Links } | %{ $_.href } | ?{ $_ -Match "apache-maven-[\d.]+-bin.zip$" }
  }
  InstallTool -Name "Maven" -Url $MavenDownloadUrl -Prefix apache-maven*
}

Function SetupMavenSettings {
  if($MavenServerIds) {
    if(!(Test-Path $MavenSecuritySettings)) {
      Log-Info "Encrypting Master Password For Maven..."
      $MasterPasswordCredential = Get-Credential -Credential "Master Password"
      $MasterPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($MasterPasswordCredential.Password)
      )
      $EncryptedMasterPassword = mvn --encrypt-master-password """$MasterPassword"""
      @"
      <settingsSecurity>
        <master>$EncryptedMasterPassword</master>
      </settingsSecurity>
      "@ | Out-File $MavenSecuritySettings
    }
    if(!(Test-Path $MavenSettings)) {
      Log-Info "Encrypting Server Passwords For Maven..."
      $ServerCredential = Get-Credential -Credential ""
      $ServerUserName = $ServerCredential.UserName
      $ServerPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ServerCredential.Password)
      )
      $EncryptedServerPassword = mvn --encrypt-password """$ServerPassword"""
      $MavenServerIds.Split(",") | %{ @"
        <server>
          <id>$_</id>
          <username>$ServerUserName</username>
          <password>$EncryptedServerPassword</password>
        </server>
        "@
      } | Out-String | %{ @"
        <settings>
          <servers>
            $_
          </servers>
        </settings>
        "@
      } | Out-File $MavenSettings
    }
  }
}

Function CleanupMavenRepo {
  if(Test-Path $MavenRepo) {
    Get-ChildItem -Recurse $MavenRepo -Include @("_maven.repositories", "_remote.repositories",
      "maven-metadata-local.xml", "*.lastUpdated", "resolver-status.properties") |
      %{ Remove-Item -Force -ErrorAction Ignore $_ }
  }
}

Function InstallEclipse {
  if($Online) {
    $EclipseDownloadUrl = Invoke-WebRequest -Uri "https://www.eclipse.org/downloads/eclipse-packages" |
      %{ $_.Links } | %{ $_.href } | ?{ $_ -Match "eclipse-jee-.+x86_64.zip$" } |
      %{ "https://www.eclipse.org$_&mirror_id=1" }
  }

  InstallTool -Name "Eclipse" -Url $EclipseDownloadUrl -Prefix eclipse-jee*
}

Function SetupEclipseWorkspace {
  if(!(Test-Path $EclipseWorkspace)) {
    @"
    eclipse.preferences.version=1
    showIntro=false
    "@ | Out-File-Force "$EclipseWorkspace\.metadata\.plugins\org.eclipse.core.runtime\.settings\org.eclipse.ui.prefs"
    @"
    <?xml version="1.0" encoding="UTF-8"?>
    <state reopen="false"/>
    "@ | Out-File-Force "$EclipseWorkspace\.metadata\.plugins\org.eclipse.ui.intro\introstate"
    if(Test-Path $EclipseFormatterFullPath -PathType Leaf) {
      [xml]$EclipseFormatterContent = Get-Content $EclipseFormatterFullPath
      $EclipseFormatterContent.GetElementsByTagName("setting") |
        %{ $_.id + "=" + $_.value } | Sort | Out-String |
        Out-File-Force "$EclipseWorkspace\.metadata\.plugins\org.eclipse.core.runtime\.settings\org.eclipse.jdt.core.prefs"
    }
    @"
    editor_save_participant_org.eclipse.jdt.ui.postsavelistener.cleanup=true
    sp_cleanup.add_default_serial_version_id=true
    sp_cleanup.add_generated_serial_version_id=false
    sp_cleanup.add_missing_annotations=true
    sp_cleanup.add_missing_deprecated_annotations=true
    sp_cleanup.add_missing_methods=false
    sp_cleanup.add_missing_nls_tags=false
    sp_cleanup.add_missing_override_annotations=true
    sp_cleanup.add_missing_override_annotations_interface_methods=true
    sp_cleanup.add_serial_version_id=false
    sp_cleanup.always_use_blocks=true
    sp_cleanup.always_use_parentheses_in_expressions=false
    sp_cleanup.always_use_this_for_non_static_field_access=true
    sp_cleanup.always_use_this_for_non_static_method_access=false
    sp_cleanup.convert_functional_interfaces=true
    sp_cleanup.convert_to_enhanced_for_loop=true
    sp_cleanup.correct_indentation=false
    sp_cleanup.format_source_code=true
    sp_cleanup.format_source_code_changes_only=false
    sp_cleanup.insert_inferred_type_arguments=false
    sp_cleanup.make_local_variable_final=true
    sp_cleanup.make_parameters_final=false
    sp_cleanup.make_private_fields_final=true
    sp_cleanup.make_type_abstract_if_missing_method=false
    sp_cleanup.make_variable_declarations_final=false
    sp_cleanup.never_use_blocks=false
    sp_cleanup.never_use_parentheses_in_expressions=true
    sp_cleanup.on_save_use_additional_actions=true
    sp_cleanup.organize_imports=true
    sp_cleanup.qualify_static_field_accesses_with_declaring_class=false
    sp_cleanup.qualify_static_member_accesses_through_instances_with_declaring_class=true
    sp_cleanup.qualify_static_member_accesses_through_subtypes_with_declaring_class=true
    sp_cleanup.qualify_static_member_accesses_with_declaring_class=false
    sp_cleanup.qualify_static_method_accesses_with_declaring_class=false
    sp_cleanup.remove_private_constructors=true
    sp_cleanup.remove_redundant_type_arguments=true
    sp_cleanup.remove_trailing_whitespaces=false
    sp_cleanup.remove_trailing_whitespaces_all=true
    sp_cleanup.remove_trailing_whitespaces_ignore_empty=false
    sp_cleanup.remove_unnecessary_casts=true
    sp_cleanup.remove_unnecessary_nls_tags=false
    sp_cleanup.remove_unused_imports=false
    sp_cleanup.remove_unused_local_variables=false
    sp_cleanup.remove_unused_private_fields=true
    sp_cleanup.remove_unused_private_members=false
    sp_cleanup.remove_unused_private_methods=true
    sp_cleanup.remove_unused_private_types=true
    sp_cleanup.sort_members=false
    sp_cleanup.sort_members_all=false
    sp_cleanup.use_anonymous_class_creation=false
    sp_cleanup.use_blocks=false
    sp_cleanup.use_blocks_only_for_return_and_throw=false
    sp_cleanup.use_lambda=true
    sp_cleanup.use_parentheses_in_expressions=false
    sp_cleanup.use_this_for_non_static_field_access=true
    sp_cleanup.use_this_for_non_static_field_access_only_if_necessary=false
    sp_cleanup.use_this_for_non_static_method_access=true
    sp_cleanup.use_this_for_non_static_method_access_only_if_necessary=true
    "@ | Out-File-Force "$EclipseWorkspace\.metadata\.plugins\org.eclipse.core.runtime\.settings\org.eclipse.jdt.ui.prefs"
    @"
    decorator_filetext_decoration={name}
    decorator_foldertext_decoration={name}
    decorator_projecttext_decoration={name} [{repository }{branch}{ branch_status}]
    decorator_show_dirty_icon=true
    decorator_submoduletext_decoration={name} [{branch}{ branch_status}]{ short_message}
    eclipse.preferences.version=1
    "@ | Out-File-Force "$EclipseWorkspace\.metadata\.plugins\org.eclipse.core.runtime\.settings\org.eclipse.egit.ui.prefs"
    Get-ChildItem -Path $CurrentFolder -Recurse -Force -Filter .git -Depth 1 | %{ $_.Parent.FullName } |
      %{ "<item value=""$_""/>" } | Out-String | %{ @"
      <?xml version="1.0" encoding="UTF-8"?>
      <section name="Workbench">
        <section name="MavenProjectImportWizardPage">
          <list key="rootDirectory">
            $_
          </list>
            <list key="projectNameTemplate">
            <item value="[artifactId]"/>
            <item value="[artifactId]-TRUNK"/>
            <item value="[artifactId]-[version]"/>
            <item value="[groupId].[artifactId]"/>
            <item value="[groupId].[artifactId]-[version]"/>
            <item value="[name]"/>
          </list>
        </section>
      </section>
      "@
    } | Out-File-Force "$EclipseWorkspace\.metadata\.plugins\org.eclipse.m2e.core.ui\dialog_settings.xml"
    @"
    <?xml version="1.0" encoding="UTF-8" standalone="no"?>
    <launchConfiguration type="org.eclipse.m2e.Maven2LaunchConfigurationType">
      <booleanAttribute key="M2_DEBUG_OUTPUT" value="false"/>
      <stringAttribute key="M2_GOALS" value="clean install"/>
      <booleanAttribute key="M2_NON_RECURSIVE" value="false"/>
      <booleanAttribute key="M2_OFFLINE" value="false"/>
      <stringAttribute key="M2_PROFILES" value=""/>
      <listAttribute key="M2_PROPERTIES"/>
      <stringAttribute key="M2_RUNTIME" value="EMBEDDED"/>
      <booleanAttribute key="M2_SKIP_TESTS" value="false"/>
      <intAttribute key="M2_THREADS" value="1"/>
      <booleanAttribute key="M2_UPDATE_SNAPSHOTS" value="false"/>
      <stringAttribute key="M2_USER_SETTINGS" value=""/>
      <booleanAttribute key="M2_WORKSPACE_RESOLUTION" value="false"/>
      <stringAttribute key="org.eclipse.jdt.launching.WORKING_DIRECTORY" value="${project_loc}"/>
    </launchConfiguration>
    "@ | Out-File-Force "$EclipseWorkspace\.metadata\.plugins\org.eclipse.debug.core\.launches\Clean Install Current Project.launch"
    @"
    org.eclipse.ui.commands=<?xml version\="1.0" encoding\="UTF-8"?>\r\n<org.eclipse.ui.commands>\r\n<keyBinding commandId\="org.eclipse.m2e.core.pomFileAction.run" contextId\="org.eclipse.ui.contexts.window" keyConfigurationId\="org.eclipse.ui.defaultAcceleratorConfiguration" keySequence\="CTRL+SHIFT+B"/>\r\n<keyBinding contextId\="org.eclipse.ui.contexts.window" keyConfigurationId\="org.eclipse.ui.defaultAcceleratorConfiguration" keySequence\="ALT+SHIFT+X M"/>\r\n<keyBinding contextId\="org.eclipse.ui.contexts.window" keyConfigurationId\="org.eclipse.ui.defaultAcceleratorConfiguration" keySequence\="CTRL+SHIFT+B"/>\r\n<keyBinding commandId\="org.eclipse.debug.ui.commands.ToggleBreakpoint" contextId\="org.eclipse.ui.contexts.window" keyConfigurationId\="org.eclipse.ui.defaultAcceleratorConfiguration" keySequence\="SHIFT+B"/>\r\n</org.eclipse.ui.commands>
    "@ | Out-File-Force "$EclipseWorkspace\.metadata\.plugins\org.eclipse.core.runtime\.settings\org.eclipse.ui.workbench.prefs"
  }
}

InstallGit
CloneRepos

Install7Zip
InstallJdk
InstallMaven
SetupMavenSettings
CleanupMavenRepo

InstallEclipse
SetupEclipseWorkspace
Log-Info "Starting Eclipse..."
eclipse -data "$EclipseWorkspace"

powershell
