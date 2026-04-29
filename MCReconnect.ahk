; MCReconnect.ahk
; Minecraft AFK Kick Auto-Reconnector
; AHK v1 - Compile with Ahk2Exe to a standalone EXE (no AHK install needed)
; Settings are session-only - nothing written to disk.

#NoEnv
#SingleInstance Force
#Persistent
SetWorkingDir %A_ScriptDir%
SendMode Input
SetTitleMatchMode, 2

; ============================================================
;  GLOBALS
; ============================================================
global g_Running             := false
global g_WizardActive        := false
global g_WizardTarget        := ""
global g_WizardHotkey        := "F8"
global g_ProcessName         := ""
global g_WindowMode          := "Windowed"
global g_EffectiveTotalTime  := 0
global g_StartTime           := 0

global g_ReconnDelay    := 5000
global g_ReconnVariance := 2000
global g_ReconnVarOn    := true
global g_TotalTime      := 0
global g_TotalVariance  := 60000
global g_TotalVarOn     := true

; Detection arrays (up to 5 rows, AND gate)
global g_DetectX     := []
global g_DetectY     := []
global g_DetectColor := []
Loop 5 {
    g_DetectX[A_Index]     := 0
    g_DetectY[A_Index]     := 0
    g_DetectColor[A_Index] := "0xFFFFFF"
}

; Reconnect flow step arrays (up to 8 rows)
global g_StepType := []
global g_StepX    := []
global g_StepY    := []
global g_StepWait := []
Loop 8 {
    g_StepType[A_Index] := "Click"
    g_StepX[A_Index]    := 0
    g_StepY[A_Index]    := 0
    g_StepWait[A_Index] := 500
}
; Default step types for first 3 rows
g_StepType[1] := "Click"     ; Back to title / dismiss disconnect
g_StepType[2] := "DblClick"  ; Multiplayer button
g_StepType[3] := "DblClick"  ; Server in list

; Process picker list (populated at runtime)
global g_PickerList := []

; ============================================================
;  BUILD MAIN GUI
; ============================================================
Gui, Main:+AlwaysOnTop
Gui, Main:+LastFound
Gui, Main:Font, s9, Segoe UI

; --- Process ---
Gui, Main:Add, GroupBox, x8 y5 w460 h52, Process
Gui, Main:Add, Text,     x16 y24 w60,    Process:
Gui, Main:Add, Edit,     x75 y22 w285    vCtrl_ProcessName,
Gui, Main:Add, Button,   x364 y20 w96    gBtn_PickProcess, Pick Process...

; --- Window Mode ---
Gui, Main:Add, GroupBox, x8 y60 w460 h52, Window Mode
Gui, Main:Add, Text,     x16 y78, Mode:
Gui, Main:Add, Radio,    x52 y77 vCtrl_WinWindowed   gEvt_WinMode +Group Checked, Windowed
Gui, Main:Add, Radio,    x125 y77 vCtrl_WinBorderless gEvt_WinMode,               Borderless
Gui, Main:Add, Radio,    x210 y77 vCtrl_WinFullscreen gEvt_WinMode,               Fullscreen (unreliable)
Gui, Main:Add, Text,     x16 y94 w450 cRed vCtrl_FullscreenWarn +Hidden, ! AHK pixel functions are unreliable in exclusive fullscreen. Use Windowed or Borderless.

; --- Wizard Hotkey ---
Gui, Main:Add, GroupBox, x8 y115 w460 h42, Wizard Capture Hotkey
Gui, Main:Add, Text,     x16 y132, Hotkey:
Gui, Main:Add, Edit,     x62 y130 w70 vCtrl_WizardHotkey, F8
Gui, Main:Add, Text,     x140 y132 w325 cGray, (While wizard is active: hover over the pixel/button and press this key)

; --- Kick Detection ---
Gui, Main:Add, GroupBox, x8 y160 w460 h178, Kick Detection  [AND gate - all enabled rows must match]
Gui, Main:Add, Text,     x14  y178 w18,  #
Gui, Main:Add, Text,     x34  y178 w48,  X (rel)
Gui, Main:Add, Text,     x86  y178 w48,  Y (rel)
Gui, Main:Add, Text,     x138 y178 w90,  Color (0xRRGGBB)
Gui, Main:Add, Text,     x232 y178 w50,  Tolerance
Gui, Main:Add, Text,     x285 y178 w110, Actions
Gui, Main:Add, Text, x400 y178 w28, On
Gui, Main:Add, CheckBox, x400 y199 w24 vDetEnable1 gEvt_DetEn1 Checked,
Gui, Main:Add, CheckBox, x400 y223 w24 vDetEnable2 gEvt_DetEn2,
Gui, Main:Add, CheckBox, x400 y247 w24 vDetEnable3 gEvt_DetEn3,
Gui, Main:Add, CheckBox, x400 y271 w24 vDetEnable4 gEvt_DetEn4,
Gui, Main:Add, CheckBox, x400 y295 w24 vDetEnable5 gEvt_DetEn5,

Loop 5 {
    row := A_Index
    yy  := 175 + (row * 24)
    Gui, Main:Add, Text,     x14  y%yy% w18,  %row%
    Gui, Main:Add, Edit,     x34  y%yy% w48   vDetX%row%,     0
    Gui, Main:Add, Edit,     x86  y%yy% w48   vDetY%row%,     0
    Gui, Main:Add, Edit,     x138 y%yy% w90   vDetColor%row%, 0xFFFFFF
    Gui, Main:Add, Edit,     x232 y%yy% w46   vDetTol%row%,   10
    Gui, Main:Add, Button,   x282 y%yy% w58   gBtn_DetWiz%row%, Capture
    Gui, Main:Add, Button,   x344 y%yy% w52   gBtn_DetTest%row%, Test
}

; --- Reconnect Flow Steps ---
Gui, Main:Add, GroupBox, x8 y342 w460 h228, Reconnect Flow Steps
Gui, Main:Add, Text,     x14  y360 w18,  #
Gui, Main:Add, Text,     x34  y360 w74,  Action
Gui, Main:Add, Text,     x112 y360 w48,  X (rel)
Gui, Main:Add, Text,     x164 y360 w48,  Y (rel)
Gui, Main:Add, Text,     x216 y360 w84,  Wait After (ms)
Gui, Main:Add, Text,     x304 y360 w58,  Capture
Gui, Main:Add, Text,     x366 y360 w28,  On

Loop 8 {
    row := A_Index
    yy  := 357 + (row * 24)
    Gui, Main:Add, Text,          x14  y%yy% w18,  %row%
    Gui, Main:Add, DropDownList,  x34  y%yy% w74   vStepType%row%, Click||DblClick|Wait
    Gui, Main:Add, Edit,          x112 y%yy% w48   vStepX%row%,    0
    Gui, Main:Add, Edit,          x164 y%yy% w48   vStepY%row%,    0
    Gui, Main:Add, Edit,          x216 y%yy% w84   vStepWait%row%, 500
    Gui, Main:Add, Button,        x304 y%yy% w58   gBtn_StepWiz%row%, Capture
}
; Step row checkboxes (outside loop for literal g-labels)
Gui, Main:Add, Text,     x366 y360 w28, On
Gui, Main:Add, CheckBox, x366 y381 w24 vStepEnable1 gEvt_StepEn1 Checked,
Gui, Main:Add, CheckBox, x366 y405 w24 vStepEnable2 gEvt_StepEn2 Checked,
Gui, Main:Add, CheckBox, x366 y429 w24 vStepEnable3 gEvt_StepEn3 Checked,
Gui, Main:Add, CheckBox, x366 y453 w24 vStepEnable4 gEvt_StepEn4,
Gui, Main:Add, CheckBox, x366 y477 w24 vStepEnable5 gEvt_StepEn5,
Gui, Main:Add, CheckBox, x366 y501 w24 vStepEnable6 gEvt_StepEn6,
Gui, Main:Add, CheckBox, x366 y525 w24 vStepEnable7 gEvt_StepEn7,
Gui, Main:Add, CheckBox, x366 y549 w24 vStepEnable8 gEvt_StepEn8,
; Set default dropdown selections (row 1 = Click, rows 2-3 = DblClick)
GuiControl, Main:Choose, StepType1, 1
GuiControl, Main:Choose, StepType2, 2
GuiControl, Main:Choose, StepType3, 2

; --- Timing ---
Gui, Main:Add, GroupBox, x8 y574 w460 h88, Timing
Gui, Main:Add, Text,     x16 y591 w132, Reconnect Delay (ms):
Gui, Main:Add, Edit,     x150 y589 w80  vCtrl_ReconnDelay, 5000
Gui, Main:Add, CheckBox, x240 y591      vCtrl_ReconnVarOn gEvt_ReconnVarOn Checked, Variance (ms):
Gui, Main:Add, Edit,     x340 y589 w80  vCtrl_ReconnVariance, 2000

Gui, Main:Add, Text,     x16 y617 w132, Total Runtime (ms):
Gui, Main:Add, Edit,     x150 y615 w80  vCtrl_TotalTime gEvt_TotalTimeChanged, 0
Gui, Main:Add, Text,     x240 y617 w100 cGray, (0 = run forever)
Gui, Main:Add, CheckBox, x345 y617      vCtrl_TotalVarOn gEvt_TotalVarOn Checked, Variance (ms):

Gui, Main:Add, Text,     x16 y641 w132, Total Variance (ms):
Gui, Main:Add, Edit,     x150 y639 w80  vCtrl_TotalVariance,  60000

; --- Control ---
Gui, Main:Add, GroupBox, x8 y666 w460 h58, Control
Gui, Main:Add, Button,   x16 y682 w100 h34 gBtn_Play,  Play
Gui, Main:Add, Button,   x122 y682 w100 h34 gBtn_Stop, Stop
GuiControl, Main:Disable, Btn_Stop
Gui, Main:Add, Text,     x232 y690 w232 vCtrl_Status cGray, Status: Idle

Gui, Main:Show, w478 h730, MCReconnect - Minecraft Auto-Reconnector

; Initial grey-out state for unchecked rows
; Detection rows 2-5 start disabled (checkbox unchecked)
Loop 5 {
    if (A_Index > 1)
        ToggleDetRow(A_Index)
}
; Step rows 4-8 start disabled
Loop 8 {
    if (A_Index > 3)
        ToggleStepRow(A_Index)
}
; Reconnect Variance: checkbox starts checked, explicitly enable its edit field
GuiControl, Main:Enable, Ctrl_ReconnVariance
; Total Time starts at 0, so variance controls are greyed out
GuiControl, Main:Disable, Ctrl_TotalVarOn
GuiControl, Main:Disable, Ctrl_TotalVariance
return

; ============================================================
;  WINDOW MODE RADIO
; ============================================================
Evt_WinMode:
    Gui, Main:Submit, NoHide
    if (Ctrl_WinWindowed) {
        g_WindowMode := "Windowed"
        GuiControl, Main:Hide, Ctrl_FullscreenWarn
    } else if (Ctrl_WinBorderless) {
        g_WindowMode := "Borderless"
        GuiControl, Main:Hide, Ctrl_FullscreenWarn
    } else {
        g_WindowMode := "Fullscreen"
        GuiControl, Main:Show, Ctrl_FullscreenWarn
    }
return

; ============================================================
;  PROCESS PICKER
; ============================================================
Btn_PickProcess:
    WinGet, winList, List
    g_PickerList := []
    seen := {}
    Loop %winList% {
        hwnd  := winList%A_Index%
        WinGetTitle, wtitle, ahk_id %hwnd%
        WinGet,      wproc,  ProcessName, ahk_id %hwnd%
        if (wtitle = "" || wproc = "")
            continue
        key := wproc . "|" . wtitle
        if (seen[key])
            continue
        seen[key] := 1
        g_PickerList.Push({proc: wproc, title: wtitle})
    }

    Gui, Picker:+AlwaysOnTop
    Gui, Picker:Font, s9, Segoe UI
    Gui, Picker:Add, Text, x8 y8, Select the Minecraft game window:
    Gui, Picker:Add, ListView, x8 y26 w500 h340 vPickerLV gPickerDblClick +LV0x1, Process Name|Window Title
    Loop % g_PickerList.Length() {
        item := g_PickerList[A_Index]
        LV_Add("", item.proc, item.title)
    }
    LV_ModifyCol(1, 140)
    LV_ModifyCol(2, 340)
    Gui, Picker:Add, Button, x8   y374 w80 gBtn_PickerOK,     OK
    Gui, Picker:Add, Button, x96  y374 w80 gBtn_PickerCancel, Cancel
    Gui, Picker:Show, w520 h408, Select Process
return

PickerDblClick:
    gosub Btn_PickerOK
return

Btn_PickerOK:
    row := LV_GetNext(0, "Focused")
    if (row < 1) {
        MsgBox, 48, No Selection, Please click a row to select it first.
        return
    }
    item := g_PickerList[row]
    g_ProcessName := item.proc
    GuiControl, Main:, Ctrl_ProcessName, % item.proc
    Gui, Picker:Destroy
return

Btn_PickerCancel:
PickerGuiClose:
    Gui, Picker:Destroy
return

; ============================================================
;  WIZARD SYSTEM
; ============================================================
; Capture buttons for Detection rows
Btn_DetWiz1:
    SetWizardTarget("Det1")
return
Btn_DetWiz2:
    SetWizardTarget("Det2")
return
Btn_DetWiz3:
    SetWizardTarget("Det3")
return
Btn_DetWiz4:
    SetWizardTarget("Det4")
return
Btn_DetWiz5:
    SetWizardTarget("Det5")
return

; Capture buttons for Step rows
Btn_StepWiz1:
    SetWizardTarget("Step1")
return
Btn_StepWiz2:
    SetWizardTarget("Step2")
return
Btn_StepWiz3:
    SetWizardTarget("Step3")
return
Btn_StepWiz4:
    SetWizardTarget("Step4")
return
Btn_StepWiz5:
    SetWizardTarget("Step5")
return
Btn_StepWiz6:
    SetWizardTarget("Step6")
return
Btn_StepWiz7:
    SetWizardTarget("Step7")
return
Btn_StepWiz8:
    SetWizardTarget("Step8")
return

SetWizardTarget(target) {
    global g_Running, g_WizardActive, g_WizardTarget, g_WizardHotkey
    if (g_Running) {
        MsgBox, 48, Bot Running, Stop the bot before using the wizard.
        return
    }
    if (g_WizardActive) {
        ; Cancel previous wizard first
        try Hotkey, % g_WizardHotkey, WizardCapture, Off
        g_WizardActive := false
    }
    Gui, Main:Submit, NoHide
    hk := Trim(Ctrl_WizardHotkey)
    if (hk = "")
        hk := "F8"
    g_WizardHotkey := hk
    g_WizardTarget := target
    g_WizardActive := true
    Hotkey, %hk%, WizardCapture, On
    SetStatus("Wizard active for [" . target . "] - hover and press " . hk . " to capture. Press Esc to cancel.")
}

WizardCapture:
    if (!g_WizardActive)
        return
    MouseGetPos, mx, my
    hwnd := GetGameHWND()
    if (!hwnd) {
        MsgBox, 48, No Window, Game window not found. Set the process name first.
        g_WizardActive := false
        Hotkey, % g_WizardHotkey, WizardCapture, Off
        SetStatus("Wizard cancelled - window not found.")
        return
    }
    WinGetPos, wx, wy, , , ahk_id %hwnd%
    rx := mx - wx
    ry := my - wy
    PixelGetColor, col, mx, my, RGB

    target := g_WizardTarget
    if (SubStr(target, 1, 3) = "Det") {
        row := SubStr(target, 4)
        GuiControl, Main:, DetX%row%,     %rx%
        GuiControl, Main:, DetY%row%,     %ry%
        GuiControl, Main:, DetColor%row%, %col%
        GuiControl, Main:, DetEnable%row%, 1
    } else if (SubStr(target, 1, 4) = "Step") {
        row := SubStr(target, 5)
        GuiControl, Main:, StepX%row%, %rx%
        GuiControl, Main:, StepY%row%, %ry%
        GuiControl, Main:, StepEnable%row%, 1
    }
    g_WizardActive := false
    Hotkey, % g_WizardHotkey, WizardCapture, Off
    SetStatus("Captured (" . rx . ", " . ry . ")  Color: " . col . "  for [" . target . "]")
return

; Cancel wizard with Escape
~Escape::
    if (g_WizardActive) {
        g_WizardActive := false
        try Hotkey, % g_WizardHotkey, WizardCapture, Off
        SetStatus("Wizard cancelled.")
    }
return

; ============================================================
;  DETECTION TEST BUTTONS
; ============================================================
Btn_DetTest1:
    TestDetRow(1)
return
Btn_DetTest2:
    TestDetRow(2)
return
Btn_DetTest3:
    TestDetRow(3)
return
Btn_DetTest4:
    TestDetRow(4)
return
Btn_DetTest5:
    TestDetRow(5)
return

TestDetRow(row) {
    hwnd := GetGameHWND()
    if (!hwnd) {
        MsgBox, 48, No Window, Game window not found.
        return
    }
    WinGetPos, wx, wy, , , ahk_id %hwnd%
    rx  := GetCtrlVal("DetX"     . row) + 0
    ry  := GetCtrlVal("DetY"     . row) + 0
    exp := GetCtrlVal("DetColor" . row)
    tol := GetCtrlVal("DetTol"   . row) + 0
    sx  := rx + wx
    sy  := ry + wy
    PixelGetColor, actual, sx, sy, RGB
    match := ColorMatch(actual, exp, tol)
    result := match ? "YES - MATCH" : "NO - no match"
    MsgBox, 64, Detection Test Row %row%, Position (rel): %rx%, %ry%`nExpected color: %exp%`nActual color:   %actual%`nTolerance: %tol%`n`nResult: %result%
}

; ============================================================
;  PLAY / STOP
; ============================================================
Btn_Play:
    if (g_Running) {
        SetStatus("Already running.")
        return
    }
    Gui, Main:Submit, NoHide
    ReadGUISettings()
    if (g_ProcessName = "") {
        MsgBox, 48, No Process, Please set the game process name first (use Pick Process).
        return
    }
    if (!GetGameHWND()) {
        MsgBox, 48, Window Not Found, The game window was not found. Make sure the game is running.
        return
    }
    g_Running              := true
    g_StartTime            := A_TickCount
    g_EffectiveTotalTime   := 0
    SetStatus("Status: Running - monitoring for kick...")
    GuiControl, Main:Disable, Btn_Play
    GuiControl, Main:Enable,  Btn_Stop
    SetTimer, BotTick, 1000
return

Btn_Stop:
    StopBot("Stopped by user.")
return

StopBot(reason = "Stopped.") {
    global g_Running, g_WizardActive, g_WizardHotkey
    if (!g_Running && !g_WizardActive)
        return
    g_Running      := false
    g_WizardActive := false
    try Hotkey, % g_WizardHotkey, WizardCapture, Off
    SetTimer, BotTick, Off
    SetStatus("Status: " . reason)
    GuiControl, Main:Enable,  Btn_Play
    GuiControl, Main:Disable, Btn_Stop
}

; ============================================================
;  BOT TICK  (every 1 second)
; ============================================================
BotTick:
    if (!g_Running)
        return

    ; --- Total runtime check ---
    if (g_TotalTime > 0) {
        if (!g_EffectiveTotalTime) {
            if (g_TotalVarOn && g_TotalVariance > 0) {
                Random, rvar, 0, % g_TotalVariance * 2
                variance := rvar - g_TotalVariance
            } else {
                variance := 0
            }
            g_EffectiveTotalTime := g_TotalTime + variance
            if (g_EffectiveTotalTime < 1000)
                g_EffectiveTotalTime := 1000
        }
        elapsed := A_TickCount - g_StartTime
        if (elapsed >= g_EffectiveTotalTime) {
            StopBot("Total runtime reached - auto stopped.")
            return
        }
    }

    ; --- Kick detection ---
    if (IsKickDetected()) {
        SetTimer, BotTick, Off
        SetStatus("Status: Kick detected! Waiting to reconnect...")

        ; Reconnect delay with optional variance
        delay := g_ReconnDelay
        if (g_ReconnVarOn && g_ReconnVariance > 0) {
            Random, rdel, 0, % g_ReconnVariance * 2
            delay += rdel - g_ReconnVariance
        }
        if (delay < 0)
            delay := 0

        Sleep, %delay%

        if (!g_Running)
            return

        SetStatus("Status: Reconnecting...")
        RunReconnectFlow()

        if (g_Running) {
            SetStatus("Status: Running - monitoring for kick...")
            SetTimer, BotTick, 1000
        }
    }
return

; ============================================================
;  KICK DETECTION
; ============================================================
IsKickDetected() {
    global g_DetectX, g_DetectY, g_DetectColor
    hwnd := GetGameHWND()
    if (!hwnd)
        return false
    WinGetPos, wx, wy, , , ahk_id %hwnd%

    ; AND gate: every enabled row must match
    anyEnabled := false
    Loop 5 {
        row := A_Index
        ena := GetCtrlVal("DetEnable" . row)
        if (!ena)
            continue
        anyEnabled := true
        sx  := g_DetectX[row]     + wx
        sy  := g_DetectY[row]     + wy
        exp := g_DetectColor[row]
        tol := GetCtrlVal("DetTol" . row) + 0
        PixelGetColor, actual, sx, sy, RGB
        if (!ColorMatch(actual, exp, tol))
            return false
    }
    return anyEnabled  ; return false if nothing is enabled (prevents false trigger)
}

; ============================================================
;  RECONNECT FLOW
; ============================================================
RunReconnectFlow() {
    global g_StepType, g_StepX, g_StepY, g_StepWait
    hwnd := GetGameHWND()
    if (!hwnd) {
        SetStatus("Status: Game window lost during reconnect!")
        return
    }

    Loop 8 {
        row := A_Index
        if (!GetCtrlVal("StepEnable" . row))
            continue
        if (!g_Running)
            return

        WinGetPos, wx, wy, , , ahk_id %hwnd%
        ax   := g_StepX[row]    + wx
        ay   := g_StepY[row]    + wy
        typ  := g_StepType[row]
        wms  := g_StepWait[row]

        if (typ = "Click") {
            Click, %ax%, %ay%
        } else if (typ = "DblClick") {
            Click, %ax%, %ay%
            Sleep, 80
            Click, %ax%, %ay%
        }
        ; "Wait" type: just does the sleep below, no click

        Sleep, %wms%
    }
}

; ============================================================
;  HELPERS
; ============================================================
GetGameHWND() {
    global g_ProcessName
    if (g_ProcessName = "")
        return 0
    WinGet, hwnd, ID, ahk_exe %g_ProcessName%
    return hwnd + 0
}

ReadGUISettings() {
    global g_ProcessName, g_ReconnDelay, g_ReconnVariance, g_ReconnVarOn
    global g_TotalTime, g_TotalVariance, g_TotalVarOn
    global g_DetectX, g_DetectY, g_DetectColor
    global g_StepType, g_StepX, g_StepY, g_StepWait
    Gui, Main:Submit, NoHide

    g_ProcessName    := Ctrl_ProcessName
    g_ReconnDelay    := Ctrl_ReconnDelay    + 0
    g_ReconnVariance := Ctrl_ReconnVariance + 0
    g_ReconnVarOn    := Ctrl_ReconnVarOn    + 0
    g_TotalTime      := Ctrl_TotalTime      + 0
    g_TotalVariance  := Ctrl_TotalVariance  + 0
    g_TotalVarOn     := Ctrl_TotalVarOn     + 0

    if (g_ReconnDelay    < 0) g_ReconnDelay    := 0
    if (g_ReconnVariance < 0) g_ReconnVariance := 0
    if (g_TotalTime      < 0) g_TotalTime      := 0
    if (g_TotalVariance  < 0) g_TotalVariance  := 0

    Loop 5 {
        row := A_Index
        g_DetectX[row]     := GetCtrlVal("DetX"     . row) + 0
        g_DetectY[row]     := GetCtrlVal("DetY"     . row) + 0
        g_DetectColor[row] := GetCtrlVal("DetColor" . row)
    }
    Loop 8 {
        row  := A_Index
        ddl  := GetCtrlVal("StepType" . row)   ; returns selected text from DDL
        g_StepType[row] := ddl
        g_StepX[row]    := GetCtrlVal("StepX"    . row) + 0
        g_StepY[row]    := GetCtrlVal("StepY"    . row) + 0
        g_StepWait[row] := GetCtrlVal("StepWait" . row) + 0
        if (g_StepWait[row] < 0)
            g_StepWait[row] := 0
    }
}

GetCtrlVal(ctrlName) {
    GuiControlGet, val, Main:, %ctrlName%
    return val
}

ColorMatch(actual, expected, tolerance) {
    ; Normalise: ensure both have 0x prefix, then convert to integer
    if (SubStr(actual, 1, 2) != "0x")
        actual := "0x" . actual
    if (SubStr(expected, 1, 2) != "0x")
        expected := "0x" . expected
    a := actual   + 0
    e := expected + 0
    aR := (a >> 16) & 0xFF
    aG := (a >>  8) & 0xFF
    aB :=  a        & 0xFF
    eR := (e >> 16) & 0xFF
    eG := (e >>  8) & 0xFF
    eB :=  e        & 0xFF
    tol := tolerance + 0
    return (Abs(aR-eR) <= tol && Abs(aG-eG) <= tol && Abs(aB-eB) <= tol)
}

SetStatus(msg) {
    GuiControl, Main:, Ctrl_Status, %msg%
}

; ============================================================
;  CHECKBOX / EDIT CHANGE HANDLERS
; ============================================================

; --- Reconnect Variance toggle ---
Evt_ReconnVarOn:
    GuiControlGet, state, Main:, Ctrl_ReconnVarOn
    if (state)
        GuiControl, Main:Enable,  Ctrl_ReconnVariance
    else
        GuiControl, Main:Disable, Ctrl_ReconnVariance
return

; --- Total Time change: grey out variance controls when 0 ---
Evt_TotalTimeChanged:
    GuiControlGet, val, Main:, Ctrl_TotalTime
    if (val = "" or val = 0) {
        GuiControl, Main:Disable, Ctrl_TotalVarOn
        GuiControl, Main:Disable, Ctrl_TotalVariance
        GuiControl, Main:, Ctrl_TotalVarOn, 0
    } else {
        GuiControl, Main:Enable, Ctrl_TotalVarOn
        GuiControl, Main:, Ctrl_TotalVarOn, 1
        GuiControl, Main:Enable, Ctrl_TotalVariance
    }
return

; --- Total Variance toggle ---
Evt_TotalVarOn:
    GuiControlGet, state, Main:, Ctrl_TotalVarOn
    if (state)
        GuiControl, Main:Enable,  Ctrl_TotalVariance
    else
        GuiControl, Main:Disable, Ctrl_TotalVariance
return

; --- Detection row checkbox handlers ---
Evt_DetEn1:
    ToggleDetRow(1)
return
Evt_DetEn2:
    ToggleDetRow(2)
return
Evt_DetEn3:
    ToggleDetRow(3)
return
Evt_DetEn4:
    ToggleDetRow(4)
return
Evt_DetEn5:
    ToggleDetRow(5)
return

; --- Step row checkbox handlers ---
Evt_StepEn1:
    ToggleStepRow(1)
return
Evt_StepEn2:
    ToggleStepRow(2)
return
Evt_StepEn3:
    ToggleStepRow(3)
return
Evt_StepEn4:
    ToggleStepRow(4)
return
Evt_StepEn5:
    ToggleStepRow(5)
return
Evt_StepEn6:
    ToggleStepRow(6)
return
Evt_StepEn7:
    ToggleStepRow(7)
return
Evt_StepEn8:
    ToggleStepRow(8)
return

ToggleDetRow(row) {
    GuiControlGet, state, Main:, DetEnable%row%
    if (state) {
        GuiControl, Main:Enable,  DetX%row%
        GuiControl, Main:Enable,  DetY%row%
        GuiControl, Main:Enable,  DetColor%row%
        GuiControl, Main:Enable,  DetTol%row%
        GuiControl, Main:Enable,  Btn_DetWiz%row%
        GuiControl, Main:Enable,  Btn_DetTest%row%
    } else {
        GuiControl, Main:Disable, DetX%row%
        GuiControl, Main:Disable, DetY%row%
        GuiControl, Main:Disable, DetColor%row%
        GuiControl, Main:Disable, DetTol%row%
        GuiControl, Main:Disable, Btn_DetWiz%row%
        GuiControl, Main:Disable, Btn_DetTest%row%
    }
}

ToggleStepRow(row) {
    GuiControlGet, state, Main:, StepEnable%row%
    if (state) {
        GuiControl, Main:Enable,  StepType%row%
        GuiControl, Main:Enable,  StepX%row%
        GuiControl, Main:Enable,  StepY%row%
        GuiControl, Main:Enable,  StepWait%row%
        GuiControl, Main:Enable,  Btn_StepWiz%row%
    } else {
        GuiControl, Main:Disable, StepType%row%
        GuiControl, Main:Disable, StepX%row%
        GuiControl, Main:Disable, StepY%row%
        GuiControl, Main:Disable, StepWait%row%
        GuiControl, Main:Disable, Btn_StepWiz%row%
    }
}

; ============================================================
;  GUI CLOSE
; ============================================================
MainGuiClose:
    StopBot("Exiting.")
    ExitApp
return
