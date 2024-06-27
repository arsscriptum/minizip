@echo off
setlocal EnableDelayedExpansion

:: ==============================================================================
:: 
::      ｂｕｉｌｄ．ｂａｔ
::
::      𝒸𝓊𝓈𝓉ℴ𝓂 𝒷𝓊𝒾𝓁𝒹 𝓈𝒸𝓇𝒾𝓅𝓉 𝒻ℴ𝓇 ℊℯ𝓉𝒶𝒹𝓂
::
:: ==============================================================================
::   arsccriptum - made in quebec 2020 <guillaumeplante.qc@gmail.com>
:: ==============================================================================

goto :init

:init
    set "__scripts_root=%AutomationScriptsRoot%"
    call :read_script_data development\build-automation  BuildAutomation
    set "__script_file=%~0"
    set "__target=%~1"
    set "__script_path=%~dp0"
    set "__makefile=%__scripts_root%\make\make.bat"
    set "__lib_date=%__scripts_root%\batlibs\date.bat"
    set "__lib_out=%__scripts_root%\batlibs\out.bat"
    ::*** This is the important line ***
    set "__build_cfg=%__script_path%buildcfg.ini"
    set "__build_cancelled=0"
    goto :validate


:header
    echo. %__script_name% v%__script_version%
    echo.    This script is part of Ars Scriptum build wrappers.
    echo.
    goto :eof

:header_err
    echo. ======================================================
    echo. = This script is part of Ars Scriptum build wrappers =
    echo. ======================================================
    echo.
    echo. YOU NEED TO HAVE THE BuildAutomation Scripts setup
    echo. on you system...
    echo. https://github.com/arsscriptum/BuildAutomation
    goto :eof


:read_script_data
    if not defined OrganizationHKCU::=          call :header_err && call :error_missing_path OrganizationHKCU::= & goto :eof
    set regpath=%OrganizationHKCU::=%
    for /f "tokens=2,*" %%A in ('REG.exe query %regpath%\%1 /v %2') do (
            set "__scripts_root=%%B"
        )
    goto :eof

:validate
    if not defined __scripts_root          call :header_err && call :error_missing_path __scripts_root & goto :eof
    if not exist %__makefile%  call :error_missing_script "%__makefile%" & goto :eof
    if not exist %__lib_date%  call :error_missing_script "%__lib_date%" & goto :eof
    if not exist %__lib_out%  call :error_missing_script "%__lib_out%" & goto :eof
    if not exist %__build_cfg%  call :error_missing_script "%__build_cfg%" & goto :eof
    goto :build


:: ==============================================================================
::   call make
:: ==============================================================================
:call_make_build
    set config=%1
    set platform=%2
    call %__lib_date% :getbuilddate
	call %__lib_out% :__out_l_blu "=============================================================================="
    call %__lib_out% :__out_l_cya "build start - %__build_cfg% - %config% - %platform%"
    call %__lib_out% :__out_l_blu "=============================================================================="    
    call %__makefile% /v /i %__build_cfg% /t Build /c %config% /p %platform%
    goto :finished


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
    call :call_make_build Debug x86
    call :call_make_build Release x86
    goto :eof

:: ==============================================================================
::   Build x64
:: ==============================================================================
:build_x64
    call :call_make_build Debug x64
    call :call_make_build Release x64
    goto :eof

:: ==============================================================================
::   Build x64 Debug
:: ==============================================================================
:build_x64_debug
    call :call_make_build Debug x64
    goto :eof


:: ==============================================================================
::   Build x64 Release
:: ==============================================================================
:build_x64_release
    call :call_make_build Release x64
    goto :eof

:: ==============================================================================
::   clean all
:: ==============================================================================
:clean
    call %__makefile% /v /i %__build_cfg% /t Clean /c Debug /p x86
    call %__makefile% /v /i %__build_cfg% /t Clean /c Release /p x86
    call %__makefile% /v /i %__build_cfg% /t Clean /c Debug /p x64
    call %__makefile% /v /i %__build_cfg% /t Clean /c Release /p x64
    goto :eof


:protek
    set config=%1
    set platform=%2
    set executable=corelib
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


:: ==============================================================================
::   Build
:: ==============================================================================
:build
    call %__lib_out% :__out_d_mag "deleting %cd%\bin"
    RMDIR /S /Q %cd%\bin
    call :build_static
    goto :finished


:finished
    ::call %__lib_out% :__out_l_cya "Finished"
    goto :eof

