VERSION 5.00
Begin VB.Form dialog_AutosaveWarning 
   Appearance      =   0  'Flat
   AutoRedraw      =   -1  'True
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   " Autosave data detected"
   ClientHeight    =   6975
   ClientLeft      =   45
   ClientTop       =   315
   ClientWidth     =   9165
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
   ScaleHeight     =   465
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   611
   ShowInTaskbar   =   0   'False
   Begin VB.PictureBox picWarning 
      Appearance      =   0  'Flat
      AutoRedraw      =   -1  'True
      BackColor       =   &H80000005&
      BorderStyle     =   0  'None
      DrawStyle       =   5  'Transparent
      ForeColor       =   &H80000008&
      Height          =   615
      Left            =   240
      ScaleHeight     =   41
      ScaleMode       =   3  'Pixel
      ScaleWidth      =   49
      TabIndex        =   4
      Top             =   240
      Width           =   735
   End
   Begin PhotoDemon.pdListBox lstAutosaves 
      Height          =   3450
      Left            =   240
      TabIndex        =   3
      Top             =   2400
      Width           =   3615
      _ExtentX        =   6376
      _ExtentY        =   6085
   End
   Begin PhotoDemon.pdButton cmdOK 
      Height          =   735
      Left            =   1800
      TabIndex        =   0
      Top             =   6060
      Width           =   3540
      _ExtentX        =   5821
      _ExtentY        =   1296
      Caption         =   "Restore selected autosaves"
   End
   Begin VB.PictureBox picPreview 
      Appearance      =   0  'Flat
      AutoRedraw      =   -1  'True
      BackColor       =   &H00808080&
      BeginProperty Font 
         Name            =   "Tahoma"
         Size            =   9.75
         Charset         =   0
         Weight          =   400
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      ForeColor       =   &H00FFFFFF&
      Height          =   3405
      Left            =   3960
      ScaleHeight     =   225
      ScaleMode       =   3  'Pixel
      ScaleWidth      =   330
      TabIndex        =   1
      Top             =   2430
      Width           =   4980
   End
   Begin PhotoDemon.pdButton cmdCancel 
      Height          =   735
      Left            =   5400
      TabIndex        =   2
      Top             =   6060
      Width           =   3540
      _ExtentX        =   5821
      _ExtentY        =   1296
      Caption         =   "Discard all autosaves"
   End
   Begin PhotoDemon.pdLabel lblTitle 
      Height          =   285
      Index           =   0
      Left            =   240
      Top             =   2040
      Width           =   8730
      _ExtentX        =   15399
      _ExtentY        =   503
      Caption         =   "autosave entries found:"
      ForeColor       =   4210752
   End
   Begin PhotoDemon.pdLabel lblWarning 
      Height          =   645
      Index           =   1
      Left            =   240
      Top             =   960
      Width           =   8745
      _ExtentX        =   0
      _ExtentY        =   0
      Caption         =   "Warning"
      ForeColor       =   4210752
      Layout          =   1
   End
   Begin PhotoDemon.pdLabel lblWarning 
      Height          =   525
      Index           =   0
      Left            =   1005
      Top             =   330
      Width           =   8055
      _ExtentX        =   0
      _ExtentY        =   0
      Alignment       =   2
      Caption         =   "Autosave data found.  Would you like to restore it?"
      FontSize        =   12
      ForeColor       =   2105376
      Layout          =   1
   End
   Begin VB.Line Line1 
      BorderColor     =   &H8000000D&
      X1              =   16
      X2              =   595
      Y1              =   120
      Y2              =   120
   End
End
Attribute VB_Name = "dialog_AutosaveWarning"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'Autosave (unsafe shutdown) Prompt/Dialog
'Copyright 2014-2017 by Tanner Helland
'Created: 19/January/14
'Last updated: 10/January/17
'Last update: implement better theming support
'
'PhotoDemon now provides AutoSave functionality.  If the program terminates unexpectedly, this dialog will be raised,
' which gives the user an option to restore any in-progress image edits.
'
'Images that had been loaded by PhotoDemon but never modified will not be shown.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'The user input from the dialog
Private userAnswer As VbMsgBoxResult

'Collection of Autosave XML entries found
Private m_numOfXMLFound As Long
Private m_XmlEntries() As AutosaveXML

'When this dialog finally closes, the calling function can use this sub to retrieve the entries the user wants saved.
Friend Sub FillArrayWithSaveResults(ByRef dstArray() As AutosaveXML)
    
    ReDim dstArray(0 To m_numOfXMLFound - 1) As AutosaveXML
    
    Dim i As Long
    For i = 0 To m_numOfXMLFound - 1
        dstArray(i) = m_XmlEntries(i)
    Next i
    
End Sub

Public Property Get DialogResult() As VbMsgBoxResult
    DialogResult = userAnswer
End Property

'The ShowDialog routine presents the user with the form.  FormID MUST BE SET in advance of calling this.
Public Sub ShowDialog()
    
    'Draw a warning icon
    Dim warningIconSize As Long
    warningIconSize = FixDPI(32)
    Dim warningDIB As pdDIB
    If IconsAndCursors.LoadResourceToDIB("generic_warning", warningDIB, warningIconSize, warningIconSize, 0) Then
        picWarning.BackColor = g_Themer.GetGenericUIColor(UI_Background)
        warningDIB.AlphaBlendToDC picWarning.hDC, , (picWarning.ScaleWidth - warningDIB.GetDIBWidth) \ 2, (picWarning.ScaleHeight - warningDIB.GetDIBHeight) \ 2
        picWarning.Picture = picWarning.Image
    Else
        picWarning.Visible = False
    End If
    
    'Display a brief explanation of the dialog at the top of the window
    lblWarning(1).Caption = g_Language.TranslateMessage("A previous PhotoDemon session terminated unexpectedly.  Would you like to automatically recover the following autosaved images?")
    
    'Provide a default answer of "do not restore" (in the event that the user clicks the "x" button in the top-right)
    userAnswer = vbNo
    
    'Load command button images
    Dim buttonIconSize As Long
    buttonIconSize = FixDPI(32)
    cmdOK.AssignImage "generic_ok", , buttonIconSize, buttonIconSize
    cmdCancel.AssignImage "generic_cancel", , buttonIconSize, buttonIconSize
    
    'Apply any custom styles to the form
    ApplyThemeAndTranslations Me

    'Populate the AutoSave entry list box
    DisplayAutosaveEntries

    'Display the form
    ShowPDDialog vbModal, Me, True

End Sub

'If the user cancels, warn them that these image will be lost foreeeever.
Private Sub cmdCancel_Click()

    Dim msgReturn As VbMsgBoxResult
    msgReturn = PDMsgBox("If you exit now, this autosave data will be lost forever.  Are you sure you want to exit?", vbExclamation Or vbYesNo, "Warning: autosave data will be deleted")
    
    If (msgReturn = vbYes) Then
        userAnswer = vbNo
        Me.Hide
    End If

End Sub

'OK button
Private Sub CmdOK_Click()
    userAnswer = vbYes
    Me.Hide
End Sub

Private Sub Form_Unload(Cancel As Integer)
    ReleaseFormTheming Me
End Sub

'Update the active image preview in the top-right
Private Sub UpdatePreview(ByVal srcImagePath As String)
    
    'Display a preview of the selected image
    Dim tmpDIB As pdDIB
    Set tmpDIB = New pdDIB
    If tmpDIB.CreateFromFile(srcImagePath) Then
        tmpDIB.RenderToPictureBox picPreview
    Else
        picPreview.Picture = LoadPicture("")
        Dim strToPrint As String
        strToPrint = g_Language.TranslateMessage("Preview not available")
        picPreview.CurrentX = (picPreview.ScaleWidth - picPreview.textWidth(strToPrint)) \ 2
        picPreview.CurrentY = (picPreview.ScaleHeight - picPreview.textHeight(strToPrint)) \ 2
        picPreview.Print strToPrint
    End If
    
End Sub

'Fill the AutoSave entries list with any images found from the Autosave engine
Private Function DisplayAutosaveEntries() As Boolean

    'Because we've arrived at this point, we know that the Autosave engine has found at least *some* usable image data.
    ' Our goal now is to present that image data to the user, so they can select which images (if any) they want us
    ' to restore.
    
    'The Autosaves module will already contain a list of all Undo XML files found by the Autosave engine.
    ' It has stored this data in its private m_XmlEntries() array.  We can request a copy of this array as follows:
    Autosaves.GetXMLAutosaveEntries m_XmlEntries(), m_numOfXMLFound
    
    'All XML entries will now have been matched up with their latest Undo entry.  Fill the listbox with their data,
    ' ignoring any entries that do not have binary image data attached.
    lstAutosaves.SetAutomaticRedraws False
    lstAutosaves.Clear
    
    Dim i As Long
    For i = 0 To m_numOfXMLFound - 1
        lstAutosaves.AddItem m_XmlEntries(i).friendlyName
    Next i
    
    'Select the entry at the top of the list by default
    lstAutosaves.ListIndex = 0
    lstAutosaves.SetAutomaticRedraws True, True
    
End Function

Private Sub lstAutosaves_Click()
    
    'PD always saves a thumbnail of the latest image state to the same Undo path as the XML file, but with
    ' the "pdasi" extension (which represents "PD autosave image").
    Dim previewPath As String
    previewPath = m_XmlEntries(lstAutosaves.ListIndex).xmlPath & ".pdasi"
    UpdatePreview previewPath
    
End Sub
