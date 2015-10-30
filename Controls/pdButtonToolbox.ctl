VERSION 5.00
Begin VB.UserControl pdButtonToolbox 
   Appearance      =   0  'Flat
   BackColor       =   &H80000005&
   ClientHeight    =   3600
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   4800
   ClipBehavior    =   0  'None
   BeginProperty Font 
      Name            =   "Tahoma"
      Size            =   9.75
      Charset         =   0
      Weight          =   400
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   HasDC           =   0   'False
   HitBehavior     =   0  'None
   PaletteMode     =   4  'None
   ScaleHeight     =   240
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   320
   ToolboxBitmap   =   "pdButtonToolbox.ctx":0000
End
Attribute VB_Name = "pdButtonToolbox"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon Toolbox Button control
'Copyright 2014-2015 by Tanner Helland
'Created: 19/October/14
'Last updated: 12/January/15
'Last update: rewrite control to handle its own caption and tooltip translations
'
'In a surprise to precisely no one, PhotoDemon has some unique needs when it comes to user controls - needs that
' the intrinsic VB controls can't handle.  These range from the obnoxious (lack of an "autosize" property for
' anything but labels) to the critical (no Unicode support).
'
'As such, I've created many of my own UCs for the program.  All are owner-drawn, with the goal of maintaining
' visual fidelity across the program, while also enabling key features like Unicode support.
'
'A few notes on this toolbox button control, specifically:
'
' 1) Why make a separate control for toolbox buttons?  I could add a style property to the regular PD button, but I don't
'     like the complications that introduces.  "Do one thing and do it well" is the idea with PD user controls.
' 2) High DPI settings are handled automatically.
' 3) A hand cursor is automatically applied, and clicks are returned via the Click event.
' 4) Coloration is automatically handled by PD's internal theming engine.
' 5) This button does not support text, by design.  It is image-only.
' 6) This button does not automatically set its Value property when clicked.  It simply raises a Click() event.  This is
'     by design to make it easier to toggle state in the toolbox maintenance code.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'This control really only needs one event raised - Click
Public Event Click()

'Because VB focus events are wonky, especially when we use CreateWindow within a UC, this control raises its own
' specialized focus events.  If you need to track focus, use these instead of the default VB functions.
Public Event GotFocusAPI()
Public Event LostFocusAPI()

'Current button state; TRUE if down, FALSE if up.  Note that this may not correspond with mouse state, depending on
' button properties (buttons can toggle in various ways).
Private m_ButtonState As Boolean

'Button images.  (Since this control doesn't support text, you'd better make use of these!)
Private btImage As pdDIB                'You must specify this image manually, at run-time.
Private btImageDisabled As pdDIB        'Auto-created disabled version of the image.
Private btImageHover As pdDIB           'Auto-created hover (glow) version of the image.

'As of Feb 2015, this control also supports unique images when depressed.  This feature is optional!
Private btImage_Pressed As pdDIB
Private btImageHover_Pressed As pdDIB   'Auto-created hover (glow) version of the image.

'(x, y) position of the button image.  This is auto-calculated by the control.
Private btImageCoords As POINTAPI

'Current back color.  Because this control sits on a variety of places in PD (like the canvas status bar), its BackColor
' sometimes needs to be set manually.
Private m_BackColor As OLE_COLOR

'AutoToggle mode allows the button to operate as a normal button (e.g. no persistent value)
Private m_AutoToggle As Boolean

'StickyToggle mode allows the button to operate as a checkbox (e.g. a persistent value, that switches on every click)
Private m_StickyToggle As Boolean

'In some circumstances, an image alone is sufficient for indicating "pressed" state.  This value tells the control to *not* render a custom
' highlight state when a button is depressed.
Private m_DontHighlightDownState As Boolean

'User control support class.  Historically, many classes (and associated subclassers) were required by each user control,
' but I've since attempted to wrap these into a single master control support class.
Private WithEvents ucSupport As pdUCSupport
Attribute ucSupport.VB_VarHelpID = -1

'This toolbox button control is designed to be used in a "radio button"-like system, where buttons exist in a group, and the
' pressing of one results in the unpressing of any others.  For the rare circumstances where this behavior is undesirable
' (e.g. the pdCanvas status bar, where some instances of this control serve as actual buttons), the AutoToggle property can
' be set to TRUE.  This will cause the button to operate as a normal command button, which depresses on MouseDown and raises
' on MouseUp.
Public Property Get AutoToggle() As Boolean
    AutoToggle = m_AutoToggle
End Property

Public Property Let AutoToggle(ByVal newToggle As Boolean)
    m_AutoToggle = newToggle
End Property

'BackColor is an important property for this control, as it may sit on other controls whose backcolor is not guaranteed in advance.
' So we can't rely on theming alone to determine this value.
Public Property Get BackColor() As OLE_COLOR
    BackColor = m_BackColor
End Property

Public Property Let BackColor(ByVal newColor As OLE_COLOR)
    m_BackColor = newColor
    RedrawBackBuffer
End Property

'In some circumstances, an image alone is sufficient for indicating "pressed" state.  This value tells the control to *not* render a custom
' highlight state when button state is TRUE (pressed).
Public Property Get DontHighlightDownState() As Boolean
    DontHighlightDownState = m_DontHighlightDownState
End Property

Public Property Let DontHighlightDownState(ByVal newState As Boolean)
    m_DontHighlightDownState = newState
    If Value Then RedrawBackBuffer
End Property

'The Enabled property is a bit unique; see http://msdn.microsoft.com/en-us/library/aa261357%28v=vs.60%29.aspx
Public Property Get Enabled() As Boolean
Attribute Enabled.VB_UserMemId = -514
    Enabled = UserControl.Enabled
End Property

Public Property Let Enabled(ByVal newValue As Boolean)
    
    UserControl.Enabled = newValue
    PropertyChanged "Enabled"
    
    'Redraw the control
    RedrawBackBuffer
    
End Property

'Sticky toggle allows this button to operate as a checkbox, where each click toggles its value.  If I was smart, I would have implemented
' the button's toggle behavior as a single property with multiple enum values, but I didn't think of it in advance, so now I'm stuck
' with this.  Do not set both StickyToggle and AutoToggle, as the button will not behave correctly.
Public Property Get StickyToggle() As Boolean
    StickyToggle = m_StickyToggle
End Property

Public Property Let StickyToggle(ByVal newValue As Boolean)
    m_StickyToggle = newValue
End Property

'hWnds aren't exposed by default
Public Property Get hWnd() As Long
Attribute hWnd.VB_UserMemId = -515
    hWnd = UserControl.hWnd
End Property

'Container hWnd must be exposed for external tooltip handling
Public Property Get ContainerHwnd() As Long
    ContainerHwnd = UserControl.ContainerHwnd
End Property

'The most relevant part of this control is this Value property, which is important since this button operates as a toggle.
Public Property Get Value() As Boolean
    Value = m_ButtonState
End Property

Public Property Let Value(ByVal newValue As Boolean)
    
    'Update our internal value tracker, but only if autotoggle is not active.  (Autotoggle causes the button to behave like
    ' a normal button, so there's no concept of a persistent "value".)
    If (m_ButtonState <> newValue) And (Not m_AutoToggle) Then
    
        m_ButtonState = newValue
        
        'Redraw the control to match the new state
        RedrawBackBuffer
        
        'Note that we don't raise a Click event here.  This is by design.  The toolbox handles all toggle code for these buttons,
        ' and it's more efficient to let it handle this, as it already has a detailed notion of things like program state, which
        ' affects whether buttons are clickable, etc.
        
        'As such, the Click event is not raised for Value changes alone - only for actions initiated by actual user input.
        
    End If
    
End Property

'Assign a DIB to this button.  Matching disabled and hover state DIBs are automatically generated.
' Note that you can supply an existing DIB, or a resource name.  You must supply one or the other (obviously).
' No preprocessing is currently applied to DIBs loaded as a resource.
Public Sub AssignImage(Optional ByVal resName As String = "", Optional ByRef srcDIB As pdDIB, Optional ByVal scalePixelsWhenDisabled As Long = 0, Optional ByVal customGlowWhenHovered As Long = 0)
    
    'Load the requested resource DIB, as necessary
    If Len(resName) <> 0 Then loadResourceToDIB resName, srcDIB
        
    'Start by making a copy of the source DIB
    Set btImage = New pdDIB
    btImage.createFromExistingDIB srcDIB
        
    'Next, create a grayscale copy of the image for the disabled state
    Set btImageDisabled = New pdDIB
    btImageDisabled.createFromExistingDIB btImage
    GrayscaleDIB btImageDisabled, True
    If scalePixelsWhenDisabled <> 0 Then ScaleDIBRGBValues btImageDisabled, scalePixelsWhenDisabled, True
    
    'Finally, create a "glowy" hovered version of the DIB for hover state
    Set btImageHover = New pdDIB
    btImageHover.createFromExistingDIB btImage
    If customGlowWhenHovered = 0 Then
        ScaleDIBRGBValues btImageHover, UC_HOVER_BRIGHTNESS, True
    Else
        ScaleDIBRGBValues btImageHover, customGlowWhenHovered, True
    End If
    
    'Request a control layout update, which will also calculate a centered position for the new image
    UpdateControlLayout

End Sub

'Assign an *OPTIONAL* special DIB to this button, to be used only when the button is pressed.  A disabled-state image is not generated,
' but a hover-state one is.
'
'IMPORTANT NOTE!  To reduce resource usage, PD requires that this optional "pressed" image have identical dimensions to the primary image.
' This greatly simplifies layout and painting issues, so I do not expect to change it.
'
'Note that you can supply an existing DIB, or a resource name.  You must supply one or the other (obviously).  No preprocessing is currently
' applied to DIBs loaded as a resource, but in the future we will need to deal with high-DPI concerns.
Public Sub AssignImage_Pressed(Optional ByVal resName As String = "", Optional ByRef srcDIB As pdDIB, Optional ByVal scalePixelsWhenDisabled As Long = 0, Optional ByVal customGlowWhenHovered As Long = 0)
    
    'Load the requested resource DIB, as necessary
    If Len(resName) <> 0 Then loadResourceToDIB resName, srcDIB
    
    'Start by making a copy of the source DIB
    Set btImage_Pressed = New pdDIB
    btImage_Pressed.createFromExistingDIB srcDIB
    
    'Also create a "glowy" hovered version of the DIB for hover state
    Set btImageHover_Pressed = New pdDIB
    btImageHover_Pressed.createFromExistingDIB btImage_Pressed
    If customGlowWhenHovered = 0 Then
        ScaleDIBRGBValues btImageHover_Pressed, UC_HOVER_BRIGHTNESS, True
    Else
        ScaleDIBRGBValues btImageHover_Pressed, customGlowWhenHovered, True
    End If
    
    'If the control is currently pressed, request a redraw
    If Value Then RedrawBackBuffer

End Sub

'A few key events are also handled
Private Sub ucSupport_KeyDownCustom(ByVal Shift As ShiftConstants, ByVal vkCode As Long, markEventHandled As Boolean)
        
    'If space is pressed, and our value is not true, raise a click event.
    If (vkCode = VK_SPACE) Then

        If ucSupport.DoIHaveFocus And Me.Enabled Then
        
            'Sticky toggle mode causes the button to toggle between true/false
            If m_StickyToggle Then
            
                Value = Not Value
                RedrawBackBuffer
                RaiseEvent Click
            
            'Other modes behave identically
            Else
            
                If (Not m_ButtonState) Then
                    Value = True
                    RedrawBackBuffer
                    RaiseEvent Click
                End If
            
            End If
            
        End If
        
    End If

End Sub

Private Sub ucSupport_KeyUpCustom(ByVal Shift As ShiftConstants, ByVal vkCode As Long, markEventHandled As Boolean)

    'If space was pressed, and AutoToggle is active, remove the button state and redraw it
    If (vkCode = VK_SPACE) Then

        If Me.Enabled And Value And m_AutoToggle Then
            Value = False
            RedrawBackBuffer
        End If
        
    End If

End Sub

'To improve responsiveness, MouseDown is used instead of Click.
' (TODO: switch to MouseUp, so we have a chance to draw the down button state and provide some visual feedback)
Private Sub ucSupport_MouseDownCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)

    If Me.Enabled Then
        
        'Sticky toggle allows the button to operate as a checkbox
        If m_StickyToggle Then
            Value = Not Value
        
        'Non-sticky toggle modes will always cause the button to be TRUE on a MouseDown event
        Else
            If (Not Value) Then Value = True
        End If
        
        RedrawBackBuffer True
        RaiseEvent Click
        
    End If
        
End Sub

Private Sub ucSupport_MouseEnter(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    ucSupport.RequestCursor IDC_HAND
    RedrawBackBuffer
End Sub

'When the mouse leaves the UC, we must repaint the button (as it's no longer hovered)
Private Sub ucSupport_MouseLeave(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    ucSupport.RequestCursor IDC_DEFAULT
    RedrawBackBuffer
End Sub

Private Sub ucSupport_MouseUpCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal ClickEventAlsoFiring As Boolean)
    
    'If toggle mode is active, remove the button's TRUE state and redraw it
    If m_AutoToggle And Value Then Value = False
    RedrawBackBuffer
    
End Sub

Private Sub ucSupport_GotFocusAPI()
    RedrawBackBuffer
    RaiseEvent GotFocusAPI
End Sub

Private Sub ucSupport_LostFocusAPI()
    RedrawBackBuffer
    RaiseEvent LostFocusAPI
End Sub

Private Sub ucSupport_RepaintRequired(ByVal updateLayoutToo As Boolean)
    If updateLayoutToo Then UpdateControlLayout
    RedrawBackBuffer
End Sub

Private Sub ucSupport_WindowResize(ByVal newWidth As Long, ByVal newHeight As Long)
    UpdateControlLayout
    RedrawBackBuffer
End Sub

'INITIALIZE control
Private Sub UserControl_Initialize()
    
    'Initialize a master user control support class
    Set ucSupport = New pdUCSupport
    ucSupport.RegisterControl UserControl.hWnd
    
    'Request some additional input functionality (custom mouse and key events)
    ucSupport.RequestExtraFunctionality True, True
    ucSupport.SpecifyRequiredKeys VK_SPACE
    
    'In design mode, initialize a base theming class, so our paint functions don't fail
    If g_Themer Is Nothing Then Set g_Themer = New pdVisualThemes
        
    'Update the control size parameters at least once
    UpdateControlLayout
                
End Sub

'Set default properties
Private Sub UserControl_InitProperties()
    Value = False
    BackColor = vbWhite
    AutoToggle = False
    StickyToggle = False
    DontHighlightDownState = False
End Sub

'At run-time, painting is handled by the support class.  In the IDE, however, we must rely on VB's internal paint event.
Private Sub UserControl_Paint()
    ucSupport.RequestIDERepaint UserControl.hDC
End Sub

Private Sub UserControl_ReadProperties(PropBag As PropertyBag)
    With PropBag
        m_BackColor = .ReadProperty("BackColor", vbWhite)
        AutoToggle = .ReadProperty("AutoToggle", False)
        m_DontHighlightDownState = .ReadProperty("DontHighlightDownState", False)
        StickyToggle = .ReadProperty("StickyToggle", False)
    End With
End Sub

Private Sub UserControl_Resize()
    If Not g_IsProgramRunning Then ucSupport.RequestRepaint True
End Sub

Private Sub UserControl_WriteProperties(PropBag As PropertyBag)
    With PropBag
        .WriteProperty "BackColor", m_BackColor, vbWhite
        .WriteProperty "AutoToggle", m_AutoToggle, False
        .WriteProperty "DontHighlightDownState", m_DontHighlightDownState, False
        .WriteProperty "StickyToggle", m_StickyToggle, False
    End With
End Sub

'Because this control automatically forces all internal buttons to identical sizes, we have to recalculate a number
' of internal sizing metrics whenever the control size changes.
Private Sub UpdateControlLayout()
    
    'Retrieve DPI-aware control dimensions from the support class
    Dim bWidth As Long, bHeight As Long
    bWidth = ucSupport.GetBackBufferWidth
    bHeight = ucSupport.GetBackBufferHeight
    
    'Determine positioning of the button image, if any
    If Not (btImage Is Nothing) Then
        btImageCoords.x = (bWidth - btImage.getDIBWidth) \ 2
        btImageCoords.y = (bHeight - btImage.getDIBHeight) \ 2
    End If
            
End Sub

'Use this function to completely redraw the back buffer from scratch.  Note that this is computationally expensive compared to just flipping the
' existing buffer to the screen, so only redraw the backbuffer if the control state has somehow changed.
Private Sub RedrawBackBuffer(Optional ByVal raiseImmediateDrawEvent As Boolean = False)
    
    If g_IsProgramRunning Then
    
        'Colors used throughout this paint function are determined by several factors:
        ' 1) Control enablement (disabled buttons are grayed)
        ' 2) Hover state (hovered buttons glow)
        ' 3) Value (pressed buttons have a different appearance, obviously)
        ' 4) The central themer (which contains default values for all these scenarios)
        Dim btnColorBorder As Long, btnColorFill As Long
        Dim curColor As Long
        
        If Me.Enabled Then
        
            'Is the button pressed?
            If m_ButtonState And (Not m_DontHighlightDownState) Then
                btnColorFill = g_Themer.GetThemeColor(PDTC_ACCENT_ULTRALIGHT)
                btnColorBorder = g_Themer.GetThemeColor(PDTC_ACCENT_HIGHLIGHT)
                
            'The button is not pressed
            Else
            
                'In AutoToggle mode, use mouse state to determine coloring
                If m_AutoToggle And ucSupport.IsMouseButtonDown(pdLeftButton) Then
                    btnColorFill = g_Themer.GetThemeColor(PDTC_ACCENT_ULTRALIGHT)
                    btnColorBorder = g_Themer.GetThemeColor(PDTC_ACCENT_HIGHLIGHT)
                Else
                    If ucSupport.IsMouseInside Then
                        btnColorFill = m_BackColor
                        btnColorBorder = g_Themer.GetThemeColor(PDTC_ACCENT_DEFAULT)
                    Else
                        btnColorFill = m_BackColor
                        btnColorBorder = m_BackColor
                    End If
                End If
            End If
            
        'The button is disabled
        Else
            btnColorFill = m_BackColor
            btnColorBorder = m_BackColor
        End If
        
        'Request the back buffer DC, and ask the support module to erase any existing rendering for us.
        Dim bufferDC As Long, bWidth As Long, bHeight As Long
        bufferDC = ucSupport.GetBackBufferDC(True, btnColorFill)
        bWidth = ucSupport.GetBackBufferWidth
        bHeight = ucSupport.GetBackBufferHeight
        
        'A single-pixel border is always drawn around the control
        GDI_Plus.GDIPlusDrawRectOutlineToDC bufferDC, 0, 0, bWidth - 1, bHeight - 1, btnColorBorder, 255, 1
        
        'Paint the image, if any
        If Not (btImage Is Nothing) Then
            
            If Me.Enabled Then
                If Value And (Not (btImage_Pressed Is Nothing)) Then
                    If ucSupport.IsMouseInside Then
                        btImageHover_Pressed.alphaBlendToDC bufferDC, 255, btImageCoords.x, btImageCoords.y
                    Else
                        btImage_Pressed.alphaBlendToDC bufferDC, 255, btImageCoords.x, btImageCoords.y
                    End If
                Else
                    If ucSupport.IsMouseInside Then
                        btImageHover.alphaBlendToDC bufferDC, 255, btImageCoords.x, btImageCoords.y
                    Else
                        btImage.alphaBlendToDC bufferDC, 255, btImageCoords.x, btImageCoords.y
                    End If
                End If
            Else
                btImageDisabled.alphaBlendToDC bufferDC, 255, btImageCoords.x, btImageCoords.y
            End If
            
        End If
        
    End If
    
    'Paint the final result to the screen, as relevant
    ucSupport.RequestRepaint raiseImmediateDrawEvent
    
End Sub

'The color selector dialog has the unique need of capturing colors from anywhere on the screen, using a custom hook solution.  For it to work,
' the pdInputMouse class inside this button control must forcibly release its capture.
' NOTE: this behavior has been disabled pending additional testing.  It causes some nasty side-effects on Win 10, and it's eclectic enough
'        that fixing it isn't an immediate priority.
'Public Sub OverrideMouseCapture(ByVal newState As Boolean)
'    cMouseEvents.setCaptureOverride newState
'    cMouseEvents.setCursorOverrideState newState
'End Sub

'External functions can call this to request a redraw.  This is helpful for live-updating theme settings, as in the Preferences dialog.
Public Sub UpdateAgainstCurrentTheme()
    If g_IsProgramRunning Then ucSupport.UpdateAgainstThemeAndLanguage
End Sub

'By design, PD prefers to not use design-time tooltips.  Apply tooltips at run-time, using this function.
' (IMPORTANT NOTE: translations are handled automatically.  Always pass the original English text!)
Public Sub AssignTooltip(ByVal newTooltip As String, Optional ByVal newTooltipTitle As String, Optional ByVal newTooltipIcon As TT_ICON_TYPE = TTI_NONE)
    ucSupport.AssignTooltip UserControl.ContainerHwnd, newTooltip, newTooltipTitle, newTooltipIcon
End Sub

