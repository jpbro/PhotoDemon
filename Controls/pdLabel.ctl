VERSION 5.00
Begin VB.UserControl pdLabel 
   BackColor       =   &H80000005&
   CanGetFocus     =   0   'False
   ClientHeight    =   690
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   3945
   DrawStyle       =   5  'Transparent
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
   ScaleHeight     =   46
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   263
   ToolboxBitmap   =   "pdLabel.ctx":0000
End
Attribute VB_Name = "pdLabel"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon Unicode Label control
'Copyright 2014-2017 by Tanner Helland
'Created: 28/October/14
'Last updated: 02/November/15
'Last update: convert to ucSupport.  This control was a messy one, but it has the most to gain from program-level
'             font caching (vs each control maintaining its own font copy).
'
'In a surprise to precisely no one, PhotoDemon has some unique needs when it comes to user controls - needs that
' the intrinsic VB controls can't handle.  These range from the obnoxious (lack of an "autosize" property for
' anything but labels) to the critical (no Unicode support).
'
'As such, I've created many of my own UCs for the program.  All are owner-drawn, with the goal of maintaining
' visual fidelity across the program, while also enabling key features like Unicode support.
'
'A few notes on this label control, specifically:
'
' 1) This label uses an either/or system for its size: either the control is auto-sized based on caption length, or the
'    caption font is automatically shrunk until the caption can fit within the control border region.
' 2) High DPI settings are handled automatically.
' 3) By design, this control does not accept focus, and it does not raise any input-related events.
' 4) Coloration is automatically handled by PD's internal theming engine.
' 5) RTL language support is a work in progress.  I've designed the control so that RTL support can be added simply by
'    fixing some layout issues in this control, without the need to modify any control instances throughout PD.
'    However, working out any bugs is difficult without an RTL language to test, so further work has been postponed
'    for now.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'This control raises no events, by design.

'Rather than handle autosize and wordwrap separately, this control combines them into a single "Layout" property.
' All four possible layout approaches are covered by this enum.
Public Enum PD_LABEL_LAYOUT
    AutoFitCaption = 0
    AutoFitCaptionPlusWordWrap = 1
    AutoSizeControl = 2
    AutoSizeControlPlusWordWrap = 3
End Enum

#If False Then
    Private Const AutoFitCaption = 0, AutoFitCaptionPlusWordWrap = 1, AutoSizeControl = 2, AutoSizeControlPlusWordWrap = 3
#End If

'Control (and caption) layout
Private m_Layout As PD_LABEL_LAYOUT

'Normally, we let this control automatically determine its colors according to the current theme.  However, in some rare cases
' (like the pdCanvas status bar), we may want to override the automatic BackColor with a custom one.  Two variables are used
' for this: a BackColor/ForeColor property (which is normally ignored), and a boolean flag property "UseCustomBack/ForeColor".
Private m_BackColor As OLE_COLOR
Private m_UseCustomBackColor As Boolean

Private m_ForeColor As OLE_COLOR
Private m_UseCustomForeColor As Boolean

'On certain layouts, this control will try to shrink the caption to fit within the control.  If it cannot physically do it
' (because we run out of font sizes), this failure state will be set to TRUE.  When that happens, ellipses will be added to
' the control caption.
Private m_FitFailure As Boolean

'User control support class.  Historically, many classes (and associated subclassers) were required by each user control,
' but I've since attempted to wrap these into a single master control support class.
Private WithEvents ucSupport As pdUCSupport
Attribute ucSupport.VB_VarHelpID = -1

'Local list of themable colors.  This list includes all potential colors used by this class, regardless of state change
' or internal control settings.  The list is updated by calling the UpdateColorList function.
' (Note also that this list does not include variants, e.g. "BorderColor" vs "BorderColor_Hovered".  Variant values are
'  automatically calculated by the color management class, and they are retrieved by passing boolean modifiers to that
'  class, rather than treating every imaginable variant as a separate constant.)
Private Enum PDLABEL_COLOR_LIST
    [_First] = 0
    PDL_Background = 0
    PDL_Caption = 1
    [_Last] = 1
    [_Count] = 2
End Enum

'Color retrieval and storage is handled by a dedicated class; this allows us to optimize theme interactions,
' without worrying about the details locally.
Private m_Colors As pdThemeColors

Public Function GetControlType() As PD_ControlType
    GetControlType = pdct_Label
End Function

Public Function GetControlName() As String
    GetControlName = UserControl.Extender.Name
End Function

'Alignment is handled just like VB's internal label alignment property.
Public Property Get Alignment() As AlignmentConstants
    Alignment = ucSupport.GetCaptionAlignment()
End Property

Public Property Let Alignment(ByVal newAlignment As AlignmentConstants)
    ucSupport.SetCaptionAlignment newAlignment
    If (Not MainModule.IsProgramRunning()) Then UpdateControlLayout
    PropertyChanged "Alignment"
End Property

Public Property Get BackColor() As OLE_COLOR
    BackColor = m_BackColor
End Property

Public Property Let BackColor(ByVal newColor As OLE_COLOR)
    If m_BackColor <> newColor Then
        m_BackColor = newColor
        RedrawBackBuffer
    End If
End Property

'Caption is handled just like the common control label's caption property.  It is valid at design-time, and any translation,
' if present, will not be processed until run-time.
' IMPORTANT NOTE: only the ENGLISH caption is returned.  I don't have a reason for returning a translated caption (if any),
'                  but I can revisit in the future if that ever becomes relevant.
Public Property Get Caption() As String
Attribute Caption.VB_UserMemId = -518
Attribute Caption.VB_MemberFlags = "200"
    Caption = ucSupport.GetCaptionText
End Property

Public Property Let Caption(ByRef newCaption As String)
    
    ucSupport.SetCaptionText newCaption
    
    'Normally we would rely on the ucSupport class to raise redraw events for us, but this label control is a weird one,
    ' since we may need to resize the entire control when the caption changes.  As such, force an immediate layout update.
    UpdateControlLayout
    
    PropertyChanged "Caption"
    
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

Public Property Get FontBold() As Boolean
    FontBold = ucSupport.GetCaptionFontBold
End Property

Public Property Let FontBold(ByVal newBoldSetting As Boolean)
    ucSupport.SetCaptionFontBold newBoldSetting
    PropertyChanged "FontBold"
End Property

Public Property Get FontItalic() As Boolean
    FontItalic = ucSupport.GetCaptionFontItalic
End Property

Public Property Let FontItalic(ByVal newItalicSetting As Boolean)
    ucSupport.SetCaptionFontItalic newItalicSetting
    PropertyChanged "FontItalic"
End Property

Public Property Get FontSize() As Single
    FontSize = ucSupport.GetCaptionFontSize
End Property

Public Property Let FontSize(ByVal newSize As Single)
    ucSupport.SetCaptionFontSize newSize
    PropertyChanged "FontSize"
End Property

Public Property Get ForeColor() As OLE_COLOR
    ForeColor = m_ForeColor
End Property

Public Property Let ForeColor(ByVal newColor As OLE_COLOR)
    If m_ForeColor <> newColor Then
        m_ForeColor = newColor
        RedrawBackBuffer
    End If
End Property

Public Property Get Layout() As PD_LABEL_LAYOUT
    Layout = m_Layout
End Property

Public Property Let Layout(ByVal newLayout As PD_LABEL_LAYOUT)
    m_Layout = newLayout
    UpdateControlLayout
End Property

Public Property Get UseCustomBackColor() As Boolean
    UseCustomBackColor = m_UseCustomBackColor
End Property

Public Property Let UseCustomBackColor(ByVal newSetting As Boolean)
    If newSetting <> m_UseCustomBackColor Then
        m_UseCustomBackColor = newSetting
        RedrawBackBuffer
    End If
End Property

Public Property Get UseCustomForeColor() As Boolean
    UseCustomForeColor = m_UseCustomForeColor
End Property

Public Property Let UseCustomForeColor(ByVal newSetting As Boolean)
    If newSetting <> m_UseCustomForeColor Then
        m_UseCustomForeColor = newSetting
        RedrawBackBuffer
    End If
End Property

Private Sub ucSupport_MouseEnter(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    ucSupport.RequestCursor IDC_ARROW
End Sub

Private Sub ucSupport_RepaintRequired(ByVal updateLayoutToo As Boolean)
    If updateLayoutToo Then UpdateControlLayout Else RedrawBackBuffer
End Sub

'hWnds aren't exposed by default
Public Property Get hWnd() As Long
Attribute hWnd.VB_UserMemId = -515
    hWnd = UserControl.hWnd
End Property

'Container hWnd must be exposed for external tooltip handling
Public Property Get ContainerHwnd() As Long
    ContainerHwnd = UserControl.ContainerHwnd
End Property

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

Public Sub SetPosition(ByVal newLeft As Long, ByVal newTop As Long)
    ucSupport.RequestNewPosition newLeft, newTop
End Sub

Public Sub SetPositionAndSize(ByVal newLeft As Long, ByVal newTop As Long, ByVal newWidth As Long, ByVal newHeight As Long)
    ucSupport.RequestFullMove newLeft, newTop, newWidth, newHeight, True
End Sub

'INITIALIZE control
Private Sub UserControl_Initialize()
    
    'Initialize a master user control support class
    Set ucSupport = New pdUCSupport
    ucSupport.RegisterControl UserControl.hWnd, False
    ucSupport.RequestExtraFunctionality True
    ucSupport.RequestCaptionSupport False
    ucSupport.SetCaptionAutomaticPainting False
    
    'Prep the color manager and load default colors
    Set m_Colors = New pdThemeColors
    Dim colorCount As PDLABEL_COLOR_LIST: colorCount = [_Count]
    m_Colors.InitializeColorList "GenericPDControl", colorCount
    If Not MainModule.IsProgramRunning() Then UpdateColorList
    
End Sub

'Set default properties
Private Sub UserControl_InitProperties()
        
    Alignment = vbLeftJustify
    Caption = "caption"
    Layout = AutoFitCaption
    
    BackColor = vbWindowBackground
    UseCustomBackColor = False
    
    ForeColor = RGB(96, 96, 96)
    UseCustomForeColor = False
    
    FontBold = False
    FontItalic = False
    FontSize = 10
    
End Sub

'At run-time, painting is handled by PD's pdWindowPainter class.  In the IDE, however, we must rely on VB's internal paint event.
Private Sub UserControl_Paint()
    ucSupport.RequestIDERepaint UserControl.hDC
End Sub

Private Sub UserControl_ReadProperties(PropBag As PropertyBag)

    With PropBag
        Alignment = .ReadProperty("Alignment", vbLeftJustify)
        BackColor = .ReadProperty("BackColor", vbWindowBackground)
        Caption = .ReadProperty("Caption", "caption")
        FontBold = .ReadProperty("FontBold", False)
        FontItalic = .ReadProperty("FontItalic", False)
        FontSize = .ReadProperty("FontSize", 10)
        ForeColor = .ReadProperty("ForeColor", RGB(96, 96, 96))
        Layout = .ReadProperty("Layout", AutoFitCaption)
        UseCustomBackColor = .ReadProperty("UseCustomBackColor", False)
        UseCustomForeColor = .ReadProperty("UseCustomForeColor", False)
    End With

End Sub

Private Sub UserControl_Resize()
    If (Not MainModule.IsProgramRunning()) Then ucSupport.NotifyIDEResize UserControl.Width, UserControl.Height
End Sub

Private Sub UserControl_WriteProperties(PropBag As PropertyBag)

    'Store all associated properties
    With PropBag
        .WriteProperty "Alignment", Alignment, vbLeftJustify
        .WriteProperty "BackColor", m_BackColor, vbWindowBackground
        .WriteProperty "Caption", Caption, "caption"
        .WriteProperty "FontBold", FontBold, False
        .WriteProperty "FontItalic", FontItalic, False
        .WriteProperty "FontSize", FontSize, 10
        .WriteProperty "ForeColor", m_ForeColor, RGB(96, 96, 96)
        .WriteProperty "Layout", m_Layout, AutoFitCaption
        .WriteProperty "UseCustomBackColor", m_UseCustomBackColor, False
        .WriteProperty "UseCustomForeColor", m_UseCustomForeColor, False
    End With
    
End Sub

'Because this control supports a variety of text layouts, we have to recalculate our internal sizing metrics under
' a number of different conditions.  This "catch-all" function handles all resize/fit responsibilities.
Private Sub UpdateControlLayout()
    
    'Retrieve DPI-aware control dimensions from the support class
    Dim bWidth As Long, bHeight As Long
    bWidth = ucSupport.GetBackBufferWidth
    bHeight = ucSupport.GetBackBufferHeight
    
    'Depending on the layout in use (e.g. autosize vs non-autosize), we may need to reposition the user control.
    ' Right-aligned labels in particular must have their .Left property modified, any time the .Width property is modified.
    ' To facilitate this behavior, we'll store the original label's width and height; this will let us know how far we
    ' need to move the label, if any.
    Dim controlRect As RECTL, controlWidth As Long, controlHeight As Long
    ucSupport.GetControlRect controlRect
    controlWidth = controlRect.Right - controlRect.Left
    controlHeight = controlRect.Bottom - controlRect.Top
    
    'Different layout styles will modify the control's behavior based on the width (normal labels) or height
    ' (wordwrap labels) of the current caption
    Dim stringWidth As Long, stringHeight As Long
    
    'The end goal of this process is to end up with an appropriate control size.  When auto-fitting text, this process is
    ' fairly simple; we simply want to make sure the label is tall enough for the selected font.  For autosized labels,
    ' the process is significantly more convoluted.
    
    'Each caption layout has its own considerations.  We'll handle all four possibilities in turn.
    Select Case m_Layout
    
        'Auto-fit caption requires the control caption to fit entirely within the control's boundaries, with no provision
        ' for word-wrapping.  Most of the nasty work of this case is handled by ucSupport (which wraps pdCaption).
        Case AutoFitCaption
            
            'Measure the font relative to the current control size
            ucSupport.SetCaptionWordWrap False
            stringWidth = ucSupport.GetCaptionWidth(True)
            stringHeight = ucSupport.GetCaptionHeight()
            
            'If the font is at its normal size (e.g. autofit is not required), there is a small chance that the label will
            ' still not be tall enough (vertically) to hold it.  This is due to rendering differences between system fonts
            ' on different OSes.  As such, we always perform a failsafe check on the label's height, and increase it if necessary.
            If (stringHeight > controlHeight) Then ucSupport.RequestNewSize controlWidth, stringHeight
            
            'If the caption still does not fit within the available area (because it's so damn large that we can't physically
            ' shrink the font enough to compensate), set the failure state to TRUE.
            If stringWidth > controlWidth Then
                m_FitFailure = True
            Else
                m_FitFailure = False
            End If
            
        'Identical to the auto-fit steps above, but instead of fitting the caption horizontally, we fit it vertically.
        Case AutoFitCaptionPlusWordWrap
            
            'We don't actually need to do anything here; just set the caption wordwrap state to match
            ucSupport.SetCaptionWordWrap True
            
        'Resize the control horizontally to fit the caption, with no changes made to current font size.
        Case AutoSizeControl
            
            'Measure the current caption, without autofit behavior active
            ucSupport.SetCaptionWordWrap False
            stringWidth = ucSupport.GetCaptionWidth(False)
            stringHeight = ucSupport.GetCaptionHeight(False)
            
            If stringWidth = 0 Then stringWidth = 1
            If stringHeight = 0 Then stringHeight = 1
            
            'Request a matching size from the support class.
            ucSupport.RequestNewSize stringWidth, stringHeight
            
        'Resize the control vertically to fit the caption, with no changes made to current font size.
        Case AutoSizeControlPlusWordWrap
            
            'Measure the current caption, without autofit behavior active
            ucSupport.SetCaptionWordWrap True
            stringWidth = controlWidth
            stringHeight = ucSupport.GetCaptionHeight(False)
            
            If stringWidth = 0 Then stringWidth = 1
            If stringHeight = 0 Then stringHeight = 1
            
            'Request a matching size from the support class.
            ucSupport.RequestNewSize stringWidth, stringHeight
            
    End Select
    
    'If the label's caption alignment is RIGHT, and AUTOSIZE is active, we must move the LEFT property by a proportional amount
    ' to any size changes.
    If (ucSupport.GetCaptionAlignment = vbRightJustify) And (controlWidth <> ucSupport.GetBackBufferWidth) And (m_Layout = AutoSizeControl) Then
        ucSupport.RequestNewPosition controlRect.Left + (ucSupport.GetBackBufferWidth - controlWidth), controlRect.Top
    End If
    
    'With all size metrics handled, we can now paint the back buffer
    RedrawBackBuffer
            
End Sub

'Use this function to completely redraw the back buffer from scratch.  Note that this is computationally expensive compared to just flipping the
' existing buffer to the screen, so only redraw the backbuffer if the control state has somehow changed.
Private Sub RedrawBackBuffer()
    
    'Because labels are so prevalent throughout the program, this function may end up being called when PD is going down.
    ' As such, we need to perform a failsafe check on the theming class.
    If g_ProgramShuttingDown Then
        If (g_Themer Is Nothing) Then Exit Sub
    End If
    
    'Retrieve DPI-aware control dimensions from the support class
    Dim bWidth As Long, bHeight As Long
    bWidth = ucSupport.GetBackBufferWidth
    bHeight = ucSupport.GetBackBufferHeight
    
    'Figure out which back color to use.  This is normally determined by theme, but individual labels also allow a custom
    ' .BackColor property.
    Dim targetColor As Long
    If m_UseCustomBackColor Then
        targetColor = m_BackColor
    Else
        targetColor = m_Colors.RetrieveColor(PDL_Background, Me.Enabled)
    End If
    
    'Request the back buffer DC, and ask the support module to erase any existing rendering for us.
    Dim bufferDC As Long
    bufferDC = ucSupport.GetBackBufferDC(True, targetColor)
    
    'Text color also varies by theme, and possibly control enablement
    If m_UseCustomForeColor Then
        targetColor = m_ForeColor
    Else
        targetColor = m_Colors.RetrieveColor(PDL_Caption, Me.Enabled)
    End If
    
    'Paint the caption manually
    Select Case m_Layout
    
        Case AutoFitCaption
            ucSupport.PaintCaptionManually_Clipped 0, 0, ucSupport.GetBackBufferWidth, ucSupport.GetBackBufferHeight, targetColor, m_FitFailure, False
            
        Case AutoSizeControl
            ucSupport.PaintCaptionManually_Clipped 0, 0, ucSupport.GetBackBufferWidth, ucSupport.GetBackBufferHeight, targetColor, False, True
            
        Case AutoFitCaptionPlusWordWrap
            ucSupport.PaintCaptionManually_Clipped 0, 0, ucSupport.GetBackBufferWidth, ucSupport.GetBackBufferHeight, targetColor, m_FitFailure, False
            
        Case AutoSizeControlPlusWordWrap
            ucSupport.PaintCaptionManually_Clipped 0, 0, ucSupport.GetBackBufferWidth, ucSupport.GetBackBufferHeight, targetColor, False, True
            
    End Select
    
    'Paint the final result to the screen, as relevant
    ucSupport.RequestRepaint
    If (Not MainModule.IsProgramRunning()) Then UserControl.Refresh
    
End Sub

'Before this control does any painting, we need to retrieve relevant colors from PD's primary theming class.  Note that this
' step must also be called if/when PD's visual theme settings change.
Private Sub UpdateColorList()
    m_Colors.LoadThemeColor PDL_Background, "Background", IDE_WHITE
    m_Colors.LoadThemeColor PDL_Caption, "Caption", IDE_GRAY
End Sub

'External functions can call this to request a redraw.  This is helpful for live-updating theme settings, as in the Preferences dialog.
Public Sub UpdateAgainstCurrentTheme(Optional ByVal hostFormhWnd As Long = 0)
    If ucSupport.ThemeUpdateRequired Then
        UpdateColorList
        If MainModule.IsProgramRunning() Then ucSupport.UpdateAgainstThemeAndLanguage
    End If
End Sub

'Post-translation, we can request an immediate refresh
Public Sub RequestRefresh()
    ucSupport.RequestRepaint True
End Sub

'By design, PD prefers to not use design-time tooltips.  Apply tooltips at run-time, using this function.
' (IMPORTANT NOTE: translations are handled automatically.  Always pass the original English text!)
Public Sub AssignTooltip(ByVal newTooltip As String, Optional ByVal newTooltipTitle As String, Optional ByVal newTooltipIcon As TT_ICON_TYPE = TTI_NONE)
    ucSupport.AssignTooltip UserControl.ContainerHwnd, newTooltip, newTooltipTitle, newTooltipIcon
End Sub
