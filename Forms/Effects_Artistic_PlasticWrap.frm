VERSION 5.00
Begin VB.Form FormPlasticWrap 
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   " Plastic wrap"
   ClientHeight    =   6540
   ClientLeft      =   45
   ClientTop       =   285
   ClientWidth     =   12075
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
   ScaleWidth      =   805
   ShowInTaskbar   =   0   'False
   Begin PhotoDemon.pdCommandBar cmdBar 
      Align           =   2  'Align Bottom
      Height          =   750
      Left            =   0
      TabIndex        =   0
      Top             =   5790
      Width           =   12075
      _ExtentX        =   21299
      _ExtentY        =   1323
   End
   Begin PhotoDemon.pdSlider sldRadius 
      Height          =   705
      Left            =   6000
      TabIndex        =   2
      Top             =   1560
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "smoothness"
      Max             =   200
      SigDigits       =   1
      Value           =   20
      DefaultValue    =   20
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
   Begin PhotoDemon.pdSlider sldDetail 
      Height          =   705
      Left            =   6000
      TabIndex        =   3
      Top             =   600
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "detail"
      Max             =   16
      Value           =   4
      NotchPosition   =   2
      NotchValueCustom=   4
   End
   Begin PhotoDemon.pdSlider sldDistance 
      Height          =   705
      Left            =   6000
      TabIndex        =   4
      Top             =   2520
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "thickness"
      SigDigits       =   2
      Value           =   2
      DefaultValue    =   2
   End
   Begin PhotoDemon.pdSlider sldAngle 
      Height          =   705
      Left            =   6000
      TabIndex        =   5
      Top             =   3480
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "light angle"
      Min             =   -180
      Max             =   180
      SigDigits       =   1
   End
   Begin PhotoDemon.pdSlider sldDepth 
      Height          =   705
      Left            =   6000
      TabIndex        =   6
      Top             =   4440
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "light intensity"
      Min             =   0.1
      SigDigits       =   2
      Value           =   5
      DefaultValue    =   5
   End
End
Attribute VB_Name = "FormPlasticWrap"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'"Plastic Wrap" Image effect
'Copyright 2017-2017 by Tanner Helland
'Created: 03/August/17
'Last updated: 07/August/17
'Last update: put finishing touches on the algorithm
'
'"Plastic wrap" has been available in Photoshop for well over two decades at this point, but I've yet to see
' an open-source software package reproduce the effect well.  (For example, try GIMP's analog of it, in the
' Filters > Light and Shadow menu.  It's just a Script-Fu wrapper, and it's terrible.  Ugh.)
'
'As usual, this means I had to design PhotoDemon's implementation from scratch, and also as usual, I think
' the end result is pretty darn great!  To my knowledge, this the closest anyone's come to reproducing
' Photoshop's effect, and while there are still differences (some by design, to improve output on modern photo
' sizes), I think our technique is actually the preferable one - and any differences are small enough that you
' can still use our technique to mimic tutorials that utilize the Photoshop effect.
'
'The actual effect implementation is simple: it's basically a modified "Metal" filter, which reduces image
' structure to a series of alternating ridges and troughs, followed by a modified "Emboss" filter, which
' basically calculates a slope and direction at each point in the image.  We also apply some highlight and
' smoothing effects, obviously, to produce a "shiny" result that looks like the filter's namesake.
'
'Thanks to the simplicity of our implementation, most of the work can be done in a grayscale color space,
' which means performance is quite snappy.  (In fact, I believe this is how Photoshop does it as well, which
' could explain how they were able to implement a demanding filter like this so many years ago.)
'
'Anyway, that should explain the geometry behind our implementation, and why the effect's settings bear some
' resemblance to the "Metal" and "Emboss" effects.  I particularly like the lighting controls in our
' implementation, which are a neat improvement over the Photoshop version.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'To improve preview performance, a persistent effect DIB is cached locally
Private m_GrayDIB As pdDIB

Public Sub ApplyPlasticWrap(ByVal effectParams As String, Optional ByVal toPreview As Boolean = False, Optional ByRef dstPic As pdFxPreviewCtl)
    
    If (Not toPreview) Then Message "Wrapping image in plastic..."
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString effectParams
    
    Dim wrapDetail As Long, wrapSmoothness As Double
    Dim lightAngle As Double, lightDepth As Double, lightDistance As Double
    
    With cParams
        wrapDetail = .GetLong("detail", sldDetail.Value)
        wrapSmoothness = .GetDouble("radius", sldRadius.Value)
        lightAngle = .GetDouble("angle", sldAngle.Value)
        lightDepth = .GetDouble("depth", sldDepth.Value)
        lightDistance = .GetDouble("thickness", sldDistance.Value)
    End With
    
    'Create a local array and point it at the pixel data of the current image
    Dim dstSA As SAFEARRAY2D
    EffectPrep.PrepImageData dstSA, toPreview, dstPic
    
    'If this is a preview, we need to adjust the smoothness (kernel radius) to match the size of the preview box
    If toPreview Then
        wrapSmoothness = wrapSmoothness * curDIBValues.previewModifier
        lightDistance = lightDistance * curDIBValues.previewModifier
    End If
    
    'Retrieve a normalized luminance map of the current image
    Dim grayMap() As Byte
    DIBs.GetDIBGrayscaleMap workingDIB, grayMap, True
    
    'If the user specified a non-zero smoothness, apply it now
    If (wrapSmoothness > 0) Then Filters_ByteArray.GaussianBlur_IIR_ByteArray grayMap, workingDIB.GetDIBWidth, workingDIB.GetDIBHeight, wrapSmoothness, 3
        
    'Re-normalize the data (this ends up not being necessary, but it could be exposed to the user in a future update)
    'Filters_ByteArray.normalizeByteArray grayMap, workingDIB.getDIBWidth, workingDIB.getDIBHeight
    
    'Next, we need to generate a sinusoidal octave lookup table for the graymap.  This causes the luminance of the
    ' map to vary evenly between the number of detail points requested by the user.
    
    'Detail cannot be lower than 2, but it is presented to the user as [0, (arbitrary upper bound)],
    ' so add two to the total now
    wrapDetail = wrapDetail + 2
    
    'We will be using pdFilterLUT to generate corresponding RGB lookup tables, which means we need to use
    ' POINTFLOAT arrays
    Dim gCurve() As POINTFLOAT
    ReDim gCurve(0 To wrapDetail) As POINTFLOAT
    
    Dim detailModifier As Double
    detailModifier = 1# / CDbl(wrapDetail)
    
    'X values are evenly distributed from 0 to 255, obviously
    Dim i As Long
    For i = 0 To wrapDetail
        gCurve(i).x = CDbl(i) * detailModifier * 255#
    Next i
    
    'Y values alternate between the shadow and highlight colors (which are pure black and pure white for this effect).
    ' Because we're only applying this to a gray channel, we don't need per-channel lookups
    For i = 0 To wrapDetail
        If ((i Mod 2) = 0) Then gCurve(i).y = 0 Else gCurve(i).y = 255
    Next i
    
    'Convert our point array into an actual curve
    Dim gLookup() As Byte
    
    Dim cLut As pdFilterLUT
    Set cLut = New pdFilterLUT
    cLut.FillLUT_Curve gLookup, gCurve
        
    'Next, we will apply the curve to the grayscale map.
    
    'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
    Dim x As Long, y As Long, initX As Long, initY As Long, finalX As Long, finalY As Long
    initX = curDIBValues.Left
    initY = curDIBValues.Top
    finalX = curDIBValues.Right
    finalY = curDIBValues.Bottom
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    If (Not toPreview) Then ProgressBars.SetProgBarMax finalY * 2
    progBarCheck = ProgressBars.FindBestProgBarValue()
    
    For y = initY To finalY
    For x = initX To finalX
        grayMap(x, y) = gLookup(grayMap(x, y))
    Next x
        If (y And progBarCheck) = 0 Then
            If Interface.UserPressedESC() Then Exit For
            SetProgBarVal y
        End If
    Next y
    
    'Now we have a graymap that represents the (smoothened) gradient of colors in the image.  We now need to calculate
    ' the slope at every pixel, and apply those results to an actual 32-bpp DIB we can use for blending.
    If (m_GrayDIB Is Nothing) Then Set m_GrayDIB = New pdDIB
    m_GrayDIB.CreateBlank workingDIB.GetDIBWidth, workingDIB.GetDIBHeight, 32, 0, 0
    
    'Convert the rotation angle to radians
    lightAngle = lightAngle * (PI / 180#)
    
    'Find the cos and sin of this angle and store the values
    Dim cosTheta As Double, sinTheta As Double
    cosTheta = Cos(lightAngle)
    sinTheta = Sin(lightAngle)
    
    'New X value, remapped around a center point of (0, 0)
    Dim nX As Double
    
    'Source X and Y values, which are used to solve for the hue of a given point
    Dim srcX As Double, srcY As Double
    
    'Interpolation variables
    Dim xDiff As Double, yDiff As Double, topRowValue As Double, bottomRowValue As Double
    Dim x0 As Long, x1 As Long, y0 As Long, y1 As Long, gInterp As Long
    Dim g As Long
    Const ONE_DIV_255 As Double = 1# / 255#
    
    'To avoid new values from interfering with calculations as we go, we will place all results into
    ' a new, "safe" array
    Dim finalGrayMap() As Byte
    ReDim finalGrayMap(0 To workingDIB.GetDIBWidth - 1, 0 To workingDIB.GetDIBHeight - 1) As Byte
    
    'Loop through each pixel in the image, converting values as we go
    For y = initY To finalY
    For x = initX To finalX
        
        'Retrieve source graymap value
        g = grayMap(x, y)
        
        'Move x according to the user's distance parameter
        nX = x + lightDistance
    
        'Calculate a rotated source x/y pixel
        srcX = cosTheta * (nX - x) + x
        srcY = sinTheta * (nX - x) + y
        
        'Interpolate the hypothetical pixel value at this position
        x0 = Int(srcX)
        x1 = x0 + 1
        xDiff = srcX - x0
        y0 = Int(srcY)
        y1 = y0 + 1
        yDiff = srcY - y0
        
        If (x0 < initX) Then
            x0 = initX
        ElseIf (x0 > finalX) Then
            x0 = finalX
        End If
        
        If (x1 < initX) Then
            x1 = initX
        ElseIf (x1 > finalX) Then
            x1 = finalX
        End If
        
        If (y0 < initY) Then
            y0 = initY
        ElseIf (y0 > finalY) Then
            y0 = finalY
        End If
        
        If (y1 < initY) Then
            y1 = initY
        ElseIf (y1 > finalY) Then
            y1 = finalY
        End If
        
        'Blend in the x-direction
        topRowValue = CDbl(grayMap(x0, y0)) * (1# - xDiff) + CDbl(grayMap(x1, y0)) * xDiff
        bottomRowValue = CDbl(grayMap(x0, y1)) * (1# - xDiff) + CDbl(grayMap(x1, y1)) * xDiff
    
        'Finally, blend in the y-direction
        gInterp = bottomRowValue * yDiff + topRowValue * (1# - yDiff)
        
        'Calculate an emboss value (which is just the difference between the source pixel and the interpolated pixel
        ' value at our hypothetical emboss position)
        g = (g - gInterp) * lightDepth
                
        'Clamp for safety
        If (g > 255) Then
            g = 255
        ElseIf (g < 0) Then
            g = 0
        End If
        
        finalGrayMap(x, y) = g
        
    Next x
        If (Not toPreview) Then
            If (y And progBarCheck) = 0 Then
                If Interface.UserPressedESC() Then Exit For
                SetProgBarVal finalY + y
            End If
        End If
    Next y
    
    'Because the end result is somewhat pixelated (due to the integer maths involved), it helps to gently blur
    ' the final result.
    Dim blurRadius As Long
    blurRadius = Int(3# * curDIBValues.previewModifier)
    If (blurRadius < 1) Then blurRadius = 1
    Filters_ByteArray.HorizontalBlur_ByteArray finalGrayMap, workingDIB.GetDIBWidth, workingDIB.GetDIBHeight, blurRadius, blurRadius
    Filters_ByteArray.VerticalBlur_ByteArray finalGrayMap, workingDIB.GetDIBWidth, workingDIB.GetDIBHeight, blurRadius, blurRadius
    
    'With the graymap successfully converted, we can now apply it to the image.
    workingDIB.SetAlphaPremultiplication True
    Dim cCompositor As pdCompositor
    Set cCompositor = New pdCompositor
    
    'Really dense blend, similar to Photoshop:
    'DIBs.CreateDIBFromGrayscaleMap_Alpha m_GrayDIB, finalGrayMap, workingDIB.GetDIBWidth, workingDIB.GetDIBHeight
    'cCompositor.QuickMergeTwoDibsOfEqualSize workingDIB, m_GrayDIB, BL_NORMAL, 100#
    
    'Lighter, modern blend:
    DIBs.CreateDIBFromGrayscaleMap m_GrayDIB, finalGrayMap, workingDIB.GetDIBWidth, workingDIB.GetDIBHeight
    cCompositor.QuickMergeTwoDibsOfEqualSize workingDIB, m_GrayDIB, BL_SCREEN, 100#, , LA_INHERIT
    
    'If this is *not* a preview, wipe our local caches before exiting
    If (Not toPreview) Then Set m_GrayDIB = Nothing
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering using the data inside workingDIB
    EffectPrep.FinalizeImageData toPreview, dstPic, True
            
End Sub

'OK button
Private Sub cmdBar_OKClick()
    Process "Plastic wrap", , GetLocalParamString(), UNDO_Layer
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

Private Sub UpdatePreview()
    If cmdBar.PreviewsAllowed Then Me.ApplyPlasticWrap GetLocalParamString(), True, pdFxPreview
End Sub

Private Sub sldAngle_Change()
    UpdatePreview
End Sub

Private Sub sldDepth_Change()
    UpdatePreview
End Sub

Private Sub sldDetail_Change()
    UpdatePreview
End Sub

Private Sub sldDistance_Change()
    UpdatePreview
End Sub

Private Sub sldRadius_Change()
    UpdatePreview
End Sub

'If the user changes the position and/or zoom of the preview viewport, the entire preview must be redrawn.
Private Sub pdFxPreview_ViewportChanged()
    UpdatePreview
End Sub

Private Function GetLocalParamString() As String
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    
    With cParams
        .AddParam "detail", sldDetail.Value
        .AddParam "radius", sldRadius.Value
        .AddParam "angle", sldAngle.Value
        .AddParam "depth", sldDepth.Value
        .AddParam "thickness", sldDistance.Value
    End With
    
    GetLocalParamString = cParams.GetParamString()
    
End Function
