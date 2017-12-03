VERSION 5.00
Begin VB.Form dialog_OutlineSettings 
   Appearance      =   0  'Flat
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   "Outline settings"
   ClientHeight    =   8205
   ClientLeft      =   45
   ClientTop       =   375
   ClientWidth     =   12660
   BeginProperty Font 
      Name            =   "Tahoma"
      Size            =   8.25
      Charset         =   0
      Weight          =   400
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ScaleHeight     =   547
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   844
   ShowInTaskbar   =   0   'False
   StartUpPosition =   1  'CenterOwner
   Begin PhotoDemon.pdDropDown cboCorner 
      Height          =   390
      Left            =   6480
      TabIndex        =   6
      Top             =   5820
      Width           =   6015
      _ExtentX        =   10610
      _ExtentY        =   688
   End
   Begin PhotoDemon.pdColorSelector csOutline 
      Height          =   1215
      Left            =   120
      TabIndex        =   4
      Top             =   4440
      Width           =   6015
      _ExtentX        =   10610
      _ExtentY        =   2143
      Caption         =   "outline color and opacity"
   End
   Begin VB.PictureBox picPenPreview 
      Appearance      =   0  'Flat
      AutoRedraw      =   -1  'True
      BackColor       =   &H00FFFFFF&
      ForeColor       =   &H00000000&
      Height          =   2535
      Left            =   120
      ScaleHeight     =   167
      ScaleMode       =   3  'Pixel
      ScaleWidth      =   823
      TabIndex        =   2
      Top             =   480
      Width           =   12375
   End
   Begin PhotoDemon.pdCommandBar cmdBar 
      Align           =   2  'Align Bottom
      Height          =   750
      Left            =   0
      TabIndex        =   1
      Top             =   7455
      Width           =   12660
      _ExtentX        =   22331
      _ExtentY        =   1323
      AutoloadLastPreset=   -1  'True
      DontAutoUnloadParent=   -1  'True
      DontResetAutomatically=   -1  'True
   End
   Begin PhotoDemon.pdButtonStrip btsStyle 
      Height          =   1095
      Left            =   120
      TabIndex        =   0
      Top             =   3120
      Width           =   12375
      _ExtentX        =   21828
      _ExtentY        =   1931
      Caption         =   "outline style"
      FontSize        =   12
   End
   Begin PhotoDemon.pdLabel lblTitle 
      Height          =   315
      Index           =   0
      Left            =   120
      Top             =   120
      Width           =   9375
      _ExtentX        =   16536
      _ExtentY        =   556
      Caption         =   "preview"
      FontSize        =   12
   End
   Begin PhotoDemon.pdSlider sltOutlineOpacity 
      CausesValidation=   0   'False
      Height          =   405
      Left            =   120
      TabIndex        =   3
      Top             =   5760
      Width           =   6060
      _ExtentX        =   4868
      _ExtentY        =   873
      Max             =   100
      Value           =   100
      NotchPosition   =   2
      NotchValueCustom=   100
   End
   Begin PhotoDemon.pdSlider sltOutlineWidth 
      CausesValidation=   0   'False
      Height          =   705
      Left            =   120
      TabIndex        =   5
      Top             =   6360
      Width           =   6060
      _ExtentX        =   10689
      _ExtentY        =   1270
      Caption         =   "outline width"
      Min             =   1
      Max             =   100
      SigDigits       =   1
      Value           =   1
      NotchPosition   =   1
      NotchValueCustom=   100
      DefaultValue    =   1
   End
   Begin PhotoDemon.pdLabel lblTitle 
      Height          =   315
      Index           =   1
      Left            =   6480
      Top             =   5400
      Width           =   5655
      _ExtentX        =   9975
      _ExtentY        =   556
      Caption         =   "corner shape"
      FontSize        =   12
   End
   Begin PhotoDemon.pdLabel lblTitle 
      Height          =   315
      Index           =   2
      Left            =   6480
      Top             =   4440
      Width           =   5655
      _ExtentX        =   9975
      _ExtentY        =   556
      Caption         =   "line cap shape"
      FontSize        =   12
   End
   Begin PhotoDemon.pdDropDown cboLineCap 
      Height          =   390
      Left            =   6480
      TabIndex        =   7
      Top             =   4860
      Width           =   6015
      _ExtentX        =   10610
      _ExtentY        =   688
   End
   Begin PhotoDemon.pdSlider sltMiterLimit 
      CausesValidation=   0   'False
      Height          =   705
      Left            =   6480
      TabIndex        =   8
      Top             =   6360
      Width           =   6060
      _ExtentX        =   10689
      _ExtentY        =   1270
      Caption         =   "miter limit"
      Min             =   1
      Max             =   100
      SigDigits       =   1
      Value           =   10
      NotchPosition   =   2
      NotchValueCustom=   3
   End
End
Attribute VB_Name = "dialog_OutlineSettings"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'Pen Selection Dialog
'Copyright 2015-2017 by Tanner Helland
'Created: 30/June/15 (but assembled from many bits written earlier)
'Last updated: 30/June/15
'Last update: start migrating pen creation bits into this singular dialog
'
'Comprehensive pen selection dialog.  This dialog is currently based around the properties of GDI+ pens, but it could
' easily be expanded in the future due to its modular design.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'OK/Cancel result from the dialog
Private userAnswer As VbMsgBoxResult

'The original pen when the dialog was first loaded
Private m_OldPen As String

'Pen strings are generated with the help of an outline (GDI+ pen) class.  This class also renders a preview of the current pen.
Private m_PenPreview As pd2DPen

'If a user control spawned this dialog, it will pass itself as a reference.  We can then send pen updates back
' to the control, allowing for real-time updates on the screen despite a modal dialog being raised!
Private parentPenControl As pdPenSelector

'Pen previews are rendered using a pd2DPath as the sample
Private m_PreviewPath As pd2DPath

'Recently used pens are loaded to/saved from a custom XML file
Private m_XMLEngine As pdXML

'The file where we'll store recent pen data when the program is closed.  (At present, this file is located in PD's
' /Data/Presets/ folder.
Private m_XMLFilename As String

'Pen preview DIB
Private m_PreviewDIB As pdDIB

'To prevent recursive setting changes, this value can be set to TRUE to prevent live preview updates
Private m_SuspendRedraws As Boolean

'The user's answer is returned via this property
Public Property Get DialogResult() As VbMsgBoxResult
    DialogResult = userAnswer
End Property

'The newly selected pen (if any) is returned via this property
Public Property Get NewPen() As String
    NewPen = m_PenPreview.GetPenPropertiesAsXML
End Property

'The ShowDialog routine presents the user with this form.
Public Sub ShowDialog(ByVal initialPen As String, Optional ByRef callingControl As pdPenSelector = Nothing)
    
    'Store a reference to the calling control (if any)
    Set parentPenControl = callingControl

    'Provide a default answer of "cancel" (in the event that the user clicks the "x" button in the top-right)
    userAnswer = vbCancel
    
    'Cache the initial pen parameters so we can access it elsewhere
    m_OldPen = initialPen
    Set m_PenPreview = New pd2DPen
    m_PenPreview.SetPenPropertiesFromXML initialPen
    m_PenPreview.CreatePen
    
    If Len(initialPen) = 0 Then initialPen = m_PenPreview.GetPenPropertiesAsXML
    
    'Sync all controls to the initial pen parameters
    SyncControlsToOutlineObject
    UpdatePreview
    
    'Make sure that the proper cursor is set
    Screen.MousePointer = 0
    
    'Apply extra images and tooltips to certain controls
    
    'Apply visual themes
    ApplyThemeAndTranslations Me
    
    'Initialize an XML engine, which we will use to read/write recent pen data to file
    Set m_XMLEngine = New pdXML
    
    'The XML file will be stored in the Preset path (/Data/Presets)
    m_XMLFilename = g_UserPreferences.GetPresetPath & "Pen_Selector.xml"
    
    'TODO: if an XML file exists, load its contents now
    'loadRecentPenList
        
    'Display the dialog
    ShowPDDialog vbModal, Me, True

End Sub

Private Sub btsStyle_Click(ByVal buttonIndex As Long)
    
    'TODO: show/hide a dash settings panel when dash mode is active
    
    UpdatePreview
    
End Sub

Private Sub cboCorner_Click()
    UpdatePreview
End Sub

Private Sub cboLineCap_Click()
    UpdatePreview
End Sub

'CANCEL BUTTON
Private Sub cmdBar_CancelClick()
    userAnswer = vbCancel
    Me.Hide
End Sub

'OK BUTTON
Private Sub cmdBar_OKClick()

    'Store the newPen value (which the dialog handler will use to return the selected brush to the caller)
    UpdateOutlineObject
    
    'TODO: save the current list of recently used pens
    'saveRecentPenList
    
    userAnswer = vbOK
    Me.Visible = False

End Sub

Private Sub cmdBar_RequestPreviewUpdate()
    UpdatePreview
End Sub

Private Sub cmdBar_ResetClick()
    
    'Reset our generic outline object
    Set m_PenPreview = New pd2DPen
    m_PenPreview.ResetAllProperties
    m_PenPreview.CreatePen
    
    'Synchronize all controls to the updated settings
    SyncControlsToOutlineObject
    UpdatePreview
    
End Sub

Private Sub csOutline_ColorChanged()
    UpdatePreview
End Sub

Private Sub Form_Load()
    
    m_SuspendRedraws = True
    
    'Populate the main style button strip
    btsStyle.AddItem "solid"
    btsStyle.AddItem "dashes"
    btsStyle.AddItem "dots"
    btsStyle.AddItem "dash + dot"
    btsStyle.AddItem "dash + dot + dot"
    btsStyle.ListIndex = 0
    
    'Line cap shapes
    cboLineCap.Clear
    cboLineCap.AddItem "flat"
    cboLineCap.AddItem "square"
    cboLineCap.AddItem "round"
    cboLineCap.AddItem "triangle"
    cboLineCap.ListIndex = 0
    
    'Corner shapes
    cboCorner.Clear
    cboCorner.AddItem "miter"
    cboCorner.AddItem "bevel"
    cboCorner.AddItem "round"
    cboCorner.ListIndex = 0
    
    If MainModule.IsProgramRunning() Then
        If m_PenPreview Is Nothing Then Set m_PenPreview = New pd2DPen
        If m_PreviewPath Is Nothing Then Set m_PreviewPath = New pd2DPath
        Set m_PreviewDIB = New pdDIB
    End If
    
    m_SuspendRedraws = False
    
End Sub

Private Sub Form_Unload(Cancel As Integer)
    ReleaseFormTheming Me
End Sub

'Update our internal pen class against any/all changed settings.
Private Sub UpdateOutlineObject()

    With m_PenPreview
        .SetPenProperty P2_PenStyle, btsStyle.ListIndex
        .SetPenProperty P2_PenColor, csOutline.Color
        .SetPenProperty P2_PenOpacity, sltOutlineOpacity.Value
        .SetPenProperty P2_PenWidth, sltOutlineWidth.Value
        .SetPenProperty P2_PenLineCap, cboLineCap.ListIndex
        .SetPenProperty P2_PenDashCap, cboLineCap.ListIndex       'For now, dash cap mirrors line cap
        .SetPenProperty P2_PenLineJoin, cboCorner.ListIndex
        .SetPenProperty P2_PenMiterLimit, sltMiterLimit.Value
        .CreatePen
    End With
    
End Sub

Private Sub UpdatePreview()
    
    If (Not m_SuspendRedraws) Then
    
        'Make sure our outline object is up-to-date
        UpdateOutlineObject
        
        'Prep the preview DIB
        If m_PreviewDIB Is Nothing Then Set m_PreviewDIB = New pdDIB
        
        If (m_PreviewDIB.GetDIBWidth <> Me.picPenPreview.ScaleWidth) Or (m_PreviewDIB.GetDIBHeight <> Me.picPenPreview.ScaleHeight) Then
            m_PreviewDIB.CreateBlank Me.picPenPreview.ScaleWidth, Me.picPenPreview.ScaleHeight, 24, 0
        Else
            m_PreviewDIB.ResetDIB
        End If
        
        'Prep the preview path.  Note that we manually pad it to make the preview look a little prettier.
        Dim tmpRect As RECTF, hPadding As Single, vPadding As Single
        
        hPadding = m_PenPreview.GetPenProperty(P2_PenWidth) * 2
        If hPadding > FixDPIFloat(12) Then hPadding = FixDPIFloat(12)
        vPadding = hPadding
        
        With tmpRect
            .Left = 0
            .Top = 0
            .Width = m_PreviewDIB.GetDIBWidth
            .Height = m_PreviewDIB.GetDIBHeight
        End With
        
        m_PreviewPath.ResetPath
        m_PreviewPath.CreateSamplePathForRect tmpRect, hPadding, vPadding
        
        'Paint the preview path
        Dim cPainter As pd2DPainter, cSurface As pd2DSurface
        Drawing2D.QuickCreatePainter cPainter
        Drawing2D.QuickCreateSurfaceFromDC cSurface, m_PreviewDIB.GetDIBDC, False
        cPainter.FillRectangleF cSurface, g_CheckerboardBrush, 0, 0, m_PreviewDIB.GetDIBWidth, m_PreviewDIB.GetDIBHeight
        
        cSurface.SetSurfaceAntialiasing P2_AA_HighQuality
        cPainter.DrawPath cSurface, m_PenPreview, m_PreviewPath
        Set cSurface = Nothing
        
        'Copy the preview image to the screen
        m_PreviewDIB.RenderToPictureBox Me.picPenPreview
        
        'Notify our parent of the update
        If Not (parentPenControl Is Nothing) Then parentPenControl.NotifyOfLivePenChange m_PenPreview.GetPenPropertiesAsXML
        
    End If
    
End Sub

Private Sub SyncControlsToOutlineObject()
        
    m_SuspendRedraws = True
        
    With m_PenPreview
        
        btsStyle.ListIndex = .GetPenProperty(P2_PenStyle)
        
        csOutline.Color = .GetPenProperty(P2_PenColor)
        sltOutlineOpacity.Value = .GetPenProperty(P2_PenOpacity)
        sltOutlineWidth.Value = .GetPenProperty(P2_PenWidth)
        
        cboLineCap.ListIndex = .GetPenProperty(P2_PenLineCap)
        cboCorner.ListIndex = .GetPenProperty(P2_PenLineJoin)
        sltMiterLimit.Value = .GetPenProperty(P2_PenMiterLimit)
    
    End With
        
    m_SuspendRedraws = False
    
End Sub

Private Sub sltMiterLimit_Change()
    UpdatePreview
End Sub

Private Sub sltOutlineOpacity_Change()
    UpdatePreview
End Sub

Private Sub sltOutlineWidth_Change()
    UpdatePreview
End Sub
