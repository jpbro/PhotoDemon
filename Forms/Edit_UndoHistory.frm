VERSION 5.00
Begin VB.Form FormUndoHistory 
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   " Undo history"
   ClientHeight    =   6420
   ClientLeft      =   45
   ClientTop       =   285
   ClientWidth     =   9615
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
   ScaleHeight     =   428
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   641
   ShowInTaskbar   =   0   'False
   Begin PhotoDemon.pdLabel lblTitle 
      Height          =   255
      Left            =   480
      Top             =   5280
      Width           =   8895
      _ExtentX        =   15690
      _ExtentY        =   450
      Caption         =   "* current image state"
      FontItalic      =   -1  'True
   End
   Begin PhotoDemon.pdListBoxOD lstUndo 
      Height          =   5055
      Left            =   240
      TabIndex        =   1
      Top             =   120
      Width           =   9135
      _ExtentX        =   20558
      _ExtentY        =   8916
      Caption         =   "available image states"
   End
   Begin PhotoDemon.pdCommandBarMini cmdBar 
      Align           =   2  'Align Bottom
      Height          =   735
      Left            =   0
      TabIndex        =   0
      Top             =   5685
      Width           =   9615
      _ExtentX        =   16960
      _ExtentY        =   1296
      DontAutoUnloadParent=   -1  'True
   End
End
Attribute VB_Name = "FormUndoHistory"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'Undo History dialog
'Copyright 2014-2017 by Tanner Helland
'Created: 14/July/14
'Last updated: 22/May/16
'Last update: overhaul UI to use new owner-drawn pdListBox
'
'This is a first draft of a functional Undo History browser for PD.  Most applications provide this as a floating
' toolbar, but because that would require some complicated UI work (including integration into PD's window manager),
' I'm postponing such an implementation until after we've gotten the browser working first.
'
'All previous image states, including selections, are available for restoration.
'
'Obviously, this dialog interacts heavily with the pdUndo class, as only the undo manager has access to the full
' Undo/Redo stack, including detailed information like process IDs, Undo file types, etc.
'
'When the user selects a point for restoration, the Undo/Redo manager handles the actual work of restoring the image
' to that point.  This dialog simply presents the list to the user, and returns a clicked index position to pdUndo.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'This array contains the contents of the current Undo stack, as copied from the pdUndo class
Private m_undoEntries() As PD_UndoEntry

'Total number of Undo entries, and index of the current Undo entry (e.g. the current image state in the undo/redo chain).
Private m_numOfUndos As Long, m_curUndoIndex As Long

'Height of each Undo content block
Private Const BLOCKHEIGHT As Long = 58

'Two font objects; one for names and one for descriptions.  (Two are needed because they have different sizes and colors,
' and it is faster to cache these values rather than constantly recreating them on a single pdFont object.)
Private m_TitleFont As pdFont, m_DescriptionFont As pdFont

'The size at which we render the thumbnail images
Private Const UNDO_THUMB_SMALL As Long = 48

Private Function GetStringForUndoType(ByVal typeOfUndo As PD_UndoType, Optional ByVal layerID As Long = 0) As String

    Dim newText As String
    
    Select Case typeOfUndo
    
        Case UNDO_EVERYTHING
            newText = vbNullString
            
        Case UNDO_IMAGE, UNDO_IMAGE_VECTORSAFE, UNDO_IMAGEHEADER
            newText = vbNullString
            
        Case UNDO_LAYER, UNDO_LAYER_VECTORSAFE, UNDO_LAYERHEADER
            If Not (pdImages(g_CurrentImage).GetLayerByID(layerID) Is Nothing) Then
                newText = g_Language.TranslateMessage("layer: %1", pdImages(g_CurrentImage).GetLayerByID(layerID).GetLayerName())
            Else
                newText = vbNullString
            End If
        
        Case UNDO_SELECTION
            newText = g_Language.TranslateMessage("selection shape shown")
        
    End Select
    
    GetStringForUndoType = newText

End Function

Private Sub cmdBar_OKClick()
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.AddParam "UndoHistoryPoint", lstUndo.ListIndex + 1
    Process "Undo history", , cParams.GetParamString(), UNDO_NOTHING
End Sub

Private Sub Form_Load()
    
    'Initialize a custom font object for undo action names
    Set m_TitleFont = New pdFont
    m_TitleFont.SetFontBold True
    m_TitleFont.SetFontSize 12
    m_TitleFont.CreateFontObject
    m_TitleFont.SetTextAlignment vbLeftJustify
    
    '...and a second custom font object for undo descriptions
    Set m_DescriptionFont = New pdFont
    m_DescriptionFont.SetFontBold False
    m_DescriptionFont.SetFontSize 10
    m_DescriptionFont.CreateFontObject
    m_DescriptionFont.SetTextAlignment vbLeftJustify
    
    'Retrieve a copy of all Undo data from the current image's undo manager
    pdImages(g_CurrentImage).UndoManager.CopyUndoStack m_numOfUndos, m_curUndoIndex, m_undoEntries
    
    'Populate the owner-drawn listbox with the retrieved Undo data (including thumbnails)
    lstUndo.ListItemHeight = FixDPI(BLOCKHEIGHT)
    lstUndo.SetAutomaticRedraws False
    Dim i As Long
    For i = 0 To m_numOfUndos - 1
        lstUndo.AddItem , i
    Next i
    lstUndo.SetAutomaticRedraws True, True
    lstUndo.ListIndex = m_curUndoIndex - 1
    
    'Apply translations and visual themes
    ApplyThemeAndTranslations Me
    
End Sub

Private Sub Form_Unload(Cancel As Integer)
    ReleaseFormTheming Me
End Sub

Private Sub lstUndo_DrawListEntry(ByVal bufferDC As Long, ByVal itemIndex As Long, itemTextEn As String, ByVal itemIsSelected As Boolean, ByVal itemIsHovered As Boolean, ByVal ptrToRectF As Long)
    
    'Retrieve the boundary region for this list entry
    Dim tmpRectF As RECTF
    CopyMemory ByVal VarPtr(tmpRectF), ByVal ptrToRectF, 16&
    
    Dim offsetY As Single, offsetX As Single
    offsetX = tmpRectF.Left
    offsetY = tmpRectF.Top + FixDPI(2)
        
    Dim linePadding As Long
    linePadding = FixDPI(2)
    
    Dim mHeight As Single
        
    'If this filter has been selected, draw the background with the system's current selection color
    If itemIsSelected Then
        m_TitleFont.SetFontColor g_Themer.GetGenericUIColor(UI_TextClickableSelected)
        m_DescriptionFont.SetFontColor g_Themer.GetGenericUIColor(UI_TextClickableSelected)
    Else
        m_TitleFont.SetFontColor g_Themer.GetGenericUIColor(UI_TextClickableUnselected, , , itemIsHovered)
        m_DescriptionFont.SetFontColor g_Themer.GetGenericUIColor(UI_TextClickableUnselected, , , itemIsHovered)
    End If
    
    'Prepare a title string (with an asterisk added to the "current" image state title)
    Dim drawString As String
    drawString = ""
    If (itemIndex + 1) = m_curUndoIndex Then drawString = "* "
    drawString = drawString & CStr(itemIndex + 1) & " - " & g_Language.TranslateMessage(m_undoEntries(itemIndex).processID)
    
    'Render the thumbnail for this entry
    Dim thumbWidth As Long
    thumbWidth = offsetX + FixDPI(4) + FixDPI(UNDO_THUMB_SMALL)
    GDI_Plus.GDIPlus_StretchBlt Nothing, offsetX + FixDPI(4), offsetY + (FixDPI(BLOCKHEIGHT) - FixDPI(UNDO_THUMB_SMALL)) \ 2, FixDPI(UNDO_THUMB_SMALL), FixDPI(UNDO_THUMB_SMALL), m_undoEntries(itemIndex).thumbnailLarge, 0, 0, m_undoEntries(itemIndex).thumbnailLarge.GetDIBWidth, m_undoEntries(itemIndex).thumbnailLarge.GetDIBHeight, , , bufferDC
    
    'Render the title text
    If (Len(drawString) <> 0) Then
        m_TitleFont.AttachToDC bufferDC
        m_TitleFont.FastRenderText thumbWidth + FixDPI(16) + offsetX, offsetY + FixDPI(4), drawString
        m_TitleFont.ReleaseFromDC
    End If
            
    'Below that, add the description text (if any)
    drawString = GetStringForUndoType(m_undoEntries(itemIndex).undoType, m_undoEntries(itemIndex).undoLayerID)
    
    If (Len(drawString) <> 0) Then
        mHeight = m_TitleFont.GetHeightOfString(drawString) + linePadding
        m_DescriptionFont.AttachToDC bufferDC
        m_DescriptionFont.FastRenderText thumbWidth + FixDPI(16) + offsetX, offsetY + FixDPI(4) + mHeight, drawString
        m_DescriptionFont.ReleaseFromDC
    End If
        
End Sub
