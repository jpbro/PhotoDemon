VERSION 5.00
Begin VB.Form toolpanel_Selections 
   Appearance      =   0  'Flat
   BackColor       =   &H80000005&
   BorderStyle     =   0  'None
   ClientHeight    =   1515
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   16650
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
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ScaleHeight     =   101
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   1110
   ShowInTaskbar   =   0   'False
   Visible         =   0   'False
   Begin PhotoDemon.pdDropDown cboSelSmoothing 
      Height          =   735
      Left            =   2760
      TabIndex        =   1
      Top             =   30
      Width           =   2415
      _ExtentX        =   4260
      _ExtentY        =   1296
      Caption         =   "smoothing"
      FontSizeCaption =   10
   End
   Begin PhotoDemon.pdDropDown cboSelRender 
      Height          =   735
      Left            =   120
      TabIndex        =   2
      Top             =   30
      Width           =   2415
      _ExtentX        =   4260
      _ExtentY        =   1296
      Caption         =   "appearance"
      FontSizeCaption =   10
   End
   Begin PhotoDemon.pdColorSelector csSelectionHighlight 
      Height          =   375
      Left            =   240
      TabIndex        =   3
      Top             =   840
      Width           =   2325
      _ExtentX        =   4101
      _ExtentY        =   661
   End
   Begin PhotoDemon.pdSlider sltSelectionFeathering 
      CausesValidation=   0   'False
      Height          =   405
      Left            =   2760
      TabIndex        =   4
      Top             =   840
      Visible         =   0   'False
      Width           =   2550
      _ExtentX        =   4498
      _ExtentY        =   714
      Max             =   100
   End
   Begin PhotoDemon.pdContainer ctlGroupSelectionSubcontainer 
      Height          =   1470
      Index           =   0
      Left            =   5340
      TabIndex        =   5
      Top             =   0
      Width           =   9975
      _ExtentX        =   0
      _ExtentY        =   0
      Begin PhotoDemon.pdDropDown cboSelArea 
         Height          =   735
         Index           =   0
         Left            =   120
         TabIndex        =   6
         Top             =   30
         Width           =   2415
         _ExtentX        =   4260
         _ExtentY        =   1296
         Caption         =   "area"
         FontSizeCaption =   10
      End
      Begin PhotoDemon.pdSlider sltSelectionBorder 
         CausesValidation=   0   'False
         Height          =   405
         Index           =   0
         Left            =   120
         TabIndex        =   7
         Top             =   840
         Width           =   2550
         _ExtentX        =   4498
         _ExtentY        =   714
         Min             =   1
         Max             =   1000
         ScaleStyle      =   2
         Value           =   1
         DefaultValue    =   1
      End
      Begin PhotoDemon.pdSpinner tudSel 
         Height          =   345
         Index           =   0
         Left            =   2820
         TabIndex        =   8
         Top             =   375
         Width           =   1320
         _ExtentX        =   2328
         _ExtentY        =   714
         Min             =   -30000
         Max             =   30000
      End
      Begin PhotoDemon.pdSpinner tudSel 
         Height          =   345
         Index           =   1
         Left            =   2820
         TabIndex        =   9
         Top             =   885
         Width           =   1320
         _ExtentX        =   2328
         _ExtentY        =   714
         Min             =   -30000
         Max             =   30000
      End
      Begin PhotoDemon.pdSpinner tudSel 
         Height          =   345
         Index           =   2
         Left            =   4380
         TabIndex        =   10
         Top             =   375
         Width           =   1320
         _ExtentX        =   2328
         _ExtentY        =   714
         DefaultValue    =   100
         Min             =   -30000
         Max             =   30000
      End
      Begin PhotoDemon.pdSpinner tudSel 
         Height          =   345
         Index           =   3
         Left            =   4380
         TabIndex        =   11
         Top             =   885
         Width           =   1320
         _ExtentX        =   2328
         _ExtentY        =   714
         DefaultValue    =   100
         Min             =   -30000
         Max             =   30000
      End
      Begin PhotoDemon.pdSlider sltCornerRounding 
         CausesValidation=   0   'False
         Height          =   735
         Left            =   5760
         TabIndex        =   12
         Top             =   30
         Width           =   2670
         _ExtentX        =   4710
         _ExtentY        =   1296
         Caption         =   "corner rounding"
         FontSizeCaption =   10
         Max             =   100
         SigDigits       =   1
      End
      Begin PhotoDemon.pdLabel lblSelection 
         Height          =   240
         Index           =   1
         Left            =   2790
         Top             =   45
         Width           =   1395
         _ExtentX        =   0
         _ExtentY        =   503
         Caption         =   "position (x, y)"
      End
      Begin PhotoDemon.pdLabel lblSelection 
         Height          =   240
         Index           =   2
         Left            =   4350
         Top             =   45
         Width           =   1395
         _ExtentX        =   2461
         _ExtentY        =   503
         Caption         =   "size (w, h)"
      End
   End
   Begin PhotoDemon.pdContainer ctlGroupSelectionSubcontainer 
      Height          =   1470
      Index           =   1
      Left            =   5340
      TabIndex        =   34
      Top             =   0
      Width           =   9975
      _ExtentX        =   0
      _ExtentY        =   0
      Begin PhotoDemon.pdDropDown cboSelArea 
         Height          =   735
         Index           =   1
         Left            =   120
         TabIndex        =   35
         Top             =   30
         Width           =   2415
         _ExtentX        =   4260
         _ExtentY        =   1296
         Caption         =   "area"
         FontSizeCaption =   10
      End
      Begin PhotoDemon.pdSlider sltSelectionBorder 
         CausesValidation=   0   'False
         Height          =   405
         Index           =   1
         Left            =   120
         TabIndex        =   36
         Top             =   840
         Width           =   2550
         _ExtentX        =   4498
         _ExtentY        =   714
         Min             =   1
         Max             =   1000
         ScaleStyle      =   2
         Value           =   1
         DefaultValue    =   1
      End
      Begin PhotoDemon.pdSpinner tudSel 
         Height          =   345
         Index           =   4
         Left            =   2820
         TabIndex        =   37
         Top             =   375
         Width           =   1320
         _ExtentX        =   2328
         _ExtentY        =   714
         Min             =   -30000
         Max             =   30000
      End
      Begin PhotoDemon.pdSpinner tudSel 
         Height          =   345
         Index           =   5
         Left            =   2820
         TabIndex        =   38
         Top             =   885
         Width           =   1320
         _ExtentX        =   2328
         _ExtentY        =   714
         Min             =   -30000
         Max             =   30000
      End
      Begin PhotoDemon.pdSpinner tudSel 
         Height          =   345
         Index           =   6
         Left            =   4380
         TabIndex        =   39
         Top             =   375
         Width           =   1320
         _ExtentX        =   2328
         _ExtentY        =   714
         DefaultValue    =   100
         Min             =   -30000
         Max             =   30000
      End
      Begin PhotoDemon.pdSpinner tudSel 
         Height          =   345
         Index           =   7
         Left            =   4380
         TabIndex        =   0
         Top             =   885
         Width           =   1320
         _ExtentX        =   2328
         _ExtentY        =   714
         DefaultValue    =   100
         Min             =   -30000
         Max             =   30000
      End
      Begin PhotoDemon.pdLabel lblSelection 
         Height          =   240
         Index           =   3
         Left            =   4350
         Top             =   45
         Width           =   3435
         _ExtentX        =   6059
         _ExtentY        =   503
         Caption         =   "size (w, h)"
      End
      Begin PhotoDemon.pdLabel lblSelection 
         Height          =   240
         Index           =   0
         Left            =   2790
         Top             =   45
         Width           =   1395
         _ExtentX        =   0
         _ExtentY        =   503
         Caption         =   "position (x, y)"
      End
   End
   Begin PhotoDemon.pdContainer ctlGroupSelectionSubcontainer 
      Height          =   1470
      Index           =   2
      Left            =   5340
      TabIndex        =   26
      Top             =   0
      Width           =   9975
      _ExtentX        =   0
      _ExtentY        =   0
      Begin PhotoDemon.pdDropDown cboSelArea 
         Height          =   735
         Index           =   2
         Left            =   120
         TabIndex        =   27
         Top             =   30
         Width           =   2415
         _ExtentX        =   4260
         _ExtentY        =   1296
         Caption         =   "area"
         FontSizeCaption =   10
      End
      Begin PhotoDemon.pdSlider sltSelectionBorder 
         CausesValidation=   0   'False
         Height          =   405
         Index           =   2
         Left            =   120
         TabIndex        =   28
         Top             =   840
         Width           =   2550
         _ExtentX        =   4498
         _ExtentY        =   714
         Min             =   1
         Max             =   1000
         ScaleStyle      =   2
         Value           =   1
         DefaultValue    =   1
      End
      Begin PhotoDemon.pdSpinner tudSel 
         Height          =   345
         Index           =   8
         Left            =   2820
         TabIndex        =   29
         Top             =   375
         Width           =   1320
         _ExtentX        =   2328
         _ExtentY        =   714
         Min             =   -30000
         Max             =   30000
      End
      Begin PhotoDemon.pdSpinner tudSel 
         Height          =   345
         Index           =   9
         Left            =   2820
         TabIndex        =   30
         Top             =   885
         Width           =   1320
         _ExtentX        =   2328
         _ExtentY        =   714
         Min             =   -30000
         Max             =   30000
      End
      Begin PhotoDemon.pdSpinner tudSel 
         Height          =   345
         Index           =   10
         Left            =   4380
         TabIndex        =   31
         Top             =   375
         Width           =   1320
         _ExtentX        =   2328
         _ExtentY        =   714
         Min             =   -30000
         Max             =   30000
      End
      Begin PhotoDemon.pdSpinner tudSel 
         Height          =   345
         Index           =   11
         Left            =   4380
         TabIndex        =   32
         Top             =   885
         Width           =   1320
         _ExtentX        =   2328
         _ExtentY        =   714
         Min             =   -30000
         Max             =   30000
      End
      Begin PhotoDemon.pdSlider sltSelectionLineWidth 
         CausesValidation=   0   'False
         Height          =   735
         Left            =   5880
         TabIndex        =   33
         Top             =   30
         Width           =   2670
         _ExtentX        =   4710
         _ExtentY        =   1296
         Caption         =   "line width"
         FontSizeCaption =   10
         Min             =   1
         Max             =   1000
         ScaleStyle      =   2
         Value           =   1
         DefaultValue    =   1
      End
      Begin PhotoDemon.pdLabel lblSelection 
         Height          =   240
         Index           =   5
         Left            =   4350
         Top             =   45
         Width           =   1425
         _ExtentX        =   0
         _ExtentY        =   503
         Caption         =   "2nd point (x, y)"
      End
      Begin PhotoDemon.pdLabel lblSelection 
         Height          =   240
         Index           =   4
         Left            =   2790
         Top             =   45
         Width           =   1485
         _ExtentX        =   0
         _ExtentY        =   503
         Caption         =   "1st point (x, y)"
      End
   End
   Begin PhotoDemon.pdContainer ctlGroupSelectionSubcontainer 
      Height          =   1470
      Index           =   3
      Left            =   5340
      TabIndex        =   22
      Top             =   0
      Width           =   9975
      _ExtentX        =   0
      _ExtentY        =   0
      Begin PhotoDemon.pdDropDown cboSelArea 
         Height          =   735
         Index           =   3
         Left            =   120
         TabIndex        =   23
         Top             =   30
         Width           =   2415
         _ExtentX        =   4260
         _ExtentY        =   1296
         Caption         =   "area"
         FontSizeCaption =   10
      End
      Begin PhotoDemon.pdSlider sltSelectionBorder 
         CausesValidation=   0   'False
         Height          =   405
         Index           =   3
         Left            =   120
         TabIndex        =   24
         Top             =   840
         Width           =   2550
         _ExtentX        =   4498
         _ExtentY        =   714
         Min             =   1
         Max             =   1000
         ScaleStyle      =   2
         Value           =   1
         DefaultValue    =   1
      End
      Begin PhotoDemon.pdSlider sltPolygonCurvature 
         CausesValidation=   0   'False
         Height          =   735
         Left            =   2760
         TabIndex        =   25
         Top             =   30
         Width           =   2670
         _ExtentX        =   4710
         _ExtentY        =   1296
         Caption         =   "curvature"
         FontSizeCaption =   10
         Max             =   1
         SigDigits       =   2
      End
   End
   Begin PhotoDemon.pdContainer ctlGroupSelectionSubcontainer 
      Height          =   1470
      Index           =   4
      Left            =   5340
      TabIndex        =   18
      Top             =   0
      Width           =   9975
      _ExtentX        =   0
      _ExtentY        =   0
      Begin PhotoDemon.pdDropDown cboSelArea 
         Height          =   735
         Index           =   4
         Left            =   120
         TabIndex        =   19
         Top             =   30
         Width           =   2415
         _ExtentX        =   4260
         _ExtentY        =   1296
         Caption         =   "area"
         FontSizeCaption =   10
      End
      Begin PhotoDemon.pdSlider sltSelectionBorder 
         CausesValidation=   0   'False
         Height          =   405
         Index           =   4
         Left            =   120
         TabIndex        =   20
         Top             =   840
         Width           =   2550
         _ExtentX        =   4498
         _ExtentY        =   714
         Min             =   1
         Max             =   1000
         ScaleStyle      =   2
         Value           =   1
         DefaultValue    =   1
      End
      Begin PhotoDemon.pdSlider sltSmoothStroke 
         CausesValidation=   0   'False
         Height          =   735
         Left            =   2760
         TabIndex        =   21
         Top             =   30
         Visible         =   0   'False
         Width           =   2670
         _ExtentX        =   4710
         _ExtentY        =   1296
         Caption         =   "stroke smoothing"
         FontSizeCaption =   10
         Max             =   1
         SigDigits       =   2
      End
   End
   Begin PhotoDemon.pdContainer ctlGroupSelectionSubcontainer 
      Height          =   1470
      Index           =   5
      Left            =   5340
      TabIndex        =   13
      Top             =   0
      Width           =   9975
      _ExtentX        =   0
      _ExtentY        =   0
      Begin PhotoDemon.pdDropDown cboWandCompare 
         Height          =   375
         Left            =   3300
         TabIndex        =   14
         Top             =   855
         Width           =   2415
         _ExtentX        =   4260
         _ExtentY        =   661
      End
      Begin PhotoDemon.pdButtonStrip btsWandArea 
         Height          =   1185
         Left            =   120
         TabIndex        =   15
         Top             =   45
         Width           =   2895
         _ExtentX        =   5106
         _ExtentY        =   2090
         Caption         =   "area"
         FontSizeCaption =   10
      End
      Begin PhotoDemon.pdSlider sltWandTolerance 
         CausesValidation=   0   'False
         Height          =   675
         Left            =   3240
         TabIndex        =   16
         Top             =   60
         Width           =   2550
         _ExtentX        =   4498
         _ExtentY        =   1191
         Caption         =   "tolerance"
         FontSizeCaption =   10
         Max             =   255
         SigDigits       =   1
      End
      Begin PhotoDemon.pdButtonStrip btsWandMerge 
         Height          =   1185
         Left            =   6120
         TabIndex        =   17
         Top             =   45
         Width           =   2895
         _ExtentX        =   5106
         _ExtentY        =   2090
         Caption         =   "sampling area"
         FontSizeCaption =   10
      End
   End
End
Attribute VB_Name = "toolpanel_Selections"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon Selection Tool Panel
'Copyright 2013-2017 by Tanner Helland
'Created: 02/Oct/13
'Last updated: 06/June/17
'Last update: allow selection property changes even if the current tool and shape don't match; however, these are
'             now processed somewhat differently.  (See individual UI element events for details.)
'
'This form includes all user-editable settings for PD's various selection tools.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'The value of all controls on this form are saved and loaded to file by this class
Private WithEvents lastUsedSettings As pdLastUsedSettings
Attribute lastUsedSettings.VB_VarHelpID = -1

Private Sub btsWandArea_Click(ByVal buttonIndex As Long)
    
    'If a selection is already active, change its type to match the current option, then redraw it
    If SelectionsAllowed(False) And (g_CurrentTool = Selections.GetRelevantToolFromSelectShape()) Then
        pdImages(g_CurrentImage).MainSelection.SetSelectionProperty sp_WandSearchMode, buttonIndex
        ViewportEngine.Stage3_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    End If
    
End Sub

Private Sub btsWandMerge_Click(ByVal buttonIndex As Long)

    'If a selection is already active, change its type to match the current option, then redraw it
    If SelectionsAllowed(False) And (g_CurrentTool = Selections.GetRelevantToolFromSelectShape()) Then
        pdImages(g_CurrentImage).MainSelection.SetSelectionProperty sp_WandSampleMerged, buttonIndex
        ViewportEngine.Stage3_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    End If

End Sub

Private Sub cboSelArea_Click(Index As Integer)

    sltSelectionBorder(Index).Visible = (cboSelArea(Index).ListIndex = sa_Border)
    
    'If a selection is already active, change its type to match the current selection, then redraw it
    If SelectionsAllowed(False) And (g_CurrentTool = Selections.GetRelevantToolFromSelectShape()) Then
        pdImages(g_CurrentImage).MainSelection.SetSelectionProperty sp_Area, cboSelArea(Index).ListIndex
        pdImages(g_CurrentImage).MainSelection.SetSelectionProperty sp_BorderWidth, sltSelectionBorder(Index).Value
        ViewportEngine.Stage3_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    End If
    
End Sub

'The "selection rendering technique" dropdown always receives event processing, even if the current selection
' tool does not match the active selection shape.  (Other tool changes are typically restricted by selection type.)
Private Sub cboSelRender_Click()
    
    'Show or hide the color selector, as appropriate
    csSelectionHighlight.Visible = (cboSelRender.ListIndex = PDSR_Highlight)
    
    'Redraw the viewport
    Selections.NotifySelectionRenderChange PDSR_RenderMode, cboSelRender.ListIndex
    If SelectionsAllowed(False) Then ViewportEngine.Stage3_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)

End Sub

'Selection smoothing is handled universally, even if the current selection shape does not match the active
' selection tool.  (This is done because selection smoothing is universally supported across all shapes.)
Private Sub cboSelSmoothing_Click()

    UpdateSelectionPanelLayout
    
    'If a selection is already active, change its type to match the current selection, then redraw it
    If SelectionsAllowed(False) Then
        pdImages(g_CurrentImage).MainSelection.SetSelectionProperty sp_Smoothing, cboSelSmoothing.ListIndex
        pdImages(g_CurrentImage).MainSelection.SetSelectionProperty sp_FeatheringRadius, sltSelectionFeathering.Value
        ViewportEngine.Stage3_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    End If

End Sub

Private Sub cboWandCompare_Click()
    
    'Limit the accuracy of the tolerance for certain comparison methods.
    If (cboWandCompare.ListIndex > 1) Then
        sltWandTolerance.SigDigits = 0
    Else
        sltWandTolerance.SigDigits = 1
    End If
    
    'If a selection is already active, change its type to match the current option, then redraw it
    If SelectionsAllowed(False) And (g_CurrentTool = Selections.GetRelevantToolFromSelectShape()) Then
        pdImages(g_CurrentImage).MainSelection.SetSelectionProperty sp_WandCompareMethod, cboWandCompare.ListIndex
        ViewportEngine.Stage3_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    End If
    
End Sub

Private Sub csSelectionHighlight_ColorChanged()
    
    'Redraw the viewport
    Selections.NotifySelectionRenderChange PDSR_HighlightColor, csSelectionHighlight.Color
    If SelectionsAllowed(False) Then ViewportEngine.Stage3_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    
End Sub

Private Sub Form_Load()
    
    'Suspend any visual updates while the form is being loaded
    ViewportEngine.DisableRendering
    
    Dim suspendActive As Boolean
    If (g_OpenImageCount > 0) Then
        suspendActive = True
        pdImages(g_CurrentImage).MainSelection.SuspendAutoRefresh True
    End If
    
    'Initialize various selection tool settings
    
    'Selection visual styles (Highlight, Lightbox, or Outline)
    cboSelRender.Clear
    cboSelRender.AddItem " highlight", 0
    cboSelRender.AddItem " lightbox", 1
    cboSelRender.AddItem " ants", 2
    cboSelRender.AddItem " outline", 3
    cboSelRender.ListIndex = 0
    
    csSelectionHighlight.Color = RGB(255, 58, 72)
    csSelectionHighlight.Visible = True
    
    'Selection smoothing (currently none, antialiased, fully feathered)
    cboSelSmoothing.Clear
    cboSelSmoothing.AddItem " none", 0
    cboSelSmoothing.AddItem " antialiased", 1
    cboSelSmoothing.AddItem " feathered", 2
    cboSelSmoothing.ListIndex = 1
    
    'Selection types (currently interior, exterior, border)
    Dim i As Long
    For i = 0 To cboSelArea.Count - 1
        cboSelArea(i).SetAutomaticRedraws False
        cboSelArea(i).AddItem " interior", 0
        cboSelArea(i).AddItem " exterior", 1
        cboSelArea(i).AddItem " border", 2
        cboSelArea(i).ListIndex = 0
        cboSelArea(i).SetAutomaticRedraws True
    Next i
    
    'Magic wand options
    btsWandMerge.AddItem "image", 0
    btsWandMerge.AddItem "layer", 1
    btsWandMerge.ListIndex = 0
    
    btsWandArea.AddItem "contiguous", 0
    btsWandArea.AddItem "global", 1
    btsWandArea.ListIndex = 0
    
    Interface.PopulateFloodFillTypes cboWandCompare
    
    'Load any last-used settings for this form
    Set lastUsedSettings = New pdLastUsedSettings
    lastUsedSettings.SetParentForm Me
    lastUsedSettings.LoadAllControlValues
    
    If suspendActive Then pdImages(g_CurrentImage).MainSelection.SuspendAutoRefresh False
    
    'If a selection is already active, synchronize all UI elements to match
    If suspendActive Then
        If pdImages(g_CurrentImage).IsSelectionActive Then Selections.SyncTextToCurrentSelection g_CurrentImage
    End If
    
    ViewportEngine.EnableRendering
    
    'Update everything against the current theme.  This will also set tooltips for various controls.
    UpdateAgainstCurrentTheme

End Sub

Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)

    'Save all last-used settings to file
    If (Not lastUsedSettings Is Nothing) Then
        lastUsedSettings.SaveAllControlValues
        lastUsedSettings.SetParentForm Nothing
    End If

End Sub

Private Sub lastUsedSettings_ReadCustomPresetData()
    
    'Reset the selection coordinate boxes to 0
    Dim i As Long
    For i = 0 To tudSel.Count - 1
        tudSel(i).Value = 0
    Next i
    
    'Pull certain universal selection settings from PD's main preferences file
    If (Not g_UserPreferences Is Nothing) Then
        cboSelRender.ListIndex = Selections.GetSelectionRenderMode()
        csSelectionHighlight.Color = Selections.GetSelectionRenderColor()
    End If
    
End Sub

Private Sub sltCornerRounding_Change()
    If SelectionsAllowed(True) And (g_CurrentTool = Selections.GetRelevantToolFromSelectShape()) Then
        pdImages(g_CurrentImage).MainSelection.SetSelectionProperty sp_RoundedCornerRadius, sltCornerRounding.Value
        ViewportEngine.Stage3_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    End If
End Sub

Private Sub sltPolygonCurvature_Change()
    If SelectionsAllowed(True) And (g_CurrentTool = Selections.GetRelevantToolFromSelectShape()) Then
        pdImages(g_CurrentImage).MainSelection.SetSelectionProperty sp_PolygonCurvature, sltPolygonCurvature.Value
        ViewportEngine.Stage3_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    End If
End Sub

Private Sub sltSelectionBorder_Change(Index As Integer)
    If SelectionsAllowed(False) And (g_CurrentTool = Selections.GetRelevantToolFromSelectShape()) Then
        pdImages(g_CurrentImage).MainSelection.SetSelectionProperty sp_BorderWidth, sltSelectionBorder(Index).Value
        ViewportEngine.Stage3_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    End If
End Sub

Private Sub sltSelectionFeathering_Change()
    If SelectionsAllowed(False) Then
        pdImages(g_CurrentImage).MainSelection.SetSelectionProperty sp_FeatheringRadius, sltSelectionFeathering.Value
        ViewportEngine.Stage3_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    End If
End Sub

Private Sub sltSelectionLineWidth_Change()
    If SelectionsAllowed(True) And (g_CurrentTool = Selections.GetRelevantToolFromSelectShape()) Then
        pdImages(g_CurrentImage).MainSelection.SetSelectionProperty sp_LineWidth, sltSelectionLineWidth.Value
        ViewportEngine.Stage3_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    End If
End Sub

'When certain selection settings are enabled or disabled, corresponding controls are shown or hidden.  To keep the
' panel concise and clean, we move other controls up or down depending on what controls are visible.
Public Sub UpdateSelectionPanelLayout()

    'Display the feathering slider as necessary
    sltSelectionFeathering.Visible = (cboSelSmoothing.ListIndex = es_FullyFeathered)
    
    'Display the border slider as necessary
    If (Selections.GetSelectionSubPanelFromCurrentTool < cboSelArea.Count - 1) And (Selections.GetSelectionSubPanelFromCurrentTool > 0) Then
        sltSelectionBorder(Selections.GetSelectionSubPanelFromCurrentTool).Visible = (cboSelArea(Selections.GetSelectionSubPanelFromCurrentTool).ListIndex = sa_Border)
    End If
    
End Sub

Private Sub sltSmoothStroke_Change()
    If SelectionsAllowed(False) And (g_CurrentTool = Selections.GetRelevantToolFromSelectShape()) Then
        pdImages(g_CurrentImage).MainSelection.SetSelectionProperty sp_SmoothStroke, sltSmoothStroke.Value
        ViewportEngine.Stage3_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    End If
End Sub

Private Sub sltWandTolerance_Change()
    If SelectionsAllowed(False) And (g_CurrentTool = Selections.GetRelevantToolFromSelectShape()) Then
        pdImages(g_CurrentImage).MainSelection.SetSelectionProperty sp_WandTolerance, sltWandTolerance.Value
        ViewportEngine.Stage3_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    End If
End Sub

'When the selection text boxes are updated, change the scrollbars to match
Private Sub tudSel_Change(Index As Integer)
    UpdateSelectionsValuesViaText
End Sub

'All text boxes wrap this function.  Note that text box changes are not relayed unless the current selection shape
' matches the current selection tool.
Private Sub UpdateSelectionsValuesViaText()
    If SelectionsAllowed(True) Then
        If (Not pdImages(g_CurrentImage).MainSelection.GetAutoRefreshSuspend) And (g_CurrentTool = Selections.GetRelevantToolFromSelectShape()) Then
            pdImages(g_CurrentImage).MainSelection.UpdateViaTextBox
            ViewportEngine.Stage3_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
        End If
    End If
End Sub

'Updating against the current theme accomplishes a number of things:
' 1) All user-drawn controls are redrawn according to the current g_Themer settings.
' 2) All tooltips and captions are translated according to the current language.
' 3) ApplyThemeAndTranslations is called, which redraws the form itself according to any theme and/or system settings.
'
'This function is called at least once, at Form_Load, but can be called again if the active language or theme changes.
Public Sub UpdateAgainstCurrentTheme()

    'Start by redrawing the form according to current theme and translation settings.  (This function also takes care of
    ' any common controls that may still exist in the program.)
    ApplyThemeAndTranslations Me
    
    'Tooltips must be manually re-assigned according to the current language.  This is a necessary evil, if the user switches
    ' between two non-English languages at run-time.
    cboSelRender.AssignTooltip "Click to change the way selections are rendered onto the image canvas.  This has no bearing on selection contents - only the way they appear while editing."
    cboSelSmoothing.AssignTooltip "This option controls how smoothly a selection blends with its surroundings."
        
    Dim i As Long
    For i = 0 To cboSelArea.Count - 1
        cboSelArea(i).AssignTooltip "These options control the area affected by a selection.  The selection can be modified on-canvas while any of these settings are active.  For more advanced selection adjustments, use the Select menu."
        sltSelectionBorder(i).AssignTooltip "This option adjusts the width of the selection border."
    Next i
    
    sltSelectionFeathering.AssignTooltip "This feathering slider allows for immediate feathering adjustments.  For performance reasons, it is limited to small radii.  For larger feathering radii, please use the Select -> Feathering menu."
    sltCornerRounding.AssignTooltip "This option adjusts the roundness of a rectangular selection's corners."
    sltSelectionLineWidth.AssignTooltip "This option adjusts the width of a line selection."
    
    sltPolygonCurvature.AssignTooltip "This option adjusts the curvature, if any, of a polygon selection's sides."
    sltSmoothStroke.AssignTooltip "This option increases the smoothness of a hand-drawn lasso selection."
    sltWandTolerance.AssignTooltip "Tolerance controls how similar two pixels must be before adding them to a magic wand selection."
    
    btsWandMerge.AssignTooltip "The magic wand can operate on the entire image, or just the active layer."
    btsWandArea.AssignTooltip "Normally, the magic wand will spread out from the target pixel, adding neighboring pixels to the selection as it goes.  You can alternatively set it to search the entire image, without regards for continuity."
    
    cboWandCompare.AssignTooltip "This option controls which criteria the magic wand uses to determine whether a pixel should be added to the current selection."

End Sub
