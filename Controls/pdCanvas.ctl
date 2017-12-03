VERSION 5.00
Begin VB.UserControl pdCanvas 
   Appearance      =   0  'Flat
   AutoRedraw      =   -1  'True
   BackColor       =   &H80000010&
   ClientHeight    =   7695
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   13290
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
   ForeColor       =   &H8000000D&
   HasDC           =   0   'False
   KeyPreview      =   -1  'True
   OLEDropMode     =   1  'Manual
   ScaleHeight     =   513
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   886
   ToolboxBitmap   =   "pdCanvas.ctx":0000
   Begin VB.PictureBox picProgressBar 
      Appearance      =   0  'Flat
      BackColor       =   &H00E0E0E0&
      BorderStyle     =   0  'None
      ForeColor       =   &H80000008&
      Height          =   255
      Left            =   0
      ScaleHeight     =   17
      ScaleMode       =   3  'Pixel
      ScaleWidth      =   886
      TabIndex        =   0
      Top             =   6975
      Visible         =   0   'False
      Width           =   13290
   End
   Begin PhotoDemon.pdImageStrip ImageStrip 
      Height          =   990
      Left            =   6240
      TabIndex        =   6
      Top             =   600
      Visible         =   0   'False
      Width           =   990
      _ExtentX        =   1746
      _ExtentY        =   1746
   End
   Begin PhotoDemon.pdStatusBar StatusBar 
      Height          =   345
      Left            =   0
      TabIndex        =   5
      Top             =   7350
      Width           =   13290
      _ExtentX        =   23442
      _ExtentY        =   609
   End
   Begin PhotoDemon.pdCanvasView CanvasView 
      Height          =   4935
      Left            =   360
      TabIndex        =   4
      Top             =   600
      Width           =   4575
      _ExtentX        =   8281
      _ExtentY        =   8916
   End
   Begin PhotoDemon.pdButtonToolbox cmdCenter 
      Height          =   255
      Left            =   5040
      TabIndex        =   3
      Top             =   5640
      Visible         =   0   'False
      Width           =   255
      _ExtentX        =   450
      _ExtentY        =   450
      AutoToggle      =   -1  'True
      BackColor       =   -2147483626
      UseCustomBackColor=   -1  'True
   End
   Begin PhotoDemon.pdScrollBar hScroll 
      Height          =   255
      Left            =   360
      TabIndex        =   2
      Top             =   5640
      Visible         =   0   'False
      Width           =   4575
      _ExtentX        =   8070
      _ExtentY        =   450
      OrientationHorizontal=   -1  'True
      VisualStyle     =   1
   End
   Begin PhotoDemon.pdScrollBar vScroll 
      Height          =   4935
      Left            =   5040
      TabIndex        =   1
      Top             =   600
      Visible         =   0   'False
      Width           =   255
      _ExtentX        =   450
      _ExtentY        =   8705
      VisualStyle     =   1
   End
   Begin VB.Menu mnuImageTabsContext 
      Caption         =   "&Image"
      Visible         =   0   'False
      Begin VB.Menu mnuTabstripPopup 
         Caption         =   "&Save"
         Enabled         =   0   'False
         Index           =   0
      End
      Begin VB.Menu mnuTabstripPopup 
         Caption         =   "Save copy (&lossless)"
         Index           =   1
      End
      Begin VB.Menu mnuTabstripPopup 
         Caption         =   "Save &as..."
         Index           =   2
      End
      Begin VB.Menu mnuTabstripPopup 
         Caption         =   "Revert"
         Enabled         =   0   'False
         Index           =   3
      End
      Begin VB.Menu mnuTabstripPopup 
         Caption         =   "-"
         Index           =   4
      End
      Begin VB.Menu mnuTabstripPopup 
         Caption         =   "Open location in E&xplorer"
         Index           =   5
      End
      Begin VB.Menu mnuTabstripPopup 
         Caption         =   "-"
         Index           =   6
      End
      Begin VB.Menu mnuTabstripPopup 
         Caption         =   "&Close"
         Index           =   7
      End
      Begin VB.Menu mnuTabstripPopup 
         Caption         =   "Close all except this"
         Index           =   8
      End
   End
End
Attribute VB_Name = "pdCanvas"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon Canvas User Control (previously a standalone form)
'Copyright 2002-2017 by Tanner Helland
'Created: 29/November/02
'Last updated: 05/March/16
'Last update: finish integrating the image strip control as a canvas element
'
'In 2013, PD's canvas was rebuilt as a dedicated user control, and instead of each image maintaining its own canvas inside
' separate, dedicated windows (which required a *ton* of code to keep in sync with the main PD window), a single canvas was
' integrated directly into the main window, and shared by all windows.
'
'Technically, the primary canvas is only the first entry in an array.  This was done deliberately in case I ever added support for
' multiple canvases being usable at once.  This has some neat possibilities - for example, having side-by-side canvases at
' different locations on an image - but there's a lot of messy UI considerations with something like this, especially if the two
' viewports can support different images simultaneously.  So I have postponed this work until some later date, with the caveat
' that implementing it will be a lot of work, and likely have unexpected interactions throughout the program.
'
'This canvas relies on pdInputMouse for all mouse interactions.  See the pdInputMouse class for details on why we do our own mouse
' management instead of using VB's intrinsic mouse functions.
'
'As much as possible, I've tried to keep paint tool operation within this canvas to a minimum.  Generally speaking, the only tool
' interactions the canvas should handle is reporting mouse events to external functions that actually handle paint tool processing
' and rendering.  To that end, try to adhere to the existing tool implementation format when adding new tool support.  (Selections
' are currently the exception to this rule, because they were implemented long before other tools and thus aren't as
' well-contained.  I hope to someday remedy this.)
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'Because VB focus events are wonky, especially when we use CreateWindow within a UC, this control raises its own
' specialized focus events.  If you need to track focus, use these instead of the default VB functions.
Public Event GotFocusAPI()
Public Event LostFocusAPI()

Private Enum PD_MOUSEEVENT
    pMouseDown = 0
    pMouseMove = 1
    pMouseUp = 2
End Enum

#If False Then
    Private Const pMouseDown = 0, pMouseMove = 1, pMouseUp = 2
#End If

Private Const SM_CXVSCROLL As Long = 2
Private Const SM_CYHSCROLL As Long = 3

'Mouse interactions are complicated in this form, so we sometimes need to cache button values and process them elsewhere
Private m_LMBDown As Boolean, m_RMBDown As Boolean

'Every time a canvas MouseMove event occurs, this number is incremented by one.  If mouse events are coming in fast and furious,
' we can delay renders between them to improve responsiveness.  (This number is reset to zero when the mouse is released.)
Private m_NumOfMouseMovements As Long

'If the mouse is currently over the canvas, this will be set to TRUE.
Private m_IsMouseOverCanvas As Boolean

'Track initial mouse button locations
Private m_InitMouseX As Double, m_InitMouseY As Double

'On the canvas's MouseDown event, this control will mark the relevant point of interest index for the active layer (if any).
' If a point of interest has not been selected, this value will be reset to poi_Undefined (-1).
Private m_CurPOI As PD_PointOfInterest

'As some POI interactions may cause the canvas to redraw, we also cache the *last* point of interest.  When this mismatches the
' current one, a UI-only viewport redraw is requested, and the last/current point values are synched.
Private m_LastPOI As PD_PointOfInterest

'To improve performance, we can ask the canvas to not refresh itself until we say so.
Private m_SuspendRedraws As Boolean

'Some tools support the ability to auto-activate a layer beneath the mouse.  If supported, during the MouseMove event,
' this value (m_LayerAutoActivateIndex) will be updated with the index of the layer that will be auto-activated if the
' user presses the mouse button.  This can be used to modify things like cursor behavior, to make sure the user receives
' accurate feedback on what a given action will affect.
Private m_LayerAutoActivateIndex As Long

'Selection tools need to know if a selection was active before mouse events start.  If it is, creation of an invalid new selection
' will add "Remove Selection" to the Undo/Redo chain; however, if no selection was active, the working selection will simply
' be erased.
Private m_SelectionActiveBeforeMouseEvents As Boolean

'When we reflow the interface, we mark a special "resize" state to prevent recursive automatic reflow event notifications
Private m_InternalResize As Boolean

'In Feb '15, Raj added a great context menu to the image tabstrip.  To help simplify menu enable/disable behavior,
' this enum can be used to identify individual menu entries.
Private Enum POPUP_MENU_ENTRIES
    POP_SAVE = 0
    POP_SAVE_COPY = 1
    POP_SAVE_AS = 2
    POP_REVERT = 3
    POP_OPEN_IN_EXPLORER = 5
    POP_CLOSE = 7
    POP_CLOSE_OTHERS = 8
End Enum

#If False Then
    Private Const POP_SAVE = 0, POP_SAVE_COPY = 1, POP_SAVE_AS = 2, POP_REVERT = 3, POP_OPEN_IN_EXPLORER = 5, POP_CLOSE = 7, POP_CLOSE_OTHERS = 8
#End If

'User control support class.  Historically, many classes (and associated subclassers) were required by each user control,
' but I've since attempted to wrap these into a single master control support class.
Private WithEvents ucSupport As pdUCSupport
Attribute ucSupport.VB_VarHelpID = -1

'Local list of themable colors.  This list includes all potential colors used by this class, regardless of state change
' or internal control settings.  The list is updated by calling the UpdateColorList function.
' (Note also that this list does not include variants, e.g. "BorderColor" vs "BorderColor_Hovered".  Variant values are
'  automatically calculated by the color management class, and they are retrieved by passing boolean modifiers to that
'  class, rather than treating every imaginable variant as a separate constant.)
Private Enum PDCANVAS_COLOR_LIST
    [_First] = 0
    PDC_Background = 0
    PDC_StatusBar = 1
    PDC_SpecialButtonBackground = 2
    [_Last] = 2
    [_Count] = 3
End Enum

'Color retrieval and storage is handled by a dedicated class; this allows us to optimize theme interactions,
' without worrying about the details locally.
Private m_Colors As pdThemeColors

Public Function GetControlType() As PD_ControlType
    GetControlType = pdct_Canvas
End Function

Public Function GetControlName() As String
    GetControlName = UserControl.Extender.Name
End Function

'Helper functions to ensure ideal UI behavior
Public Function IsScreenCoordInsideCanvasView(ByVal srcX As Long, ByVal srcY As Long) As Boolean

    'Get the canvas view's window
    Dim tmpRect As RECT
    If (Not g_WindowManager Is Nothing) Then
        g_WindowManager.GetWindowRect_API_Universal CanvasView.hWnd, VarPtr(tmpRect)
        IsScreenCoordInsideCanvasView = PDMath.IsPointInRect(srcX, srcY, tmpRect)
    Else
        IsScreenCoordInsideCanvasView = False
    End If
    
End Function

Public Function GetCanvasViewHWnd() As Long
    GetCanvasViewHWnd = CanvasView.hWnd
End Function

Public Sub ManuallyNotifyCanvasMouse(ByVal mouseX As Long, ByVal mouseY As Long)
    CanvasView.NotifyExternalMouseMove mouseX, mouseY
End Sub

'External functions can call this to set the current network state (which in turn, draws a relevant icon to the status bar)
Public Sub SetNetworkState(ByVal newNetworkState As Boolean)
    StatusBar.SetNetworkState newNetworkState
End Sub

'Use these functions to forcibly prevent the canvas from redrawing itself.  REDRAWS WILL NOT HAPPEN AGAIN UNTIL YOU RESTORE ACCESS!
' (Also note that this function relays state changes to the underlying pdCanvasView object; as such, do not set m_SuspendRedraws
'  manually - only set it via this function, to ensure the canvas and underlying canvas view stay in sync.)
Public Function GetRedrawSuspension() As Boolean
    GetRedrawSuspension = m_SuspendRedraws Or CanvasView.GetRedrawSuspension()
End Function

Public Sub SetRedrawSuspension(ByVal newRedrawValue As Boolean)
    CanvasView.SetRedrawSuspension newRedrawValue
    m_SuspendRedraws = newRedrawValue
End Sub

'Need to wipe the canvas?  Call this function, but please be careful - it will literally erase the canvas's back buffer.
Public Sub ClearCanvas()
    
    CanvasView.ClearCanvas
    StatusBar.ClearCanvas
    
    If (g_OpenImageCount <= 0) Then
        SetScrollVisibility PD_HORIZONTAL, False
        SetScrollVisibility PD_VERTICAL, False
    
    'If any valid images are loaded, scroll bars are always made visible
    Else
        SetScrollVisibility PD_HORIZONTAL, True
        SetScrollVisibility PD_VERTICAL, True
    End If
    
    Me.AlignCanvasView
    
End Sub

'Get/Set scroll bar value
Public Function GetScrollValue(ByVal barType As PD_ORIENTATION) As Long
    If (barType = PD_HORIZONTAL) Then GetScrollValue = hScroll.Value Else GetScrollValue = vScroll.Value
End Function

Public Sub SetScrollValue(ByVal barType As PD_ORIENTATION, ByVal newValue As Long)
    
    If (barType = PD_HORIZONTAL) Then
        hScroll.Value = newValue
    ElseIf (barType = PD_VERTICAL) Then
        vScroll.Value = newValue
    Else
        hScroll.Value = newValue
        vScroll.Value = newValue
    End If
    
    'If automatic redraws are suspended, the scroll bars change events won't fire, so we must manually notify external UI elements
    If Me.GetRedrawSuspension Then RelayViewportChanges
    
End Sub

'Get/Set scroll max/min
Public Function GetScrollMax(ByVal barType As PD_ORIENTATION) As Long
    If (barType = PD_HORIZONTAL) Then GetScrollMax = hScroll.Max Else GetScrollMax = vScroll.Max
End Function

Public Function GetScrollMin(ByVal barType As PD_ORIENTATION) As Long
    If (barType = PD_HORIZONTAL) Then GetScrollMin = hScroll.Min Else GetScrollMin = vScroll.Min
End Function

Public Sub SetScrollMax(ByVal barType As PD_ORIENTATION, ByVal newMax As Long)
    If (barType = PD_HORIZONTAL) Then hScroll.Max = newMax Else vScroll.Max = newMax
End Sub

Public Sub SetScrollMin(ByVal barType As PD_ORIENTATION, ByVal newMin As Long)
    If (barType = PD_HORIZONTAL) Then hScroll.Min = newMin Else vScroll.Min = newMin
End Sub

'Set scroll bar LargeChange value
Public Sub SetScrollLargeChange(ByVal barType As PD_ORIENTATION, ByVal newLargeChange As Long)
    If (barType = PD_HORIZONTAL) Then hScroll.LargeChange = newLargeChange Else vScroll.LargeChange = newLargeChange
End Sub

'Get/Set scrollbar visibility.  Note that visibility is only toggled as necessary, so this function is preferable to
' calling .Visible properties directly.
Public Function GetScrollVisibility(ByVal barType As PD_ORIENTATION) As Boolean
    If (barType = PD_HORIZONTAL) Then
        GetScrollVisibility = hScroll.Visible
    Else
        GetScrollVisibility = vScroll.Visible
    End If
End Function

Public Sub SetScrollVisibility(ByVal barType As PD_ORIENTATION, ByVal newVisibility As Boolean)
    
    'If the scroll bar status wasn't actually changed, we can avoid a forced screen refresh
    Dim changesMade As Boolean
    changesMade = False
    
    If (barType = PD_HORIZONTAL) Then
        If (newVisibility <> hScroll.Visible) Then
            hScroll.Visible = newVisibility
            changesMade = True
        End If
    
    ElseIf (barType = PD_VERTICAL) Then
        If (newVisibility <> vScroll.Visible) Then
            vScroll.Visible = newVisibility
            changesMade = True
        End If
    
    Else
        If (newVisibility <> hScroll.Visible) Or (newVisibility <> vScroll.Visible) Then
            hScroll.Visible = newVisibility
            vScroll.Visible = newVisibility
            changesMade = True
        End If

    End If
    
    'When scroll bar visibility is changed, we must move the main canvas picture box to match
    If changesMade Then
    
        'The "center" button between the scroll bars has the same visibility as the scrollbars; it's only visible if both bars are visible
        cmdCenter.Visible = CBool(hScroll.Visible And vScroll.Visible)
        Me.AlignCanvasView
        
    End If
    
End Sub

Public Sub DisplayImageSize(ByRef srcImage As pdImage, Optional ByVal clearSize As Boolean = False)
    StatusBar.DisplayImageSize srcImage, clearSize
End Sub

Public Sub DisplayCanvasMessage(ByRef cMessage As String)
    StatusBar.DisplayCanvasMessage cMessage
End Sub

Public Sub DisplayCanvasCoordinates(ByVal xCoord As Double, ByVal yCoord As Double, Optional ByVal clearCoords As Boolean = False)
    StatusBar.DisplayCanvasCoordinates xCoord, yCoord, clearCoords
End Sub

Public Sub RequestViewportRedraw(Optional ByVal refreshImmediately As Boolean = False)
    CanvasView.RequestRedraw refreshImmediately
End Sub

'Tabstrip relays include the next five functions
Public Sub NotifyTabstripAddNewThumb(ByVal pdImageIndex As Long)
    ImageStrip.AddNewThumb pdImageIndex
End Sub

Public Sub NotifyTabstripNewActiveImage(ByVal pdImageIndex As Long)
    ImageStrip.NotifyNewActiveImage pdImageIndex
End Sub

Public Sub NotifyTabstripUpdatedImage(ByVal pdImageIndex As Long)
    ImageStrip.NotifyUpdatedImage pdImageIndex
End Sub

Public Sub NotifyTabstripRemoveThumb(ByVal pdImageIndex As Long, Optional ByVal refreshStrip As Boolean = True)
    ImageStrip.RemoveThumb pdImageIndex, refreshStrip
End Sub

Public Sub NotifyTabstripTotalRedrawRequired(Optional ByVal regenerateThumbsToo As Boolean = False)
    ImageStrip.RequestTotalRedraw regenerateThumbsToo
End Sub

'Return the current width/height of the underlying canvas view
Public Function GetCanvasWidth() As Long
    GetCanvasWidth = CanvasView.GetCanvasWidth
End Function

Public Function GetCanvasHeight() As Long
    GetCanvasHeight = CanvasView.GetCanvasHeight
End Function

Public Function GetStatusBarHeight() As Long
    GetStatusBarHeight = StatusBar.GetHeight
End Function

Public Function GetProgBarReference() As PictureBox
    Set GetProgBarReference = picProgressBar
End Function

'The Enabled property is a bit unique; see http://msdn.microsoft.com/en-us/library/aa261357%28v=vs.60%29.aspx
Public Property Get Enabled() As Boolean
Attribute Enabled.VB_UserMemId = -514
    Enabled = UserControl.Enabled
End Property

Public Property Let Enabled(ByVal newValue As Boolean)
    UserControl.Enabled = newValue
    PropertyChanged "Enabled"
End Property

Public Property Get hWnd()
    hWnd = UserControl.hWnd
End Property

Public Property Get ContainerHwnd() As Long
    ContainerHwnd = UserControl.ContainerHwnd
End Property

'Note that this control does *not* return its own DC.  Instead, it returns the DC of the underlying CanvasView object.
' This is by design.
Public Property Get hDC()
    hDC = CanvasView.hDC
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

Private Sub CanvasView_LostFocusAPI()
    m_LMBDown = False
    m_RMBDown = False
End Sub

'When the control receives focus, if the focus isn't received via mouse click, display a focus rect around the active button
Private Sub ucSupport_GotFocusAPI()
    RaiseEvent GotFocusAPI
End Sub

'When the control loses focus, erase any focus rects it may have active
Private Sub ucSupport_LostFocusAPI()
    RaiseEvent LostFocusAPI
End Sub

'Get/set zoom-related UI elements
Public Function IsZoomEnabled() As Boolean
    IsZoomEnabled = StatusBar.IsZoomEnabled
End Function

Public Sub SetZoomDropDownIndex(ByVal newIndex As Long)
    StatusBar.SetZoomDropDownIndex newIndex
End Sub

Public Function GetZoomDropDownIndex() As Long
    GetZoomDropDownIndex = StatusBar.GetZoomDropDownIndex
End Function

'Only use this function for initially populating the zoom drop-down
Public Function GetZoomDropDownReference() As pdDropDown
    Set GetZoomDropDownReference = StatusBar.GetZoomDropDownReference
End Function

'Various input events are bubbled up from the underlying CanvasView control.  It provides no handling over paint and
' tool events, so we must reroute those events here.

'At present, the only App Commands the canvas handles are forward/back, which link to Undo/Redo
Private Sub CanvasView_AppCommand(ByVal cmdID As AppCommandConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    
    If Me.IsCanvasInteractionAllowed() Then
    
        Select Case cmdID
        
            'Back button: currently triggers Undo
            Case AC_BROWSER_BACKWARD, AC_UNDO
                If pdImages(g_CurrentImage).UndoManager.GetUndoState Then Process "Undo", , , UNDO_Nothing
                
            'Forward button: currently triggers Redo
            Case AC_BROWSER_FORWARD, AC_REDO
                If pdImages(g_CurrentImage).UndoManager.GetRedoState Then Process "Redo", , , UNDO_Nothing
                
        End Select

    End If

End Sub

Private Sub CanvasView_KeyDownCustom(ByVal Shift As ShiftConstants, ByVal vkCode As Long, ByRef markEventHandled As Boolean)

    markEventHandled = False
    
    'Make sure canvas interactions are allowed (e.g. an image has been loaded, etc)
    If Me.IsCanvasInteractionAllowed() Then
    
        Dim hOffset As Long, vOffset As Long
        Dim canvasUpdateRequired As Boolean

        'Any further processing depends on which tool is currently active
        Select Case g_CurrentTool
        
            'Drag-to-pan canvas
            Case NAV_DRAG
                    
            'Move stuff around
            Case NAV_MOVE
            
                'Handle arrow keys first
                If (vkCode = VK_UP) Or (vkCode = VK_DOWN) Or (vkCode = VK_LEFT) Or (vkCode = VK_RIGHT) Then
            
                    'Calculate offset modifiers for the current layer
                    If (vkCode = VK_UP) Then vOffset = vOffset - 1
                    If (vkCode = VK_DOWN) Then vOffset = vOffset + 1
                    If (vkCode = VK_LEFT) Then hOffset = hOffset - 1
                    If (vkCode = VK_RIGHT) Then hOffset = hOffset + 1
                    
                    If (vkCode = VK_UP) Or (vkCode = VK_DOWN) Or (vkCode = VK_LEFT) Or (vkCode = VK_RIGHT) Then canvasUpdateRequired = True
                    
                    'Apply the offsets
                    With pdImages(g_CurrentImage).GetActiveLayer
                        .SetLayerOffsetX .GetLayerOffsetX + hOffset
                        .SetLayerOffsetY .GetLayerOffsetY + vOffset
                    End With
                    
                    'Redraw the viewport if necessary
                    If canvasUpdateRequired Then
                        markEventHandled = True
                        ViewportEngine.Stage2_CompositeAllLayers pdImages(g_CurrentImage), Me
                    End If
                    
                'Handle non-arrow keys next
                Else
                
                    'Delete key: delete the active layer (if allowed)
                    If (vkCode = VK_DELETE) And pdImages(g_CurrentImage).GetNumOfLayers > 1 Then
                        markEventHandled = True
                        Process "Delete layer", False, BuildParamList("layerindex", pdImages(g_CurrentImage).GetActiveLayerIndex), UNDO_Image_VectorSafe
                    End If
                    
                    'Insert: raise Add New Layer dialog
                    If (vkCode = VK_INSERT) Then
                        markEventHandled = True
                        Process "Add new layer", True
                    End If
                
                    'Tab and Shift+Tab: move through layer stack
                    If (vkCode = VK_TAB) Then
                        
                        markEventHandled = True
                        
                        'Retrieve the active layer index
                        Dim curLayerIndex As Long
                        curLayerIndex = pdImages(g_CurrentImage).GetActiveLayerIndex
                        
                        'Advance the layer index according to the Shift modifier
                        If (Shift And vbShiftMask) <> 0 Then
                            curLayerIndex = curLayerIndex + 1
                        Else
                            curLayerIndex = curLayerIndex - 1
                        End If
                        
                        If (curLayerIndex < 0) Then curLayerIndex = pdImages(g_CurrentImage).GetNumOfLayers - 1
                        If (curLayerIndex > pdImages(g_CurrentImage).GetNumOfLayers - 1) Then curLayerIndex = 0
                        
                        'Activate the new layer
                        pdImages(g_CurrentImage).SetActiveLayerByIndex curLayerIndex
                        
                        'Redraw the viewport and interface to match
                        ViewportEngine.Stage3_CompositeCanvas pdImages(g_CurrentImage), Me
                        SyncInterfaceToCurrentImage
                        
                    End If
                
                    'Space bar: toggle active layer visibility
                    If (vkCode = VK_SPACE) Then
                        markEventHandled = True
                        pdImages(g_CurrentImage).GetActiveLayer.SetLayerVisibility (Not pdImages(g_CurrentImage).GetActiveLayer.GetLayerVisibility)
                        ViewportEngine.Stage2_CompositeAllLayers pdImages(g_CurrentImage), Me
                        Interface.SyncInterfaceToCurrentImage
                    End If
                
                End If
            
            'Selection tools use a universal handler
            Case SELECT_RECT, SELECT_CIRC, SELECT_LINE, SELECT_POLYGON, SELECT_LASSO, SELECT_WAND
                Selections.NotifySelectionKeyDown Me, Shift, vkCode, markEventHandled
                
        End Select
        
    End If

End Sub

Private Sub CanvasView_KeyUpCustom(ByVal Shift As ShiftConstants, ByVal vkCode As Long, markEventHandled As Boolean)
    
    markEventHandled = False

    'Make sure canvas interactions are allowed (e.g. an image has been loaded, etc)
    If IsCanvasInteractionAllowed() Then
        
        'Any further processing depends on which tool is currently active
        Select Case g_CurrentTool
        
            Case NAV_DRAG
            
            Case NAV_MOVE
            
            'Selection tools use a universal handler
            Case SELECT_RECT, SELECT_CIRC, SELECT_LINE, SELECT_POLYGON, SELECT_LASSO, SELECT_WAND
                Selections.NotifySelectionKeyUp Me, Shift, vkCode, markEventHandled
                
        End Select
        
    End If
    
End Sub

Private Sub cmdCenter_Click()
    CanvasManager.CenterOnScreen
End Sub

Private Sub CanvasView_MouseDownCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal timeStamp As Long)
    
    'Make sure interactions with this canvas are allowed
    If (Not Me.IsCanvasInteractionAllowed()) Then Exit Sub
    
    'Because VB does not allow an user control to receive focus if it contains controls that can receive focus, the arrow buttons
    ' can behave unpredictably (for example, if the zoom box has focus, and the user clicks on the canvas, the canvas will not
    ' receive focus and arrow key presses will continue to interact with the zoom box instead of the viewport)
    ' (NOTE: this should be fixed as of 6.6, as a dedicated picture box is now used for rendering)
    
    'Note whether a selection is active when mouse interactions began
    m_SelectionActiveBeforeMouseEvents = (pdImages(g_CurrentImage).IsSelectionActive And pdImages(g_CurrentImage).MainSelection.IsLockedIn)
    
    'These variables will hold the corresponding (x,y) coordinates on the IMAGE - not the VIEWPORT.
    ' (This is important if the user has zoomed into an image, and used scrollbars to look at a different part of it.)
    Dim imgX As Double, imgY As Double
    
    'Note that displayImageCoordinates returns a copy of the displayed coordinates via imgX/Y
    DisplayImageCoordinates x, y, pdImages(g_CurrentImage), Me, imgX, imgY
    
    'We also need a copy of the current mouse position relative to the active layer.  (This became necessary in PD 7.0, as layers
    ' may have non-destructive affine transforms active, which means we can't blindly switch between image and layer coordinate spaces!)
    Dim layerX As Single, layerY As Single
    Drawing.ConvertImageCoordsToLayerCoords_Full pdImages(g_CurrentImage), pdImages(g_CurrentImage).GetActiveLayer, imgX, imgY, layerX, layerY
    
    'Display a relevant cursor for the current action
    SetCanvasCursor pMouseDown, Button, x, y, imgX, imgY, layerX, layerY
    
    'Check mouse button use
    If (Button = vbLeftButton) Then
        
        m_LMBDown = True
        m_NumOfMouseMovements = 0
            
        'Remember this location
        m_InitMouseX = x
        m_InitMouseY = y
        
        'Some functions may not operate on the current layer, but on the layer under the mouse
        Dim layerUnderMouse As Long
        
        'Ask the current layer if these coordinates correspond to a point of interest.  We don't always use this return value,
        ' but a number of functions could potentially ask for it, so we cache it at MouseDown time and hang onto it until
        ' the mouse is released.
        m_CurPOI = pdImages(g_CurrentImage).GetActiveLayer.CheckForPointOfInterest(imgX, imgY)
        
        'Any further processing depends on which tool is currently active
        Select Case g_CurrentTool
        
            'Drag-to-pan canvas
            Case NAV_DRAG
                SetInitialCanvasScrollValues FormMain.mainCanvas(0)
                
            'Move stuff around
            Case NAV_MOVE
            
                'Prior to moving or transforming a layer, we need to check the state of the "auto-activate layer beneath mouse"
                ' option; if it is set, check (and possibly modify) the active layer based on the mouse position.
                If CBool(toolpanel_MoveSize.chkAutoActivateLayer) Then
                
                    layerUnderMouse = Layers.GetLayerUnderMouse(imgX, imgY, True)
                    
                    'The "getLayerUnderMouse" function will return a layer index if the mouse is over a layer.  If the mouse is not
                    ' over a layer, it will return -1.
                    If (layerUnderMouse > -1) Then
                    
                        'If the layer under the mouse is not already active, activate it now
                        If (layerUnderMouse <> pdImages(g_CurrentImage).GetActiveLayerIndex) Then
                            Layers.SetActiveLayerByIndex layerUnderMouse, False
                            ViewportEngine.Stage3_CompositeCanvas pdImages(g_CurrentImage), Me
                        End If
                    
                    End If
                
                End If
                
                'Initiate the layer transformation engine.  Note that nothing will happen until the user actually moves the mouse.
                Tools.SetInitialLayerToolValues pdImages(g_CurrentImage), pdImages(g_CurrentImage).GetActiveLayer, imgX, imgY, pdImages(g_CurrentImage).GetActiveLayer.CheckForPointOfInterest(imgX, imgY)
            
            'Color picker
            Case COLOR_PICKER
                ColorPicker.NotifyMouseXY m_LMBDown, imgX, imgY, Me
            
            'Selections
            Case SELECT_RECT, SELECT_CIRC, SELECT_LINE, SELECT_POLYGON, SELECT_LASSO, SELECT_WAND
                Selections.NotifySelectionMouseDown Me, imgX, imgY
                
            'Text layer behavior varies depending on whether the current layer is a text layer or not
            Case VECTOR_TEXT, VECTOR_FANCYTEXT
                
                'One of two things can happen when the mouse is clicked in text mode:
                ' 1) The current layer is a text layer, and the user wants to edit it (move it around, resize, etc)
                ' 2) The user wants to add a new text layer, which they can do by clicking over a non-text layer portion of the image
                
                'Let's start by distinguishing between these two states.
                Dim userIsEditingCurrentTextLayer As Boolean
                
                'Check to see if the current layer is a text layer
                If pdImages(g_CurrentImage).GetActiveLayer.IsLayerText Then
                
                    'Did the user click on a POI for this layer?  If they did, the user is editing the current text layer.
                    userIsEditingCurrentTextLayer = (m_CurPOI <> poi_Undefined)
                    
                'The current active layer is not a text layer.
                Else
                    userIsEditingCurrentTextLayer = False
                End If
                
                'If the user is editing the current text layer, we can switch directly into layer transform mode
                If userIsEditingCurrentTextLayer Then
                    
                    'Initiate the layer transformation engine.  Note that nothing will happen until the user actually moves the mouse.
                    Tools.SetInitialLayerToolValues pdImages(g_CurrentImage), pdImages(g_CurrentImage).GetActiveLayer, imgX, imgY, pdImages(g_CurrentImage).GetActiveLayer.CheckForPointOfInterest(imgX, imgY)
                    
                'The user is not editing a text layer.  Create a new text layer now.
                Else
                    
                    'Create a new text layer directly; note that we *do not* pass this command through the central processor, as we do not
                    ' want the delay associated with full Undo/Redo creation.
                    If (g_CurrentTool = VECTOR_TEXT) Then
                        Layers.AddNewLayer pdImages(g_CurrentImage).GetActiveLayerIndex, PDL_TEXT, 0, 0, 0, True, "", imgX, imgY, True
                    ElseIf (g_CurrentTool = VECTOR_FANCYTEXT) Then
                        Layers.AddNewLayer pdImages(g_CurrentImage).GetActiveLayerIndex, PDL_TYPOGRAPHY, 0, 0, 0, True, "", imgX, imgY, True
                    End If
                    
                    'Use a special initialization command that basically copies all existing text properties into the newly created layer.
                    Tools.SyncCurrentLayerToToolOptionsUI
                    
                    'Put the newly created layer into transform mode, with the bottom-right corner selected
                    Tools.SetInitialLayerToolValues pdImages(g_CurrentImage), pdImages(g_CurrentImage).GetActiveLayer, imgX, imgY, poi_CornerSE
                    
                    'Also, note that we have just created a new text layer.  The MouseUp event needs to know this, so it can initiate a full-image Undo/Redo event.
                    Tools.SetCustomToolState PD_TEXT_TOOL_CREATED_NEW_LAYER
                    
                    'Redraw the viewport immediately
                    ViewportEngine.Stage2_CompositeAllLayers pdImages(g_CurrentImage), FormMain.mainCanvas(0), poi_CornerSE
                
                End If
            
            Case PAINT_BASICBRUSH, PAINT_SOFTBRUSH, PAINT_ERASER
                Paintbrush.NotifyBrushXY m_LMBDown, imgX, imgY, timeStamp, Me
                
            Case PAINT_FILL
                FillTool.NotifyMouseXY m_LMBDown, imgX, imgY, Me
                
            'In the future, other tools can be handled here
            Case Else
            
            
        End Select
    
    ElseIf (Button = vbRightButton) Then
    
        m_RMBDown = True
        
        'TODO: right-button functionality
    
    End If
    
End Sub

Private Sub CanvasView_MouseEnter(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    m_IsMouseOverCanvas = True
End Sub

'When the mouse leaves the window, if no buttons are down, clear the coordinate display.
' (We must check for button states because the user is allowed to do things like drag selection nodes outside the image,
'  or paint outside the image.)
Private Sub CanvasView_MouseLeave(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    
    m_IsMouseOverCanvas = False
    
    Select Case g_CurrentTool
        Case PAINT_BASICBRUSH, PAINT_SOFTBRUSH, PAINT_ERASER, PAINT_FILL
            ViewportEngine.Stage4_FlipBufferAndDrawUI pdImages(g_CurrentImage), Me
    End Select
    
    'If the mouse is not being used, clear the image coordinate display entirely
    If (Not m_LMBDown) And (Not m_RMBDown) Then ClearImageCoordinatesDisplay
    
End Sub

Private Sub CanvasView_MouseMoveCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal timeStamp As Long)
    
    m_IsMouseOverCanvas = True
    
    'Make sure interactions with this canvas are allowed
    If Not IsCanvasInteractionAllowed() Then Exit Sub
    
    m_NumOfMouseMovements = m_NumOfMouseMovements + 1
    m_LMBDown = ((Button And pdLeftButton) <> 0)
    
    'These variables will hold the corresponding (x,y) coordinates on the image - NOT the viewport
    Dim imgX As Double, imgY As Double
    
    'Display the image coordinates under the mouse pointer
    DisplayImageCoordinates x, y, pdImages(g_CurrentImage), Me, imgX, imgY
    
    'We also need a copy of the current mouse position relative to the active layer.  (This became necessary in PD 7.0, as layers
    ' may have non-destructive affine transforms active, which means we can't reuse image coordinates as layer coordinates!)
    Dim layerX As Single, layerY As Single
    Drawing.ConvertImageCoordsToLayerCoords_Full pdImages(g_CurrentImage), pdImages(g_CurrentImage).GetActiveLayer, imgX, imgY, layerX, layerY
        
    'Check the left mouse button
    If m_LMBDown Then
    
        Select Case g_CurrentTool
        
            'Drag-to-pan canvas
            Case NAV_DRAG
                Tools.PanImageCanvas m_InitMouseX, m_InitMouseY, x, y, pdImages(g_CurrentImage), FormMain.mainCanvas(0)
            
            'Move stuff around
            Case NAV_MOVE
                Message "Shift key: preserve layer aspect ratio", "DONOTLOG"
                Tools.TransformCurrentLayer imgX, imgY, pdImages(g_CurrentImage), pdImages(g_CurrentImage).GetActiveLayer, FormMain.mainCanvas(0), (Shift And vbShiftMask)
        
            'Color picker
            Case COLOR_PICKER
                ColorPicker.NotifyMouseXY m_LMBDown, imgX, imgY, Me
            
            'Selection tools
            Case SELECT_RECT, SELECT_CIRC, SELECT_LINE, SELECT_POLYGON, SELECT_LASSO, SELECT_WAND
                Selections.NotifySelectionMouseMove Me, True, Shift, imgX, imgY, m_NumOfMouseMovements
                
            'Text layers are identical to the move tool
            Case VECTOR_TEXT, VECTOR_FANCYTEXT
                Message "Shift key: preserve layer aspect ratio"
                Tools.TransformCurrentLayer imgX, imgY, pdImages(g_CurrentImage), pdImages(g_CurrentImage).GetActiveLayer, FormMain.mainCanvas(0), (Shift And vbShiftMask)
            
            'Unlike other tools, the paintbrush engine controls when the main viewport gets redrawn.
            ' (Some tricks are used to improve performance, including coalescing render events if they occur
            '  quickly enough.)  As such, there is no viewport redraw request here.
            Case PAINT_BASICBRUSH, PAINT_SOFTBRUSH, PAINT_ERASER
                Paintbrush.NotifyBrushXY m_LMBDown, imgX, imgY, timeStamp, Me
                
            Case PAINT_FILL
                FillTool.NotifyMouseXY True, imgX, imgY, Me
                
        End Select
    
    'This else means the LEFT mouse button is NOT down
    Else
        
        'Display a relevant cursor for the current action
        SetCanvasCursor pMouseMove, Button, x, y, imgX, imgY, layerX, layerY
    
        Select Case g_CurrentTool
        
            'Drag-to-navigate
            Case NAV_DRAG
            
            'Move stuff around
            Case NAV_MOVE
            
                'If the user has the "auto-activate layer beneath mouse" option set, report the current layer name in the
                ' message bar; this is helpful for determining what layer will be affected by a given action.
                If CBool(toolpanel_MoveSize.chkAutoActivateLayer) Then
                
                    Dim layerUnderMouse As Long
                    layerUnderMouse = Layers.GetLayerUnderMouse(imgX, imgY, True)
                    
                    'The "getLayerUnderMouse" function will return a layer index if the mouse is over a layer.  If the mouse is not
                    ' over a layer, it will return -1.
                    If (layerUnderMouse > -1) Then
                        m_LayerAutoActivateIndex = layerUnderMouse
                        
                        'To spare the debug logger from receiving too many events, forcibly prevent logging of this message
                        ' while in debug mode.
                        #If DEBUGMODE = 1 Then
                            Message "Target layer: %1", pdImages(g_CurrentImage).GetLayerByIndex(layerUnderMouse).GetLayerName, "DONOTLOG"
                        #Else
                            Message "Target layer: %1", pdImages(g_CurrentImage).GetLayerByIndex(layerUnderMouse).GetLayerName
                        #End If
                    
                    'The mouse is not over a layer.  Default to the active layer, which allows the user to interact with the
                    ' layer even if it lies off-canvas.
                    Else
                        m_LayerAutoActivateIndex = pdImages(g_CurrentImage).GetActiveLayerIndex
                        
                        #If DEBUGMODE = 1 Then
                            Message "Target layer: %1", g_Language.TranslateMessage("(none)"), "DONOTLOG"
                        #Else
                            Message "Target layer: %1", g_Language.TranslateMessage("(none)")
                        #End If
                        
                    End If
                
                'Auto-activation is disabled.  Don't bother reporting the layer beneath the mouse to the user, as actions can
                ' only affect the active layer!
                Else
                    Message ""
                    m_LayerAutoActivateIndex = pdImages(g_CurrentImage).GetActiveLayerIndex
                End If
            
            'Color picker
            Case COLOR_PICKER
                ColorPicker.NotifyMouseXY m_LMBDown, imgX, imgY, Me
                
            'Selection tools
            Case SELECT_RECT, SELECT_CIRC, SELECT_LINE, SELECT_POLYGON, SELECT_LASSO, SELECT_WAND
                Selections.NotifySelectionMouseMove Me, False, Shift, imgX, imgY, m_NumOfMouseMovements
                
            'Text tools
            Case VECTOR_TEXT, VECTOR_FANCYTEXT
            
            Case PAINT_BASICBRUSH, PAINT_SOFTBRUSH, PAINT_ERASER
                Paintbrush.NotifyBrushXY m_LMBDown, imgX, imgY, timeStamp, Me
                
            Case PAINT_FILL
                FillTool.NotifyMouseXY False, imgX, imgY, Me
                
            Case Else
            
        End Select
        
    End If
    
End Sub

Private Sub CanvasView_MouseUpCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal clickEventAlsoFiring As Boolean, ByVal timeStamp As Long)
    
    'Make sure interactions with this canvas are allowed
    If Not Me.IsCanvasInteractionAllowed() Then Exit Sub
    
    'Display the image coordinates under the mouse pointer
    Dim imgX As Double, imgY As Double
    DisplayImageCoordinates x, y, pdImages(g_CurrentImage), Me, imgX, imgY
    
    'We also need a copy of the current mouse position relative to the active layer.  (This became necessary in PD 7.0, as layers
    ' may have non-destructive affine transforms active, which means we can't blindly switch between image and layer coordinate spaces!)
    Dim layerX As Single, layerY As Single
    Drawing.ConvertImageCoordsToLayerCoords_Full pdImages(g_CurrentImage), pdImages(g_CurrentImage).GetActiveLayer, imgX, imgY, layerX, layerY
    
    'Display a relevant cursor for the current action
    SetCanvasCursor pMouseUp, Button, x, y, imgX, imgY, layerX, layerY
    
    'Check mouse buttons
    If (Button = vbLeftButton) Then
    
        m_LMBDown = False
    
        Select Case g_CurrentTool
        
            'Click-to-drag navigation
            Case NAV_DRAG
                
            'Move stuff around
            Case NAV_MOVE
            
                'Pass a final transform request to the layer handler.  This will initiate Undo/Redo creation, among other things.
                If (m_NumOfMouseMovements > 0) Then Tools.TransformCurrentLayer imgX, imgY, pdImages(g_CurrentImage), pdImages(g_CurrentImage).GetActiveLayer, FormMain.mainCanvas(0), (Shift And vbShiftMask), True
                
                'Reset the generic tool mouse tracking function
                Tools.TerminateGenericToolTracking
                
            'Color picker
            Case COLOR_PICKER
                ColorPicker.NotifyMouseXY m_LMBDown, imgX, imgY, Me
                
            'Selection tools have their own dedicated handler
            Case SELECT_RECT, SELECT_CIRC, SELECT_LINE, SELECT_POLYGON, SELECT_LASSO, SELECT_WAND
                Selections.NotifySelectionMouseUp Me, Shift, imgX, imgY, clickEventAlsoFiring, m_SelectionActiveBeforeMouseEvents
                
            'Text layers
            Case VECTOR_TEXT, VECTOR_FANCYTEXT
                
                'Pass a final transform request to the layer handler.  This will initiate Undo/Redo creation, among other things.
                
                '(Note that this function branches according to two states: whether this click is creating a new text layer (which requires a full
                ' image stack Undo/Redo), or whether we are simply modifying an existing layer.
                If (Tools.GetCustomToolState = PD_TEXT_TOOL_CREATED_NEW_LAYER) Then
                    
                    'Mark the current tool as busy to prevent any unwanted UI syncing
                    Tools.SetToolBusyState True
                    
                    'See if this was just a click (as it might be at creation time).
                    If clickEventAlsoFiring Or (m_NumOfMouseMovements <= 2) Or (pdImages(g_CurrentImage).GetActiveLayer.GetLayerWidth < 4) Or (pdImages(g_CurrentImage).GetActiveLayer.GetLayerHeight < 4) Then
                        
                        'Update the layer's size.  At present, we simply make it fill the current viewport.
                        Dim curImageRectF As RectF
                        pdImages(g_CurrentImage).ImgViewport.GetIntersectRectImage curImageRectF
                        
                        With pdImages(g_CurrentImage)
                            .GetActiveLayer.SetLayerOffsetX curImageRectF.Left
                            .GetActiveLayer.SetLayerOffsetY curImageRectF.Top
                            .GetActiveLayer.SetLayerWidth curImageRectF.Width
                            .GetActiveLayer.SetLayerHeight curImageRectF.Height
                        End With
                        
                        'If the current text box is empty, set some new text to orient the user
                        If (g_CurrentTool = VECTOR_TEXT) Then
                            If (Len(toolpanel_Text.txtTextTool.Text) = 0) Then toolpanel_Text.txtTextTool.Text = g_Language.TranslateMessage("(enter text here)")
                        Else
                            If (Len(toolpanel_FancyText.txtTextTool.Text) = 0) Then toolpanel_FancyText.txtTextTool.Text = g_Language.TranslateMessage("(enter text here)")
                        End If
                        
                        'Manually synchronize the new size values against their on-screen UI elements
                        Tools.SyncToolOptionsUIToCurrentLayer
                        
                        'Manually force a viewport redraw
                        ViewportEngine.Stage2_CompositeAllLayers pdImages(g_CurrentImage), FormMain.mainCanvas(0)
                        
                    'If the user already specified a size, use their values to finalize the layer size
                    Else
                        Tools.TransformCurrentLayer imgX, imgY, pdImages(g_CurrentImage), pdImages(g_CurrentImage).GetActiveLayer, FormMain.mainCanvas(0), (Shift And vbShiftMask)
                    End If
                    
                    'As a failsafe, ensure the layer has a proper rotational center point.  (If the user dragged the mouse so that
                    ' the text box was 0x0 pixels at some size, the rotational center point math would have failed and become (0, 0)
                    ' to match.)
                    pdImages(g_CurrentImage).GetActiveLayer.SetLayerRotateCenterX 0.5
                    pdImages(g_CurrentImage).GetActiveLayer.SetLayerRotateCenterY 0.5
                    
                    'Release the tool engine
                    Tools.SetToolBusyState False
                    
                    'Process the addition of the new layer; this will create proper Undo/Redo data for the entire image (required, as the layer order
                    ' has changed due to this new addition).
                    With pdImages(g_CurrentImage).GetActiveLayer
                        Process "New text layer", , BuildParamList("layerheader", .GetLayerHeaderAsXML(), "layerdata", .GetVectorDataAsXML), UNDO_Image_VectorSafe
                    End With
                    
                    'Manually synchronize menu, layer toolbox, and other UI settings against the newly created layer.
                    Interface.SyncInterfaceToCurrentImage
                    
                    'Finally, set focus to the text layer text entry box
                    If (g_CurrentTool = VECTOR_TEXT) Then toolpanel_Text.txtTextTool.SelectAll Else toolpanel_FancyText.txtTextTool.SelectAll
                    
                'The user is simply editing an existing layer.
                Else
                    
                    'As a convenience to the user, ignore clicks that don't actually change layer settings
                    If (m_NumOfMouseMovements > 0) Then Tools.TransformCurrentLayer imgX, imgY, pdImages(g_CurrentImage), pdImages(g_CurrentImage).GetActiveLayer, FormMain.mainCanvas(0), (Shift And vbShiftMask), True
                    
                End If
                
                'Reset the generic tool mouse tracking function
                Tools.TerminateGenericToolTracking
            
            'Notify the brush engine of the final result, then permanently commit this round of brush work
            Case PAINT_BASICBRUSH, PAINT_SOFTBRUSH, PAINT_ERASER
                Paintbrush.NotifyBrushXY m_LMBDown, imgX, imgY, timeStamp, Me
                Paintbrush.CommitBrushResults
                
            Case PAINT_FILL
                FillTool.NotifyMouseXY m_LMBDown, imgX, imgY, Me
                
            Case Else
                    
        End Select
                        
    End If
    
    If (Button = vbRightButton) Then m_RMBDown = False
    
    'Reset any tracked point of interest value for this layer
    m_CurPOI = poi_Undefined
        
    'Reset the mouse movement tracker
    m_NumOfMouseMovements = 0
    
End Sub

Public Sub CanvasView_MouseWheelHorizontal(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal scrollAmount As Double)
    If (Not IsCanvasInteractionAllowed()) Then Exit Sub
    If hScroll.Visible Then hScroll.RelayMouseWheelEvent False, Button, Shift, x, y, scrollAmount
End Sub

'Vertical mousewheel scrolling.  Note that Shift+Wheel and Ctrl+Wheel modifiers do NOT raise this event; pdInputMouse automatically
' reroutes them to MouseWheelHorizontal and MouseWheelZoom, respectively.
Public Sub CanvasView_MouseWheelVertical(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal scrollAmount As Double)
    
    If Not IsCanvasInteractionAllowed() Then Exit Sub
    
    'PhotoDemon uses the standard photo editor convention of Ctrl+Wheel = zoom, Shift+Wheel = h_scroll, and Wheel = v_scroll.
    ' Some users (for reasons I don't understand??) expect plain mousewheel to zoom the image.  For these users, we now
    ' display a helpful message telling them to use the damn Ctrl modifier like everyone else.
    If vScroll.Visible Then
        vScroll.RelayMouseWheelEvent True, Button, Shift, x, y, scrollAmount
        
    'The user is using the mousewheel without Ctrl/Shift modifiers, even without a visible scrollbar.
    ' Display a message about how mousewheels are supposed to work.
    Else
        Message "Mouse Wheel = VERTICAL SCROLL,  Shift + Wheel = HORIZONTAL SCROLL,  Ctrl + Wheel = ZOOM"
    End If
    
    'NOTE: horizontal scrolling via Shift+Vertical Wheel is handled in the separate _MouseWheelHorizontal event.
    'NOTE: zooming via Ctrl+Vertical Wheel is handled in the separate _MouseWheelZoom event.
    
End Sub

Public Sub CanvasView_MouseWheelZoom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal zoomAmount As Double)
    
    If Not IsCanvasInteractionAllowed() Then Exit Sub
    
    'Before doing anything else, cache the current mouse coordinates (in both Canvas and Image coordinate spaces)
    Dim imgX As Double, imgY As Double
    ConvertCanvasCoordsToImageCoords Me, pdImages(g_CurrentImage), x, y, imgX, imgY, True
    
    'Suspend automatic viewport redraws until we are done with our calculations
    ViewportEngine.DisableRendering
    
    'Calculate a new zoom value
    If StatusBar.IsZoomEnabled Then
        If (zoomAmount > 0) Then
            If (StatusBar.GetZoomDropDownIndex > 0) Then StatusBar.SetZoomDropDownIndex g_Zoom.GetNearestZoomInIndex(StatusBar.GetZoomDropDownIndex)
        ElseIf (zoomAmount < 0) Then
            If (StatusBar.GetZoomDropDownIndex <> g_Zoom.GetZoomCount) Then StatusBar.SetZoomDropDownIndex g_Zoom.GetNearestZoomOutIndex(StatusBar.GetZoomDropDownIndex)
        End If
    End If
    
    'Re-enable automatic viewport redraws
    ViewportEngine.EnableRendering
    
    'Request a manual redraw from ViewportEngine.Stage1_InitializeBuffer, while supplying our x/y coordinates so that it can preserve mouse position
    ' relative to the underlying image.
    ViewportEngine.Stage1_InitializeBuffer pdImages(g_CurrentImage), FormMain.mainCanvas(0), VSR_PreservePointPosition, x, y, imgX, imgY
    
    'Notify external UI elements of the change
    RelayViewportChanges

End Sub

Private Sub ImageStrip_Click(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)

    If (Button And pdRightButton) <> 0 Then
        
        ucSupport.RequestCursor IDC_DEFAULT
        
        'Enable various pop-up menu entries.  Wherever possible, we simply want to mimic the official PD menu, which saves
        ' us having to supply our own heuristics for menu enablement.
        mnuTabstripPopup(POP_SAVE).Enabled = FormMain.MnuFile(8).Enabled
        mnuTabstripPopup(POP_SAVE_COPY).Enabled = FormMain.MnuFile(9).Enabled
        mnuTabstripPopup(POP_SAVE_AS).Enabled = FormMain.MnuFile(10).Enabled
        mnuTabstripPopup(POP_REVERT).Enabled = FormMain.MnuFile(11).Enabled
        mnuTabstripPopup(POP_CLOSE).Enabled = FormMain.MnuFile(5).Enabled
        
        'Two special commands only appear in this menu: Open in Explorer, and Close Other Images
        ' Use our own enablement heuristics for these.
        
        'Open in Explorer only works if the image is currently on-disk
        mnuTabstripPopup(POP_OPEN_IN_EXPLORER).Enabled = (Len(pdImages(g_CurrentImage).ImgStorage.GetEntry_String("CurrentLocationOnDisk", vbNullString)) > 0)
        
        'Close Other Images only works if more than one image is open.  We can determine this using the Next/Previous Image items
        ' in the Window menu
        mnuTabstripPopup(POP_CLOSE).Enabled = FormMain.MnuWindow(5).Enabled
        
        'Raise the context menu
        UserControl.PopupMenu mnuImageTabsContext, x:=x, y:=y
        ShowCursor 1
        
    End If
    
End Sub

Private Sub ImageStrip_ItemClosed(ByVal itemIndex As Long)
    CanvasManager.FullPDImageUnload itemIndex
End Sub

Private Sub ImageStrip_ItemSelected(ByVal itemIndex As Long)
    CanvasManager.ActivatePDImage itemIndex, "user clicked image thumbnail"
End Sub

'When the image strip's position changes, we may need to move it to an entirely new position.  This also necessitates
' a layout adjustment of all other controls on the canvas.
Private Sub ImageStrip_PositionChanged()
    If (Not m_InternalResize) Then Me.AlignCanvasView
End Sub

'All popup menu clicks are handled here
Private Sub mnuTabstripPopup_Click(Index As Integer)

    Select Case Index
        
        'Save
        Case 0
            FileMenu.MenuSave pdImages(g_CurrentImage)
        
        'Save copy (lossless)
        Case 1
            FileMenu.MenuSaveLosslessCopy pdImages(g_CurrentImage)
        
        'Save as
        Case 2
            FileMenu.MenuSaveAs pdImages(g_CurrentImage)
        
        'Revert
        Case 3
            
            pdImages(g_CurrentImage).UndoManager.RevertToLastSavedState
                        
            'Also, redraw the current child form icon
            CreateCustomFormIcons pdImages(g_CurrentImage)
            ImageStrip.NotifyUpdatedImage g_CurrentImage
        
        '(separator)
        Case 4
        
        'Open location in Explorer
        Case 5
            Dim filePath As String, shellCommand As String
            filePath = pdImages(g_CurrentImage).ImgStorage.GetEntry_String("CurrentLocationOnDisk", vbNullString)
            shellCommand = "explorer.exe /select,""" & filePath & """"
            Shell shellCommand, vbNormalFocus
        
        '(separator)
        Case 6
        
        'Close
        Case 7
            CanvasManager.FullPDImageUnload g_CurrentImage
        
        'Close all but this
        Case 8
            
            Dim curImageID As Long
            curImageID = pdImages(g_CurrentImage).imageID
            
            Dim i As Long
            For i = 0 To UBound(pdImages)
                If (Not pdImages(i) Is Nothing) Then
                    If pdImages(i).imageID <> curImageID Then FullPDImageUnload i
                End If
            Next i
    
    End Select

End Sub

Private Sub ucSupport_WindowResize(ByVal newWidth As Long, ByVal newHeight As Long)
    AlignCanvasView
End Sub

Private Sub UserControl_Initialize()
    
    'Initialize a master user control support class
    Set ucSupport = New pdUCSupport
    ucSupport.RegisterControl UserControl.hWnd, False, True
    ucSupport.RequestExtraFunctionality True
    
    'Prep the color manager and load default colors
    Set m_Colors = New pdThemeColors
    Dim colorCount As PDCANVAS_COLOR_LIST: colorCount = [_Count]
    m_Colors.InitializeColorList "PDCanvas", colorCount
    If Not MainModule.IsProgramRunning() Then UpdateColorList
    
    If MainModule.IsProgramRunning() Then
        
        'Allow the control to generate its own redraw requests
        Me.SetRedrawSuspension False
        
        'Set scroll bar size to match the current system default (which changes based on DPI, theming, and other factors)
        hScroll.Height = GetSystemMetrics(SM_CYHSCROLL)
        vScroll.Width = GetSystemMetrics(SM_CXVSCROLL)
        
        'Align the main picture box
        AlignCanvasView
        
        'Reset any POI trackers
        m_CurPOI = poi_Undefined
        m_LastPOI = poi_Undefined
        
    End If
    
End Sub

Private Sub HScroll_Scroll(ByVal eventIsCritical As Boolean)
    
    'Regardless of viewport state, cache the current scroll bar value inside the current image
    If (Not pdImages(g_CurrentImage) Is Nothing) Then pdImages(g_CurrentImage).ImgViewport.SetHScrollValue hScroll.Value
    
    If (Not Me.GetRedrawSuspension) Then
        
        'Request the scroll-specific viewport pipeline stage
        ViewportEngine.Stage2_CompositeAllLayers pdImages(g_CurrentImage), Me
        
        'Notify any other relevant UI elements
        RelayViewportChanges
        
    End If
    
End Sub

Public Sub UpdateCanvasLayout()
    If (g_OpenImageCount = 0) Then Me.ClearCanvas Else Me.AlignCanvasView
    StatusBar.ReflowStatusBar (g_OpenImageCount > 0)
End Sub

Private Function ShouldImageStripBeVisible() As Boolean
    
    ShouldImageStripBeVisible = False
    
    'User preference = "Always visible"
    If (ImageStrip.VisibilityMode = 0) Then
        If (g_OpenImageCount > 0) Then ShouldImageStripBeVisible = True
    
    'User preference = "Visible if 2+ images loaded"
    ElseIf (ImageStrip.VisibilityMode = 1) Then
        If (g_OpenImageCount > 1) Then ShouldImageStripBeVisible = True
        
    'User preference = "Never visible"
    End If
    
End Function

'Given the current user control rect, modify it to account for the image tabstrip's position, and also fill a new rect
' with the tabstrip's dimensions.
Private Sub FillTabstripRect(ByRef ucRect As RectF, ByRef dstRect As RectF)
    
    Dim cSize As Long
    cSize = ImageStrip.ConstrainingSize
    
    With dstRect

        Select Case ImageStrip.Alignment
        
            Case vbAlignTop
                .Left = ucRect.Left
                .Top = ucRect.Top
                .Width = ucRect.Width
                .Height = cSize
                ucRect.Top = ucRect.Top + cSize
                ucRect.Height = ucRect.Height - cSize
            
            Case vbAlignBottom
                .Left = ucRect.Left
                .Top = (ucRect.Top + ucRect.Height) - cSize
                .Width = ucRect.Width
                .Height = cSize
                ucRect.Height = ucRect.Height - cSize
            
            Case vbAlignLeft
                .Left = ucRect.Left
                .Top = ucRect.Top
                .Width = cSize
                .Height = ucRect.Height
                ucRect.Left = ucRect.Left + cSize
                ucRect.Width = ucRect.Width - cSize
            
            Case vbAlignRight
                .Left = (ucRect.Left + ucRect.Width) - cSize
                .Top = ucRect.Top
                .Width = cSize
                .Height = ucRect.Height
                ucRect.Width = ucRect.Width - cSize
        
        End Select
        
    End With
    
End Sub

'Given the current user control rect, modify it to account for the status bar's position, and also fill a new rect
' with the status bar's dimensions.
Private Sub FillStatusBarRect(ByRef ucRect As RectF, ByRef dstRect As RectF)
    ucRect.Height = ucRect.Height - StatusBar.GetHeight
    dstRect.Top = ucRect.Top + ucRect.Height
    dstRect.Height = StatusBar.GetHeight
    dstRect.Left = ucRect.Left
    dstRect.Width = ucRect.Width
End Sub

Public Sub AlignCanvasView()
        
    'Prevent recursive redraws by putting the entire UC into "resize mode"; while in this mode, we ignore anything that
    ' attempts to auto-initiate a canvas realignment request.
    If m_InternalResize Then Exit Sub
    m_InternalResize = True
    
    'Measurements must come from ucSupport (to guarantee that they're DPI-aware)
    Dim bWidth As Long, bHeight As Long
    bWidth = ucSupport.GetControlWidth
    bHeight = ucSupport.GetControlHeight
    
    'Using the DPI-aware measurements, construct a rect that defines the entire available control area
    Dim ucRect As RectF
    ucRect.Left = 0
    ucRect.Top = 0
    ucRect.Width = bWidth
    ucRect.Height = bHeight
    
    'The image tabstrip, if visible, gets placement preference
    Dim tabstripVisible As Boolean, tabstripRect As RectF
    tabstripVisible = ShouldImageStripBeVisible
    
    'If we are showing the tabstrip for the first time, we need to position it prior to displaying it
    If tabstripVisible Then
        FillTabstripRect ucRect, tabstripRect
    Else
        ImageStrip.Visible = tabstripVisible
    End If
    
    'With the tabstrip rect in place, we now need to calculate a status bar rect
    Dim statusBarRect As RectF
    FillStatusBarRect ucRect, statusBarRect
    
    'As of version 7.0, scroll bars are always visible.  This matches the behavior of paint-centric software like Krita,
    ' and makes it much easier to enable scrolling past the edge of an image (without resorting to stupid click-hold
    ' scroll behavior like GIMP).
    Dim hScrollTop As Long, hScrollLeft As Long, vScrollTop As Long, vScrollLeft As Long
    hScrollLeft = ucRect.Left
    hScrollTop = (ucRect.Top + ucRect.Height) - hScroll.GetHeight
    If hScroll.Visible Then ucRect.Height = ucRect.Height - hScroll.GetHeight
    
    vScrollTop = ucRect.Top
    vScrollLeft = (ucRect.Left + ucRect.Width) - vScroll.GetWidth
    If vScroll.Visible Then ucRect.Width = ucRect.Width - vScroll.GetWidth
    
    'With scroll bar positions calculated, calculate width/height values for the main canvas picture box
    Dim cvTop As Long, cvLeft As Long, cvWidth As Long, cvHeight As Long
    cvTop = ucRect.Top
    cvLeft = ucRect.Left
    cvWidth = ucRect.Width
    cvHeight = ucRect.Height
    
    'Move the CanvasView box into position first
    If (CanvasView.GetLeft <> cvLeft) Or (CanvasView.GetTop <> cvTop) Or (CanvasView.GetWidth <> cvWidth) Or (CanvasView.GetHeight <> cvHeight) Then
        If ((cvWidth > 0) And (cvHeight > 0)) Then
            CanvasView.SetPositionAndSize cvLeft, cvTop, cvWidth, cvHeight
        End If
    End If
    
    '...Followed by the scrollbars
    If (hScroll.Left <> hScrollLeft) Or (hScroll.Top <> hScrollTop) Or (hScroll.Width <> cvWidth) Then
        If (cvWidth > 0) Then hScroll.SetPositionAndSize hScrollLeft, hScrollTop, cvWidth, hScroll.GetHeight
    End If
    
    If (vScroll.Left <> vScrollLeft) Or (vScroll.Top <> vScrollTop) Or (vScroll.Height <> cvHeight) Then
        If (cvHeight > 0) Then vScroll.SetPositionAndSize vScrollLeft, vScrollTop, vScroll.GetWidth, cvHeight
    End If
    
    '...Followed by the "center" button (which sits between the scroll bars)
    If (cmdCenter.GetLeft <> vScrollLeft) Or (cmdCenter.GetTop <> hScrollTop) Then
        cmdCenter.SetLeft vScrollLeft
        cmdCenter.SetTop hScrollTop
    End If
    
    '...Followed by the status bar
    With statusBarRect
        StatusBar.SetPositionAndSize .Left, .Top, .Width, .Height
    End With
    
    '...and the progress bar placeholder.  (Note that it doesn't need a special rect - we always just position it
    ' above the status bar.)
    With statusBarRect
        picProgressBar.Move .Left, .Top - picProgressBar.Height, .Width, picProgressBar.Height
    End With
    
    '...And finally, the image tabstrip (as relevant)
    With tabstripRect
        ImageStrip.SetPositionAndSize .Left, .Top, .Width, .Height
    End With
    
    If tabstripVisible And (Not ImageStrip.Visible) Then ImageStrip.Visible = True
    
    m_InternalResize = False
    
End Sub

'At run-time, painting is handled by PD's pdWindowPainter class.  In the IDE, however, we must rely on VB's internal paint event.
Private Sub UserControl_Paint()
    If Not MainModule.IsProgramRunning() Then ucSupport.RequestIDERepaint UserControl.hDC
End Sub

Private Sub UserControl_Resize()
    If Not MainModule.IsProgramRunning() Then ucSupport.RequestRepaint True
End Sub

Private Sub UserControl_Show()

    If MainModule.IsProgramRunning() Then
        
        'XP users may not have Segoe UI available, which will cause the following lines to throw an error;
        ' it's not really a problem, as the labels will just keep their Tahoma font, but we must catch it anyway.
        On Error GoTo CanvasShowError
                
        'TODO: see if this is still valid, since we've moved theming much earlier in the load process
        'Now comes a bit of an odd case.  This control's _Show event happens relatively early in the load process due to it
        ' being present on FormMain.  Because of that, the global interface font value may not be loaded yet.  To avoid
        ' problems from this, we will just load Segoe UI by default, and if that fails (as it may on XP), the labels will
        ' retain their default Tahoma label.
        
        'Convert all labels to the current interface font
        If (Len(g_InterfaceFont) = 0) Then
            #If DEBUGMODE = 1 Then
                pdDebug.LogAction "WARNING: pdCanvas.UserControl_Show had to make a premature decision about g_InterfaceFont"
            #End If
            g_InterfaceFont = "Segoe UI"
        End If
        
CanvasShowError:
        
    End If
    
End Sub

'At present, the only component of the canvas that saves preferences is the image tabstrip
Public Sub ReadUserPreferences()
    ImageStrip.ReadUserPreferences
End Sub

Public Sub WriteUserPreferences()
    ImageStrip.WriteUserPreferences
End Sub

Private Sub VScroll_Scroll(ByVal eventIsCritical As Boolean)
        
    'Regardless of viewport state, cache the current scroll bar value inside the current image
    If Not pdImages(g_CurrentImage) Is Nothing Then
        pdImages(g_CurrentImage).ImgViewport.SetVScrollValue vScroll.Value
    End If
        
    If (Not Me.GetRedrawSuspension) Then
    
        'Request the scroll-specific viewport pipeline stage
        ViewportEngine.Stage2_CompositeAllLayers pdImages(g_CurrentImage), Me
        
        'Notify any other relevant UI elements
        RelayViewportChanges
        
    End If
    
End Sub

Public Function PopulateSizeUnits()
    StatusBar.PopulateSizeUnits
End Function

'Various drawing tools support high-rate mouse input.  Change that behavior here.
Public Sub SetMouseInput_HighRes(ByVal newState As Boolean)
    CanvasView.SetMouseInput_HighRes newState
End Sub

Public Sub SetMouseInput_AutoDrop(ByVal newState As Boolean)
    CanvasView.SetMouseInput_AutoDrop newState
End Sub

Public Function GetNumMouseEventsPending() As Long
    GetNumMouseEventsPending = CanvasView.GetNumMouseEventsPending()
End Function

Public Function GetNextMouseMovePoint(ByVal ptrToDstMMP As Long) As Boolean
    GetNextMouseMovePoint = CanvasView.GetNextMouseMovePoint(ptrToDstMMP)
End Function

'Whenever the mouse cursor needs to be reset, use this function to do so.  Also, when a new tool is created or a new tool feature
' is added, make sure to visit this sub and make any necessary cursor changes!
'
'A lot of extra values are passed to this function.  Individual tools can use those at their leisure to customize their cursor requests.
' RELAY: the actual cursor request needs to be passed to pdCanvasView, and we need to make sure its MouseEnter event also calls this.
Private Sub SetCanvasCursor(ByVal curMouseEvent As PD_MOUSEEVENT, ByVal Button As Integer, ByVal x As Single, ByVal y As Single, ByVal imgX As Double, ByVal imgY As Double, ByVal layerX As Double, ByVal layerY As Double)
    
    If ((Not MainModule.IsProgramRunning()) Or g_ProgramShuttingDown) Then Exit Sub
    
    'Some cursor functions operate on a POI basis
    Dim curPOI As PD_PointOfInterest

    'Obviously, cursor setting is handled separately for each tool.
    Select Case g_CurrentTool
        
        Case NAV_DRAG
        
            'When click-dragging the image to scroll around it, the cursor depends on being over the image
            If IsMouseOverImage(x, y, pdImages(g_CurrentImage)) Then
                
                If (curMouseEvent = pMouseUp) Or (Button = 0) Then
                    CanvasView.RequestCursor_PNG "cursor_handopen", 0, 0
                Else
                    CanvasView.RequestCursor_PNG "cursor_handclosed", 0, 0
                End If
            
            'If the cursor is not over the image, change to an arrow cursor
            Else
                CanvasView.RequestCursor_System IDC_ARROW
            End If
        
        Case NAV_MOVE
            
            'When transforming layers, the cursor depends on the active POI
            curPOI = pdImages(g_CurrentImage).GetActiveLayer.CheckForPointOfInterest(imgX, imgY)
            
            Select Case curPOI
            
                'Mouse is not over the current layer
                Case poi_Undefined
                    CanvasView.RequestCursor_System IDC_ARROW
                    
                'Mouse is over the top-left corner
                Case poi_CornerNW
                    CanvasView.RequestCursor_System IDC_SIZENWSE
                    
                'Mouse is over the top-right corner
                Case poi_CornerNE
                    CanvasView.RequestCursor_System IDC_SIZENESW
                    
                'Mouse is over the bottom-left corner
                Case poi_CornerSW
                    CanvasView.RequestCursor_System IDC_SIZENESW
                    
                'Mouse is over the bottom-right corner
                Case poi_CornerSE
                    CanvasView.RequestCursor_System IDC_SIZENWSE
                    
                'Mouse is over a rotation handle
                Case poi_EdgeE, poi_EdgeS, poi_EdgeW, poi_EdgeN
                    CanvasView.RequestCursor_System IDC_SIZEALL
                    'CanvasView.RequestCursor_PNG "cursor_rotate", 7, 7
                    
                'Mouse is within the layer, but not over a specific node
                Case poi_Interior
                
                    'This case is unique because if the user has elected to ignore transparent pixels, they cannot move a layer
                    ' by dragging the mouse within a transparent region of the layer.  Thus, before changing the cursor,
                    ' check to see if the hovered layer index is the same as the current layer index; if it isn't, don't display
                    ' the Move cursor.  (Note that this works because the getLayerUnderMouse function, called during the MouseMove
                    ' event, automatically factors the transparency check into its calculation.  Thus we don't have to
                    ' re-evaluate the setting here.)
                    If (m_LayerAutoActivateIndex = pdImages(g_CurrentImage).GetActiveLayerIndex) Then
                        CanvasView.RequestCursor_System IDC_SIZEALL
                    Else
                        CanvasView.RequestCursor_System IDC_ARROW
                    End If
                    
            End Select
            
            'The move tool is unique because it will request a redraw of the viewport when the POI changes, so that the current
            ' POI can be highlighted.
            If (m_LastPOI <> curPOI) Then
                m_LastPOI = curPOI
                ViewportEngine.Stage4_FlipBufferAndDrawUI pdImages(g_CurrentImage), Me, curPOI
            End If
            
        
        'The color-picker custom-draws its own outline.
        Case COLOR_PICKER
            CanvasView.RequestCursor_System IDC_ICON
            If (Button = 0) Then ViewportEngine.Stage4_FlipBufferAndDrawUI pdImages(g_CurrentImage), Me
            
        Case SELECT_RECT, SELECT_CIRC
        
            'When transforming selections, the cursor image depends on its proximity to a point of interest.
            Select Case IsCoordSelectionPOI(imgX, imgY, pdImages(g_CurrentImage))
            
                Case poi_Undefined
                    CanvasView.RequestCursor_System IDC_ARROW
                Case poi_CornerNW
                    CanvasView.RequestCursor_System IDC_SIZENWSE
                Case poi_CornerNE
                    CanvasView.RequestCursor_System IDC_SIZENESW
                Case poi_CornerSE
                    CanvasView.RequestCursor_System IDC_SIZENWSE
                Case poi_CornerSW
                    CanvasView.RequestCursor_System IDC_SIZENESW
                Case poi_EdgeN
                    CanvasView.RequestCursor_System IDC_SIZENS
                Case poi_EdgeE
                    CanvasView.RequestCursor_System IDC_SIZEWE
                Case poi_EdgeS
                    CanvasView.RequestCursor_System IDC_SIZENS
                Case poi_EdgeW
                    CanvasView.RequestCursor_System IDC_SIZEWE
                Case poi_Interior
                    CanvasView.RequestCursor_System IDC_SIZEALL
            
            End Select
        
        Case SELECT_LINE
        
            'When transforming selections, the cursor image depends on its proximity to a point of interest.
            '
            'For a line selection, the possible transform IDs are:
            ' -1 - Cursor is not near an endpoint
            ' 0 - Near x1/y1
            ' 1 - Near x2/y2
            Select Case IsCoordSelectionPOI(imgX, imgY, pdImages(g_CurrentImage))
            
                Case poi_Undefined
                    CanvasView.RequestCursor_System IDC_ARROW
                Case 0
                    CanvasView.RequestCursor_System IDC_SIZEALL
                Case 1
                    CanvasView.RequestCursor_System IDC_SIZEALL
            
            End Select
        
         Case SELECT_POLYGON
            
            Select Case IsCoordSelectionPOI(imgX, imgY, pdImages(g_CurrentImage))
            
                Case poi_Undefined
                    CanvasView.RequestCursor_System IDC_ARROW
                
                'numOfPolygonPoints: mouse is inside the polygon, but not over a polygon node
                Case poi_Interior
                    If pdImages(g_CurrentImage).MainSelection.IsLockedIn Then
                        CanvasView.RequestCursor_System IDC_SIZEALL
                    Else
                        CanvasView.RequestCursor_System IDC_ARROW
                    End If
                    
                'Everything else: mouse is over a polygon node
                Case Else
                    CanvasView.RequestCursor_System IDC_SIZEALL
                    
            End Select
        
        Case SELECT_LASSO
            
            Select Case IsCoordSelectionPOI(imgX, imgY, pdImages(g_CurrentImage))
            
                Case poi_Undefined
                    CanvasView.RequestCursor_System IDC_ARROW
                
                'poi_Interior: mouse is inside the lasso selection area.  As a convenience to the user, we don't update the cursor
                '   if they're still in "drawing" mode - we only update it if the selection is complete.
                Case poi_Interior
                    If pdImages(g_CurrentImage).MainSelection.IsLockedIn Then
                        CanvasView.RequestCursor_System IDC_SIZEALL
                    Else
                        CanvasView.RequestCursor_System IDC_ARROW
                    End If
                    
            End Select
            
        Case SELECT_WAND
        
            Select Case IsCoordSelectionPOI(imgX, imgY, pdImages(g_CurrentImage))
            
                Case poi_Undefined
                    CanvasView.RequestCursor_System IDC_ARROW
                
                '0: mouse is inside the lasso selection area.  As a convenience to the user, we don't update the cursor
                '   if they're still in "drawing" mode - we only update it if the selection is complete.
                Case Else
                    CanvasView.RequestCursor_System IDC_SIZEALL
                    
            End Select
        
        Case VECTOR_TEXT, VECTOR_FANCYTEXT

            'The text tool bears a lot of similarity to the Move / Size tool, although the resulting behavior is
            ' obviously quite different.
            
            'First, see if the active layer is a text layer.  If it is, we need to check for POIs.
            If pdImages(g_CurrentImage).GetActiveLayer.IsLayerText Then
                
                'When transforming layers, the cursor depends on the active POI
                curPOI = pdImages(g_CurrentImage).GetActiveLayer.CheckForPointOfInterest(imgX, imgY)
                
                Select Case curPOI
    
                    'Mouse is not over the current layer
                    Case poi_Undefined
                        CanvasView.RequestCursor_System IDC_IBEAM
    
                    'Mouse is over the top-left corner
                    Case poi_CornerNW
                        CanvasView.RequestCursor_System IDC_SIZENWSE
                    
                    'Mouse is over the top-right corner
                    Case poi_CornerNE
                        CanvasView.RequestCursor_System IDC_SIZENESW
                    
                    'Mouse is over the bottom-left corner
                    Case poi_CornerSW
                        CanvasView.RequestCursor_System IDC_SIZENESW
                    
                    'Mouse is over the bottom-right corner
                    Case poi_CornerSE
                        CanvasView.RequestCursor_System IDC_SIZENWSE
                        
                    'Mouse is over a rotation handle
                    Case poi_EdgeE, poi_EdgeS, poi_EdgeW, poi_EdgeN
                        CanvasView.RequestCursor_System IDC_SIZEALL
                    
                    'Mouse is within the layer, but not over a specific node
                    Case poi_Interior
                        CanvasView.RequestCursor_System IDC_SIZEALL
                    
                End Select
                
                'Similar to the move tool, texts tools will request a redraw of the viewport when the POI changes, so that the current
                ' POI can be highlighted.
                If (m_LastPOI <> curPOI) Then
                    m_LastPOI = curPOI
                    ViewportEngine.Stage4_FlipBufferAndDrawUI pdImages(g_CurrentImage), Me, curPOI
                End If
                
            'If the current layer is *not* a text layer, clicking anywhere will create a new text layer
            Else
                CanvasView.RequestCursor_System IDC_IBEAM
            End If
        
        'Paint tools are a little weird, because we custom-draw the current brush outline - but *only*
        ' if no mouse button is down.  (If a button *is* down, the paint operation will automatically
        ' request a viewport refresh.)
        Case PAINT_BASICBRUSH, PAINT_SOFTBRUSH, PAINT_ERASER, PAINT_FILL
            CanvasView.RequestCursor_System IDC_ICON
            If (Button = 0) Then ViewportEngine.Stage4_FlipBufferAndDrawUI pdImages(g_CurrentImage), Me
            
        Case Else
            CanvasView.RequestCursor_System IDC_ARROW
            
    End Select

End Sub

'Is the mouse currently over the canvas?
Public Function IsMouseOverCanvas() As Boolean
    IsMouseOverCanvas = m_IsMouseOverCanvas
End Function

'Simple, unified way to see if canvas interaction is allowed.
Public Function IsCanvasInteractionAllowed() As Boolean
    IsCanvasInteractionAllowed = CanvasView.IsCanvasInteractionAllowed
End Function

'If the viewport experiences changes to scroll or zoom values, this function will be automatically called.  Any relays to external
' functions (functions that rely on viewport settings, obviously) should be handled here.
' TODO: migrate this function elsewhere, so things other than the canvas can easily utilize it.
Public Sub RelayViewportChanges()
    toolbar_Layers.NotifyViewportChange
End Sub

Public Sub NotifyImageStripVisibilityMode(ByVal newMode As Long)
    ImageStrip.VisibilityMode = newMode
End Sub

Public Sub NotifyImageStripAlignment(ByVal newAlignment As AlignConstants)
    ImageStrip.Alignment = newAlignment
End Sub

Public Sub SetCursorToCanvasPosition(ByVal newCanvasX As Double, ByVal newCanvasY As Double)
    CanvasView.SetCursorToCanvasPosition newCanvasX, newCanvasY
End Sub

'Before this control does any painting, we need to retrieve relevant colors from PD's primary theming class.  Note that this
' step must also be called if/when PD's visual theme settings change.
Private Sub UpdateColorList()
    With m_Colors
        .LoadThemeColor PDC_Background, "Background", IDE_GRAY
        .LoadThemeColor PDC_StatusBar, "StatusBar", IDE_GRAY
        .LoadThemeColor PDC_SpecialButtonBackground, "SpecialButtonBackground", IDE_GRAY
    End With
End Sub

'External functions can call this to request a redraw.  This is helpful for live-updating theme settings, as in the Preferences dialog,
' and/or retranslating all button captions against the current language.
Public Sub UpdateAgainstCurrentTheme(Optional ByVal hostFormhWnd As Long = 0)
    
    If ucSupport.ThemeUpdateRequired Then
        
        Debug.Print "(the primary canvas is retheming itself - watch for excessive invocations!)"
        
        'Suspend redraws until all theme updates are complete
        Me.SetRedrawSuspension True
        
        UpdateColorList
        ucSupport.SetCustomBackcolor m_Colors.RetrieveColor(PDC_Background, Me.Enabled)
        UserControl.BackColor = m_Colors.RetrieveColor(PDC_Background, Me.Enabled)
        If MainModule.IsProgramRunning() Then ucSupport.UpdateAgainstThemeAndLanguage
        
        CanvasView.UpdateAgainstCurrentTheme
        StatusBar.UpdateAgainstCurrentTheme
        ImageStrip.UpdateAgainstCurrentTheme
        
        'Reassign tooltips to any relevant controls.  (This also triggers a re-translation against language changes.)
        Dim centerButtonIconSize As Long
        centerButtonIconSize = FixDPI(14)
        cmdCenter.AssignImage "zoom_center", , centerButtonIconSize, centerButtonIconSize
        cmdCenter.AssignTooltip "Center the image inside the viewport"
        cmdCenter.BackColor = m_Colors.RetrieveColor(PDC_SpecialButtonBackground, Me.Enabled)
        cmdCenter.UpdateAgainstCurrentTheme
        
        hScroll.UpdateAgainstCurrentTheme
        vScroll.UpdateAgainstCurrentTheme
        
        'Any controls that utilize a custom background color must now be updated to match *our* background color.
        Dim sbBackColor As Long
        sbBackColor = m_Colors.RetrieveColor(PDC_StatusBar, Me.Enabled)
        
        Me.UpdateCanvasLayout
        
        'Restore redraw capabilities
        Me.SetRedrawSuspension False
    
    End If
    
End Sub
