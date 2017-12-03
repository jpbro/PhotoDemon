VERSION 5.00
Begin VB.Form FormZoomBlur 
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   " Zoom blur"
   ClientHeight    =   6540
   ClientLeft      =   45
   ClientTop       =   285
   ClientWidth     =   12030
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
   Begin PhotoDemon.pdFxPreviewCtl pdFxPreview 
      Height          =   5625
      Left            =   120
      TabIndex        =   1
      Top             =   120
      Width           =   5625
      _ExtentX        =   9922
      _ExtentY        =   9922
      DisableZoomPan  =   -1  'True
      PointSelection  =   -1  'True
   End
   Begin PhotoDemon.pdSlider sltDistance 
      Height          =   705
      Left            =   6000
      TabIndex        =   2
      Top             =   2760
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "distance"
      Min             =   -200
      Max             =   200
   End
   Begin PhotoDemon.pdSlider sltXCenter 
      Height          =   405
      Left            =   6000
      TabIndex        =   3
      Top             =   1560
      Width           =   2895
      _ExtentX        =   5106
      _ExtentY        =   873
      Max             =   1
      SigDigits       =   2
      Value           =   0.5
      NotchPosition   =   2
      NotchValueCustom=   0.5
   End
   Begin PhotoDemon.pdSlider sltYCenter 
      Height          =   405
      Left            =   9000
      TabIndex        =   4
      Top             =   1560
      Width           =   2895
      _ExtentX        =   5106
      _ExtentY        =   873
      Max             =   1
      SigDigits       =   2
      Value           =   0.5
      NotchPosition   =   2
      NotchValueCustom=   0.5
   End
   Begin PhotoDemon.pdLabel lblTitle 
      Height          =   285
      Index           =   0
      Left            =   6000
      Top             =   1200
      Width           =   5925
      _ExtentX        =   0
      _ExtentY        =   0
      Caption         =   "center position (x, y)"
      FontSize        =   12
      ForeColor       =   4210752
   End
   Begin PhotoDemon.pdLabel lblExplanation 
      Height          =   435
      Index           =   0
      Left            =   6120
      Top             =   2130
      Width           =   5655
      _ExtentX        =   0
      _ExtentY        =   0
      Alignment       =   2
      Caption         =   "Note: you can also set a center position by clicking the preview window."
      FontSize        =   9
      ForeColor       =   4210752
      Layout          =   1
   End
End
Attribute VB_Name = "FormZoomBlur"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'Zoom Blur Tool
'Copyright 2013-2017 by Tanner Helland
'Created: 27/August/13
'Last updated: 11/June/16
'Last update: rewrite algorithm to support variable center positioning
'
'Basic zoom blur tool.  Performance is middling, but the end result is of reasonably good quality.
'
'All source code in this file is licensed under a modified BSD license. This means you may use the code in your own
' projects IF you provide attribution. For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'Apply motion blur to an image using a "modern" approach that allows for both in and out zoom
'Inputs: distance of the blur
Public Sub ApplyZoomBlur(ByVal functionParams As String, Optional ByVal toPreview As Boolean = False, Optional ByRef dstPic As pdFxPreviewCtl)
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString functionParams
    
    Dim zDistance As Double, zCenterX As Double, zCenterY As Double
    zDistance = cParams.GetDouble("distance", 0#)
    zCenterX = cParams.GetDouble("center-x", 0.5)
    zCenterY = cParams.GetDouble("center-y", 0.5)
    
    If (Not toPreview) Then Message "Applying zoom blur..."
    
    'Create a local array and point it at the pixel data of the current image
    Dim dstImageData() As Byte
    Dim dstSA As SAFEARRAY2D
    EffectPrep.PrepImageData dstSA, toPreview, dstPic, , , True
    CopyMemory ByVal VarPtrArray(dstImageData()), VarPtr(dstSA), 4
    
    'Create a second local array.  This will contain the a copy of the current image, and we will use it as our source reference
    ' (This is necessary to prevent diffused pixels from spreading across the image as we go.)
    Dim srcDIB As pdDIB
    Set srcDIB = New pdDIB
    srcDIB.CreateFromExistingDIB workingDIB
    
    Dim srcImageData() As Byte, srcSA As SAFEARRAY2D
    srcDIB.WrapArrayAroundDIB srcImageData, srcSA
       
    'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
    Dim x As Long, y As Long, initX As Long, initY As Long, finalX As Long, finalY As Long
    initX = curDIBValues.Left
    initY = curDIBValues.Top
    finalX = curDIBValues.Right
    finalY = curDIBValues.Bottom
            
    'These values will help us access locations in the array more quickly.
    ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
    Dim qvDepth As Long, xQuick As Long, xQuickInner As Long, yQuick As Long
    qvDepth = curDIBValues.BytesPerPixel
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    ProgressBars.SetProgBarMax finalY
    progBarCheck = ProgressBars.FindBestProgBarValue()
    
    Dim newR As Long, newG As Long, newB As Long, newA As Long
    Dim r As Long, g As Long, b As Long, a As Long
    
    'Calculate the center of the image
    Dim midX As Double, midY As Double
    midX = CDbl(finalX - initX) * zCenterX
    midX = midX + initX
    midY = CDbl(finalY - initY) * zCenterY
    midY = midY + initY
    
    'Rotation values
    Dim theta As Double, sDistance As Double, prevDistance As Double, distCalc As Double
    
    'X and Y values, remapped around a center point of (0, 0)
    Dim nX As Double, nY As Double
    
    'Reverse-mapped source X and Y values
    Dim srcX As Double, srcY As Double
    
    'It's very time-consuming to sample every point along the zoom line, so instead, we sample only a portion of points.
    ' This value is determined by the total zoom distance (with an enforced minimum so that short blur radii work okay).
    Dim numSamples As Long
    numSamples = Abs(zDistance)
    If (numSamples < 8) Then numSamples = 8
    
    Dim tmpSamples As Long, sampRatio As Single
    
    Dim maxRadius As Double
    maxRadius = Sqr(finalX * finalX + finalY * finalY)
    
    Dim i As Long
    Dim tmpDistance As Double
    Dim cosTheta As Single, sinTheta As Single
    
    Dim distRatio As Double
    distRatio = CDbl(zDistance) / 100
    
    'Loop through each pixel in the image, converting values as we go
    For y = initY To finalY
    For x = initX To finalX
        
        xQuick = x * qvDepth
        
        'Reset all averages and cache the source color values
        newB = 0
        newG = 0
        newR = 0
        newA = 0
        
        b = srcImageData(xQuick, y)
        g = srcImageData(xQuick + 1, y)
        r = srcImageData(xQuick + 2, y)
        a = srcImageData(xQuick + 3, y)
        
        'Remap the coordinates around a center point of (0, 0)
        nX = x - midX
        nY = y - midY
        
        'Calculate distance automatically and reset the "previous distance" cache
        sDistance = Sqr((nX * nX) + (nY * nY))
        distCalc = distRatio * sDistance
        prevDistance = sDistance
        
        'Calculate theta and precalculate expensive trig functions
        theta = PDMath.Atan2_Fastest(nY, nX)
        cosTheta = Cos(theta)
        sinTheta = Sin(theta)
        
        'Figure out how many times we're going to sample this line.  The number of samples directly correlates to this pixel's
        ' distance from the center of the image.  (Pixels nearer the center are sampled less, because they are blurred less.)
        tmpSamples = CDbl(numSamples) * (sDistance / maxRadius)
        If (tmpSamples < 4) Then
            tmpSamples = 4
        ElseIf (tmpSamples > numSamples) Then
            tmpSamples = numSamples
        End If
        
        sampRatio = (1# / numSamples)
        
        'We now want to sample (numSamples) pixels lying along this theta, but at different distances from the center.
        For i = 1 To tmpSamples
            
            'Calculate a new distance, but do not allow the distance to flip sign
            tmpDistance = (i * sampRatio) * distCalc + sDistance
            If (tmpDistance < 0) Then tmpDistance = 0
            
            'If this sample is very close to the previous sample, there's no point in calculating it.
            ' (This function performs no subsampling, so pixel coordinates are always integer-clamped; this means that two
            ' pixels whose distance differs by less than half a pixel are effectively the same coordinate.)
            If (Abs(tmpDistance - prevDistance) > 0.5) Then
                
                'Convert the new distance and original theta back to cartesian coordinates and clamp to image edges
                srcX = tmpDistance * cosTheta + midX
                srcY = tmpDistance * sinTheta + midY
                
                If (srcX < 0) Then srcX = 0
                If (srcX > finalX) Then srcX = finalX
                If (srcY < 0) Then srcY = 0
                If (srcY > finalY) Then srcY = finalY
                
                xQuickInner = Int(srcX) * qvDepth
                yQuick = Int(srcY)
                
                b = srcImageData(xQuickInner, yQuick)
                g = srcImageData(xQuickInner + 1, yQuick)
                r = srcImageData(xQuickInner + 2, yQuick)
                a = srcImageData(xQuickInner + 3, yQuick)
                
                'Cache this distance so we can skip the next sample if it lies too close to this one
                prevDistance = tmpDistance
            
            End If
            
            'Keep a running total of average pixel values
            newR = newR + r
            newG = newG + g
            newB = newB + b
            newA = newA + a
            
        Next i
        
        sampRatio = 1# / tmpSamples
        dstImageData(xQuick, y) = newB * sampRatio
        dstImageData(xQuick + 1, y) = newG * sampRatio
        dstImageData(xQuick + 2, y) = newR * sampRatio
        dstImageData(xQuick + 3, y) = newA * sampRatio
                
    Next x
        If (Not toPreview) Then
            If (y And progBarCheck) = 0 Then
                If Interface.UserPressedESC() Then Exit For
                SetProgBarVal y
            End If
        End If
    Next y
    
    'Safely deallocate all image arrays
    srcDIB.UnwrapArrayFromDIB srcImageData
    
    CopyMemory ByVal VarPtrArray(dstImageData), 0&, 4
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    EffectPrep.FinalizeImageData toPreview, dstPic, True
    
End Sub

Private Sub cmdBar_OKClick()
    Process "Zoom blur", , GetFilterParamString(), UNDO_LAYER
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
    If cmdBar.PreviewsAllowed Then Me.ApplyZoomBlur GetFilterParamString(), True, pdFxPreview
End Sub

Private Function GetFilterParamString() As String
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    With cParams
        .AddParam "distance", sltDistance.Value
        .AddParam "center-x", sltXCenter.Value
        .AddParam "center-y", sltYCenter.Value
    End With
    
    GetFilterParamString = cParams.GetParamString
    
End Function

Private Sub pdFxPreview_PointSelected(xRatio As Double, yRatio As Double)
    cmdBar.MarkPreviewStatus False
    sltXCenter.Value = xRatio
    sltYCenter.Value = yRatio
    cmdBar.MarkPreviewStatus True
    UpdatePreview
End Sub

Private Sub sltDistance_Change()
    UpdatePreview
End Sub

'If the user changes the position and/or zoom of the preview viewport, the entire preview must be redrawn.
Private Sub pdFxPreview_ViewportChanged()
    UpdatePreview
End Sub

Private Sub sltXCenter_Change()
    UpdatePreview
End Sub

Private Sub sltYCenter_Change()
    UpdatePreview
End Sub
