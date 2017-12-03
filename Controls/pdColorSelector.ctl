VERSION 5.00
Begin VB.UserControl pdColorSelector 
   Appearance      =   0  'Flat
   BackColor       =   &H80000005&
   ClientHeight    =   1710
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   4680
   ClipControls    =   0   'False
   DrawStyle       =   5  'Transparent
   FillStyle       =   0  'Solid
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
   MousePointer    =   99  'Custom
   ScaleHeight     =   114
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   312
   ToolboxBitmap   =   "pdColorSelector.ctx":0000
End
Attribute VB_Name = "pdColorSelector"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon Color Selector custom control
'Copyright 2013-2017 by Tanner Helland
'Created: 17/August/13
'Last updated: 28/October/15
'Last update: finish integration with pdUCSupport, which let us cut a ton of redundant code
'
'This thin user control is basically an empty control that when clicked, displays a color selection window.  If a
' color is selected (e.g. Cancel is not pressed), it updates its back color to match, and raises a "ColorChanged"
' event.
'
'Though simple, this control solves a lot of problems.  It is especially helpful for improving interaction with the
' command bar user control, as it easily supports color reset/randomize/preset events.  It is also nice to be able
' to update a single master function for color selection, then have the change propagate to all tool windows.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************


Option Explicit

'This control doesn't really do anything interesting, besides allow a color to be selected.
Public Event ColorChanged()

'Because VB focus events are wonky, especially when we use CreateWindow within a UC, this control raises its own
' specialized focus events.  If you need to track focus, use these instead of the default VB functions.
Public Event GotFocusAPI()
Public Event LostFocusAPI()

'This control uses two layout rects: one for the clickable primary color region, and another for the rect where the user
' can copy over the color from the main screen.  These rects are calculated by the UpdateControlLayout function.
Private m_PrimaryColorRect As RECT, m_SecondaryColorRect As RECT

'The control's current color
Private curColor As OLE_COLOR

'When the select color dialog is live, this will be set to TRUE
Private isDialogLive As Boolean

'These values will be TRUE while the mouse is inside the corresponding clickable button region; we must track these at
' module-level to know how to render the control during paint events.
Private m_MouseInPrimaryButton As Boolean, m_MouseInSecondaryButton As Boolean

'Most instances of the control provide a "quick select" box on the right that contains the current main window color.
' In some places, this color is irrelevant (like the Levels dialog), so we suppress it via a dedicated property.
Private m_ShowMainWindowColor As Boolean

'User control support class.  Historically, many classes (and associated subclassers) were required by each user control,
' but I've since attempted to wrap these into a single master control support class.
Private WithEvents ucSupport As pdUCSupport
Attribute ucSupport.VB_VarHelpID = -1

'Local list of themable colors.  This list includes all potential colors used by this class, regardless of state change
' or internal control settings.  The list is updated by calling the UpdateColorList function.
' (Note also that this list does not include variants, e.g. "BorderColor" vs "BorderColor_Hovered".  Variant values are
'  automatically calculated by the color management class, and they are retrieved by passing boolean modifiers to that
'  class, rather than treating every imaginable variant as a separate constant.)
Private Enum PDCS_COLOR_LIST
    [_First] = 0
    PDCS_Border = 0
    [_Last] = 0
    [_Count] = 1
End Enum

'Color retrieval and storage is handled by a dedicated class; this allows us to optimize theme interactions,
' without worrying about the details locally.
Private m_Colors As pdThemeColors

Public Function GetControlType() As PD_ControlType
    GetControlType = pdct_ColorSelector
End Function

Public Function GetControlName() As String
    GetControlName = UserControl.Extender.Name
End Function

'Caption is handled just like the common control label's caption property.  It is valid at design-time, and any translation,
' if present, will not be processed until run-time.
' IMPORTANT NOTE: only the ENGLISH caption is returned.  I don't have a reason for returning a translated caption (if any),
'                  but I can revisit in the future if it ever becomes relevant.
Public Property Get Caption() As String
Attribute Caption.VB_UserMemId = -518
    Caption = ucSupport.GetCaptionText()
End Property

Public Property Let Caption(ByRef newCaption As String)
    ucSupport.SetCaptionText newCaption
    PropertyChanged "Caption"
End Property

'At present, all this control does is store a color value
Public Property Get Color() As OLE_COLOR
    Color = curColor
End Property

Public Property Let Color(ByVal newSelectedColor As OLE_COLOR)
    
    curColor = newSelectedColor
    RedrawBackBuffer
    
    PropertyChanged "Color"
    RaiseEvent ColorChanged
    
End Property

'The Enabled property is a bit unique; see http://msdn.microsoft.com/en-us/library/aa261357%28v=vs.60%29.aspx
Public Property Get Enabled() As Boolean
Attribute Enabled.VB_UserMemId = -514
    Enabled = UserControl.Enabled
End Property

Public Property Let Enabled(ByVal newValue As Boolean)
    UserControl.Enabled = newValue
    PropertyChanged "Enabled"
    RedrawBackBuffer
End Property

Public Property Get FontSize() As Single
    FontSize = ucSupport.GetCaptionFontSize()
End Property

Public Property Let FontSize(ByVal newSize As Single)
    ucSupport.SetCaptionFontSize newSize
    PropertyChanged "FontSize"
End Property

'hWnds aren't exposed by default
Public Property Get hWnd() As Long
    hWnd = UserControl.hWnd
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

Public Property Get ShowMainWindowColor() As Boolean
    ShowMainWindowColor = m_ShowMainWindowColor
End Property

Public Property Let ShowMainWindowColor(ByVal newState As Boolean)
    m_ShowMainWindowColor = newState
    PropertyChanged "ShowMainWindowColor"
    UpdateControlLayout
End Property

'Call this to force a display of the color window.  Note that it's *public*, so outside callers can raise dialogs, too.
Public Sub DisplayColorSelection()
    
    isDialogLive = True
    
    'Store the current color
    Dim newColorSelection As Long, oldColor As Long
    oldColor = Color
    
    'Use the default color dialog to select a new color
    If ShowColorDialog(newColorSelection, CLng(curColor), Me) Then
        Color = newColorSelection
    Else
        Color = oldColor
    End If
    
    isDialogLive = False
    
End Sub

Private Sub ucSupport_KeyDownSystem(ByVal Shift As ShiftConstants, ByVal whichSysKey As PD_NavigationKey, markEventHandled As Boolean)
    
    'Enter/Esc get reported directly to the system key handler.  Note that we track the return, because TRUE
    ' means the key was successfully forwarded to the relevant handler.  (If FALSE is returned, no control
    ' accepted the keypress, meaning we should forward the event down the line.)
    markEventHandled = NavKey.NotifyNavKeypress(Me, whichSysKey, Shift)
    
End Sub

'Primary color area raises a dialog; secondary color area copies the color from the main screen
Private Sub ucSupport_MouseDownCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal timeStamp As Long)
    If IsMouseInPrimaryButton(x, y) And ((Button Or pdLeftButton) <> 0) Then DisplayColorSelection
    If IsMouseInSecondaryButton(x, y) And ((Button Or pdLeftButton) <> 0) Then Me.Color = layerpanel_Colors.clrVariants.Color
End Sub

Private Sub ucSupport_MouseEnter(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    RedrawBackBuffer
    UpdateCursor x, y
End Sub

Private Sub ucSupport_MouseLeave(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    m_MouseInPrimaryButton = False
    m_MouseInSecondaryButton = False
    RedrawBackBuffer
    UpdateCursor -100, -100
End Sub

Private Sub ucSupport_MouseMoveCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal timeStamp As Long)
    
    UpdateCursor x, y
    Dim redrawRequired As Boolean
    
    If IsMouseInPrimaryButton(x, y) <> m_MouseInPrimaryButton Then
        m_MouseInPrimaryButton = IsMouseInPrimaryButton(x, y)
        redrawRequired = True
    End If
    
    If IsMouseInSecondaryButton(x, y) <> m_MouseInSecondaryButton Then
        m_MouseInSecondaryButton = IsMouseInSecondaryButton(x, y)
        redrawRequired = True
    End If
    
    If redrawRequired Then
        RedrawBackBuffer
        MakeNewTooltip
    End If
    
End Sub

Private Sub ucSupport_GotFocusAPI()
    RaiseEvent GotFocusAPI
End Sub

Private Sub ucSupport_LostFocusAPI()
    RaiseEvent LostFocusAPI
End Sub

'On program-wide color changes, redraw ourselves accordingly
Private Sub ucSupport_CustomMessage(ByVal wMsg As Long, ByVal wParam As Long, ByVal lParam As Long, ByRef bHandled As Boolean, ByRef lReturn As Long)
    Select Case wMsg
        Case WM_PD_PRIMARY_COLOR_CHANGE, WM_PD_COLOR_MANAGEMENT_CHANGE
            RedrawBackBuffer
    End Select
End Sub

Private Sub ucSupport_RepaintRequired(ByVal updateLayoutToo As Boolean)
    If updateLayoutToo Then UpdateControlLayout
    RedrawBackBuffer
End Sub

Private Sub UserControl_Initialize()
    
    'Initialize a master user control support class
    Set ucSupport = New pdUCSupport
    ucSupport.RegisterControl UserControl.hWnd, True
    ucSupport.RequestExtraFunctionality True
    ucSupport.RequestCaptionSupport
    
    'This class needs to redraw itself when the primary window color changes.  Request notifications from the program-wide color change wMsg.
    ucSupport.SubclassCustomMessage WM_PD_PRIMARY_COLOR_CHANGE, True
    ucSupport.SubclassCustomMessage WM_PD_COLOR_MANAGEMENT_CHANGE, True
    
    'Prep the color manager and load default colors
    Set m_Colors = New pdThemeColors
    Dim colorCount As PDCS_COLOR_LIST: colorCount = [_Count]
    m_Colors.InitializeColorList "PDColorSelector", colorCount
    If Not MainModule.IsProgramRunning() Then UpdateColorList
    
    'Update the control size parameters at least once
    UpdateControlLayout
    
End Sub

Private Sub UserControl_InitProperties()
    Color = RGB(255, 255, 255)
    FontSize = 12
    Caption = ""
    ShowMainWindowColor = True
End Sub

'At run-time, painting is handled by the support class.  In the IDE, however, we must rely on VB's internal paint event.
Private Sub UserControl_Paint()
    ucSupport.RequestIDERepaint UserControl.hDC
End Sub

Private Sub UserControl_ReadProperties(PropBag As PropertyBag)
    With PropBag
        Color = .ReadProperty("curColor", RGB(255, 255, 255))
        Caption = .ReadProperty("Caption", "")
        FontSize = .ReadProperty("FontSize", 12)
        ShowMainWindowColor = .ReadProperty("ShowMainWindowColor", True)
    End With
End Sub

Private Sub UserControl_Resize()
    If Not MainModule.IsProgramRunning() Then ucSupport.RequestRepaint True
End Sub

Private Sub UserControl_WriteProperties(PropBag As PropertyBag)
    With PropBag
        .WriteProperty "Caption", ucSupport.GetCaptionText, ""
        .WriteProperty "FontSize", ucSupport.GetCaptionFontSize, 12
        .WriteProperty "curColor", curColor, RGB(255, 255, 255)
        .WriteProperty "ShowMainWindowColor", m_ShowMainWindowColor, True
    End With
End Sub

'Whenever a control property changes that affects control size or layout (including internal changes, like caption adjustments),
' call this function to recalculate the control's layout
Private Sub UpdateControlLayout()
    
    'Retrieve DPI-aware control dimensions from the support class
    Dim bWidth As Long, bHeight As Long
    bWidth = ucSupport.GetBackBufferWidth
    bHeight = ucSupport.GetBackBufferHeight
    
    'Next, determine the positioning of the caption, if present.  (ucSupport.GetCaptionBottom tells us where the
    ' caption text ends vertically.)
    If ucSupport.IsCaptionActive Then
        
        'The primary and secondary buttons are placed relative to the caption; secondary first
        With m_SecondaryColorRect
            .Top = ucSupport.GetCaptionBottom + 2
            .Bottom = bHeight - 2
            
            If m_ShowMainWindowColor Then
                .Right = bWidth - 2
                .Left = .Right - FixDPI(24)
            Else
                .Right = bWidth + 10
                .Left = bWidth + 9
            End If
            
        End With
        
        With m_PrimaryColorRect
            .Top = ucSupport.GetCaptionBottom + 2
            .Left = FixDPI(8)
            .Bottom = bHeight - 2
            If m_ShowMainWindowColor Then .Right = m_SecondaryColorRect.Left Else .Right = bWidth - 2
        End With
        
    'If there's no caption, allow the clickable portion to fill the entire control
    Else
        
        With m_SecondaryColorRect
            .Top = 1
            .Bottom = bHeight - 2
            
            If m_ShowMainWindowColor Then
                .Right = bWidth - 2
                .Left = .Right - FixDPI(24)
            Else
                .Right = bWidth + 10
                .Left = bWidth + 9
            End If
            
        End With
        
        With m_PrimaryColorRect
            .Top = 1
            .Left = 1
            .Bottom = bHeight - 2
            If m_ShowMainWindowColor Then .Right = m_SecondaryColorRect.Left Else .Right = bWidth - 2
        End With
        
    End If
            
End Sub

'When the mouse moves, the cursor should be updated to match
Private Sub UpdateCursor(ByVal x As Single, ByVal y As Single)
    If IsMouseInPrimaryButton(x, y) Or IsMouseInSecondaryButton(x, y) Then
        ucSupport.RequestCursor IDC_HAND
    Else
        ucSupport.RequestCursor IDC_DEFAULT
    End If
End Sub

'Returns TRUE if the mouse is inside the clickable region of the primary color selector
' (e.g. NOT the caption area, if one exists)
Private Function IsMouseInPrimaryButton(ByVal x As Single, ByVal y As Single) As Boolean
    IsMouseInPrimaryButton = PDMath.IsPointInRect(x, y, m_PrimaryColorRect)
End Function

Private Function IsMouseInSecondaryButton(ByVal x As Single, ByVal y As Single) As Boolean
    IsMouseInSecondaryButton = PDMath.IsPointInRect(x, y, m_SecondaryColorRect)
End Function

'Redraw the entire control, including the caption (if present)
Private Sub RedrawBackBuffer()
    
    'Request the back buffer DC, and ask the support module to erase any existing rendering for us.
    Dim bufferDC As Long
    bufferDC = ucSupport.GetBackBufferDC(True)
    
    'NOTE: if a caption exists, it has already been drawn.  We just need to draw the clickable button portion.
    If MainModule.IsProgramRunning() And (bufferDC <> 0) Then
    
        'Calculate default border colors.  (Note that there are two: one for hover state, and one for default state)
        Dim defaultBorderColor As Long, activeBorderColor As Long
        defaultBorderColor = m_Colors.RetrieveColor(PDCS_Border, Me.Enabled)
        activeBorderColor = m_Colors.RetrieveColor(PDCS_Border, Me.Enabled, , True)
        
        'Note that primary and second color buttons *are* color-managed, so their appearance changes based
        ' on the current working space.
        Dim primaryColorCM As Long, secondaryColorCM As Long
        
        'Render the primary and secondary color button default appearances
        With m_PrimaryColorRect
            ColorManagement.ApplyDisplayColorManagement_SingleColor Me.Color, primaryColorCM
            GDI_Plus.GDIPlusFillRectToDC bufferDC, .Left, .Top, .Right - .Left, .Bottom - .Top, primaryColorCM, 255
            GDI_Plus.GDIPlusDrawRectOutlineToDC bufferDC, .Left, .Top, .Right, .Bottom, defaultBorderColor, 255, 1#, False, GP_LJ_Miter
        End With
        
        If m_ShowMainWindowColor Then
            ColorManagement.ApplyDisplayColorManagement_SingleColor layerpanel_Colors.clrVariants.Color, secondaryColorCM
            With m_SecondaryColorRect
                GDI_Plus.GDIPlusFillRectToDC bufferDC, .Left, .Top, .Right - .Left, .Bottom - .Top, secondaryColorCM, 255
                GDI_Plus.GDIPlusDrawRectOutlineToDC bufferDC, .Left, .Top, .Right, .Bottom, defaultBorderColor, 255, 1#, False, GP_LJ_Miter
            End With
        End If
        
        'If either button is hovered, trace it with a bold, colored outline
        If m_MouseInPrimaryButton Then
            GDI_Plus.GDIPlusDrawRectOutlineToDC bufferDC, m_PrimaryColorRect.Left, m_PrimaryColorRect.Top, m_PrimaryColorRect.Right, m_PrimaryColorRect.Bottom, activeBorderColor, 255, 3#, False, GP_LJ_Miter
        ElseIf m_MouseInSecondaryButton And m_ShowMainWindowColor Then
            GDI_Plus.GDIPlusDrawRectOutlineToDC bufferDC, m_SecondaryColorRect.Left, m_SecondaryColorRect.Top, m_SecondaryColorRect.Right, m_SecondaryColorRect.Bottom, activeBorderColor, 255, 3#, False, GP_LJ_Miter
        End If
        
    End If
    
    'Paint the final result to the screen, as relevant
    ucSupport.RequestRepaint
    
End Sub

'If a color selection dialog is active, it will pass color updates backward to this function, so that we can let
' our parent form display live updates *while the user is playing with colors* - very cool!
Public Sub NotifyOfLiveColorChange(ByVal newSelectedColor As Long)
    Color = newSelectedColor
End Sub

'When the currently hovered color changes, we assign a new tooltip to the control
Private Sub MakeNewTooltip()
    
    'Failsafe for compile-time errors when properties are written
    If MainModule.IsProgramRunning() Then
    
        Dim toolString As String, hexString As String, rgbString As String, targetColor As Long
        
        If m_MouseInPrimaryButton Or (m_MouseInSecondaryButton And m_ShowMainWindowColor) Then
        
            If m_MouseInPrimaryButton Then
                targetColor = Me.Color
            ElseIf m_MouseInSecondaryButton And m_ShowMainWindowColor Then
                targetColor = layerpanel_Colors.clrVariants.Color
            End If
            
            'Make sure the color is an actual RGB triplet, and not an OLE color constant
            targetColor = Colors.ConvertSystemColor(targetColor)
            
            'Construct hex and RGB string representations of the target color
            hexString = "#" & UCase(Colors.GetHexStringFromRGB(targetColor))
            rgbString = g_Language.TranslateMessage("RGB(%1, %2, %3)", Colors.ExtractRed(targetColor), Colors.ExtractGreen(targetColor), Colors.ExtractBlue(targetColor))
            toolString = hexString & vbCrLf & rgbString
            
            'Append a description string to the color data
            If m_MouseInPrimaryButton Then
                toolString = toolString & vbCrLf & g_Language.TranslateMessage("Click to enter a full color selection screen.")
                Me.AssignTooltip toolString, "Active color"
            ElseIf m_MouseInSecondaryButton Then
                toolString = toolString & vbCrLf & g_Language.TranslateMessage("Click to make the main screen's paint color the active color.")
                Me.AssignTooltip toolString, "Main screen paint color"
            End If
            
        End If
        
    End If
    
End Sub

'Before this control does any painting, we need to retrieve relevant colors from PD's primary theming class.  Note that this
' step must also be called if/when PD's visual theme settings change.
Private Sub UpdateColorList()
    m_Colors.LoadThemeColor PDCS_Border, "Border", IDE_BLACK
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
    ucSupport.AssignTooltip UserControl.ContainerHwnd, newTooltip, newTooltipTitle, newTooltipIcon
End Sub
