@echo off
setlocal EnableDelayedExpansion

:: ==============================================================================
:: 
::      build.bat
::
::      build script used to build my project without launching visual studio
::      you can pass the target as first argument:
::              build.bat [x86|x64|static|dll]
::
:: ==============================================================================
::   Copyright (C) Guillaume Plante 2020 <guillaume.plante>@luminator.com
:: ==============================================================================

goto :init

:init
    :: default value for the script root: the AutomationScriptsRoot env value
    set "__scripts_root=%AutomationScriptsRoot%"
    :: read the registry for the script root, this will supercede the previous value. To get the script root from the registry:
    :: 1. get the OrganizationHKCU environment value. 2. append "\development\build-automation" to create a registry path
    :: 3. get the value of the key named BuildAutomation, this is the path of the script root we're looking for
    call :read_script_data development\build-automation  BuildAutomation
    set "__script_file=%~0"
    set "__script_path=%~dp0"
    set "__makefile=%__scripts_root%\make\make.bat"
    set "__lib_date=%__scripts_root%\batlibs\date.bat"
    set "__lib_out=%__scripts_root%\batlibs\out.bat"
    set "__cfg_file=%__script_path%buildcfg.ini"
    :: default value for verbose mode
    set "__verbose_mode=no"
    set "__verbose_option="
    set "__dynamic_mode=no"
    :: loop through all the cmd line options and check for options supported

    :: set the target and the build config values
    if not [%1]==[] (
        call :settarget %1
    )
    if not [%2]==[] (
        call :setbuildcfg %2 "%__dynamic_mode%"
    )
    set VERBOSE_MODE_BUILD=false>nul
    set SetMinimalCompilation=true>nul
    goto :parsecmdline

:header
    echo. %__script_file% - build script
    echo. This script is part of the custom build utilities from gp
    echo.
    goto :eof

:usage
    echo. Usage:
    echo. %__script_file% [target platform] [build config]
    echo.
    echo.      target platform      one of 'x86', 'x64', 'clean'
    echo.      build config         one of 'Debug', 'Release', 'DebugDll', 'ReleaseDll'
    echo.      /v                   verbose mode 
    echo.      /dll                 dynamic mode (will change Debug to DebugDll)
    echo.
    goto :eof



:parsecmdline
    :: the next step to go is here
    if "%~1"=="" goto :validate

    if /i "%~1"=="/dll" (
        set "__buildcfg=%tmpval%Dll"
        set "__dynamic_mode=yes"  & shift & goto :parsecmdline
    )         
    
    if /i "%~1"=="/v"         call :setverbosemode  & shift & goto :parsecmdline
    if /i "%~1"=="-v"         call :setverbosemode  & shift & goto :parsecmdline
    if /i "%~1"=="--verbose"  call :setverbosemode  & shift & goto :parsecmdline

    if /i "%~1"=="/r"         call :setrebuild  & shift & goto :parsecmdline
    if /i "%~1"=="/rebuild"   call :setrebuild  & shift & goto :parsecmdline
    if /i "%~1"=="-r"         call :setrebuild  & shift & goto :parsecmdline
    if /i "%~1"=="--rebuild"  call :setrebuild  & shift & goto :parsecmdline

    shift
    goto :parsecmdline



:setrebuild
    set SetMinimalCompilation=false>nul
    goto :eof

:setverbosemode
    set "__verbose_mode=yes"
    set "__verbose_option=/v"
    set VERBOSE_MODE_BUILD=true>nul
    goto :eof


:settarget
    set tmpval=%1
    set "__target=%tmpval%"
    goto :eof


:setbuildcfg
    set tmpval=%1
    set "__buildcfg=%tmpval%"
    goto :eof


:header
    echo. %__script_name% v%__script_version%
    echo.    This script is part of my custom LTG build wrappers.
    echo.
    goto :eof

:header_err
    echo. =======================================================
    echo. = This script is part of my custom LTG build wrappers =
    echo. =======================================================
    echo.
    echo. YOU NEED TO HAVE THE BuildAutomation Scripts setup
    echo. on you system...
    echo. http://vsvr-gitlab-01/guillaume.plante/buildautomation
    goto :eof


:read_script_data
    if not defined OrganizationHKCU (
        call :header_err && call :error_missing_path OrganizationHKCU::= & goto :eof
    )
    set regpath=%OrganizationHKCU::=%
    for /f "tokens=2,*" %%A in ('REG.exe query %regpath%\%1 /v %2') do (
            set "__scripts_root=%%B"
        )
    goto :eof

:printverbose
    set logmsg=%1
    if /i "%__verbose_mode%"=="yes" (
        call %__lib_out% :__out_n_d_cya "[verbose] "
        call %__lib_out% :__out_l_gry %logmsg%
    )
    goto :eof




:validate
    if not defined __scripts_root          call :header_err && call :error_missing_path __scripts_root & goto :eof
    if not exist %__makefile%  call :error_missing_script "%__makefile%" & goto :eof
    if not exist %__lib_date%  call :error_missing_script "%__lib_date%" & goto :eof
    if not exist %__lib_out%  call :error_missing_script "%__lib_out%" & goto :eof
    if not exist %__cfg_file%  call :error_missing_script "%__cfg_file%" & goto :eof
    goto :build


:: ==============================================================================
::   call make
:: ==============================================================================
:call_make_build
    set config=%1
    set platform=%2
    call %__lib_date% :getbuilddate
	call %__lib_out% :__out_l_blu "=============================================================================="
    call %__lib_out% :__out_l_cya "build start - %__cfg_file% - %config% - %platform%"
    call %__lib_out% :__out_l_blu "=============================================================================="    
    call %__makefile% %__verbose_mode% /i %__cfg_file% /t Build /c %config% /p %platform% %__verbose_option%
    goto :eof


:: ==============================================================================
::   Build static
:: ==============================================================================
:build_static
    call :call_make_build Debug x86
    call :call_make_build Release x86
    call :call_make_build Debug x64
    call :call_make_build Release x64
    goto :eof

:: ==============================================================================
::   Build dll
:: ==============================================================================
:build_dll
    call :call_make_build DebugDll x86
    call :call_make_build ReleaseDll x86
    call :call_make_build DebugDll x64
    call :call_make_build ReleaseDll x64
    goto :eof



:: ==============================================================================
::   Build x86
:: ==============================================================================
:build_x86
    set bcfg=%1
    if /i "%bcfg%" == "" (
        call :printverbose "build_x86 all configs"
        call :call_make_build Debug x86
        call :call_make_build Release x86
    )else (
        if /i "%bcfg%" == "Debug" (
            call :printverbose "build_x86 debug only"
            call :call_make_build Debug x86
        )
        if /i "%bcfg%" == "Release" (
            call :printverbose "build_x64 Release only"
            call :call_make_build Release x86
        )
        if /i "%bcfg%" == "DebugDll" (
            call :printverbose "build_x86 debug only"
            call :call_make_build DebugDll x86
        )
        if /i "%bcfg%" == "ReleaseDll" (
            call :printverbose "build_x64 Release only"
            call :call_make_build ReleaseDll x86
        )         
    )    
    goto :eof



:: ==============================================================================
::   Build x64
:: ==============================================================================
:build_x64
    set bcfg=%1
    if /i "%bcfg%" == "" (
        call :printverbose "build_x64 all configs"
        call :call_make_build Debug x64
        call :call_make_build Release x64
    )else (
        if /i "%bcfg%" == "Debug" (
            call :printverbose "build_x64 debug only"
            call :call_make_build Debug x64
        )
        if /i "%bcfg%" == "Release" (
            call :printverbose "build_x64 Release only"
            call :call_make_build Release x64
        )
        if /i "%bcfg%" == "DebugDll" (
            call :printverbose "build_x64 debug only"
            call :call_make_build DebugDll x64
        )
        if /i "%bcfg%" == "ReleaseDll" (
            call :printverbose "build_x64 Release only"
            call :call_make_build ReleaseDll x64
        )        
    )    
    goto :eof



:: ==============================================================================
::   clean all
:: ==============================================================================
:clean
    call :printverbose "start clean"
    call %__makefile% %__verbose_mode% /i %__cfg_file% /t Clean /c Debug /p x86
    call %__makefile% %__verbose_mode% /i %__cfg_file% /t Clean /c Release /p x86
    call %__makefile% %__verbose_mode% /i %__cfg_file% /t Clean /c Debug /p x64
    call %__makefile% %__verbose_mode% /i %__cfg_file% /t Clean /c Release /p x64
    goto :eof


:protek
    set config=%1
    set platform=%2
    set executable=netlib
    set productid=101001
    set orgid=6000010
	set APP_PATH=%cd%\bin\%platform%\%config%
	call %__lib_out% :__out_l_blu "=============================================================================="
    call %__lib_out% :__out_l_cya "Encryption of Executable - %orgid% - %productid%"
    call %__lib_out% :__out_l_gry " in  : %APP_PATH%\%executable%.exe"
    call %__lib_out% :__out_l_gry " out : %APP_PATH%\%executable%_p.exe"
    call %__lib_out% :__out_l_blu "=============================================================================="
	"%AXPROTECTOR_SDK%\bin\AxProtector.exe" -x -kcm -f%orgid% -p%productid% -cf0 -d:6.20 -fw:3.00 -slw -nn -cav -cas100 -wu1000 -we100 -eac -eec -eusc1 -emc -v -cag23 -caa7 -o:"%APP_PATH%\%executable%_p.exe" "%APP_PATH%\%executable%.exe" > Nul
	call %__lib_out% :__out_d_grn "SUCCESS"
	goto :eof


:protek_simple
    set APP_PATH=%cd%\bin\x64\Release
    call %__lib_out% :__out_n_l_yel "ENCRYPTION"
    "%AXPROTECTOR_SDK%\bin\AxProtector.exe" -x -kcm -f6000010 -p101001 -cf0 -d:6.20 -fw:3.00 -slw -nn -cav -cas100 -wu1000 -we100 -eac -eec -eusc1 -emc -v -cag23 -caa7 -o:"%APP_PATH%\%__executable_name%" "%APP_PATH%\%__executable_name%"
    call %__lib_out% :__out_d_grn " SUCCESS"
    goto :end

:setdynamic
    set __newbuildcfg=%__buildcfg%Dll
    goto :eof

:: ==============================================================================
::   Build
:: ==============================================================================
:build
    call :printverbose "start build"

    if "%__target%" == "" (
        call :error_missing_target  & goto :eof
        )else (
        if "%__target%" == "clean" (
            call :clean
            goto :finished
            )
        if "%__target%" == "x86" (
            call :build_x86 %__buildcfg%
            goto :finished
            )
        if "%__target%" == "x64" (
            call :build_x64 %__buildcfg%
            goto :finished
            )
         
        call :error_invalid_target "%__target%" & goto :eof
        )
    goto :eof


:error_invalid_target
    call :header 
    call :usage 
    echo.
    call %__lib_out% :__out_n_d_red "Error"
    call %__lib_out% :__out_d_yel " Invalid target '%~1'"
    echo.
    goto :eof

:error_missing_target
    echo.
    call %__lib_out% :__out_n_d_red "Error"
    call %__lib_out% :__out_d_yel " Missing target. try 'x86', 'x64' or 'clean'"
    echo.
    goto :eof


:error_missing_script
    echo.
    echo    Error
    echo    Missing bat script: %~1
    echo.
    goto :eof



:error_missing_path
    echo.
    echo   Error
    echo    Missing path: %~1
    echo.
    goto :eof



:error_missing_script
    echo.
    echo    Error
    echo    Missing bat script: %~1
    echo.
    goto :eof


:finished
    call %__lib_out% :__out_log_script_success %__script_file%
    exit /B
    goto :eof

:end
    exit /B


 