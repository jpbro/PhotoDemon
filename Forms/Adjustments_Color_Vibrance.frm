VERSION 5.00
Begin VB.Form FormVibrance 
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   " Vibrance"
   ClientHeight    =   6540
   ClientLeft      =   45
   ClientTop       =   285
   ClientWidth     =   12030
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
   ScaleHeight     =   436
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   802
   ShowInTaskbar   =   0   'False
   Begin PhotoDemon.pdCommandBar cmdBar 
      Align           =   2  'Align Bottom
      Height          =   750
      Left            =   0
      TabIndex        =   0
      Top             =   5790
      Width           =   12030
      _ExtentX        =   21220
      _ExtentY        =   1323
   End
   Begin PhotoDemon.pdSlider sltVibrance 
      Height          =   705
      Left            =   6000
      TabIndex        =   2
      Top             =   2400
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "vibrance"
      Min             =   -100
      Max             =   100
   End
   Begin PhotoDemon.pdFxPreviewCtl pdFxPreview 
      Height          =   5625
      Left            =   120
      TabIndex        =   1
      Top             =   120
      Width           =   5625
      _ExtentX        =   9922
      _ExtentY        =   9922
   End
End
Attribute VB_Name = "FormVibrance"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'Vibrance Adjustment Tool
'Copyright 2014-2017 by Tanner Helland, first build Copyright 2013 Audioglider
'Created: 26/June/13
'Last updated: 02/August/17
'Last update: rewrite against entirely new, improved algorithm
'
'Photoshop pioneered the concept of a "vibrance" adjustment in CS4.  Vibrance is similar in concept
' to saturation (as you can probably infer from the name), but unlike saturation, it changes color
' "vibrance" in non-linear ways.  Already-vibrant colors are largely ignored by the tool, while largely
' unsaturated colors are also ignored.  Tones with middling saturation receive the largest changes,
' which is what allows the tool to produce more "realistic" output compared to linear saturation
' adjustments.
'
'The algorithm PhotoDemon uses has undergone a number of revisions.  At present, it automates an
' S-curve adjustment to the underlying image's saturation (via the HSL space, specifically - not HSV).
' This provides reasonably good control, while limiting the amount of change applied at the high and
' low ends of the scale.
'
'Thank you to Audioglider for contributing the first version of this tool to PhotoDemon.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

Public Sub Vibrance(ByVal effectParams As String, Optional ByVal toPreview As Boolean = False, Optional ByRef dstPic As pdFxPreviewCtl)
    
    If (Not toPreview) Then Message "Adjusting color vibrance..."
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString effectParams
    
    Dim vibranceAdjustment As Double
    vibranceAdjustment = cParams.GetDouble("vibrance", 0#)
    
    'Reverse the vibrance input; this way, positive values make the image more vibrant.  Negative values make it less vibrant.
    'vibranceAdjustment = -0.01 * vibranceAdjustment
    
    'Create a local array and point it at the pixel data we want to operate on
    Dim imageData() As Byte
    Dim tmpSA As SAFEARRAY2D, tmpSA1D As SAFEARRAY1D
    EffectPrep.PrepImageData tmpSA, toPreview, dstPic
        
    'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
    Dim x As Long, y As Long, initX As Long, initY As Long, finalX As Long, finalY As Long
    initX = curDIBValues.Left
    initY = curDIBValues.Top
    finalX = curDIBValues.Right
    finalY = curDIBValues.Bottom
            
    'These values will help us access locations in the array more quickly.
    ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
    Dim qvDepth As Long
    qvDepth = curDIBValues.BytesPerPixel
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    If (Not toPreview) Then ProgressBars.SetProgBarMax finalY
    progBarCheck = ProgressBars.FindBestProgBarValue()
    
    'Color and related variables
    Dim h As Double, s As Double, v As Double
    Dim rFloat As Double, gFloat As Double, bFloat As Double
    Const ONE_DIV_255 As Double = 1# / 255#
    
    'vibranceAdjustment = (vibranceAdjustment + 100#) * 0.01
    'If (vibranceAdjustment <> 0#) Then vibranceAdjustment = 1# / vibranceAdjustment
    
    'Construct a curve-based lookup table
    Dim sCurve() As POINTFLOAT
    ReDim sCurve(0 To 2) As POINTFLOAT
    sCurve(0).x = 0
    sCurve(0).y = 0
    sCurve(2).x = 255
    sCurve(2).y = 255
    
    'The middle point of the curve is automatically shifted in a gamma-like curve, according to
    ' the strength of the current adjustment.
    Dim midCurveAdj As Single
    midCurveAdj = (vibranceAdjustment / 100#) * 65#
    sCurve(1).x = 127 - midCurveAdj
    sCurve(1).y = 127 + midCurveAdj * 0.5
    
    'Use those curve coordinates to construct a full lookup table of converted values
    Dim cLut As pdFilterLUT
    Set cLut = New pdFilterLUT
    Dim sValues() As Byte
    cLut.FillLUT_Curve sValues, sCurve
    
    'Loop through each pixel in the image, converting values as we go
    initX = initX * qvDepth
    finalX = finalX * qvDepth
    
    Dim dibPointer As Long, dibStride As Long
    workingDIB.WrapArrayAroundScanline imageData, tmpSA1D, 0
    dibPointer = tmpSA1D.pvData
    dibStride = tmpSA1D.cElements
    
    For y = initY To finalY
        tmpSA1D.pvData = dibPointer + y * dibStride
    For x = initX To finalX Step qvDepth
        
        'Get the source pixel color values
        bFloat = imageData(x)
        gFloat = imageData(x + 1)
        rFloat = imageData(x + 2)
        
        'Convert to HSL
        Colors.PreciseRGBtoHSL rFloat * ONE_DIV_255, gFloat * ONE_DIV_255, bFloat * ONE_DIV_255, h, s, v
        
        'Modify saturation using our pre-built lookup table
        s = CDbl(sValues(Int(s * 255#))) * ONE_DIV_255
        
        'Convert the modified HSL values back to RGB
        Colors.PreciseHSLtoRGB h, s, v, rFloat, gFloat, bFloat
        
        imageData(x) = bFloat * 255#
        imageData(x + 1) = gFloat * 255#
        imageData(x + 2) = rFloat * 255#
        
    Next x
        If (Not toPreview) Then
            If (y And progBarCheck) = 0 Then
                If Interface.UserPressedESC() Then Exit For
                SetProgBarVal y
            End If
        End If
    Next y
    
    'Safely deallocate imageData()
    workingDIB.UnwrapArrayFromDIB imageData
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    EffectPrep.FinalizeImageData toPreview, dstPic

End Sub

Private Sub cmdBar_OKClick()
    Process "Vibrance", , GetLocalParamString(), UNDO_Layer
End Sub

Private Sub cmdBar_RequestPreviewUpdate()
    UpdatePreview
End Sub

Private Sub Form_Load()
    cmdBar.MarkPreviewStatus False
    ApplyThemeAndTranslations Me
    cmdBar.MarkPreviewStatus True
    UpdatePreview
End Sub

Private Sub Form_Unload(Cancel As Integer)
    ReleaseFormTheming Me
End Sub

'Update the preview whenever the combination slider/text control has its value changed
Private Sub sltVibrance_Change()
    UpdatePreview
End Sub

Private Sub UpdatePreview()
    If cmdBar.PreviewsAllowed Then Vibrance GetLocalParamString(), True, pdFxPreview
End Sub

'If the user changes the position and/or zoom of the preview viewport, the entire preview must be redrawn.
Private Sub pdFxPreview_ViewportChanged()
    UpdatePreview
End Sub

Private Function GetLocalParamString() As String
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    
    With cParams
        .AddParam "vibrance", sltVibrance.Value
    End With
    
    GetLocalParamString = cParams.GetParamString()
    
End Function
