VERSION 5.00
Begin VB.Form FormFiguredGlass 
   AutoRedraw      =   -1  'True
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   " Figured glass"
   ClientHeight    =   6555
   ClientLeft      =   -15
   ClientTop       =   225
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
   ScaleHeight     =   437
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   806
   ShowInTaskbar   =   0   'False
   Begin PhotoDemon.pdDropDown cboEdges 
      Height          =   735
      Left            =   6000
      TabIndex        =   2
      Top             =   4080
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1296
      Caption         =   "if pixels lie outside the image..."
   End
   Begin PhotoDemon.pdCommandBar cmdBar 
      Align           =   2  'Align Bottom
      Height          =   750
      Left            =   0
      TabIndex        =   0
      Top             =   5805
      Width           =   12090
      _ExtentX        =   21325
      _ExtentY        =   1323
   End
   Begin PhotoDemon.pdSlider sltScale 
      Height          =   705
      Left            =   6000
      TabIndex        =   3
      Top             =   840
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "scale"
      Max             =   100
      SigDigits       =   1
      Value           =   10
      DefaultValue    =   10
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
   Begin PhotoDemon.pdSlider sltTurbulence 
      Height          =   705
      Left            =   6000
      TabIndex        =   4
      Top             =   1920
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "turbulence"
      Max             =   1
      SigDigits       =   2
      Value           =   0.5
      DefaultValue    =   0.5
   End
   Begin PhotoDemon.pdSlider sltQuality 
      Height          =   705
      Left            =   6000
      TabIndex        =   5
      Top             =   3000
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
End
Attribute VB_Name = "FormFiguredGlass"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'Image "Figured Glass" Distortion
'Copyright 2013-2017 by Tanner Helland
'Created: 08/January/13
'Last updated: 26/July/17
'Last update: performance optimizations (10+% time reduction), convert to XML params
'
'This tool allows the user to apply a distort operation to an image that mimicks seeing it through warped glass, perhaps
' glass tiles of some sort.  Many different names are used for this effect - Paint.NET calls it "dents" (which I quite
' dislike); other software calls it "marbling".  I chose figured glass because it's an actual type of uneven glass - see:
' http://en.wikipedia.org/wiki/Architectural_glass#Rolled_plate_.28figured.29_glass
'
'As with other distorts in the program, bilinear interpolation (via reverse-mapping) and optional supersampling are
' available for those who desire very a high-quality transformation.
'
'Unlike other distorts, no radius is required for this effect.  It always operates on the entire image/selection.
'
'Finally, the transformation used by this tool is a modified version of a transformation originally written by
' Jerry Huxtable of JH Labs.  Jerry's original code is licensed under an Apache 2.0 license.  You may download his
' original version at the following link (good as of 07 January '13): http://www.jhlabs.com/ip/filters/index.html
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

Private m_Random As pdRandomize

Private Sub cboEdges_Click()
    UpdatePreview
End Sub

'Apply a "figured glass" effect to an image
Public Sub FiguredGlassFX(ByVal effectParams As String, Optional ByVal toPreview As Boolean = False, Optional ByRef dstPic As pdFxPreviewCtl)

    If (Not toPreview) Then Message "Projecting image through simulated glass..."
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString effectParams
    
    Dim fxScale As Double, fxTurbulence As Double, edgeHandling As Long, superSamplingAmount As Long
    
    With cParams
        fxScale = .GetDouble("scale", sltScale.Value)
        fxTurbulence = .GetDouble("turbulence", sltTurbulence.Value)
        superSamplingAmount = .GetLong("quality", sltQuality.Value)
        edgeHandling = .GetLong("edges", cboEdges.ListIndex)
    End With
    
    'Create a local array and point it at the pixel data of the current image
    Dim dstImageData() As Byte
    Dim dstSA As SafeArray2D
    EffectPrep.PrepImageData dstSA, toPreview, dstPic
    CopyMemory ByVal VarPtrArray(dstImageData()), VarPtr(dstSA), 4
    
    'Create a second local array.  This will contain the a copy of the current image, and we will use it as our source reference
    ' (This is necessary to prevent diffused pixels from spreading across the image as we go.)
    Dim srcImageData() As Byte
    Dim srcSA As SafeArray2D
    
    Dim srcDIB As pdDIB
    Set srcDIB = New pdDIB
    srcDIB.CreateFromExistingDIB workingDIB
    
    PrepSafeArray srcSA, srcDIB
    CopyMemory ByVal VarPtrArray(srcImageData()), VarPtr(srcSA), 4
        
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
    
    'During a preview, shrink the scale so that the preview accurately reflects how the final image will appear
    'If toPreview Then fxScale = fxScale * curDIBValues.previewModifier
    
    'Scale is used as a fraction of the image's smallest dimension.  There's no problem with using larger
    ' values, but at some point it distorts the image beyond recognition.
    If (curDIBValues.Width > curDIBValues.Height) Then
        fxScale = (fxScale / 100) * curDIBValues.Height
    Else
        fxScale = (fxScale / 100) * curDIBValues.Width
    End If
    
    Dim invScale As Double
    If (fxScale <> 0#) Then invScale = 1# / fxScale Else invScale = 1#
    
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
    
    'Source X and Y values, which may or may not be used as part of a bilinear interpolation function
    Dim srcX As Double, srcY As Double
    
    'pdNoise is used to calculate repeatable noise
    Dim cNoise As pdNoise
    Set cNoise = New pdNoise
    
    'To generate "random" values despite using a fixed 2D noise generator, we calculate random offsets
    ' into the "infinite grid" of possible noise values.  This yields (perceptually) random results.
    Dim rndOffsetX As Double, rndOffsetY As Double
    If (m_Random Is Nothing) Then
        Set m_Random = New pdRandomize
        m_Random.SetSeed_AutomaticAndRandom
    Else
        m_Random.SetSeed_Float m_Random.GetSeed()
    End If

    rndOffsetX = m_Random.GetRandomFloat_WH * 10000000# - 5000000#
    rndOffsetY = m_Random.GetRandomFloat_WH * 10000000# - 5000000#
    
    'Finally, an integer displacement will be used to move pixel values around.  (Note that these use a
    ' "Perlin" nomenclature, but we have since moved onto better noise generation methods.)
    Dim perlinCacheSin As Double, perlinCacheCos As Double, pNoiseCache As Double
    
    Dim multAvg As Double
    
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
        
        'Sample a number of source pixels corresponding to the user's supplied quality value; more quality means
        ' more samples, and much better representation in the final output.
        For sampleIndex = 0 To numSamples
            
            'Offset the pixel amount by the supersampling lookup table
            j = x + ssX(sampleIndex)
            k = y + ssY(sampleIndex)
            
            'Calculate a displacement for this point, using a fixed 2D noise function as the basis,
            ' but modifying it per the user's turbulence value.
            If (fxScale > 0#) Then
                pNoiseCache = PI_DOUBLE * fxTurbulence * cNoise.OpenSimplexNoise2d(rndOffsetX + j * invScale, rndOffsetY + k * invScale)
                perlinCacheSin = Sin(pNoiseCache) * fxScale
                perlinCacheCos = Cos(pNoiseCache) * fxScale * fxTurbulence
            Else
                perlinCacheSin = 0#
                perlinCacheCos = 0#
            End If
            
            'Use the sine of the displacement to calculate a unique source pixel position.  (Sine improves the roundness
            ' of the conversion, but technically it would work fine without an additional modifier due to the way
            ' fixed noise is generated.)
            srcX = j + perlinCacheSin
            srcY = k + perlinCacheCos
            
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
        multAvg = 1# / numSamplesUsed
        newR = newR * multAvg
        newG = newG * multAvg
        newB = newB * multAvg
        newA = newA * multAvg
        
        dstImageData(quickVal, y) = newB
        dstImageData(quickVal + 1, y) = newG
        dstImageData(quickVal + 2, y) = newR
        dstImageData(quickVal + 3, y) = newA
                
    Next y
        If (Not toPreview) Then
            If (x And progBarCheck) = 0 Then
                If Interface.UserPressedESC() Then Exit For
                SetProgBarVal x
            End If
        End If
    Next x
    
    'Safely deallocate all image arrays
    CopyMemory ByVal VarPtrArray(srcImageData), 0&, 4
    CopyMemory ByVal VarPtrArray(dstImageData), 0&, 4
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    EffectPrep.FinalizeImageData toPreview, dstPic
        
End Sub

Private Sub cmdBar_OKClick()
    Process "Figured glass", , GetLocalParamString(), UNDO_Layer
End Sub

Private Sub cmdBar_RequestPreviewUpdate()
    UpdatePreview
End Sub

Private Sub cmdBar_ResetClick()

    'Set the edge handler to match the default in Form_Load
    cboEdges.ListIndex = 1
    sltScale.Value = 10#
    sltTurbulence.Value = 0.5
    sltQuality.Value = 2
    m_Random.SetSeed_AutomaticAndRandom

End Sub

Private Sub Form_Load()

    'Disable previews
    cmdBar.MarkPreviewStatus False
    
    'Calculate a random z offset for the noise function
    Set m_Random = New pdRandomize
    m_Random.SetSeed_AutomaticAndRandom
    
    'I use a central function to populate the edge handling combo box; this way, I can add new methods and have
    ' them immediately available to all distort functions.
    PopDistortEdgeBox cboEdges, EDGE_REFLECT
    
    'Apply translations and visual themes
    ApplyThemeAndTranslations Me
    cmdBar.MarkPreviewStatus True
    UpdatePreview
    
End Sub

Private Sub Form_Unload(Cancel As Integer)
    ReleaseFormTheming Me
End Sub

Private Sub sltQuality_Change()
    UpdatePreview
End Sub

Private Sub sltScale_Change()
    UpdatePreview
End Sub

Private Sub sltTurbulence_Change()
    UpdatePreview
End Sub

'Redraw the on-screen preview of the transformed image
Private Sub UpdatePreview()
    If cmdBar.PreviewsAllowed Then Me.FiguredGlassFX GetLocalParamString(), True, pdFxPreview
End Sub

'If the user changes the position and/or zoom of the preview viewport, the entire preview must be redrawn.
Private Sub pdFxPreview_ViewportChanged()
    UpdatePreview
End Sub

Private Function GetLocalParamString() As String
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    
    With cParams
        .AddParam "scale", sltScale.Value
        .AddParam "turbulence", sltTurbulence.Value
        .AddParam "quality", sltQuality.Value
        .AddParam "edges", cboEdges.ListIndex
    End With
    
    GetLocalParamString = cParams.GetParamString()
    
End Function
