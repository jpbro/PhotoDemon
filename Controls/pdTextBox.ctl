VERSION 5.00
Begin VB.UserControl pdTextBox 
   Appearance      =   0  'Flat
   BackColor       =   &H0080FF80&
   ClientHeight    =   975
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   3015
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
   ScaleHeight     =   65
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   201
   ToolboxBitmap   =   "pdTextBox.ctx":0000
End
Attribute VB_Name = "pdTextBox"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon Unicode Text Box control
'Copyright 2014-2017 by Tanner Helland
'Created: 03/November/14
'Last updated: 09/February/16
'Last update: move all API edit control code out of this class, and into a dedicated pdEditBoxW class.  This greatly
'             simplifies this control, and we can reuse pdEditBoxW elsewhere.
'
'In a surprise to precisely no one, PhotoDemon has some unique needs when it comes to user controls - needs that
' the intrinsic VB controls can't handle.  These range from the obnoxious (lack of an "autosize" property for
' anything but labels) to the critical (no Unicode support).
'
'As such, I've created many of my own UCs for the program.  All are owner-drawn, with the goal of maintaining
' visual fidelity across the program, while also enabling key features like Unicode support.
'
'A few notes on this text box control, specifically:
'
' 1) Unlike other PD custom controls, this one is simply a wrapper to a system text box.
' 2) The idea with this control was not to expose all text box properties, but simply those most relevant to PD.
' 3) Focus is the real nightmare for this control, and as you will see, some complicated tricks are required to work
'    around VB's handling of tabstops in particular.
' 4) To allow use of arrow keys and other control keys, this control must hook the keyboard.  (If it does not, VB will
'    eat control keypresses, because it doesn't know about windows created via the API!)  A byproduct of this is that
'    accelerators flat-out WILL NOT WORK while this control has focus.  I haven't yet settled on a good way to handle
'    this; what I may end up doing is manually forwarding any key combinations that use Alt to the default window
'    handler, but I'm not sure this will help.  TODO!
' 5) Dynamic hooking can occasionally cause trouble in the IDE, particularly when used with break points.  It should
'    be fine once compiled.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'By design, this textbox raises fewer events than a standard text box
Public Event Change()
Public Event KeyPress(ByVal vKey As Long, ByRef preventFurtherHandling As Boolean)
Public Event Resize()
Public Event GotFocusAPI()
Public Event LostFocusAPI()

'The actual common control edit box is handled by a dedicated class
Private WithEvents m_EditBox As pdEditBoxW
Attribute m_EditBox.VB_VarHelpID = -1

'Some mouse states relative to the edit box are tracked, so we can render custom borders around the embedded box
Private m_MouseOverEditBox As Boolean

'Tracks whether the control (any component) has focus.  This is helpful as we must synchronize between VB's focus events and API
' focus events.  This value is deliberately kept separate from m_HasFocus, above, as we only use this value to raise our own
' Got/Lost focus events when the *entire control* loses focus (vs any one individual component).
Private m_ControlHasFocus As Boolean

'If the user resizes an edit box, the control's back buffer needs to be redrawn.  If we resize the edit box as part of an internal
' AutoSize calculation, however, we will already be in the midst of resizing the backbuffer - so we override the behavior of the
' UserControl_Resize event, using this variable.
Private m_InternalResizeState As Boolean

'User control support class.  Historically, many classes (and associated subclassers) were required by each user control,
' but I've since attempted to wrap these into a single master control support class.
Private WithEvents ucSupport As pdUCSupport
Attribute ucSupport.VB_VarHelpID = -1

'Local list of themable colors.  This list includes all potential colors used by the control, regardless of state change
' or internal control settings.  The list is updated by calling the UpdateColorList function.
' (Note also that this list does not include variants, e.g. "BorderColor" vs "BorderColor_Hovered".  Variant values are
'  automatically calculated by the color management class, and they are retrieved by passing boolean modifiers to that
'  class, rather than treating every imaginable variant as a separate constant.)
Private Enum PDEDITBOX_COLOR_LIST
    [_First] = 0
    PDEB_Background = 0
    PDEB_Border = 1
    PDEB_Text = 2
    [_Last] = 2
    [_Count] = 3
End Enum

'Color retrieval and storage is handled by a dedicated class; this allows us to optimize theme interactions,
' without worrying about the details locally.
Private m_Colors As pdThemeColors

'Padding distance (in px) between the user control edges and the edit box edges
Private Const EDITBOX_BORDER_PADDING As Long = 2&

Public Function GetControlType() As PD_ControlType
    GetControlType = pdct_TextBox
End Function

Public Function GetControlName() As String
    GetControlName = UserControl.Extender.Name
End Function

Public Property Get ContainerHwnd() As Long
    ContainerHwnd = UserControl.ContainerHwnd
End Property

'The Enabled property is a bit unique; see http://msdn.microsoft.com/en-us/library/aa261357%28v=vs.60%29.aspx
Public Property Get Enabled() As Boolean
Attribute Enabled.VB_UserMemId = -514
    Enabled = UserControl.Enabled
End Property

Public Property Let Enabled(ByVal newValue As Boolean)
    If Not (m_EditBox Is Nothing) Then
        m_EditBox.Enabled = newValue
        RelayUpdatedColorsToEditBox
    End If
    UserControl.Enabled = newValue
    If MainModule.IsProgramRunning() Then RedrawBackBuffer
    PropertyChanged "Enabled"
End Property

'Font properties; only a subset are used, as PD handles most font settings automatically
Public Property Get FontSize() As Single
    If (Not m_EditBox Is Nothing) Then FontSize = m_EditBox.FontSize
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
    hWnd = UserControl.hWnd
End Property

Public Property Get Multiline() As Boolean
    If (Not m_EditBox Is Nothing) Then Multiline = m_EditBox.Multiline
End Property

Public Property Let Multiline(ByVal newState As Boolean)
    If (Not m_EditBox Is Nothing) Then
        If (newState <> m_EditBox.Multiline) Then
            m_EditBox.Multiline = newState
            PropertyChanged "Multiline"
        End If
    End If
End Property

'To support high-DPI settings properly, we expose specialized move+size functions
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

Public Sub SetPositionAndSize(ByVal newLeft As Long, ByVal newTop As Long, ByVal newWidth As Long, ByVal newHeight As Long)
    ucSupport.RequestFullMove newLeft, newTop, newWidth, newHeight, True
End Sub

Public Sub SetSize(ByVal newWidth As Long, ByVal newHeight As Long)
    ucSupport.RequestNewSize newWidth, newHeight, True
End Sub

'External functions can call this to fully select the text box's contents
Public Sub SelectAll()
    If (Not m_EditBox Is Nothing) Then m_EditBox.SelectAll
End Sub

'SelStart is used by some PD functions to control caret positioning after automatic text updates (as used in the text up/down)
Public Property Get SelStart() As Long
    If (Not m_EditBox Is Nothing) Then SelStart = m_EditBox.SelStart
End Property

Public Property Let SelStart(ByVal newPosition As Long)
    If (Not m_EditBox Is Nothing) Then m_EditBox.SelStart = newPosition
End Property

Public Property Get Text() As String
Attribute Text.VB_ProcData.VB_Invoke_Property = ";Text"
Attribute Text.VB_UserMemId = 0
Attribute Text.VB_MemberFlags = "200"
    If (Not m_EditBox Is Nothing) Then Text = m_EditBox.Text
End Property

Public Property Let Text(ByRef newString As String)
    If (Not m_EditBox Is Nothing) Then
        m_EditBox.Text = newString
        If MainModule.IsProgramRunning() Then
            RaiseEvent Change
        Else
            PropertyChanged "Text"
        End If
    End If
End Property

Private Sub m_EditBox_Change()
    RaiseEvent Change
End Sub

Private Sub m_EditBox_GotFocusAPI()
    ComponentGotFocus
End Sub

Private Sub m_EditBox_KeyPress(ByVal Shift As ShiftConstants, ByVal vKey As Long, preventFurtherHandling As Boolean)
    
    'Enter/Esc/Tab keypresses receive special treatment
    If ((vKey = pdnk_Enter) Or (vKey = pdnk_Escape) Or (vKey = pdnk_Tab)) And (Not m_EditBox.Multiline) Then
        If (Not NavKey.NotifyNavKeypress(Me, vKey, Shift)) Then RaiseEvent KeyPress(vKey, preventFurtherHandling)
    Else
        RaiseEvent KeyPress(vKey, preventFurtherHandling)
    End If
    
End Sub

Private Sub m_EditBox_LostFocusAPI()
    ComponentLostFocus
End Sub

Private Sub m_EditBox_MouseEnter(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    m_MouseOverEditBox = True
    RedrawBackBuffer
End Sub

Private Sub m_EditBox_MouseLeave(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    m_MouseOverEditBox = False
    RedrawBackBuffer
End Sub

Private Sub ucSupport_RepaintRequired(ByVal updateLayoutToo As Boolean)
    If updateLayoutToo And (Not m_InternalResizeState) Then UpdateControlLayout Else RedrawBackBuffer
End Sub

Private Sub ucSupport_VisibilityChange(ByVal newVisibility As Boolean)
    
    If (Not m_EditBox Is Nothing) Then
        
        'If we haven't created the edit box yet, now is a great time to do it!
        If (m_EditBox.hWnd = 0) Then CreateEditBoxAPIWindow
        
        m_EditBox.Visible = newVisibility
        
    End If
    
End Sub

Private Sub ucSupport_WindowResize(ByVal newWidth As Long, ByVal newHeight As Long)
    RaiseEvent Resize
End Sub

'Sometimes, we want to change the UC's size to match the edit box.  Other times, we want to change the edit box's size to
' match the UC.  Use this two functions to update the appropriate size; if "editBoxGetsMoved" is TRUE, we'll forcibly set
' it to match our desired size.
Private Sub SynchronizeSizes()
    
    If (Not m_EditBox Is Nothing) Then
        
        Dim needToMove As Boolean
        needToMove = True
        
        'Start by determining a rect that we ideally want the edit box to fit within.  Note that x2 and y2 in this measurement
        ' are RIGHT AND BOTTOM measurements, not WIDTH AND HEIGHT.
        Dim tmpRect As winRect
        CalculateDesiredEditBoxRect tmpRect
        
        'Next, retrieve the edit box's current rect.  If it's already in an ideal position, skip the move step entirely.
        Dim curRect As winRect
        If m_EditBox.GetPositionRect(curRect) Then
            
            If (tmpRect.x1 = curRect.x1) And (tmpRect.x2 = curRect.x2) And (tmpRect.y1 = curRect.y1) And (tmpRect.y2 = curRect.y2) Then
                needToMove = False
            End If
            
        End If
        
        'Apply the move conditionally
        If needToMove Then
            m_InternalResizeState = True
            m_EditBox.Move tmpRect.x1, tmpRect.y1, tmpRect.x2 - tmpRect.x1, tmpRect.y2 - tmpRect.y1
            m_InternalResizeState = False
        End If
        
    End If
    
End Sub

'When one of this control's components (either the underlying UC or the edit box) gets focus, call this function to update
' trackers and UI accordingly.
Private Sub ComponentGotFocus()

    'If a component already had focus, ignore this step, as focus is just changing internally within the control
    If (Not m_ControlHasFocus) Then
        m_ControlHasFocus = True
        RaiseEvent GotFocusAPI
    End If
    
    'The user control itself should never have focus.  Forward it to the API edit box as necessary.
    If (Not m_EditBox Is Nothing) Then
        If (Not m_EditBox.HasFocus) Then m_EditBox.SetFocusToEditBox
    End If
    
    'Regardless of component state, redraw the control "just in case"
    RelayUpdatedColorsToEditBox
    RedrawBackBuffer
    
End Sub

'When one of this control's components (either the underlying UC or the edit box) loses focus, call this function to update
' trackers and UI accordingly.
Private Sub ComponentLostFocus()
    
    'If focus has simply moved to another component within the control, ignore this step
    If m_ControlHasFocus And Not ucSupport.DoIHaveFocus Then
        If (Not m_EditBox Is Nothing) Then
            If (Not m_EditBox.HasFocus) Then
                m_ControlHasFocus = False
                RaiseEvent LostFocusAPI
            End If
        End If
    End If
    
    'Regardless of component state, redraw the control "just in case"
    RelayUpdatedColorsToEditBox
    RedrawBackBuffer
    
End Sub

Private Sub CalculateDesiredEditBoxRect(ByRef targetRect As winRect)
    With targetRect
        .x1 = EDITBOX_BORDER_PADDING
        .y1 = EDITBOX_BORDER_PADDING
        .x2 = ucSupport.GetControlWidth - EDITBOX_BORDER_PADDING
        .y2 = ucSupport.GetControlHeight - EDITBOX_BORDER_PADDING
    End With
End Sub

Private Sub CalculateDesiredUCRect(ByRef targetRect As winRect)
    With targetRect
        .x1 = ucSupport.GetControlLeft
        .y1 = ucSupport.GetControlTop
        .x2 = .x1 + m_EditBox.GetWidth + EDITBOX_BORDER_PADDING * 2
        .y2 = .y1 + m_EditBox.GetHeight + EDITBOX_BORDER_PADDING * 2
    End With
End Sub

Public Function PixelWidth() As Long
    PixelWidth = ucSupport.GetControlWidth
End Function

Public Function PixelHeight() As Long
    PixelHeight = ucSupport.GetControlHeight
End Function

'Generally speaking, the underlying API edit box management class recreates itself as needed, but we need to request its
' initial creation.  During this stage, we also auto-size ourself to match the edit box's suggested size (if it's a
' single-line instance; multiline boxes can be whatever vertical size we want).
Private Sub CreateEditBoxAPIWindow()
    
    If Not (m_EditBox Is Nothing) Then
        
        Dim tmpRect As winRect
        
        'Make sure all edit box settings are up-to-date prior to creation
        m_EditBox.Enabled = Me.Enabled
        RelayUpdatedColorsToEditBox
        
        'Resize ourselves vertically to match the edit box's suggested size.
        m_InternalResizeState = True
        If Not Me.Multiline Then
            ucSupport.RequestNewSize ucSupport.GetControlWidth, m_EditBox.SuggestedHeight + EDITBOX_BORDER_PADDING * 2, False
        End If
        m_InternalResizeState = False
        
        'Now that we're the proper size, determine where we're gonna stick the edit box (relative to this control instance)
        CalculateDesiredEditBoxRect tmpRect
        
        'Ask the edit box to create itself!
        m_EditBox.CreateEditBox UserControl.hWnd, tmpRect.x1, tmpRect.y1, tmpRect.x2 - tmpRect.x1, tmpRect.y2 - tmpRect.y1, False
        
        'Because contrl sizes may have changed, we need to repaint everything
        RedrawBackBuffer
        
        'Creating the edit box may have caused this control to resize itself, so as a failsafe, raise a
        ' Resize() event manually
        RaiseEvent Resize
    
    End If
    
End Sub

Private Sub UserControl_GotFocus()
    ComponentGotFocus
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
    ucSupport.RegisterControl UserControl.hWnd, False
    
    'Prep the color manager and load default colors
    Set m_Colors = New pdThemeColors
    Dim colorCount As PDEDITBOX_COLOR_LIST: colorCount = [_Count]
    m_Colors.InitializeColorList "PDEditBox", colorCount
    If Not MainModule.IsProgramRunning() Then UpdateColorList
    
End Sub

Private Sub UserControl_InitProperties()
    Enabled = True
    FontSize = 10
    Multiline = False
    Text = ""
End Sub

'At run-time, painting is handled by PD's pdWindowPainter class.  In the IDE, however, we must rely on VB's internal paint event.
Private Sub UserControl_Paint()
    ucSupport.RequestIDERepaint UserControl.hDC
End Sub

Private Sub UserControl_ReadProperties(PropBag As PropertyBag)
    With PropBag
        Enabled = .ReadProperty("Enabled", True)
        FontSize = .ReadProperty("FontSize", 10)
        Multiline = .ReadProperty("Multiline", False)
        Text = .ReadProperty("Text", "")
    End With
End Sub

Private Sub UserControl_Resize()
    If Not MainModule.IsProgramRunning() Then ucSupport.RequestRepaint True
End Sub

Private Sub UserControl_Terminate()
    Set m_EditBox = Nothing
End Sub

Private Sub UserControl_WriteProperties(PropBag As PropertyBag)
    With PropBag
        .WriteProperty "Enabled", Me.Enabled, True
        .WriteProperty "FontSize", Me.FontSize, 10
        .WriteProperty "Multiline", Me.Multiline, False
        .WriteProperty "Text", Me.Text, ""
    End With
End Sub

Private Sub UpdateControlLayout()
    SynchronizeSizes
    RedrawBackBuffer
End Sub

'After the back buffer has been correctly sized and positioned, this function handles the actual painting.  Similarly, for state changes
' that don't require a resize (e.g. gain/lose focus), this function should be used.
Private Sub RedrawBackBuffer()
    
    'We can improve shutdown performance by ignoring redraw requests when the program is going down
    If g_ProgramShuttingDown Then
        If (g_Themer Is Nothing) Then Exit Sub
    End If
    
    'Request the back buffer DC, and ask the support module to erase any existing rendering for us.
    Dim bufferDC As Long
    bufferDC = ucSupport.GetBackBufferDC(True, m_Colors.RetrieveColor(PDEB_Background, Me.Enabled, m_ControlHasFocus, m_MouseOverEditBox))
    
    'This control's render code relies on GDI+ exclusively, so there's no point calling it in the IDE - sorry!
    If MainModule.IsProgramRunning() And (bufferDC <> 0) Then
    
        'Relay any recently changed/modified colors to the edit box, so it can repaint itself to match
        RelayUpdatedColorsToEditBox
        
        'Retrieve DPI-aware control dimensions from the support class
        Dim bWidth As Long, bHeight As Long
        bWidth = ucSupport.GetBackBufferWidth
        bHeight = ucSupport.GetBackBufferHeight
        
        'The edit box doesn't actually have a border; we render a pseudo-border onto the underlying UC, as necessary.
        Dim halfPadding As Long
        halfPadding = 1     'EDITBOX_BORDER_PADDING \ 2 - 1
        
        Dim borderWidth As Single
        If Not (m_EditBox Is Nothing) Then
            If m_EditBox.HasFocus Or m_MouseOverEditBox Then borderWidth = 3 Else borderWidth = 1
        Else
            borderWidth = 1
        End If
        GDI_Plus.GDIPlusDrawRectOutlineToDC bufferDC, halfPadding, halfPadding, (bWidth - 1) - halfPadding, (bHeight - 1) - halfPadding, m_Colors.RetrieveColor(PDEB_Border, Me.Enabled, m_ControlHasFocus, m_MouseOverEditBox), , borderWidth, False, GP_LJ_Miter
    
    End If
    
    'Paint the final result to the screen, as relevant
    ucSupport.RequestRepaint
    If (Not MainModule.IsProgramRunning()) Then UserControl.Refresh
    
End Sub

'Before this control does any painting, we need to retrieve relevant colors from PD's primary theming class.  Note that this
' step must also be called if/when PD's visual theme settings change.
Private Sub UpdateColorList()
        
    'Color list retrieval is pretty darn easy - just load each color one at a time, and leave the rest to the color class.
    ' It will build an internal hash table of the colors we request, which makes rendering much faster.
    With m_Colors
        .LoadThemeColor PDEB_Background, "Background", IDE_WHITE
        .LoadThemeColor PDEB_Border, "Border", IDE_BLUE
        .LoadThemeColor PDEB_Text, "Text", IDE_GRAY
    End With
    
    RelayUpdatedColorsToEditBox
    
End Sub

'When this control has special knowledge of a state change that affects the edit box's visual appearance, call this function.
' It will relay the relevant themed colors to the edit box class.
Private Sub RelayUpdatedColorsToEditBox()
    If (Not m_EditBox Is Nothing) Then
        m_EditBox.BackColor = m_Colors.RetrieveColor(PDEB_Background, Me.Enabled, m_ControlHasFocus, m_MouseOverEditBox)
        m_EditBox.TextColor = m_Colors.RetrieveColor(PDEB_Text, Me.Enabled, m_ControlHasFocus, m_MouseOverEditBox)
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
    If (Not m_EditBox Is Nothing) Then
        Dim targetHWnd As Long
        If m_EditBox.hWnd = 0 Then targetHWnd = UserControl.hWnd Else targetHWnd = m_EditBox.hWnd
        ucSupport.AssignTooltip targetHWnd, newTooltip, newTooltipTitle, newTooltipIcon
    End If
End Sub
