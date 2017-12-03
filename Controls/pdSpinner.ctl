VERSION 5.00
Begin VB.UserControl pdSpinner 
   BackColor       =   &H80000005&
   ClientHeight    =   420
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   1125
   DrawStyle       =   5  'Transparent
   BeginProperty Font 
      Name            =   "Tahoma"
      Size            =   8.25
      Charset         =   0
      Weight          =   400
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   HasDC           =   0   'False
   ScaleHeight     =   28
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   75
   ToolboxBitmap   =   "pdSpinner.ctx":0000
End
Attribute VB_Name = "pdSpinner"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon Spinner (formerly Text+UpDown) custom control
'Copyright 2013-2017 by Tanner Helland
'Created: 19/April/13
'Last updated: 27/February/17
'Last update: extend "significant digits" property to support any arbitrary precision
'
'Software like PhotoDemon requires a lot of controls.  Ideally, every setting should be adjustable by at least
' two mechanisms: direct text entry, and some kind of slider or scroll bar, which allows for a quick method to
' make both large and small adjustments to a given parameter.
'
'Historically, I accomplished this by providing a scroll bar and text box for every parameter in the program.
' This got the job done, but it had a number of limitations - such as requiring an enormous amount of time if
' changes ever needed to be made, and custom code being required in every form to handle text / scroll synching.
'
'In April 2013, I finally did the smart thing and built a custom text/scroll user control.  This effectively
' replaces all other text/scroll combos in the program.
'
'This control handles the following things automatically:
' 1) Synching of text and spinner values
' 2) Validation of text entries, including a function for external validation requests
' 3) Locale handling (so that both comma and decimal can be supported as valid input)
' 4) A single "Change" event that fires for either scroll or text changes, and only if a text change is valid
' 5) Support for floating-point values, with automatic formatting as relevant
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'This object can raise a Change event (which triggers when the Value property is changed by ANY means) as well as a
' an event I call "FinalChange".  FinalChange triggers under the same conditions as Change, *EXCEPT* when the mouse
' button is held down over one of the spinners.  FinalChange will not fire until the mouse button is released, which
' makes it ideal for things like syncing time-consuming UI elements.
Public Event Change()
Public Event FinalChange()
Public Event ResetClick()
Public Event Resize()
Public Event GotFocusAPI()
Public Event LostFocusAPI()

'The actual common control edit box is handled by a dedicated class
Private WithEvents m_EditBox As pdEditBoxW
Attribute m_EditBox.VB_VarHelpID = -1

'User control support class.  Historically, many classes (and associated subclassers) were required by each user control,
' but I've since attempted to wrap these into a single master control support class.
Private WithEvents ucSupport As pdUCSupport
Attribute ucSupport.VB_VarHelpID = -1

'Some mouse states relative to the edit box are tracked, so we can render custom borders around the embedded box
Private m_MouseOverEditBox As Boolean

'Tracking focus is a little sketchy for this control, as it represents a mix of API windows and VB windows.  When a
' component window receives input, m_FocusCount is incremented by 1.  If a component loses input, m_FocusCount is
' decremented by 1.  The EvaluateFocusCount() function converts m_FocusCount into a simpler m_HasFocus bool, so make
' sure to call it whenever m_FocusCount changes.
Private m_FocusCount As Long, m_HasFocus As Boolean
Private m_InternalResizeState As Boolean

'Used to track value, min, and max values with extreme precision
Private m_Value As Double, m_Min As Double, m_Max As Double

'The number of significant digits used by this control.  0 means integer values.
Private m_SigDigits As Long

'As of 7.0, all spinners now support a "default value" property
Private m_DefaultValue As Double

'If the text box initiates a value change, we must track that so as to not overwrite the user's entry mid-typing
Private m_TextBoxInitiated As Boolean

'To simplify mouse_down handling, resize events fill four rects: one for the "reset" button, one for the "up" spin
' button, one for the "down" spin button, and one for the edit box itself.  Use these for simplified hit-detection.
Private m_ResetRect As RectF, m_UpRect As RectF, m_DownRect As RectF, m_EditBoxRect As RectF

'Mouse state for the various button areas
Private m_MouseDownUpButton As Boolean, m_MouseDownDownButton As Boolean
Private m_MouseOverUpButton As Boolean, m_MouseOverDownButton As Boolean, m_MouseOverResetButton As Boolean
Private m_MouseDownResetButton As Boolean, m_MouseUpResetButton As Boolean

'To mimic standard scroll bar behavior on the spin buttons, we repeat scroll events when the buttons are clicked
' and held.
Private WithEvents m_UpButtonTimer As pdTimer
Attribute m_UpButtonTimer.VB_VarHelpID = -1
Private WithEvents m_DownButtonTimer As pdTimer
Attribute m_DownButtonTimer.VB_VarHelpID = -1

'When the current control value is invalid, this is set to TRUE
Private m_ErrorState As Boolean

'2D painting support classes
Private m_Painter As pd2DPainter

'Local list of themable colors.  This list includes all potential colors used by the control, regardless of state change
' or internal control settings.  The list is updated by calling the UpdateColorList function.
' (Note also that this list does not include variants, e.g. "BorderColor" vs "BorderColor_Hovered".  Variant values are
'  automatically calculated by the color management class, and they are retrieved by passing boolean modifiers to that
'  class, rather than treating every imaginable variant as a separate constant.)
Private Enum PDSPINNER_COLOR_LIST
    [_First] = 0
    PDS_Background = 0
    PDS_Text = 1
    PDS_TextBorder = 2
    PDS_ButtonArrow = 3
    PDS_ButtonBorder = 4
    PDS_ButtonFill = 5
    PDS_ErrorBorder = 6
    [_Last] = 6
    [_Count] = 7
End Enum

'Color retrieval and storage is handled by a dedicated class; this allows us to optimize theme interactions,
' without worrying about the details locally.
Private m_Colors As pdThemeColors

'Padding distance (in px) between the user control edges and the edit box edges
Private Const EDITBOX_BORDER_PADDING As Long = 2&

Public Function GetControlType() As PD_ControlType
    GetControlType = pdct_Spinner
End Function

Public Function GetControlName() As String
    GetControlName = UserControl.Extender.Name
End Function

Public Property Get ContainerHwnd() As Long
    ContainerHwnd = UserControl.ContainerHwnd
End Property

Public Property Get DefaultValue() As Double
    DefaultValue = m_DefaultValue
End Property

Public Property Let DefaultValue(ByVal newValue As Double)
    m_DefaultValue = newValue
End Property

Public Property Get Enabled() As Boolean
Attribute Enabled.VB_UserMemId = -514
    Enabled = UserControl.Enabled
End Property

Public Property Let Enabled(ByVal newValue As Boolean)
    
    If (UserControl.Enabled <> newValue) Then
        
        UserControl.Enabled = newValue
        
        'The separate API-created edit box must be manually de/activated
        If (Not m_EditBox Is Nothing) Then
            m_EditBox.Enabled = newValue
            m_EditBox.Text = GetFormattedStringValue(m_Value)
            RelayUpdatedColorsToEditBox
        End If
        
        If MainModule.IsProgramRunning() Then RedrawBackBuffer
        PropertyChanged "Enabled"
        
    End If
    
End Property

Public Property Get FontSize() As Single
Attribute FontSize.VB_ProcData.VB_Invoke_Property = "StandardFont;Font"
Attribute FontSize.VB_UserMemId = -512
    If Not (m_EditBox Is Nothing) Then FontSize = m_EditBox.FontSize
End Property

Public Property Let FontSize(ByVal newSize As Single)
    If Not (m_EditBox Is Nothing) Then
        If newSize <> m_EditBox.FontSize Then
            m_EditBox.FontSize = newSize
            PropertyChanged "FontSize"
        End If
    End If
End Property

Public Property Get HasFocus() As Boolean
    HasFocus = ucSupport.DoIHaveFocus() Or m_EditBox.HasFocus()
End Property

Public Property Get hWnd() As Long
Attribute hWnd.VB_UserMemId = -515
    hWnd = UserControl.hWnd
End Property

'If the current text value is NOT valid, this will return FALSE.  The caller can optionally ask us to display an
' error message describing the invalidity in more detail.
Public Property Get IsValid(Optional ByVal showError As Boolean = True) As Boolean
    If m_ErrorState Then
        If showError Then
            IsTextEntryValid True
            m_EditBox.SetFocusToEditBox
            m_EditBox.SelectAll
        End If
    End If
    IsValid = Not m_ErrorState
End Property

Public Property Get Max() As Double
    Max = m_Max
End Property

Public Property Let Max(ByVal newValue As Double)
        
    m_Max = newValue
    
    'If current control values are greater than the new max, change them to match
    If (m_DefaultValue > m_Max) Then m_DefaultValue = m_Max
    If (m_Value > m_Max) Then
        m_Value = m_Max
        m_EditBox.Text = GetFormattedStringValue(m_Value)
        RaiseEvent Change
    End If
    
    PropertyChanged "Max"
    
End Property

Public Property Get Min() As Double
    Min = m_Min
End Property

Public Property Let Min(ByVal newValue As Double)
        
    m_Min = newValue
    
    'If current control values are less than the new minimum, change them to match
    If (m_DefaultValue < m_Min) Then m_DefaultValue = m_Min
    If (m_Value < m_Min) Then
        m_Value = m_Min
        m_EditBox.Text = GetFormattedStringValue(m_Value)
        RaiseEvent Change
    End If
    
    PropertyChanged "Min"
    
End Property

'Significant digits determines whether the control allows float values or int values (and with how much precision)
Public Property Get SigDigits() As Long
    SigDigits = m_SigDigits
End Property

'When the number of significant digits changes, we automatically update the text display to reflect the new amount
Public Property Let SigDigits(ByVal newValue As Long)
    m_SigDigits = newValue
    m_EditBox.Text = GetFormattedStringValue(m_Value)
    PropertyChanged "SigDigits"
End Property

Public Property Get Value() As Double
Attribute Value.VB_UserMemId = 0
    Value = m_Value
End Property

Public Property Let Value(ByVal newValue As Double)
        
    'For performance reasons, we don't make any internal changes unless the new value deviates from the existing one.
    ' (The exception to the rule is if the control is currently in error state; if that happens, we process all new
    ' value requests, in hope of receiving one that resolves the error.)
    If (newValue <> m_Value) Or m_ErrorState Then
        
        m_Value = newValue
                
        'While running, perform bounds-checking.  (It's less important in the designer, as we assume the developer
        ' will momentarily solve any faulty bound/value relationships.)
        If MainModule.IsProgramRunning() Then
            If m_Value < m_Min Then m_Value = m_Min
            If m_Value > m_Max Then m_Value = m_Max
        End If
                
        'With the value guaranteed to be in-bounds, we can now mirror it to the text box
        If Not m_TextBoxInitiated Then
        
            'Perform a final validity check
            If (Not IsValid(False)) Then
                m_EditBox.Text = GetFormattedStringValue(m_Value)
                If m_ErrorState Then
                    m_ErrorState = False
                    RedrawBackBuffer
                End If
            Else
                If (Len(m_EditBox.Text) > 0) Then
                    If Strings.StringsNotEqual(GetFormattedStringValue(m_EditBox.Text), CStr(m_Value), False) Then m_EditBox.Text = GetFormattedStringValue(m_Value)
                End If
            End If
            
        End If
    
        'Mark the value property as being changed, and raise the corresponding event.
        PropertyChanged "Value"
        RaiseEvent Change
        
    End If
                
End Property

Public Sub Reset()
    Me.Value = Me.DefaultValue
End Sub

'To support high-DPI settings properly, we expose some specialized move+size functions
Public Function GetLeft() As Long
    GetLeft = ucSupport.GetControlLeft
End Function

Public Sub SetLeft(ByVal newLeft As Long)
    ucSupport.RequestNewPosition newLeft, , True
End Sub

Public Function GetTop() As Long
    GetTop = ucSupport.GetControlTop
End Function

Public Sub SetTop(ByVal newTop As Long)
    ucSupport.RequestNewPosition , newTop, True
End Sub

Public Function GetWidth() As Long
    GetWidth = ucSupport.GetControlWidth
End Function

Public Sub SetWidth(ByVal newWidth As Long)
    ucSupport.RequestNewSize newWidth, , True
End Sub

Public Function GetHeight() As Long
    GetHeight = ucSupport.GetControlHeight
End Function

Public Sub SetHeight(ByVal newHeight As Long)
    ucSupport.RequestNewSize , newHeight, True
End Sub

'On spinner controls, edit boxes support use of "Enter" and "Esc" keys to auto-trigger "OK" and "Cancel"
' options on an associated command bar (if any)
Private Sub m_EditBox_KeyPress(ByVal Shift As ShiftConstants, ByVal vKey As Long, preventFurtherHandling As Boolean)
    
    If (vKey = pdnk_Enter) Or (vKey = pdnk_Escape) Or (vKey = pdnk_Tab) Then
        preventFurtherHandling = NavKey.NotifyNavKeypress(Me, vKey, Shift)
    End If
    
End Sub

Private Sub ucSupport_ClickCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    If PDMath.IsPointInRectF(x, y, m_ResetRect) Then
        Me.Reset
        RaiseEvent ResetClick
        RaiseEvent FinalChange
    End If
End Sub

Private Sub ucSupport_GotFocusAPI()
    m_FocusCount = m_FocusCount + 1
    EvaluateFocusCount
    RedrawBackBuffer
End Sub

Private Sub ucSupport_KeyDownCustom(ByVal Shift As ShiftConstants, ByVal vkCode As Long, markEventHandled As Boolean)
    
    If (vkCode = vbKeyAdd) Or (vkCode = VK_UP) Or (vkCode = VK_RIGHT) Then
        MoveValueDown
        markEventHandled = True
    ElseIf (vkCode = vbKeySubtract) Or (vkCode = VK_LEFT) Or (vkCode = VK_DOWN) Then
        MoveValueUp
        markEventHandled = True
    Else
        markEventHandled = False
    End If

End Sub

Private Sub ucSupport_KeyDownSystem(ByVal Shift As ShiftConstants, ByVal whichSysKey As PD_NavigationKey, markEventHandled As Boolean)
    
    'Enter/Esc get reported directly to the system key handler.  Note that we track the return, because TRUE
    ' means the key was successfully forwarded to the relevant handler.  (If FALSE is returned, no control
    ' accepted the keypress, meaning we should forward the event down the line.)
    markEventHandled = NavKey.NotifyNavKeypress(Me, whichSysKey, Shift)
    
End Sub

Private Sub ucSupport_KeyUpCustom(ByVal Shift As ShiftConstants, ByVal vkCode As Long, markEventHandled As Boolean)
    RaiseEvent FinalChange
End Sub

Private Sub ucSupport_LostFocusAPI()
    m_FocusCount = m_FocusCount - 1
    EvaluateFocusCount
    RedrawBackBuffer
End Sub

Private Sub ucSupport_MouseDownCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal timeStamp As Long)
    
    'Determine mouse button state for the up and down button areas
    If ((Button = pdLeftButton) And Me.Enabled) Then
    
        If PDMath.IsPointInRectF(x, y, m_UpRect) Then
            m_MouseDownUpButton = True
            m_MouseDownDownButton = False
            m_MouseDownResetButton = False
            
            'Adjust the value immediately
            MoveValueDown
            
            'Start the repeat timer as well
            m_UpButtonTimer.Interval = Interface.GetKeyboardDelay() * 1000
            m_UpButtonTimer.StartTimer
            
        Else
        
            m_MouseDownUpButton = False
        
            If PDMath.IsPointInRectF(x, y, m_DownRect) Then
                m_MouseDownDownButton = True
                m_MouseDownResetButton = False
                MoveValueUp
                m_DownButtonTimer.Interval = Interface.GetKeyboardDelay() * 1000
                m_DownButtonTimer.StartTimer
            Else
                m_MouseDownDownButton = False
                m_MouseDownResetButton = PDMath.IsPointInRectF(x, y, m_ResetRect)
            End If
            
        End If
        
        'Request a button redraw
        RedrawBackBuffer
        
    End If
    
End Sub

Private Sub ucSupport_MouseEnter(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    ucSupport.RequestCursor IDC_HAND
End Sub

Private Sub ucSupport_MouseLeave(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    
    ucSupport.RequestCursor IDC_DEFAULT
    
    m_MouseOverUpButton = False
    m_MouseOverDownButton = False
    m_MouseOverResetButton = False
    
    'Request a button redraw
    RedrawBackBuffer
    
End Sub

Private Sub ucSupport_MouseMoveCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal timeStamp As Long)
    
    'Determine mouse hover state for the up and down button areas
    If PDMath.IsPointInRectF(x, y, m_UpRect) Then
        m_MouseOverUpButton = True
        m_MouseOverDownButton = False
        m_MouseOverResetButton = False
    Else
        m_MouseOverUpButton = False
        If PDMath.IsPointInRectF(x, y, m_DownRect) Then
            m_MouseOverDownButton = True
            m_MouseOverResetButton = False
        Else
            m_MouseOverDownButton = False
            m_MouseOverResetButton = PDMath.IsPointInRectF(x, y, m_ResetRect)
        End If
    End If
    
    'Set an appropriate cursor
    If (m_MouseOverUpButton Or m_MouseOverDownButton Or m_MouseOverResetButton) Then ucSupport.RequestCursor IDC_HAND Else ucSupport.RequestCursor IDC_DEFAULT
    
    'Request a button redraw
    RedrawBackBuffer
    
End Sub

'Reset spin control button state on a mouse up event
Private Sub ucSupport_MouseUpCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal clickEventAlsoFiring As Boolean, ByVal timeStamp As Long)
    
    If ((Button And pdLeftButton) <> 0) Then
        
        m_MouseDownUpButton = False
        m_MouseDownDownButton = False
        m_UpButtonTimer.StopTimer
        m_DownButtonTimer.StopTimer
        
        m_MouseDownResetButton = False
        
        'When the mouse is released, raise a "FinalChange" event, which lets the caller know that they can perform any
        ' long-running actions now.  (Note that "click" events are an exception - they receive manual handling in
        ' the Click event handler; look there for details.)
        If (Not clickEventAlsoFiring) Then RaiseEvent FinalChange
        
        'Request a button redraw
        RedrawBackBuffer
        
    End If
        
End Sub

Private Sub m_DownButtonTimer_Timer()
    
    'If this is the first time the button is firing, we want to reset the button's interval to the repeat rate instead
    ' of the delay rate.
    If (m_DownButtonTimer.Interval = Interface.GetKeyboardDelay * 1000) Then
        m_DownButtonTimer.Interval = Interface.GetKeyboardRepeatRate * 1000
    End If
    
    'It's a little counter-intuitive, but the DOWN button actually moves the control value UP
    MoveValueUp
    
End Sub

Private Sub m_UpButtonTimer_Timer()

    'If this is the first time the button is firing, we want to reset the button's interval to the repeat rate instead
    ' of the delay rate.
    If (m_UpButtonTimer.Interval = Interface.GetKeyboardDelay * 1000) Then
        m_UpButtonTimer.Interval = Interface.GetKeyboardRepeatRate * 1000
    End If
    
    'It's a little counter-intuitive, but the UP button actually moves the control value DOWN
    MoveValueDown
    
End Sub

'When the control value is moved UP via button, this function is called
Private Sub MoveValueUp()
    Value = m_Value - (1# / (10# ^ m_SigDigits))
End Sub

'When the control value is moved DOWN via button, this function is called
Private Sub MoveValueDown()
    Value = m_Value + (1# / (10# ^ m_SigDigits))
End Sub

Private Sub m_EditBox_Change()
    
    If IsTextEntryValid() Then
        If m_ErrorState Then
            m_ErrorState = False
            RedrawBackBuffer
        End If
        m_TextBoxInitiated = True
        Value = CDblCustom(m_EditBox.Text)
        m_TextBoxInitiated = False
    Else
        If Me.Enabled Then
            m_ErrorState = True
            RedrawBackBuffer
        End If
    End If
    
End Sub

Private Sub m_EditBox_GotFocusAPI()
    m_FocusCount = m_FocusCount + 1
    EvaluateFocusCount
    RedrawBackBuffer
End Sub

Private Sub m_EditBox_LostFocusAPI()
    
    m_FocusCount = m_FocusCount - 1
    EvaluateFocusCount
    
    'Validate the edit box's contents when focus is lost
    If IsTextEntryValid() Then
        If m_ErrorState Then m_ErrorState = False
        Value = CDblCustom(m_EditBox.Text)
    Else
        If Me.Enabled Then m_ErrorState = True
    End If
    
    'Focus changes require a redraw
    RedrawBackBuffer
    
End Sub

Private Sub m_EditBox_MouseEnter(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    m_MouseOverEditBox = True
    RedrawBackBuffer
End Sub

Private Sub m_EditBox_MouseLeave(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    m_MouseOverEditBox = False
    RedrawBackBuffer
End Sub

Private Sub m_EditBox_Resize()
    If (Not m_InternalResizeState) Then UpdateControlLayout
End Sub

Private Sub ucSupport_RepaintRequired(ByVal updateLayoutToo As Boolean)
    If updateLayoutToo And (Not m_InternalResizeState) Then UpdateControlLayout Else RedrawBackBuffer
End Sub

Private Sub ucSupport_VisibilityChange(ByVal newVisibility As Boolean)
    If (Not m_EditBox Is Nothing) Then m_EditBox.Visible = newVisibility
End Sub

Private Sub ucSupport_WindowResize(ByVal newWidth As Long, ByVal newHeight As Long)
    RaiseEvent Resize
End Sub

Private Sub UserControl_Hide()
    If (Not m_EditBox Is Nothing) Then m_EditBox.Visible = False
End Sub

Private Sub UserControl_Initialize()
    
    'Note that we are not currently responsible for any resize events
    m_InternalResizeState = False
    
    'Initialize an edit box support class
    Set m_EditBox = New pdEditBoxW
    
    'Initialize a master user control support class
    Set ucSupport = New pdUCSupport
    ucSupport.RegisterControl UserControl.hWnd, True
    ucSupport.RequestExtraFunctionality True, True
    ucSupport.SpecifyRequiredKeys VK_UP, VK_RIGHT, VK_DOWN, VK_LEFT, vbKeyAdd, vbKeySubtract
    
    'Prep painting classes
    Drawing2D.QuickCreatePainter m_Painter
    
    'Prep the color manager and load default colors
    Set m_Colors = New pdThemeColors
    Dim colorCount As PDSPINNER_COLOR_LIST: colorCount = [_Count]
    m_Colors.InitializeColorList "PDSpinner", colorCount
    If Not MainModule.IsProgramRunning() Then UpdateColorList
    
    'Prep timer objects
    If MainModule.IsProgramRunning() Then
        Set m_UpButtonTimer = New pdTimer
        Set m_DownButtonTimer = New pdTimer
    End If
          
End Sub

Private Sub UserControl_InitProperties()
    DefaultValue = 0
    FontSize = 10
    Value = 0
    Min = 0
    Max = 10
    SigDigits = 0
End Sub

Private Sub UserControl_ReadProperties(PropBag As PropertyBag)
    With PropBag
        DefaultValue = .ReadProperty("DefaultValue", 0)
        FontSize = .ReadProperty("FontSize", 10)
        SigDigits = .ReadProperty("SigDigits", 0)
        Max = .ReadProperty("Max", 10)
        Min = .ReadProperty("Min", 0)
        Value = .ReadProperty("Value", 0)
    End With
End Sub

Private Sub UserControl_Show()
    If ((Not (m_EditBox Is Nothing)) And MainModule.IsProgramRunning()) Then CreateEditBox
End Sub

Private Sub UserControl_WriteProperties(PropBag As PropertyBag)
    With PropBag
        .WriteProperty "DefaultValue", Me.DefaultValue, 0
        .WriteProperty "Min", Me.Min, 0
        .WriteProperty "Max", Me.Max, 10
        .WriteProperty "SigDigits", Me.SigDigits, 0
        .WriteProperty "Value", Me.Value, 0
        .WriteProperty "FontSize", Me.FontSize, 10
    End With
End Sub

'This control's height cannot be set manually.  It will automatically resize itself vertically to match the underlying
' edit box height (whose size, in turn, is controlled by its current font size).
Public Sub FitUCHeightToEditBoxHeight()
    
    m_InternalResizeState = True
    
    Dim idealUCHeight As Long
    idealUCHeight = m_EditBox.SuggestedHeight() + FixDPI(EDITBOX_BORDER_PADDING) * 2 + 1
    If (ucSupport.GetControlHeight <> idealUCHeight) Then
        ucSupport.RequestNewSize ucSupport.GetControlWidth, idealUCHeight, True
        RaiseEvent Resize
    End If
    
    m_InternalResizeState = False
    
End Sub

'Generally speaking, the underlying API edit box management class recreates itself as needed, but we need to request its
' initial creation.  During this stage, we also auto-size ourself to match the edit box's suggested size (if it's a
' single-line instance; multiline boxes can be whatever vertical size we want).
Private Sub CreateEditBox()
    
    If (Not m_EditBox Is Nothing) Then
        
        'Make sure all edit box settings are up-to-date prior to creation
        m_EditBox.Enabled = Me.Enabled
        RelayUpdatedColorsToEditBox
        
        'Resize ourselves vertically to match the edit box's suggested size.
        FitUCHeightToEditBoxHeight
        
        'Now that we're the proper size, determine where we're gonna stick the edit box (relative to this control instance)
        UpdatePositionRects
        
        'Ask the edit box to create itself!
        With m_EditBoxRect
            m_EditBox.CreateEditBox UserControl.hWnd, .Left, .Top, .Width, .Height, False
        End With
        
        'Because control sizes may have changed, we need to repaint everything
        If ucSupport.AmIVisible Then RedrawBackBuffer
        
        'Creating the edit box may have caused this control to resize itself, so as a failsafe, raise a
        ' Resize() event manually
        RaiseEvent Resize
    
    End If
    
End Sub

'This function generates spin button and edit box rects that match the current user control size.  Note that it does not
' actually move or resize any windows - it simply calculates rect positions.
Private Sub UpdatePositionRects()

    'Start by caching the actual window size.  (This may be different from VB's measurements, particularly on high-DPI settings)
    Dim bWidth As Long, bHeight As Long
    bWidth = ucSupport.GetControlWidth
    bHeight = ucSupport.GetControlHeight
    
    'The reset button is fixed-width and right-aligned, so position it first
    With m_ResetRect
        .Height = (bHeight - 1) - EDITBOX_BORDER_PADDING
        .Width = .Height
        .Left = (bWidth - 1) - .Width
        .Top = EDITBOX_BORDER_PADDING - 1
    End With
    
    'Because the up/down buttons are also fixed-width, position them next.
    Dim buttonWidth As Long, buttonHeight As Long, buttonTop As Long, buttonLeft As Long
    buttonWidth = FixDPI(18)
    buttonLeft = m_ResetRect.Left - buttonWidth
    buttonTop = EDITBOX_BORDER_PADDING - 1
    buttonHeight = ((bHeight - 1) - (buttonTop * 2)) \ 2
    
    'Calculate hit-detection rects for the individual up/down buttons
    With m_UpRect
        .Left = buttonLeft
        .Width = buttonWidth
        .Top = buttonTop
        .Height = buttonHeight
    End With
    
    'With the buttons successfully positioned, allow the edit box to fill the remaining space
    With m_EditBoxRect
        .Left = EDITBOX_BORDER_PADDING
        .Top = EDITBOX_BORDER_PADDING
        .Height = (bHeight - 1) - EDITBOX_BORDER_PADDING * 2
        .Width = (buttonLeft - .Left) - 1
    End With
    
    'Mirror the up button rect positions to the down button reect positions
    With m_DownRect
        .Left = buttonLeft
        .Width = buttonWidth
        .Top = m_UpRect.Top + m_UpRect.Height + 1
        .Height = (m_EditBoxRect.Top + m_EditBoxRect.Height) - .Top + 1
    End With
    
End Sub

'Move the edit box into the position specified by m_EditBoxRect.  If it is already positioned correctly, nothing happens.
Private Sub VerifyEditBoxPosition()
    Dim editBoxRect As winRect
    If m_EditBox.GetPositionRect(editBoxRect) Then
        If (editBoxRect.x1 <> m_EditBoxRect.Left) Or (editBoxRect.y1 <> m_EditBoxRect.Top) Then
            If ((editBoxRect.x2 - editBoxRect.x1) <> m_EditBoxRect.Width) Or ((editBoxRect.y2 - editBoxRect.y1) <> m_EditBoxRect.Height) Then
                With m_EditBoxRect
                    m_EditBox.Move .Left, .Top, .Width, .Height
                End With
            End If
        End If
    End If
End Sub

Private Sub UpdateControlLayout()
    
    'Before we do anything else, we need to synchronize the user control's height to the underlying edit box height.
    ' (The edit box's font determines the default height of this control; we auto-fit to match.)
    FitUCHeightToEditBoxHeight
    
    'With the control height established, we now need to position all sub-elements within the control.
    UpdatePositionRects
    
    'Move the edit box into place, as necessary.
    VerifyEditBoxPosition
    
    'With everything positioned, we need to redraw the control from scratch
    RedrawBackBuffer
    
End Sub

'Redraw the spin button area of the control
Private Sub RedrawBackBuffer()
    
    'We can improve shutdown performance by ignoring redraw requests when the program is going down
    If g_ProgramShuttingDown Then
        If (g_Themer Is Nothing) Then Exit Sub
    End If
    
    'Request the back buffer DC, and ask the support module to erase any existing rendering for us.
    Dim finalBackColor As Long
    finalBackColor = m_Colors.RetrieveColor(PDS_Background, Me.Enabled)
    
    Dim bufferDC As Long, bWidth As Long, bHeight As Long
    bufferDC = ucSupport.GetBackBufferDC(True, finalBackColor)
    bWidth = ucSupport.GetBackBufferWidth
    bHeight = ucSupport.GetBackBufferHeight
    
    'This control's render code relies on GDI+ exclusively, so there's no point calling it in the IDE - sorry!
    If MainModule.IsProgramRunning() And (bufferDC <> 0) Then
    
        'Relay any recently changed/modified colors to the edit box, so it can repaint itself to match
        RelayUpdatedColorsToEditBox
        
        'Next, initialize a whole bunch of color values.  Note that up and down buttons are treated separately, as they may
        ' have different mouse states at any given time.
        Dim editBoxBorderColor As Long
        Dim upButtonBorderColor As Long, downButtonBorderColor As Long
        Dim upButtonFillColor As Long, downButtonFillColor As Long
        Dim upButtonArrowColor As Long, downButtonArrowColor As Long
        Dim resetButtonBorderColor As Long, resetButtonFillColor As Long, resetButtonArrowColor As Long
        
        If m_ErrorState Then
            editBoxBorderColor = m_Colors.RetrieveColor(PDS_ErrorBorder, Me.Enabled, m_EditBox.HasFocus, m_MouseOverEditBox)
        Else
            editBoxBorderColor = m_Colors.RetrieveColor(PDS_TextBorder, Me.Enabled, m_EditBox.HasFocus, m_MouseOverEditBox)
        End If
        
        upButtonArrowColor = m_Colors.RetrieveColor(PDS_ButtonArrow, Me.Enabled, m_MouseDownUpButton, m_MouseOverUpButton)
        upButtonBorderColor = m_Colors.RetrieveColor(PDS_ButtonBorder, Me.Enabled, m_MouseDownUpButton, m_MouseOverUpButton)
        upButtonFillColor = m_Colors.RetrieveColor(PDS_ButtonFill, Me.Enabled, m_MouseDownUpButton, m_MouseOverUpButton)
        downButtonArrowColor = m_Colors.RetrieveColor(PDS_ButtonArrow, Me.Enabled, m_MouseDownDownButton, m_MouseOverDownButton)
        downButtonBorderColor = m_Colors.RetrieveColor(PDS_ButtonBorder, Me.Enabled, m_MouseDownDownButton, m_MouseOverDownButton)
        downButtonFillColor = m_Colors.RetrieveColor(PDS_ButtonFill, Me.Enabled, m_MouseDownDownButton, m_MouseOverDownButton)
        resetButtonArrowColor = m_Colors.RetrieveColor(PDS_ButtonArrow, Me.Enabled, m_MouseDownResetButton, m_MouseOverResetButton)
        resetButtonBorderColor = m_Colors.RetrieveColor(PDS_ButtonBorder, Me.Enabled, m_MouseDownResetButton, m_MouseOverResetButton)
        resetButtonFillColor = m_Colors.RetrieveColor(PDS_ButtonFill, Me.Enabled, m_MouseDownResetButton, m_MouseOverResetButton)
        
        Dim cSurface As pd2DSurface, cBrush As pd2DBrush, cPen As pd2DPen
        Drawing2D.QuickCreateSurfaceFromDC cSurface, bufferDC, False
        
        'Start by filling the button regions.  We will overpaint these (as necessary) with relevant border styles
        Drawing2D.QuickCreateSolidBrush cBrush, downButtonFillColor
        m_Painter.FillRectangleF_FromRectF cSurface, cBrush, m_DownRect
        cBrush.SetBrushColor upButtonFillColor
        m_Painter.FillRectangleF_FromRectF cSurface, cBrush, m_UpRect
        cBrush.SetBrushColor resetButtonFillColor
        m_Painter.FillRectangleF_FromRectF cSurface, cBrush, m_ResetRect
        
        'Calculate positioning and color of the edit box border.  (Note that the edit box doesn't paint its own border;
        ' we render a pseudo-border onto the underlying UC around its position, instead.)
        Dim halfPadding As Long
        halfPadding = 1
        
        Dim borderWidth As Single
        If (Not m_EditBox Is Nothing) Then
            If (m_EditBox.HasFocus Or m_MouseOverEditBox) Then borderWidth = 3 Else borderWidth = 1
        Else
            borderWidth = 1
        End If
        
        Dim editBoxRenderRect As RectF
        With editBoxRenderRect
            .Left = m_EditBoxRect.Left - halfPadding
            .Top = m_EditBoxRect.Top - halfPadding
            .Width = m_EditBoxRect.Width + halfPadding * 2 - 1
            .Height = m_EditBoxRect.Height + halfPadding * 2 - 1
        End With
        
        'If the spin buttons are active, we can paint the edit box rectangle immediately.  (If they are NOT active,
        ' and we attempt to draw a chunky border, their border will accidentally overlap ours, so we must paint later.)
        If (m_MouseOverUpButton Or m_MouseOverDownButton) Then
            Drawing2D.QuickCreateSolidPen cPen, borderWidth, editBoxBorderColor, , P2_LJ_Miter
            m_Painter.DrawRectangleF_FromRectF cSurface, cPen, editBoxRenderRect
        End If
        
        'Paint button backgrounds and borders.  Note that the active button (if any) is drawn LAST, so that its chunky
        ' hover border appears over the top of any neighboring UI elements.  (This is the reason for the ugly if/then blocks.)
        Dim upButtonBorderWidth As Single, downButtonBorderWidth As Single, resetButtonBorderWidth As Single
        If m_MouseOverUpButton Then upButtonBorderWidth = 2# Else upButtonBorderWidth = 1#
        If m_MouseOverDownButton Then downButtonBorderWidth = 2# Else downButtonBorderWidth = 1#
        If m_MouseOverResetButton Then resetButtonBorderWidth = 2# Else resetButtonBorderWidth = 1#
        
        If m_MouseOverUpButton Then
            If (resetButtonBorderColor <> finalBackColor) Then
                Drawing2D.QuickCreateSolidPen cPen, resetButtonBorderWidth, resetButtonBorderColor, , P2_LJ_Miter
                m_Painter.DrawRectangleF_FromRectF cSurface, cPen, m_ResetRect
            End If
            If (downButtonBorderColor <> finalBackColor) Then
                Drawing2D.QuickCreateSolidPen cPen, downButtonBorderWidth, downButtonBorderColor, , P2_LJ_Miter
                m_Painter.DrawRectangleF_FromRectF cSurface, cPen, m_DownRect
            End If
            If (upButtonBorderColor <> finalBackColor) Then
                Drawing2D.QuickCreateSolidPen cPen, upButtonBorderWidth, upButtonBorderColor, , P2_LJ_Miter
                m_Painter.DrawRectangleF_FromRectF cSurface, cPen, m_UpRect
            End If
        Else
            If m_MouseOverDownButton Then
                If (resetButtonBorderColor <> finalBackColor) Then
                    Drawing2D.QuickCreateSolidPen cPen, resetButtonBorderWidth, resetButtonBorderColor, , P2_LJ_Miter
                    m_Painter.DrawRectangleF_FromRectF cSurface, cPen, m_ResetRect
                End If
                If (upButtonBorderColor <> finalBackColor) Then
                    Drawing2D.QuickCreateSolidPen cPen, upButtonBorderWidth, upButtonBorderColor, , P2_LJ_Miter
                    m_Painter.DrawRectangleF_FromRectF cSurface, cPen, m_UpRect
                End If
                If (downButtonBorderColor <> finalBackColor) Then
                    Drawing2D.QuickCreateSolidPen cPen, downButtonBorderWidth, downButtonBorderColor, , P2_LJ_Miter
                    m_Painter.DrawRectangleF_FromRectF cSurface, cPen, m_DownRect
                End If
            Else
                If (upButtonBorderColor <> finalBackColor) Then
                    Drawing2D.QuickCreateSolidPen cPen, upButtonBorderWidth, upButtonBorderColor, , P2_LJ_Miter
                    m_Painter.DrawRectangleF_FromRectF cSurface, cPen, m_UpRect
                End If
                If (downButtonBorderColor <> finalBackColor) Then
                    Drawing2D.QuickCreateSolidPen cPen, downButtonBorderWidth, downButtonBorderColor, , P2_LJ_Miter
                    m_Painter.DrawRectangleF_FromRectF cSurface, cPen, m_DownRect
                End If
                If (resetButtonBorderColor <> finalBackColor) Then
                    Drawing2D.QuickCreateSolidPen cPen, resetButtonBorderWidth, resetButtonBorderColor, , P2_LJ_Miter
                    m_Painter.DrawRectangleF_FromRectF cSurface, cPen, m_ResetRect
                End If
            End If
        End If
        
        'If neither spin button is active, paint the edit box last
        If (Not (m_MouseOverUpButton Or m_MouseOverDownButton)) Then
            Drawing2D.QuickCreateSolidPen cPen, borderWidth, editBoxBorderColor, , P2_LJ_Miter
            m_Painter.DrawRectangleF_FromRectF cSurface, cPen, editBoxRenderRect
        End If
        
        'Calculate coordinate positions for the spin button arrows.  These calculations include a lot of magic numbers, alas,
        ' to account for things like padding and subpixel positioning.
        cSurface.SetSurfaceAntialiasing P2_AA_HighQuality
        Dim buttonPt1 As PointFloat, buttonPt2 As PointFloat, buttonPt3 As PointFloat
                    
        'Start with the up-pointing arrow
        buttonPt1.x = m_UpRect.Left + FixDPIFloat(4) + 0.5
        buttonPt1.y = (m_UpRect.Height) / 2 + FixDPIFloat(2)
        
        buttonPt3.x = (m_UpRect.Left + m_UpRect.Width) - FixDPIFloat(5) - 0.5
        buttonPt3.y = buttonPt1.y
        
        buttonPt2.x = buttonPt1.x + (buttonPt3.x - buttonPt1.x) / 2
        buttonPt2.y = buttonPt1.y - FixDPIFloat(3)
        
        Drawing2D.QuickCreateSolidPen cPen, 2#, upButtonArrowColor, , P2_LJ_Round, P2_LC_Round
        m_Painter.DrawLineF_FromPtF cSurface, cPen, buttonPt1, buttonPt2
        m_Painter.DrawLineF_FromPtF cSurface, cPen, buttonPt2, buttonPt3
                    
        'Next, the down-pointing arrow
        buttonPt1.x = m_DownRect.Left + FixDPIFloat(4) + 0.5
        buttonPt1.y = m_DownRect.Top + (m_DownRect.Height / 2) - FixDPIFloat(2)
        
        buttonPt3.x = (m_DownRect.Left + m_DownRect.Width) - FixDPIFloat(5) - 0.5
        buttonPt3.y = buttonPt1.y
        
        buttonPt2.x = buttonPt1.x + (buttonPt3.x - buttonPt1.x) / 2
        buttonPt2.y = buttonPt1.y + FixDPIFloat(3)
        
        cPen.SetPenColor downButtonArrowColor
        m_Painter.DrawLineF_FromPtF cSurface, cPen, buttonPt1, buttonPt2
        m_Painter.DrawLineF_FromPtF cSurface, cPen, buttonPt2, buttonPt3
        
        'Finally, calculate coordinate positions for the reset button arcs.  (These are drawn dynamically.)
        Dim resetCenterX As Single, resetCenterY As Single, resetArcRadius As Single
        With m_ResetRect
            resetCenterX = .Left + (.Width / 2)
            resetCenterY = .Top + (.Height / 2)
            resetArcRadius = (.Width / 2) - 3.5
        End With
        
        cSurface.SetSurfacePixelOffset P2_PO_Half
        Drawing2D.QuickCreateSolidPen cPen, 1#, resetButtonArrowColor, , P2_LJ_Round, P2_LC_Round
        
        'New single-arrow design (which matches "reset" icons in the rest of PD):
        cPen.SetPenStartCap P2_LC_Round
        cPen.SetPenEndCap P2_LC_ArrowAnchor
        m_Painter.DrawArcF cSurface, cPen, resetCenterX, resetCenterY, resetArcRadius, 148, -305
        
        'Old double-arrow design:
        'Dim resetAngleStart As Single
        'resetAngleStart = 20#
        'cPen.SetPenStartCap P2_LC_ArrowAnchor
        'cPen.SetPenEndCap P2_LC_Round
        'm_Painter.DrawArcF cSurface, cPen, resetCenterX, resetCenterY, resetArcRadius, resetAngleStart, (170 - resetAngleStart)
        'm_Painter.DrawArcF cSurface, cPen, resetCenterX, resetCenterY, resetArcRadius, (180 + resetAngleStart), (170 - resetAngleStart)
        
        Set cSurface = Nothing: Set cBrush = Nothing: Set cPen = Nothing
    
    End If
    
    'Paint the final result to the screen, as relevant
    ucSupport.RequestRepaint
    If (Not MainModule.IsProgramRunning()) Then UserControl.Refresh

End Sub

'Because this control can contain either decimal or float values, we want to make sure any entered strings adhere
' to strict formatting rules.
Private Function GetFormattedStringValue(ByVal srcValue As Double) As String
    
    Dim formatString As String
    If (m_SigDigits = 0) Then
        formatString = "#0"
    Else
        formatString = "#0." & String$(m_SigDigits, "0")
    End If
    
    GetFormattedStringValue = Format$(CStr(srcValue), formatString)
        
    'Perform a final check for control enablement.  If the control is disabled, we do not (currently) display anything.
    If (Not Me.Enabled) Then GetFormattedStringValue = ""

End Function

'Check a passed value against a min and max value to see if it is valid.  Additionally, make sure the value is
' numeric, and allow the user to display a warning message if necessary.
Private Function IsTextEntryValid(Optional ByVal displayErrorMsg As Boolean = False) As Boolean
        
    'Some locales use a comma as a decimal separator.  Check for this and replace as necessary.
    Dim chkString As String
    chkString = m_EditBox.Text
    
    'Remember the current cursor position, too - we want to restore it after applying formatting to the numeric string
    Dim cursorPos As Long
    cursorPos = m_EditBox.SelStart
        
    'It may be possible for the user to enter consecutive ",." characters, which then cause the CDbl() below to fail.
    ' Check for this and fix it as necessary.
    If InStr(1, chkString, "..") Then
        chkString = Replace(chkString, "..", ".")
        m_EditBox.Text = chkString
        If (cursorPos >= Len(chkString)) Then cursorPos = Len(chkString)
        m_EditBox.SelStart = cursorPos
    End If
        
    If (Not IsNumeric(chkString)) Then
        If displayErrorMsg Then PDMsgBox "%1 is not a valid entry." & vbCrLf & "Please enter a numeric value.", vbExclamation Or vbOKOnly, "Invalid entry", m_EditBox.Text
        IsTextEntryValid = False
    Else
        
        Dim checkVal As Double
        checkVal = CDblCustom(chkString)
    
        If (checkVal >= m_Min) And (checkVal <= m_Max) Then
            IsTextEntryValid = True
        Else
            If displayErrorMsg Then PDMsgBox "%1 is not a valid entry." & vbCrLf & "Please enter a value between %2 and %3.", vbExclamation Or vbOKOnly, "Invalid entry", m_EditBox.Text, GetFormattedStringValue(m_Min), GetFormattedStringValue(m_Max)
            IsTextEntryValid = False
        End If
        
    End If
    
End Function

'After a component of this control obtains or loses focus, you need to call this function.  This function will figure
' out if it's time to raise a matching Got/LostFocusAPI event for the control as a whole.
Private Sub EvaluateFocusCount()
    If (m_FocusCount <> 0) Then
        If (Not m_HasFocus) Then
            m_HasFocus = True
            RaiseEvent GotFocusAPI
        End If
    Else
        If m_HasFocus Then
            m_HasFocus = False
            RaiseEvent LostFocusAPI
        End If
    End If
End Sub

'Before this control does any painting, we need to retrieve relevant colors from PD's primary theming class.  Note that this
' step must also be called if/when PD's visual theme settings change.
Private Sub UpdateColorList()
        
    'Color list retrieval is pretty darn easy - just load each color one at a time, and leave the rest to the color class.
    ' It will build an internal hash table of the colors we request, which makes rendering much faster.
    With m_Colors
        .LoadThemeColor PDS_Background, "Background", IDE_WHITE
        .LoadThemeColor PDS_Text, "Text", IDE_GRAY
        .LoadThemeColor PDS_TextBorder, "TextBorder", IDE_BLUE
        .LoadThemeColor PDS_ButtonArrow, "ButtonArrow", IDE_GRAY
        .LoadThemeColor PDS_ButtonBorder, "ButtonBorder", IDE_BLUE
        .LoadThemeColor PDS_ButtonFill, "ButtonFill", IDE_WHITE
        .LoadThemeColor PDS_ErrorBorder, "ErrorBorder", IDE_RED
    End With
    
    RelayUpdatedColorsToEditBox
    
End Sub

'When this control has special knowledge of a state change that affects the edit box's visual appearance, call this function.
' It will relay the relevant themed colors to the edit box class.
Private Sub RelayUpdatedColorsToEditBox()
    If (Not m_EditBox Is Nothing) Then
        m_EditBox.BackColor = m_Colors.RetrieveColor(PDS_Background, Me.Enabled, m_EditBox.HasFocus, m_MouseOverEditBox)
        m_EditBox.TextColor = m_Colors.RetrieveColor(PDS_Text, Me.Enabled, m_EditBox.HasFocus, m_MouseOverEditBox)
    End If
End Sub

'External functions can call this to request a redraw.  This is helpful for live-updating theme settings, as in the Preferences dialog.
Public Sub UpdateAgainstCurrentTheme(Optional ByVal hostFormhWnd As Long = 0)
    If ucSupport.ThemeUpdateRequired Then
        UpdateColorList
        If MainModule.IsProgramRunning() Then NavKey.NotifyControlLoad Me, hostFormhWnd
        If MainModule.IsProgramRunning() Then ucSupport.UpdateAgainstThemeAndLanguage
    End If
End Sub

'By design, PD prefers to not use design-time tooltips.  Apply tooltips at run-time, using this function.
' (IMPORTANT NOTE: translations are handled automatically.  Always pass the original English text!)
Public Sub AssignTooltip(ByVal newTooltip As String, Optional ByVal newTooltipTitle As String, Optional ByVal newTooltipIcon As TT_ICON_TYPE = TTI_NONE)
    ucSupport.AssignTooltip Me.hWnd, newTooltip, newTooltipTitle, newTooltipIcon
End Sub
