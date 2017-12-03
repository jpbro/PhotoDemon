VERSION 5.00
Begin VB.Form FormRainbow 
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   " Rainbow"
   ClientHeight    =   6540
   ClientLeft      =   45
   ClientTop       =   285
   ClientWidth     =   12090
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
   ScaleWidth      =   806
   ShowInTaskbar   =   0   'False
   Begin PhotoDemon.pdCommandBar cmdBar 
      Align           =   2  'Align Bottom
      Height          =   750
      Left            =   0
      TabIndex        =   0
      Top             =   5790
      Width           =   12090
      _ExtentX        =   21325
      _ExtentY        =   1323
   End
   Begin PhotoDemon.pdSlider sltOffset 
      Height          =   705
      Left            =   6000
      TabIndex        =   2
      Top             =   840
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "offset"
      Max             =   359
      SliderTrackStyle=   4
   End
   Begin PhotoDemon.pdFxPreviewCtl pdFxPreview 
      Height          =   5625
      Left            =   120
      TabIndex        =   1
      Top             =   120
      Width           =   5625
      _ExtentX        =   9922
      _ExtentY        =   9922
      DisableZoomPan  =   -1  'True
   End
   Begin PhotoDemon.pdSlider sltAngle 
      Height          =   705
      Left            =   6000
      TabIndex        =   3
      Top             =   1920
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "angle"
      Max             =   360
   End
   Begin PhotoDemon.pdSlider sltStrength 
      Height          =   705
      Left            =   6000
      TabIndex        =   4
      Top             =   3000
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "strength"
      Max             =   100
      Value           =   100
      DefaultValue    =   100
   End
   Begin PhotoDemon.pdSlider sltSaturation 
      Height          =   705
      Left            =   6000
      TabIndex        =   5
      Top             =   4080
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "saturation boost"
      Max             =   100
   End
End
Attribute VB_Name = "FormRainbow"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'Rainbow Effect dialog
'Copyright 2003-2017 by Tanner Helland
'Created: sometime 2003
'Last updated: 01/August/17
'Last update: performance improvements, migrate to XML params
'
'Fun Rainbow effect for an image.  Options should be self-explanatory.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'Apply a rainbow overlay to an image
Public Sub ApplyRainbowEffect(ByVal effectParams As String, Optional ByVal toPreview As Boolean = False, Optional ByRef dstPic As pdFxPreviewCtl)
    
    If (Not toPreview) Then Message "Sprinkling image with shimmering rainbows..."
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString effectParams
    
    Dim hueOffset As Double, rainbowAngle As Double, rainbowStrength As Double, saturationBoost As Double
    
    With cParams
        hueOffset = .GetDouble("offset", sltOffset.Value)
        rainbowAngle = .GetDouble("angle", sltAngle.Value)
        rainbowStrength = .GetDouble("strength", sltStrength.Value)
        saturationBoost = .GetDouble("saturation", sltSaturation.Value)
    End With
    
    'Convert the hue modifier to the [0, 6] range
    hueOffset = hueOffset / 360#
    
    'Convert strength from [0, 100] to [0, 1]
    rainbowStrength = rainbowStrength / 100#
    
    'Convert saturation boosting from [0, 100] to [0, 1]
    saturationBoost = saturationBoost / 100#
    
    'Create a local array and point it at the pixel data we want to operate on
    Dim imageData() As Byte
    Dim tmpSA As SAFEARRAY2D
    
    EffectPrep.PrepImageData tmpSA, toPreview, dstPic
    CopyMemory ByVal VarPtrArray(imageData()), VarPtr(tmpSA), 4
        
    'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
    Dim x As Long, y As Long, initX As Long, initY As Long, finalX As Long, finalY As Long
    initX = curDIBValues.Left
    initY = curDIBValues.Top
    finalX = curDIBValues.Right
    finalY = curDIBValues.Bottom
    
    'These values will help us access locations in the array more quickly.
    ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
    Dim xOffset As Long, qvDepth As Long
    qvDepth = curDIBValues.BytesPerPixel
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    progBarCheck = ProgressBars.FindBestProgBarValue()
    
    'Calculate the center of the image
    Dim midX As Double, midY As Double
    midX = CDbl(finalX - initX) * 0.5
    midX = midX + initX
    midY = CDbl(finalY - initY) * 0.5
    midY = midY + initY
    
    'Convert the rotation angle to radians
    rainbowAngle = rainbowAngle * (PI / 180#)
    
    'Find the cos and sin of this angle and store the values
    Dim cosTheta As Double, sinTheta As Double
    cosTheta = Cos(rainbowAngle)
    sinTheta = Sin(rainbowAngle)
    
    'Using those values, build 4 lookup tables, one each for x/y times sin/cos
    Dim xSin() As Double, xCos() As Double
    ReDim xSin(initX To finalX) As Double
    ReDim xCos(initX To finalX) As Double
    
    For x = initX To finalX
        xSin(x) = (x - midX) * sinTheta + midY
        xCos(x) = (x - midX) * cosTheta + midX
    Next
    
    Dim ySin() As Double, yCos() As Double
    ReDim ySin(initY To finalY) As Double
    ReDim yCos(initY To finalY) As Double
    For y = initY To finalY
        ySin(y) = (y - midY) * sinTheta
        yCos(y) = (y - midY) * cosTheta
    Next y
        
    'Source X value, which is used to solve for the hue of a given point
    Dim srcX As Double
    
    'Finally, a bunch of variables used in color calculation
    Dim r As Long, g As Long, b As Long
    Dim rFloat As Double, gFloat As Double, bFloat As Double
    Dim h As Double, s As Double, l As Double
    Dim hVal As Double, xDistance As Double
    
    If ((finalX - initX) <> 0) Then xDistance = 1# / (finalX - initX) Else xDistance = 1#
    
    Const ONE_DIV_255 As Double = 1# / 255#
    
    'Apply the filter
    For x = initX To finalX
        xOffset = x * qvDepth
    For y = initY To finalY
        
        'Get red, green, and blue values from the array
        b = imageData(xOffset, y)
        g = imageData(xOffset + 1, y)
        r = imageData(xOffset + 2, y)
        
        'Convert the RGB values the HSV space
        Colors.fRGBtoHSV r * ONE_DIV_255, g * ONE_DIV_255, b * ONE_DIV_255, h, s, l
        
        'Solve for the original (x) position of this pixel in the image, accounting for rotation
        srcX = xCos(x) - ySin(y)
        
        'Based on the x-coordinate of a pixel, apply a predetermined hue gradient (stretching between -1 and 5)
        hVal = srcX * xDistance
        
        'Apply the hue offset
        hVal = hVal + hueOffset
        If (hVal > 1#) Then hVal = hVal - 1#
        
        'Apply saturation boosting, if any
        s = s + (s * saturationBoost)
        If (s > 1#) Then s = 1#
        
        'Now convert those HSL values back to RGB, but substitute in our artificial hue (and possibly
        ' saturation) value(s)
        Colors.fHSVtoRGB hVal, s, l, rFloat, gFloat, bFloat
        
        'Blend the original and new RGB values according to the requested strength
        r = BlendColors(r, rFloat * 255#, rainbowStrength)
        g = BlendColors(g, gFloat * 255#, rainbowStrength)
        b = BlendColors(b, bFloat * 255#, rainbowStrength)
        
        'Assign the new RGB values back into the array
        imageData(xOffset, y) = b
        imageData(xOffset + 1, y) = g
        imageData(xOffset + 2, y) = r
        
    Next y
        If (Not toPreview) Then
            If (x And progBarCheck) = 0 Then
                If Interface.UserPressedESC() Then Exit For
                SetProgBarVal x
            End If
        End If
    Next x
        
    'Safely deallocate imageData()
    CopyMemory ByVal VarPtrArray(imageData), 0&, 4
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    EffectPrep.FinalizeImageData toPreview, dstPic
    
End Sub

Private Sub cmdBar_OKClick()
    Process "Rainbow", , GetLocalParamString(), UNDO_LAYER
End Sub

Private Sub cmdBar_RequestPreviewUpdate()
    UpdatePreview
End Sub

Private Sub cmdBar_ResetClick()
    sltStrength.Value = 100
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

Private Sub UpdatePreview()
    If cmdBar.PreviewsAllowed Then ApplyRainbowEffect GetLocalParamString(), True, pdFxPreview
End Sub

'If the user changes the position and/or zoom of the preview viewport, the entire preview must be redrawn.
Private Sub pdFxPreview_ViewportChanged()
    UpdatePreview
End Sub

Private Sub sltAngle_Change()
    UpdatePreview
End Sub

Private Sub sltOffset_Change()
    UpdatePreview
End Sub

Private Sub sltSaturation_Change()
    UpdatePreview
End Sub

Private Sub sltStrength_Change()
    UpdatePreview
End Sub

Private Function GetLocalParamString() As String
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    
    With cParams
        .AddParam "offset", sltOffset.Value
        .AddParam "angle", sltAngle.Value
        .AddParam "strength", sltStrength.Value
        .AddParam "saturation", sltSaturation.Value
    End With
    
    GetLocalParamString = cParams.GetParamString()
    
End Function
