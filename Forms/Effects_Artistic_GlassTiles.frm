VERSION 5.00
Begin VB.Form FormGlassTiles 
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   " Glass tiles"
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
   Begin PhotoDemon.pdSlider sltAngle 
      Height          =   705
      Left            =   6000
      TabIndex        =   2
      Top             =   360
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "angle"
      Min             =   -45
      Max             =   45
      SigDigits       =   1
      Value           =   45
      DefaultValue    =   45
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
   Begin PhotoDemon.pdSlider sltSize 
      Height          =   705
      Left            =   6000
      TabIndex        =   3
      Top             =   1440
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "size"
      Min             =   1
      Max             =   100
      SigDigits       =   1
      Value           =   20
      NotchPosition   =   2
      NotchValueCustom=   20
   End
   Begin PhotoDemon.pdSlider sltCurvature 
      Height          =   705
      Left            =   6000
      TabIndex        =   4
      Top             =   2520
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "curvature"
      Min             =   -20
      Max             =   20
      SigDigits       =   1
      Value           =   8
      DefaultValue    =   8
   End
   Begin PhotoDemon.pdSlider sltQuality 
      Height          =   705
      Left            =   6000
      TabIndex        =   6
      Top             =   3600
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "quality"
      Min             =   1
      Max             =   5
      Value           =   2
      NotchPosition   =   2
      NotchValueCustom=   2
   End
   Begin PhotoDemon.pdDropDown cboEdges 
      Height          =   735
      Left            =   6000
      TabIndex        =   5
      Top             =   4680
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1296
      Caption         =   "if pixels lie outside the image..."
   End
End
Attribute VB_Name = "FormGlassTiles"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'Glass Tiles Filter Dialog
'Copyright 2014-2017 by dotPDN LLC, Rick Brewster, Tom Jackson, Audioglider, and Tanner Helland (see details below)
'Created: 23/May/14
'Last updated: 01/August/17
'Last update: migrate to PD's internal filter support engine, including internal supersampling techniques
'
'"Glass tiles" is an image distortion filter that divides an image into clear glass blocks.  The curvature
' parameter generates a convex surface for positive values and a concave surface for negative values.
'
'Thank you to Audioglider for first contributing this tool to PhotoDemon.  His contribution was a VB
' translation of code first adopted from the open-source Pinta project.  Pinta, in turn, is derived from
' Paint.NET code from when Paint.NET was MIT-licensed.  (Long story.)  The current version of this algorithm
' is quite far removed from the original, but the basic trig underlying the transform is very much credited
' to the original Paint.NET team.
'
'As such, the original implementation of this code is Copyright (C) dotPDN LLC, Rick Brewster, Tom Jackson,
' and contributors.  You can download the original Pinta version of this function from this link (good as of
' August 2017): https://github.com/PintaProject/Pinta/blob/master/Pinta.Effects/Effects/TileEffect.cs
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'Apply a glass tile filter to an image
Public Sub GlassTiles(ByVal effectParams As String, Optional ByVal toPreview As Boolean = False, Optional ByRef dstPic As pdFxPreviewCtl)
    
    If (Not toPreview) Then Message "Generating glass tiles..."
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString effectParams
    
    Dim tileSize As Long, superSamplingAmount As Long, edgeHandling As Long
    Dim tileCurvature As Double, tileAngle As Double
    
    With cParams
        tileSize = .GetLong("size", sltSize.Value)
        tileCurvature = .GetDouble("curvature", sltCurvature.Value)
        tileAngle = .GetDouble("angle", sltAngle.Value)
        superSamplingAmount = .GetLong("quality", sltQuality.Value)
        edgeHandling = .GetLong("edges", cboEdges.ListIndex)
    End With
    
    If (Not toPreview) Then Message "Generating glass tiles..."
    
    'Create a local array and point it at the pixel data of the current image
    Dim dstImageData() As Byte
    Dim dstSA As SAFEARRAY2D
    EffectPrep.PrepImageData dstSA, toPreview, dstPic
    CopyMemory ByVal VarPtrArray(dstImageData()), VarPtr(dstSA), 4
    
    'Create a second local array.  This will contain the a copy of the current image, and we will use it as our source reference
    ' (This is necessary to prevent diffused pixels from spreading across the image as we go.)
    Dim srcImageData() As Byte
    Dim srcSA As SAFEARRAY2D
    
    Dim srcDIB As pdDIB
    Set srcDIB = New pdDIB
    srcDIB.CreateFromExistingDIB workingDIB
    
    PrepSafeArray srcSA, srcDIB
    CopyMemory ByVal VarPtrArray(srcImageData()), VarPtr(srcSA), 4
        
    'Tile size is simply a ratio of the current smallest dimension in the image
    If (curDIBValues.Width < curDIBValues.Height) Then
        tileSize = Int(CDbl(tileSize * curDIBValues.Width) * 0.005)
    Else
        tileSize = Int(CDbl(tileSize * curDIBValues.Height) * 0.005)
    End If
    
    If (tileSize < 1) Then tileSize = 1
                    
    'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
    Dim x As Long, y As Long, initX As Long, initY As Long, finalX As Long, finalY As Long
    initX = curDIBValues.Left
    initY = curDIBValues.Top
    finalX = curDIBValues.Right
    finalY = curDIBValues.Bottom
            
    'These values will help us access locations in the array more quickly.
    ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
    Dim quickVal As Long, qvDepth As Long
    qvDepth = curDIBValues.BytesPerPixel
    
    'Create a filter support class, which will aid with edge handling and interpolation
    Dim fSupport As pdFilterSupport
    Set fSupport = New pdFilterSupport
    fSupport.SetDistortParameters qvDepth, edgeHandling, (superSamplingAmount <> 1), curDIBValues.maxX, curDIBValues.maxY
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    progBarCheck = ProgressBars.FindBestProgBarValue()
    
    '***************************************
    ' /* BEGIN SUPERSAMPLING PREPARATION */
    
    'Due to the way this filter works, supersampling yields much better results.  Because supersampling is extremely
    ' energy-intensive, this tool uses a sliding value for quality, as opposed to a binary TRUE/FALSE for antialiasing.
    ' (For all but the lowest quality setting, antialiasing will be used, and higher quality values will simply increase
    '  the amount of supersamples taken.)
    Dim newR As Long, newG As Long, newB As Long, newA As Long
    Dim r As Long, g As Long, b As Long, a As Long
    Dim tmpSum As Long, tmpSumFirst As Long
    
    'Use the passed super-sampling constant (displayed to the user as "quality") to come up with a number of actual
    ' pixels to sample.  (The total amount of sampled pixels will range from 1 to 13).  Note that supersampling
    ' coordinates are precalculated and cached using a modified rotated grid function, which is consistent throughout PD.
    Dim numSamples As Long
    Dim ssX() As Single, ssY() As Single
    Filters_Area.GetSupersamplingTable superSamplingAmount, numSamples, ssX, ssY
    
    'Because supersampling will be used in the inner loop as (samplecount - 1), permanently decrease the sample
    ' count in advance.
    numSamples = numSamples - 1
    
    'Additional variables are needed for supersampling handling
    Dim j As Double, k As Double
    Dim sampleIndex As Long, numSamplesUsed As Long
    Dim superSampleVerify As Long, ssVerificationLimit As Long
    
    'Adaptive supersampling allows us to bypass supersampling if a pixel doesn't appear to benefit from it.  The superSampleVerify
    ' variable controls how many pixels are sampled before we perform an adaptation check.  At present, the rule is:
    ' Quality 3: check a minimum of 2 samples, Quality 4: check minimum 3 samples, Quality 5: check minimum 4 samples
    superSampleVerify = superSamplingAmount - 2
    
    'Alongside a variable number of test samples, adaptive supersampling requires some threshold that indicates samples
    ' are close enough that further supersampling is unlikely to improve output.  We calculate this as a minimum variance
    ' as 1.5 per channel (for a total of 6 variance per pixel), multiplied by the total number of samples taken.
    ssVerificationLimit = superSampleVerify * 6
    
    'To improve performance for quality 1 and 2 (which perform no supersampling), we can forcibly disable supersample checks
    ' by setting the verification checker to some impossible value.
    If (superSampleVerify <= 0) Then superSampleVerify = LONG_MAX
    
    ' /* END SUPERSAMPLING PREPARATION */
    '*************************************
    
    'Convert angles to radians
    Dim cachedSin As Double, cachedCos As Double
    cachedSin = Sin(tileAngle * (PI / 180#))
    cachedCos = Cos(tileAngle * (PI / 180#))
    
    'Calculate scale and curvature values
    Dim tileScaleAdjustment As Double, tmpCurvature As Double
    tileScaleAdjustment = PI / tileSize
    
    If (tileCurvature = 0#) Then tileCurvature = 0.1
    tmpCurvature = tileCurvature * (tileCurvature * 0.1) * (Abs(tileCurvature) / tileCurvature)
    
    'Filter algorithm variables
    Dim srcX As Double, srcY As Double
    Dim u As Double, v As Double, s As Double, t As Double
    
    'Calculate the center of the image
    Dim midX As Double, midY As Double
    midX = CDbl(finalX - initX) * 0.5
    midX = midX + initX
    midY = CDbl(finalY - initY) * 0.5
    midY = midY + initY
    
    Dim avgSamples As Double
        
    'Loop through each pixel in the image, converting values as we go
    For x = initX To finalX
        quickVal = x * qvDepth
    For y = initY To finalY
        
        'Reset all supersampling values
        newR = 0
        newG = 0
        newB = 0
        newA = 0
        numSamplesUsed = 0
        
        'Remap the coordinates around a center point of (0, 0)
        j = x - midX
        k = y - midY
        
        'Sample a number of source pixels corresponding to the user's supplied quality value; more quality means
        ' more samples, and much better representation in the final output.
        For sampleIndex = 0 To numSamples
        
            'Offset the pixel amount by the supersampling lookup table
            u = j + ssX(sampleIndex)
            v = k - ssY(sampleIndex)
            
            'Use magical math to calculate a glass tile effect
            s = (cachedCos * u) + (cachedSin * v)
            t = (-cachedSin * u) + (cachedCos * v)
            
            s = s + tmpCurvature * Tan(s * tileScaleAdjustment)
            t = t + tmpCurvature * Tan(t * tileScaleAdjustment)
            
            u = (cachedCos * s) - (cachedSin * t)
            v = (cachedSin * s) + (cachedCos * t)
            
            'Map the calculated sample locations relative to the top-left corner of the image
            srcX = midX + u
            srcY = midY + v
            
            'Use the filter support class to interpolate and edge-wrap pixels as necessary
            fSupport.GetColorsFromSource r, g, b, a, srcX, srcY, srcImageData, x, y
            
            'If adaptive supersampling is active, apply the "adaptive" aspect.  Basically, calculate a variance for the currently
            ' collected samples.  If variance is low, assume this pixel does not require further supersampling.
            ' (Note that this is an ugly shorthand way to calculate variance, but it's fast, and the chance of false outliers is
            '  small enough to make it preferable over a true variance calculation.)
            If (sampleIndex = superSampleVerify) Then
                
                'Calculate variance for the first two pixels (Q3), three pixels (Q4), or four pixels (Q5)
                tmpSum = (r + g + b + a) * superSampleVerify
                tmpSumFirst = newR + newG + newB + newA
                
                'If variance is below 1.5 per channel per pixel, abort further supersampling
                If (Abs(tmpSum - tmpSumFirst) < ssVerificationLimit) Then Exit For
            
            End If
            
            'Increase the sample count
            numSamplesUsed = numSamplesUsed + 1
            
            'Add the retrieved values to our running averages
            newR = newR + r
            newG = newG + g
            newB = newB + b
            newA = newA + a
            
        Next sampleIndex
        
        'Find the average values of all samples, apply to the pixel, and move on!
        avgSamples = 1# / numSamplesUsed
        newR = newR * avgSamples
        newG = newG * avgSamples
        newB = newB * avgSamples
        newA = newA * avgSamples
        
        dstImageData(quickVal, y) = newB
        dstImageData(quickVal + 1, y) = newG
        dstImageData(quickVal + 2, y) = newR
        dstImageData(quickVal + 3, y) = newA
        
    Next y
        If Not toPreview Then
            If (x And progBarCheck) = 0 Then
                If UserPressedESC() Then Exit For
                SetProgBarVal x
            End If
        End If
    Next x
    
    'Safely deallocate all pixel arrays
    CopyMemory ByVal VarPtrArray(srcImageData), 0&, 4
    CopyMemory ByVal VarPtrArray(dstImageData), 0&, 4
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    EffectPrep.FinalizeImageData toPreview, dstPic
    
End Sub

Private Sub cboEdges_Click()
    UpdatePreview
End Sub

Private Sub cmdBar_OKClick()
    Process "Glass tiles", , GetLocalParamString(), UNDO_LAYER
End Sub

Private Sub cmdBar_RequestPreviewUpdate()
    UpdatePreview
End Sub

Private Sub cmdBar_ResetClick()
    sltAngle.Value = 45
    sltSize.Value = 40
    sltCurvature.Value = 8
    sltQuality.Value = 2
    cboEdges.ListIndex = EDGE_CLAMP
End Sub

Private Sub Form_Load()

    'Disable previewing until the form has been fully initialized
    cmdBar.MarkPreviewStatus False
    
    'I use a central function to populate the edge handling combo box; this way, I can add new methods and have
    ' them immediately available to all distort functions.
    PopDistortEdgeBox cboEdges, EDGE_CLAMP
    
    'Apply translations and visual themes
    ApplyThemeAndTranslations Me
    cmdBar.MarkPreviewStatus True
    UpdatePreview
    
End Sub

Private Sub Form_Unload(Cancel As Integer)
    ReleaseFormTheming Me
End Sub

Private Sub sltAngle_Change()
    UpdatePreview
End Sub

Private Sub sltCurvature_Change()
    UpdatePreview
End Sub

Private Sub sltQuality_Change()
    UpdatePreview
End Sub

Private Sub sltSize_Change()
    UpdatePreview
End Sub

Private Sub UpdatePreview()
    If cmdBar.PreviewsAllowed Then Me.GlassTiles GetLocalParamString(), True, pdFxPreview
End Sub

'If the user changes the position and/or zoom of the preview viewport, the entire preview must be redrawn.
Private Sub pdFxPreview_ViewportChanged()
    UpdatePreview
End Sub

Private Function GetLocalParamString() As String
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    
    With cParams
        .AddParam "size", sltSize.Value
        .AddParam "curvature", sltCurvature.Value
        .AddParam "angle", sltAngle.Value
        .AddParam "quality", sltQuality.Value
        .AddParam "edges", cboEdges.ListIndex
    End With
    
    GetLocalParamString = cParams.GetParamString()
    
End Function
