VERSION 5.00
Begin VB.Form layerpanel_Colors 
   Appearance      =   0  'Flat
   BackColor       =   &H80000005&
   BorderStyle     =   0  'None
   ClientHeight    =   3015
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   4560
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
   LinkTopic       =   "Form1"
   ScaleHeight     =   201
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   304
   ShowInTaskbar   =   0   'False
   Visible         =   0   'False
   Begin PhotoDemon.pdColorVariants clrVariants 
      Height          =   975
      Left            =   120
      TabIndex        =   1
      Top             =   120
      Width           =   1335
      _ExtentX        =   2355
      _ExtentY        =   1720
   End
   Begin PhotoDemon.pdColorWheel clrWheel 
      Height          =   975
      Left            =   1680
      TabIndex        =   0
      Top             =   120
      Width           =   1215
      _ExtentX        =   2143
      _ExtentY        =   1720
   End
End
Attribute VB_Name = "layerpanel_Colors"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon Color Selector Tool Panel
'Copyright 2015-2017 by Tanner Helland
'Created: 15/October/15
'Last updated: 20/October/15
'Last update: actually implement color selection controls!
'
'As part of the 7.0 release, PD's right-side panel gained a lot of new functionality.  To simplify the code for
' the new panel, each chunk of related settings (e.g. layer, nav, color selector) was moved to its own subpanel.
'
'This form is the subpanel for the color selector panel.  It is currently under construction.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'The value of all controls on this form are saved and loaded to file by this class
Private WithEvents lastUsedSettings As pdLastUsedSettings
Attribute lastUsedSettings.VB_VarHelpID = -1

'To avoid nested resize calls, trackers are used
Private m_ResizeInProgress As Boolean

Private Sub clrVariants_ColorChanged(ByVal newColor As Long, ByVal srcIsInternal As Boolean)
    
    'If the clrVariant control is where the color was actually changed (and it's not just syncing itself to some
    ' external color change), relay the new color to the neighboring color wheel.
    If srcIsInternal Then clrWheel.Color = newColor
    
    'Whenever this primary color changes, we broadcast the change throughout PD, so other color selector controls
    ' know to redraw themselves accordingly.
    UserControls.PostPDMessage WM_PD_PRIMARY_COLOR_CHANGE, newColor
    
    'We also check to see if a paint-related tool is active.  If it is, assign the new color immediately.
    Select Case g_CurrentTool
    
        Case PAINT_BASICBRUSH, PAINT_SOFTBRUSH
            Paintbrush.SetBrushSourceColor newColor
            
        Case PAINT_FILL
            FillTool.SetFillBrushColor newColor
    
    End Select
    
End Sub

Private Sub clrWheel_ColorChanged(ByVal newColor As Long, ByVal srcIsInternal As Boolean)
    If srcIsInternal Then clrVariants.Color = newColor
End Sub

Private Sub Form_Load()
    
    m_ResizeInProgress = True
    
    'Load any last-used settings for this form
    Set lastUsedSettings = New pdLastUsedSettings
    lastUsedSettings.SetParentForm Me
    lastUsedSettings.LoadAllControlValues
    
    'Update everything against the current theme.  This will also set tooltips for various controls,
    ' and reflow the interface to match.
    UpdateAgainstCurrentTheme
    
    m_ResizeInProgress = False
    
End Sub

'Whenever this panel is resized, we must reflow all objects to fit the available space.
Private Sub ReflowInterface()

    Dim curFormWidth As Long, curFormHeight As Long
    curFormWidth = Me.ScaleWidth
    curFormHeight = Me.ScaleHeight
    
    'Failsafe to prevent IDE errors
    If (curFormWidth > 10) Then
        
        'Right-align the color wheel
        clrWheel.SetPositionAndSize curFormWidth - (curFormHeight + FixDPI(10)), 0, curFormHeight, curFormHeight
        
        'Fit the variant selector into the remaining area
        clrVariants.SetPositionAndSize 0, 0, clrWheel.GetLeft - FixDPI(10), curFormHeight
        
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
    
    'Reflow the interface, to account for any language changes.
    ReflowInterface
    
End Sub

Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    
    'Save all last-used settings to file
    If Not (lastUsedSettings Is Nothing) Then
        lastUsedSettings.SaveAllControlValues
        lastUsedSettings.SetParentForm Nothing
    End If
    
End Sub

Private Sub Form_Resize()
    If (Not m_ResizeInProgress) Then
        m_ResizeInProgress = True
        ReflowInterface
        m_ResizeInProgress = False
    End If
End Sub

Public Function GetCurrentColor()
    GetCurrentColor = clrVariants.Color
End Function

Public Sub SetCurrentColor(ByVal newR As Long, ByVal newG As Long, ByVal newB As Long)
    clrVariants.Color = RGB(newR, newG, newB)
    clrWheel.Color = RGB(newR, newG, newB)
End Sub
