VERSION 5.00
Begin VB.Form FormMiscDistorts 
   AutoRedraw      =   -1  'True
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   " Miscellaneous Distort Tools"
   ClientHeight    =   6540
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
   ScaleHeight     =   436
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   806
   ShowInTaskbar   =   0   'False
   Begin PhotoDemon.pdListBox lstDistorts 
      Height          =   3015
      Left            =   6000
      TabIndex        =   4
      Top             =   120
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   5318
      Caption         =   "distortions"
   End
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
   Begin PhotoDemon.pdFxPreviewCtl pdFxPreview 
      Height          =   5625
      Left            =   120
      TabIndex        =   2
      Top             =   120
      Width           =   5625
      _ExtentX        =   9922
      _ExtentY        =   9922
   End
   Begin PhotoDemon.pdSlider sltQuality 
      Height          =   705
      Left            =   6000
      TabIndex        =   1
      Top             =   3360
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
      Height          =   855
      Left            =   6000
      TabIndex        =   3
      Top             =   4320
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1508
      Caption         =   "if pixels lie outside the corrected area..."
   End
End
Attribute VB_Name = "FormMiscDistorts"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'Miscellaneous Distort Tools
'Copyright 2013-2017 by Tanner Helland
'Created: 07/June/13
'Last updated: 27/July/17
'Last update: performance improvements, migrate to XML params
'
'Some one-off distorts (e.g. no tunable parameters) are useful under very specific circumstances.  However, it is
' impractical to give every such tool its own menu entry, so all non-tunable distorts are being placed here from
' now on.
'
'Bilinear interpolation is available to improve output quality.
'
'Certain transformations aer modified versions of basic math originally shared by Paul Bourke. You can see Paul's
' original (and very helpful article) at the following link, good as of 07 June '13:
' http://paulbourke.net/miscellaneous/imagewarp/
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'Correct lens distortion in an image
Public Sub ApplyMiscDistort(ByVal effectParams As String, Optional ByVal toPreview As Boolean = False, Optional ByRef dstPic As pdFxPreviewCtl)
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString effectParams
    
    Dim distortName As String, distortStyle As Long, edgeHandling As Long, superSamplingAmount As Long
    
    With cParams
        distortName = .GetString("name", lstDistorts.List(lstDistorts.ListIndex))
        distortStyle = .GetLong("type", lstDistorts.ListIndex)
        edgeHandling = .GetLong("edges", cboEdges.ListIndex)
        superSamplingAmount = .GetLong("quality", sltQuality.Value)
    End With
    
    If (Not toPreview) Then Message "Applying %1 distortion...", distortName
    
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
    
    'Calculate the center of the image
    Dim midX As Double, midY As Double
    midX = CDbl(finalX - initX) / 2
    midX = midX + initX
    midY = CDbl(finalY - initY) / 2
    midY = midY + initY
    
    'Rotation values
    Dim theta As Double, radius As Double
    
    'X and Y values, remapped around a center point of (0, 0)
    Dim nX As Double, nY As Double
    
    'Source X and Y values, which may or may not be used as part of a bilinear interpolation function
    Dim srcX As Double, srcY As Double
        
    'Max radius is calculated as the distance from the center of the image to a corner
    Dim tWidth As Long, tHeight As Long
    tWidth = curDIBValues.Width
    tHeight = curDIBValues.Height
    
    'Because coordinates will be mapped identically for each x-coord and y-coord, we can calculate them in advance
    ' and store them in lookup tables to improve performance.
    Dim xCoords() As Double, yCoords() As Double
    ReDim xCoords(initX To finalX) As Double
    ReDim yCoords(initY To finalY) As Double
    
    'Basically, we want to remap coordinates around a center point of (0, 0), and normalize them to (-1, 1).
    ' This makes distort strength uniform regardless of image size.
    For x = initX To finalX
        xCoords(x) = (2 * x) / tWidth - 1
    Next x
    
    For y = initY To finalY
        yCoords(y) = (2 * y) / tHeight - 1
    Next y
    
    'Do the same thing for our supersampling coordinates
    For sampleIndex = 0 To numSamples
        ssX(sampleIndex) = ssX(sampleIndex) / tWidth
        ssY(sampleIndex) = ssY(sampleIndex) / tHeight
    Next sampleIndex
    
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
        
        'Pull coordinates from the lookup table
        j = xCoords(x)
        k = yCoords(y)
        
        'Sample a number of source pixels corresponding to the user's supplied quality value; more quality means
        ' more samples, and much better representation in the final output.
        For sampleIndex = 0 To numSamples
            
            'Offset the pixel amount by the supersampling lookup table
            nX = j + ssX(sampleIndex)
            nY = k + ssY(sampleIndex)
            
            'Next, map them to polar coordinates
            radius = Sqr(nX * nX + nY * nY)
            theta = PDMath.Atan2_Fastest(nY, nX)
            
            'Emphasize center
            If (distortStyle = 0) Then
                nX = 2 * Asin(nX) / PI
                nY = 2 * Asin(nY) / PI
                
            'Flatten corners
            ElseIf (distortStyle = 1) Then
                nX = Sin(nX)
                nY = Sin(nY)
                    
            'Inside-out
            ElseIf (distortStyle = 2) Then
                If (radius > 0#) Then radius = 1# - radius Else radius = -1# - radius
                nX = radius * Cos(theta)
                nY = radius * Sin(theta)
                
            'Pull in
            ElseIf (distortStyle = 3) Then
                radius = Sqr(radius)
                nX = radius * Cos(theta)
                nY = radius * Sin(theta)
                
            'Push out
            ElseIf (distortStyle = 4) Then
                radius = radius * radius
                nX = radius * Cos(theta)
                nY = radius * Sin(theta)
                
            'Rounding
            ElseIf (distortStyle = 5) Then
                If (nX < 0#) Then nX = -1# * nX * nX Else nX = nX * nX
                If (nY < 0#) Then nY = -1# * nY * nY Else nY = nY * nY
            
            'Twist edges
            ElseIf (distortStyle = 6) Then
                radius = Sin(PI * radius * 0.5)
                nX = radius * Cos(theta)
                nY = radius * Sin(theta)
            
            'Wormhole
            ElseIf (distortStyle = 7) Then
                If (radius = 0#) Then radius = 0# Else radius = Sin(1# / radius)
                nX = radius * Cos(theta)
                nY = radius * Sin(theta)
                
            End If
            
            'Convert the recalculated coordinates back to the Cartesian plane
            srcX = (tWidth * (nX + 1#)) * 0.5
            srcY = (tHeight * (nY + 1#)) * 0.5
            
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
    Process "Miscellaneous distort", , GetLocalParamString(), UNDO_LAYER
End Sub

Private Sub cmdBar_RequestPreviewUpdate()
    UpdatePreview
End Sub

Private Sub cmdBar_ResetClick()
    cboEdges.ListIndex = EDGE_WRAP
    sltQuality = 2
End Sub

Private Sub Form_Load()
    
    'Disable previews while we populate various dialog controls
    cmdBar.MarkPreviewStatus False
    
    'Populate a list of available distort operations
    lstDistorts.SetAutomaticRedraws False
    lstDistorts.Clear
    lstDistorts.AddItem g_Language.TranslateMessage("emphasize center"), 0
    lstDistorts.AddItem g_Language.TranslateMessage("flatten corners"), 1
    lstDistorts.AddItem g_Language.TranslateMessage("inside-out"), 2
    lstDistorts.AddItem g_Language.TranslateMessage("pull in"), 3
    lstDistorts.AddItem g_Language.TranslateMessage("push out"), 4
    lstDistorts.AddItem g_Language.TranslateMessage("ring"), 5
    lstDistorts.AddItem g_Language.TranslateMessage("twist edges"), 6
    lstDistorts.AddItem g_Language.TranslateMessage("wormhole"), 7
    lstDistorts.ListIndex = 0
    lstDistorts.SetAutomaticRedraws True, True
    
    'I use a central function to populate the edge handling combo box; this way, I can add new methods and have
    ' them immediately available to all distort functions.
    PopDistortEdgeBox cboEdges, EDGE_WRAP
    
    'Apply translations and visual themes
    ApplyThemeAndTranslations Me
    cmdBar.MarkPreviewStatus True
    UpdatePreview
    
End Sub

Private Sub Form_Unload(Cancel As Integer)
    ReleaseFormTheming Me
End Sub

Private Sub lstDistorts_Click()
    UpdatePreview
End Sub

'Redraw the on-screen preview of the transformed image
Private Sub UpdatePreview()
    If cmdBar.PreviewsAllowed Then ApplyMiscDistort GetLocalParamString(), True, pdFxPreview
End Sub

'If the user changes the position and/or zoom of the preview viewport, the entire preview must be redrawn.
Private Sub pdFxPreview_ViewportChanged()
    UpdatePreview
End Sub

Private Sub sltQuality_Change()
    UpdatePreview
End Sub

Private Function GetLocalParamString() As String
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    
    With cParams
        .AddParam "name", lstDistorts.List(lstDistorts.ListIndex)
        .AddParam "type", lstDistorts.ListIndex
        .AddParam "edges", cboEdges.ListIndex
        .AddParam "quality", sltQuality.Value
    End With
    
    GetLocalParamString = cParams.GetParamString()
    
End Function
