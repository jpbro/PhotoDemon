VERSION 5.00
Begin VB.Form FormExposure 
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   "Exposure"
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
   Begin VB.PictureBox picChart 
      Appearance      =   0  'Flat
      AutoRedraw      =   -1  'True
      BackColor       =   &H80000005&
      ForeColor       =   &H80000008&
      Height          =   2415
      Left            =   8400
      ScaleHeight     =   159
      ScaleMode       =   3  'Pixel
      ScaleWidth      =   223
      TabIndex        =   3
      Top             =   240
      Width           =   3375
   End
   Begin PhotoDemon.pdSlider sltExposure 
      Height          =   705
      Left            =   6000
      TabIndex        =   2
      Top             =   2880
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "exposure compensation (stops)"
      Min             =   -5
      Max             =   5
      SigDigits       =   2
      SliderTrackStyle=   2
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
   Begin PhotoDemon.pdSlider sltOffset 
      Height          =   705
      Left            =   6000
      TabIndex        =   5
      Top             =   3720
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "offset"
      Min             =   -1
      Max             =   1
      SigDigits       =   2
   End
   Begin PhotoDemon.pdSlider sltGamma 
      Height          =   705
      Left            =   6000
      TabIndex        =   4
      Top             =   4560
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "gamma"
      Min             =   0.01
      Max             =   2
      SigDigits       =   2
      Value           =   1
      NotchPosition   =   2
      NotchValueCustom=   1
   End
   Begin PhotoDemon.pdLabel lblTitle 
      Height          =   1005
      Index           =   2
      Left            =   6000
      Top             =   1320
      Width           =   2220
      _ExtentX        =   0
      _ExtentY        =   0
      Caption         =   "new exposure curve:"
      FontSize        =   12
      ForeColor       =   4210752
      Layout          =   1
   End
End
Attribute VB_Name = "FormExposure"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'Exposure Dialog
'Copyright 2013-2017 by Tanner Helland, first build Copyright 2013 Audioglider
'Created: 13/July/13
'Last updated: 20/July/17
'Last update: migrate to XML params, minor optimizations
'
'Basic image exposure adjustment dialog.  Exposure is a complex topic in photography, and (obviously) the best way to
' adjust it is at image capture time.  This is because true exposure relies on a number of variables (see
' http://en.wikipedia.org/wiki/Exposure_%28photography%29) inherent in the scene itself, with a technical definition
' of "the accumulated physical quantity of visible light energy applied to a surface during a given exposure time."
' Once a set amount of light energy has been applied to a digital sensor and the resulting photo is captured, actual
' exposure can never fully be corrected or adjusted in post-production.
'
'That said, in the event that a poor choice is made at time of photography, certain approximate adjustments can be
' applied in post-production, with the understanding that missing shadows and highlights cannot be "magically"
' recreated out of thin air.  This is done by approximating an EV adjustment using a simple power-of-two formula.
' For more information on exposure compensation, see
' http://en.wikipedia.org/wiki/Exposure_value#Exposure_compensation_in_EV
'
'Also, I have mixed feelings about dumping brightness and gamma corrections on this dialog, but Photoshop does it,
' so we may as well, too.  (They can always be ignored if you just want "pure" exposure correction.)
'
'Thank you to Audioglider for contributing the first version of this tool to PhotoDemon.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'Adjust an image's exposure.
' PRIMARY INPUT: exposureAdjust represents the number of stops to correct the image.  Each stop corresponds to a power-of-2
'                 increase (+values) or decrease (-values) in luminance.  Thus an EV of -1 will cut the amount of light in
'                 half, while an EV of +1 will double the amount of light.
Public Sub Exposure(ByVal effectParams As String, Optional ByVal toPreview As Boolean = False, Optional ByRef dstPic As pdFxPreviewCtl)
    
    If (Not toPreview) Then Message "Adjusting image exposure..."
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString effectParams
    
    Dim exposureAdjust As Double, offsetAdjust As Double, gammaAdjust As Double
    exposureAdjust = cParams.GetDouble("exposure", 0#)
    offsetAdjust = cParams.GetDouble("offset", 0#)
    gammaAdjust = cParams.GetDouble("gamma", 1#)
    
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
    Dim qvDepth As Long
    qvDepth = curDIBValues.BytesPerPixel
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    If (Not toPreview) Then ProgressBars.SetProgBarMax finalY
    progBarCheck = ProgressBars.FindBestProgBarValue()
    
    Dim r As Long, g As Long, b As Long
    
    'Exposure can be easily applied using a look-up table
    Dim gLookup(0 To 255) As Byte
    For x = 0 To 255
        gLookup(x) = GetCorrectedValue(x, 255, exposureAdjust, offsetAdjust, gammaAdjust)
    Next x
    
    'Loop through each pixel in the image, converting values as we go
    initX = initX * qvDepth
    finalX = finalX * qvDepth
    
    For y = initY To finalY
    For x = initX To finalX Step qvDepth
        
        'Get the source pixel color values
        b = imageData(x, y)
        g = imageData(x + 1, y)
        r = imageData(x + 2, y)
        
        'Apply a new value based on the lookup table
        imageData(x, y) = gLookup(b)
        imageData(x + 1, y) = gLookup(g)
        imageData(x + 2, y) = gLookup(r)
        
    Next x
        If (Not toPreview) Then
            If (y And progBarCheck) = 0 Then
                If Interface.UserPressedESC() Then Exit For
                SetProgBarVal y
            End If
        End If
    Next y
    
    'Safely deallocate imageData()
    CopyMemory ByVal VarPtrArray(imageData), 0&, 4
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    EffectPrep.FinalizeImageData toPreview, dstPic

End Sub

Private Function GetCorrectedValue(ByVal inputVal As Single, ByVal inputMax As Single, ByVal newExposure As Single, ByVal newOffset As Single, ByVal newGamma As Single) As Double
    
    Dim tmpCalculation As Double
    
    'Convert incoming value to the [0, 1] scale
    tmpCalculation = inputVal / inputMax
    
    'Apply exposure (simple power-of-two calculation)
    tmpCalculation = tmpCalculation * 2# ^ (newExposure)
    
    'Apply offset (brightness)
    tmpCalculation = tmpCalculation + newOffset
    
    'Apply gamma
    If (newGamma < 0.01) Then newGamma = 0.01
    If (tmpCalculation > 0#) Then tmpCalculation = tmpCalculation ^ (1# / newGamma)
    
    'Return to the original [0, inputMax] scale
    tmpCalculation = tmpCalculation * inputMax
    
    'Apply clipping
    If (tmpCalculation < 0#) Then tmpCalculation = 0#
    If (tmpCalculation > inputMax) Then tmpCalculation = inputMax
    
    GetCorrectedValue = tmpCalculation
    
End Function

Private Sub cmdBar_OKClick()
    Process "Exposure", , GetLocalParamString(), UNDO_Layer
End Sub

Private Sub cmdBar_RequestPreviewUpdate()
    UpdatePreview
End Sub

Private Sub cmdBar_ResetClick()
    sltGamma.Value = 1#
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

'Redrawing a preview of the exposure effect also redraws the exposure curve (which isn't really a curve, but oh well)
'TODO: rewrite this sub against pd2D
Private Sub UpdatePreview()
    
    If cmdBar.PreviewsAllowed And sltExposure.IsValid And sltOffset.IsValid And sltGamma.IsValid Then
    
        Dim prevX As Double, prevY As Double
        Dim curX As Double, curY As Double
        Dim x As Long
        
        Dim xWidth As Long, yHeight As Long
        xWidth = picChart.ScaleWidth
        yHeight = picChart.ScaleHeight
            
        'Clear out the old chart and draw a gray line across the diagonal for reference
        picChart.Picture = LoadPicture("")
        picChart.ForeColor = RGB(127, 127, 127)
        GDIPlusDrawLineToDC picChart.hDC, 0, yHeight, xWidth, 0, RGB(127, 127, 127)
        
        'Draw the corresponding exposure curve (line, actually) for this EV
        Dim expVal As Double, offsetVal As Double, gammaVal As Double, tmpVal As Double
        expVal = sltExposure
        offsetVal = sltOffset
        gammaVal = sltGamma
        
        picChart.ForeColor = RGB(0, 0, 255)
        
        prevX = 0
        prevY = yHeight
        curX = 0
        curY = yHeight
        
        For x = 0 To xWidth
            
            'Get the corrected, clamped exposure value
            tmpVal = GetCorrectedValue(x, xWidth, expVal, offsetVal, gammaVal)
            
            'Because the picture box is not square, we also need to multiply the value by the picture box's aspect ratio
            tmpVal = tmpVal * (yHeight / xWidth)
            
            'Invert this final value, because screen coordinates are upside-down
            tmpVal = yHeight - tmpVal
            
            'Draw a line between this point and the previous one, then move on to the next point
            curY = tmpVal
            curX = x
            If x = 0 Then prevY = curY
            If curY > yHeight - 1 Then curY = yHeight - 1
            
            GDIPlusDrawLineToDC picChart.hDC, prevX, prevY, curX, curY, picChart.ForeColor
            
            prevX = curX
            prevY = curY
            
        Next x
        
        picChart.Picture = picChart.Image
        picChart.Refresh
    
        'Finally, apply the exposure correction to the preview image
        Me.Exposure GetLocalParamString(), True, pdFxPreview
        
    End If
    
End Sub

'If the user changes the position and/or zoom of the preview viewport, the entire preview must be redrawn.
Private Sub pdFxPreview_ViewportChanged()
    UpdatePreview
End Sub

'Update the preview whenever the combination slider/text control has its value changed
Private Sub sltExposure_Change()
    UpdatePreview
End Sub

Private Sub sltGamma_Change()
    UpdatePreview
End Sub

Private Sub sltOffset_Change()
    UpdatePreview
End Sub

Private Function GetLocalParamString() As String
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    
    With cParams
        .AddParam "exposure", sltExposure
        .AddParam "offset", sltOffset
        .AddParam "gamma", sltGamma
    End With
    
    GetLocalParamString = cParams.GetParamString()
    
End Function
