Attribute VB_Name = "ProgressBars"
'***************************************************************************
'Miscellaneous Functions Related to the Progress Bar
'Copyright 2001-2017 by Tanner Helland
'Created: 6/12/01
'Last updated: 13/February/13
'Last update: Rewrite the progress bar code against an API progress bar on the main canvas object
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit


'API calls for our custom DoEvents replacement
Private Type winMsg
    hWnd As Long
    sysMsg As Long
    wParam As Long
    lParam As Long
    msgTime As Long
    ptX As Long
    ptY As Long
End Type

Private Declare Function TranslateMessage Lib "user32" (ByRef lpMsg As winMsg) As Long
Private Declare Function DispatchMessage Lib "user32" Alias "DispatchMessageA" (ByRef lpMsg As winMsg) As Long
Private Declare Function PeekMessage Lib "user32" Alias "PeekMessageA" (ByRef lpMsg As winMsg, ByVal hWnd As Long, ByVal wMsgFilterMin As Long, ByVal wMsgFilterMax As Long, ByVal wRemoveMsg As Long) As Long

'This object is used to render a system progress bar onto a given picture box
Private curProgBar As cProgressBarOfficial

'This function mimicks DoEvents, but instead of processing all messages for all windows on all threads (slow! error-prone!),
' it only processes messages for the supplied hWnd.
Public Sub Replacement_DoEvents(ByVal srcHwnd As Long)
    Dim tmpMsg As winMsg
    Do While PeekMessage(tmpMsg, srcHwnd, 0&, 0&, &H1&)
        TranslateMessage tmpMsg
        DispatchMessage tmpMsg
    Loop
End Sub

'These three routines make it easier to interact with the progress bar; note that two are disabled while a batch
' conversion is running - this is because the batch conversion tool appropriates the scroll bar.
Public Function GetProgBarMax() As Long
    If (Not curProgBar Is Nothing) Then GetProgBarMax = curProgBar.Max Else GetProgBarMax = 1
End Function

Public Sub SetProgBarMax(ByVal pbVal As Long)
    
    If (Macros.GetMacroStatus <> MacroBATCH) And (pbVal <> 0) Then
        
        Dim prevProgBarValue As Long
        
        'Create a new progress bar as necessary
        If (curProgBar Is Nothing) Then
            Set curProgBar = New cProgressBarOfficial
            
            'Assign the progress bar control to its container picture box on the primary canvas, then display it.
            With FormMain.mainCanvas(0).GetProgBarReference()
                curProgBar.CreateProgressBar .hWnd, 0, 0, .ScaleWidth, .ScaleHeight, True, False, False, True
                .Visible = True
            End With
            
            prevProgBarValue = 0
            
        Else
            prevProgBarValue = curProgBar.Value
        End If
        
        'Set max and min values
        curProgBar.Min = 0
        curProgBar.Max = pbVal
        
        'Set the progress bar's current value
        If (prevProgBarValue <= curProgBar.Max) Then
            curProgBar.Value = prevProgBarValue
        Else
            curProgBar.Value = 0
            curProgBar.Refresh
        End If
        
    End If
    
End Sub

Public Sub SetProgBarVal(ByVal pbVal As Long)
    
    If (Macros.GetMacroStatus <> MacroBATCH) Then
        
        If (Not curProgBar Is Nothing) Then
            curProgBar.Value = pbVal
            curProgBar.Refresh
            
            'Process some window messages on the main form, to prevent the dreaded "Not Responding" state
            ' when PD is in the midst of a long-running action.
            Replacement_DoEvents FormMain.hWnd
            
        End If
        
        'On Windows 7 (or later), we also update the taskbar to reflect the current progress
        If OS.IsWin7OrLater Then OS.SetTaskbarProgressValue pbVal, GetProgBarMax
        
    End If
    
End Sub

'We only want the progress bar updating when necessary, so this function finds a power of 2 closest to the progress bar
' maximum divided by 20.  This is a nice compromise between responsive progress bar updates and extremely fast rendering.
Public Function FindBestProgBarValue() As Long

    'First, figure out what the range of this operation will be, based on the current progress bar maximum
    Dim progBarRange As Double
    progBarRange = CDbl(GetProgBarMax())
    
    'Divide that value by some arbitrary number; the number is how many times we want the progress bar to update during
    ' the current process.  (e.g. a value of "10" means "try to update the progress bar ~10 times")  Larger numbers
    ' mean more visual updates, at some minor cost to performance.
    progBarRange = progBarRange / 18
    
    'Find the nearest power of two to that value, rounded down.  (We do this so that we can simply && the result on inner
    ' pixel processing loops, which is much faster than a modulo operation.)
    Dim nearestP2 As Long
    nearestP2 = Log(progBarRange) / Log(2#)
    FindBestProgBarValue = (2 ^ nearestP2) - 1
    
End Function

'When a function is done with the progress bar, this function must be called to free up its memory and hide the associated picture box
Public Sub ReleaseProgressBar()
    
    #If DEBUGMODE = 1 Then
        pdDebug.LogAction "Releasing progress bar..."
    #End If

    'Briefly display a full progress bar before exiting
    If (Not curProgBar Is Nothing) Then
        curProgBar.Value = curProgBar.Max
        curProgBar.Refresh
    
        'Release the progress bar and container picture box
        FormMain.mainCanvas(0).GetProgBarReference.Visible = False
        Set curProgBar = Nothing
        
    End If
    
    'On Win 7+, also reset the taskbar progress indicator
    If OS.IsWin7OrLater Then OS.SetTaskbarProgressState TBP_NoProgress
    
End Sub
