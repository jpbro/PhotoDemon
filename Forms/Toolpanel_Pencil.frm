VERSION 5.00
Begin VB.Form toolpanel_Pencil 
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
   Begin PhotoDemon.pdCheckBox chkAntialiasing 
      Height          =   375
      Left            =   6600
      TabIndex        =   4
      Top             =   360
      Width           =   3495
      _ExtentX        =   6165
      _ExtentY        =   661
      Caption         =   "antialiased"
   End
   Begin PhotoDemon.pdDropDown cboBrushSetting 
      Height          =   735
      Index           =   0
      Left            =   4080
      TabIndex        =   2
      Top             =   0
      Width           =   2295
      _ExtentX        =   4048
      _ExtentY        =   1296
      Caption         =   "blend / alpha mode"
      FontSizeCaption =   10
   End
   Begin PhotoDemon.pdSlider sltBrushSetting 
      CausesValidation=   0   'False
      Height          =   690
      Index           =   0
      Left            =   120
      TabIndex        =   0
      Top             =   0
      Width           =   3750
      _ExtentX        =   6615
      _ExtentY        =   1217
      Caption         =   "size"
      FontSizeCaption =   10
      Min             =   1
      Max             =   2000
      SigDigits       =   1
      ScaleStyle      =   1
      ScaleExponent   =   3
      Value           =   1
      NotchPosition   =   1
      DefaultValue    =   1
   End
   Begin PhotoDemon.pdSlider sltBrushSetting 
      CausesValidation=   0   'False
      Height          =   690
      Index           =   1
      Left            =   120
      TabIndex        =   1
      Top             =   660
      Width           =   3750
      _ExtentX        =   6615
      _ExtentY        =   1217
      Caption         =   "opacity"
      FontSizeCaption =   10
      Max             =   100
      SigDigits       =   1
      Value           =   100
      DefaultValue    =   100
   End
   Begin PhotoDemon.pdDropDown cboBrushSetting 
      Height          =   375
      Index           =   1
      Left            =   4185
      TabIndex        =   3
      Top             =   900
      Width           =   2190
      _ExtentX        =   3863
      _ExtentY        =   661
      FontSizeCaption =   10
   End
End
Attribute VB_Name = "toolpanel_Pencil"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon Basic Brush ("Pencil") Tool Panel
'Copyright 2016-2017 by Tanner Helland
'Created: 31/Oct/16
'Last updated: 21/December/16
'Last update: kill the "preview quality" UI, which was for debug purposes only
'
'This form includes all user-editable settings for the "pencil" canvas tool.  Unlike other programs,
' PD's pencil tool supports a number of features (like antialiasing) while maintaining the high
' performance everyone expects from a basic brush.
'
'Extremely large radii are suppored, as are all blend modes (including "erase").
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'The value of all controls on this form are saved and loaded to file by this class
Private WithEvents lastUsedSettings As pdLastUsedSettings
Attribute lastUsedSettings.VB_VarHelpID = -1

Private Sub cboBrushSetting_Click(Index As Integer)

    Select Case Index
    
        'Blend mode
        Case 0
            Paintbrush.SetBrushBlendMode cboBrushSetting(Index).ListIndex
        
        'Alpha mode
        Case 1
            Paintbrush.SetBrushAlphaMode cboBrushSetting(Index).ListIndex
            
    End Select
    
End Sub

Private Sub chkAntialiasing_Click()
    If (chkAntialiasing.Value = vbChecked) Then
        Paintbrush.SetBrushAntialiasing P2_AA_HighQuality
    Else
        Paintbrush.SetBrushAntialiasing P2_AA_None
    End If
End Sub

Private Sub Form_Load()
    
    'Populate the alpha and blend mode boxes
    Interface.PopulateBlendModeDropDown cboBrushSetting(0), BL_NORMAL
    Interface.PopulateAlphaModeDropDown cboBrushSetting(1), LA_NORMAL
        
    'Load any last-used settings for this form
    Set lastUsedSettings = New pdLastUsedSettings
    lastUsedSettings.SetParentForm Me
    lastUsedSettings.LoadAllControlValues
    
    'Update everything against the current theme.  This will also set tooltips for various controls.
    UpdateAgainstCurrentTheme
    
End Sub

Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)

    'Save all last-used settings to file
    If Not (lastUsedSettings Is Nothing) Then
        lastUsedSettings.SaveAllControlValues
        lastUsedSettings.SetParentForm Nothing
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

End Sub

Private Sub sltBrushSetting_Change(Index As Integer)
    
    Select Case Index
    
        'Radius
        Case 0
            Paintbrush.SetBrushSize sltBrushSetting(Index).Value
        
        'Opacity
        Case 1
            Paintbrush.SetBrushOpacity sltBrushSetting(Index).Value
    
    End Select
    
End Sub

'If you want to set all paintbrush settings at once, use this function
Public Sub SyncAllPaintbrushSettingsToUI()
    Paintbrush.SetBrushSize sltBrushSetting(0).Value
    Paintbrush.SetBrushOpacity sltBrushSetting(1).Value
    Paintbrush.SetBrushSourceColor layerpanel_Colors.GetCurrentColor()
    Paintbrush.SetBrushBlendMode cboBrushSetting(0).ListIndex
    Paintbrush.SetBrushAlphaMode cboBrushSetting(1).ListIndex
    If CBool(chkAntialiasing.Value) Then Paintbrush.SetBrushAntialiasing P2_AA_HighQuality Else Paintbrush.SetBrushAntialiasing P2_AA_None
End Sub

'If you want to synchronize all UI elements to match current paintbrush settings, use this function
Public Sub SyncUIToAllPaintbrushSettings()
    sltBrushSetting(0).Value = Paintbrush.GetBrushSize
    sltBrushSetting(1).Value = Paintbrush.GetBrushOpacity
    cboBrushSetting(0).ListIndex = Paintbrush.GetBrushBlendMode()
    cboBrushSetting(1).ListIndex = Paintbrush.GetBrushAlphaMode()
    If (Paintbrush.GetBrushAntialiasing = P2_AA_HighQuality) Then chkAntialiasing.Value = vbChecked Else chkAntialiasing.Value = vbUnchecked
End Sub
