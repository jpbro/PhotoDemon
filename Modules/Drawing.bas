Attribute VB_Name = "Drawing"
'***************************************************************************
'PhotoDemon Drawing Routines
'Copyright 2001-2017 by Tanner Helland
'Created: 4/3/01
'Last updated: 01/December/12
'Last update: Added DrawSystemIcon function (previously used for only the "unsaved changes" dialog
'
'Miscellaneous drawing routines that don't fit elsewhere.  At present, this includes rendering preview images,
' drawing the canvas background of image forms, and a gradient-rendering sub (used primarily on the histogram form).
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'The following Enum and two API declarations are used to draw the system information icon
Public Enum SystemIconConstants
    IDI_APPLICATION = 32512
    IDI_HAND = 32513
    IDI_QUESTION = 32514
    IDI_EXCLAMATION = 32515
    IDI_ASTERISK = 32516
    IDI_WINDOWS = 32517
End Enum

Private Declare Function LoadIconW Lib "user32" (ByVal hInstance As Long, ByVal lpIconName As Long) As Long
Private Declare Function DrawIcon Lib "user32" (ByVal hDC As Long, ByVal x As Long, ByVal y As Long, ByVal hIcon As Long) As Long

'API for converting between hWnd-specific coordinate spaces.  Note that the function technically accepts an
' array of POINTAPI points; the address passed to lpPoints should be the address of the first point in the array
' (e.g. ByRef PointArray(0)), while the cPoints parameter is the number of points in the array.  If two points are
' passed, a special Rect transform may occur on RtL systems; see http://msdn.microsoft.com/en-us/library/dd145046%28v=vs.85%29.aspx
Private Declare Function MapWindowPoints Lib "user32" (ByVal hWndFrom As Long, ByVal hWndTo As Long, ByRef lpPoints As POINTAPI, ByVal cPoints As Long) As Long

'At startup, PD caches a few different UI pens and brushes related to viewport rendering.
Private m_Painter As pd2DPainter
Private m_PenUIBase As pd2DPen, m_PenUITop As pd2DPen
Private m_PenUIBaseHighlight As pd2DPen, m_PenUITopHighlight As pd2DPen

'Given a target picture box, draw a hue preview across the horizontal axis.  This is helpful for tools that provide
' a hue slider, so that the user can easily find a color of their choosing.  Optionally, saturation and luminance
' can be provided, though it's generally assumed that those values will both be 1.0.
Public Sub DrawHueBox_HSV(ByRef dstPic As PictureBox, Optional ByVal dstSaturation As Double = 1, Optional ByVal dstLuminance As Double = 1)

    'Retrieve the picture box's dimensions
    Dim picWidth As Long, picHeight As Long
    picWidth = dstPic.ScaleWidth
    picHeight = dstPic.ScaleHeight
    
    'Use a DIB to hold the hue box before we render it on-screen.  Why?  So we can color-manage it, of course!
    Dim tmpDIB As pdDIB
    Set tmpDIB = New pdDIB
    tmpDIB.CreateBlank picWidth, picHeight, 24, 0
    
    Dim tmpR As Double, tmpG As Double, tmpB As Double
    
    'From left-to-right, draw a full hue range onto the DIB
    Dim x As Long
    For x = 0 To tmpDIB.GetDIBWidth - 1
        fHSVtoRGB x / tmpDIB.GetDIBWidth, dstSaturation, dstLuminance, tmpR, tmpG, tmpB
        GDI.DrawLineToDC tmpDIB.GetDIBDC, x, 0, x, picHeight, RGB(tmpR * 255, tmpG * 255, tmpB * 255)
    Next x
    
    'With the hue box complete, render it onto the destination picture box, with color management applied
    tmpDIB.RenderToPictureBox dstPic

End Sub

'Given a target picture box, draw a saturation preview across the horizontal axis.  This is helpful for tools that provide
' a saturation slider, so that the user can easily find a color of their choosing.  Optionally, hue and luminance can be
' provided - hue is STRONGLY recommended, but luminance can safely be assumed to be 1.0 (in most cases).
Public Sub DrawSaturationBox_HSV(ByRef dstPic As PictureBox, Optional ByVal dstHue As Double = 1, Optional ByVal dstLuminance As Double = 1)

    'Retrieve the picture box's dimensions
    Dim picWidth As Long, picHeight As Long
    picWidth = dstPic.ScaleWidth
    picHeight = dstPic.ScaleHeight
    
    'Use a DIB to hold the hue box before we render it on-screen.  Why?  So we can color-manage it, of course!
    Dim tmpDIB As pdDIB
    Set tmpDIB = New pdDIB
    tmpDIB.CreateBlank picWidth, picHeight, 24, 0
    
    Dim tmpR As Double, tmpG As Double, tmpB As Double
    
    'From left-to-right, draw a full hue range onto the DIB
    Dim x As Long
    For x = 0 To tmpDIB.GetDIBWidth - 1
        fHSVtoRGB dstHue, x / tmpDIB.GetDIBWidth, dstLuminance, tmpR, tmpG, tmpB
        GDI.DrawLineToDC tmpDIB.GetDIBDC, x, 0, x, picHeight, RGB(tmpR * 255, tmpG * 255, tmpB * 255)
    Next x
    
    'With the hue box complete, render it onto the destination picture box, with color management applied
    tmpDIB.RenderToPictureBox dstPic

End Sub

'Draw a system icon on the specified device context; this code is adopted from an example by Francesco Balena at http://www.devx.com/vb2themax/Tip/19108
Public Sub DrawSystemIcon(ByVal icon As SystemIconConstants, ByVal hDC As Long, ByVal x As Long, ByVal y As Long)
    Dim hIcon As Long
    hIcon = LoadIconW(0, icon)
    DrawIcon hDC, x, y, hIcon
End Sub

'Draw a horizontal gradient to a specified DIB from x-position xLeft to xRight.
Public Sub DrawHorizontalGradientToDIB(ByVal dstDIB As pdDIB, ByVal xLeft As Single, ByVal xRight As Single, ByVal colorLeft As Long, ByVal colorRight As Long)
    
    Dim boundsRectF As RECTF
    With boundsRectF
        .Left = (xLeft - 1)
        .Width = (xRight - xLeft) + 2
        .Top = 0
        .Height = dstDIB.GetDIBHeight
    End With
    
    Dim cSurface As pd2DSurface, cBrush As pd2DBrush
    Drawing2D.QuickCreateSurfaceFromDC cSurface, dstDIB.GetDIBDC, False
    Drawing2D.QuickCreateTwoColorGradientBrush cBrush, boundsRectF, colorLeft, colorRight
    cBrush.SetBrushGradientWrapMode P2_WM_Clamp
    
    m_Painter.FillRectangleF_FromRectF cSurface, cBrush, boundsRectF
    
End Sub

'Given a source DIB, fill it with a 2x2 alpha checkerboard pattern matching the user's current preferences.
' (The resulting DIB size is contingent on the user's checkerboard pattern size preference, FYI.)
Public Sub CreateAlphaCheckerboardDIB(ByRef srcDIB As pdDIB)

    'Retrieve the user's preferred alpha checkerboard colors, and convert the longs into individual RGB components
    Dim chkColorOne As Long, chkColorTwo As Long
    chkColorOne = g_UserPreferences.GetPref_Long("Transparency", "AlphaCheckOne", RGB(255, 255, 255))
    chkColorTwo = g_UserPreferences.GetPref_Long("Transparency", "AlphaCheckTwo", RGB(204, 204, 204))
    
    Dim r1 As Long, g1 As Long, b1 As Long
    Dim r2 As Long, g2 As Long, b2 As Long
    r1 = Colors.ExtractRed(chkColorOne)
    r2 = Colors.ExtractRed(chkColorTwo)
    g1 = Colors.ExtractGreen(chkColorOne)
    g2 = Colors.ExtractGreen(chkColorTwo)
    b1 = Colors.ExtractBlue(chkColorOne)
    b2 = Colors.ExtractBlue(chkColorTwo)
    
    'Determine a checkerboard block size based on the current user preference
    Dim chkSize As Long
    chkSize = g_UserPreferences.GetPref_Long("Transparency", "AlphaCheckSize", 1)
    
    Select Case chkSize
    
        'Small (4x4 checks)
        Case 0
            chkSize = 4
            
        'Medium (8x8 checks)
        Case 1
            chkSize = 8
        
        'Large (16x16 checks)
        Case Else
            chkSize = 16
        
    End Select
    
    'Resize the source DIB to fit a 2x2 block pattern of the requested checkerboard pattern
    srcDIB.CreateBlank chkSize * 2, chkSize * 2, 32
    
    Dim chkLookup() As Byte
    ReDim chkLookup(0 To chkSize * 2) As Byte
    Dim x As Long, y As Long
    For x = 0 To chkSize * 2
        chkLookup(x) = x \ chkSize
    Next x
    
    'Point a temporary array directly at the source DIB's bitmap bits.
    Dim srcImageData() As Byte, srcSA As SAFEARRAY2D
    srcDIB.WrapArrayAroundDIB srcImageData, srcSA
    
    'Fill the source DIB with the checkerboard pattern
    Dim chkWidth As Long
    chkWidth = srcDIB.GetDIBWidth - 1
    
    Dim xStride As Long
    For y = 0 To chkWidth
    For x = 0 To chkWidth
    
        xStride = x * 4
        
        If (((chkLookup(x) + chkLookup(y)) And 1) = 0) Then
            srcImageData(xStride, y) = b1
            srcImageData(xStride + 1, y) = g1
            srcImageData(xStride + 2, y) = r1
            srcImageData(xStride + 3, y) = 255
        Else
            srcImageData(xStride, y) = b2
            srcImageData(xStride + 1, y) = g2
            srcImageData(xStride + 2, y) = r2
            srcImageData(xStride + 3, y) = 255
        End If
        
    Next x
    Next y
    
    srcDIB.UnwrapArrayFromDIB srcImageData

End Sub

'Given an (x,y) pair on the current viewport, convert the value to coordinates on the image.
Public Function ConvertCanvasCoordsToImageCoords(ByRef srcCanvas As pdCanvas, ByRef srcImage As pdImage, ByVal canvasX As Double, ByVal canvasY As Double, ByRef imgX As Double, ByRef imgY As Double, Optional ByVal forceInBounds As Boolean = False) As Boolean

    If (Not srcImage.ImgViewport Is Nothing) Then
    
        'Get the current zoom value from the source image, then invert it.  (We're only going to use that value in division.)
        Dim zoomVal As Double
        zoomVal = 1# / g_Zoom.GetZoomValue(srcImage.GetZoom)
        
        'Get a copy of the translated image rect, in canvas coordinates.  If the canvas is a window, and the zoomed
        ' image is a poster sliding around behind it, the translate image rect contains the poster coordinates,
        ' relative to the window.  What's great about this rect is that it's already accounted for scroll bars,
        ' so we can ignore their value(s) here.
        Dim translatedImageRect As RECTF
        srcImage.ImgViewport.GetImageRectTranslated translatedImageRect
        
        'Translating the canvas coordinate pair back to the image is now easy.  Subtract the top/left offset,
        ' then divide by zoom - that's all there is to it!
        imgX = (canvasX - translatedImageRect.Left) * zoomVal
        imgY = (canvasY - translatedImageRect.Top) * zoomVal
        
        'If the caller wants the coordinates bound-checked, apply it now
        If forceInBounds Then
            If (imgX < 0) Then imgX = 0
            If (imgY < 0) Then imgY = 0
            If (imgX >= srcImage.Width - 1) Then imgX = srcImage.Width - 1
            If (imgY >= srcImage.Height - 1) Then imgY = srcImage.Height - 1
        End If
        
        ConvertCanvasCoordsToImageCoords = True
        
    Else
        ConvertCanvasCoordsToImageCoords = False
    End If
    
End Function

'Given an (x,y) pair on the current image, convert the value to coordinates on the current viewport canvas.
Public Sub ConvertImageCoordsToCanvasCoords(ByRef srcCanvas As pdCanvas, ByRef srcImage As pdImage, ByVal imgX As Double, ByVal imgY As Double, ByRef canvasX As Double, ByRef canvasY As Double, Optional ByVal forceInBounds As Boolean = False)

    If Not (srcImage.ImgViewport Is Nothing) Then
    
        'Get the current zoom value from the source image
        Dim zoomVal As Double
        zoomVal = g_Zoom.GetZoomValue(srcImage.GetZoom)
            
        'Get a copy of the translated image rect, in canvas coordinates.  If the canvas is a window, and the zoomed
        ' image is a poster sliding around behind it, the translate image rect contains the poster coordinates,
        ' relative to the window.  What's great about this rect is that it's already accounted for scroll bars,
        ' so we can ignore their value(s) here.
        Dim translatedImageRect As RECTF
        srcImage.ImgViewport.GetImageRectTranslated translatedImageRect
        
        'Translating the canvas coordinate pair back to the image is now easy.  Add the top/left offset,
        ' then multiply by zoom - that's all there is to it!
        canvasX = (imgX * zoomVal) + translatedImageRect.Left
        canvasY = (imgY * zoomVal) + translatedImageRect.Top
        
        'If the caller wants the coordinates bound-checked, apply it now
        If forceInBounds Then
        
            'Get a copy of the current viewport intersection rect, which determines bounds of this function
            Dim vIntersectRect As RECTF
            srcImage.ImgViewport.GetIntersectRectCanvas vIntersectRect
            
            If (canvasX < vIntersectRect.Left) Then canvasX = vIntersectRect.Left
            If (canvasY < vIntersectRect.Top) Then canvasY = vIntersectRect.Top
            If (canvasX >= vIntersectRect.Left + vIntersectRect.Width) Then canvasX = vIntersectRect.Left + vIntersectRect.Width - 1
            If (canvasY >= vIntersectRect.Top + vIntersectRect.Height) Then canvasY = vIntersectRect.Top + vIntersectRect.Height - 1
            
        End If
        
    End If
    
End Sub

'Given a RectF containing image-space coordinates, produce a new RectF with coordinates translated to the specified viewport canvas.
Public Sub ConvertImageCoordsToCanvasCoords_RectF(ByRef srcCanvas As pdCanvas, ByRef srcImage As pdImage, ByRef srcRectF As RECTF, ByRef dstRectF As RECTF, Optional ByVal forceInBounds As Boolean = False)

    If (Not srcImage.ImgViewport Is Nothing) Then
    
        'Get the current zoom value from the source image
        Dim zoomVal As Double
        zoomVal = g_Zoom.GetZoomValue(srcImage.GetZoom)
            
        'Get a copy of the translated image rect, in canvas coordinates.  If the canvas is a window, and the zoomed
        ' image is a poster sliding around behind it, the translate image rect contains the poster coordinates,
        ' relative to the window.  What's great about this rect is that it's already accounted for scroll bars,
        ' so we can ignore their value(s) here.
        Dim translatedImageRect As RECTF
        srcImage.ImgViewport.GetImageRectTranslated translatedImageRect
        
        'Translating the canvas coordinate pair back to the image is now easy.  Add the top/left offset,
        ' then multiply by zoom - that's all there is to it!
        dstRectF.Left = (srcRectF.Left * zoomVal) + translatedImageRect.Left
        dstRectF.Top = (srcRectF.Top * zoomVal) + translatedImageRect.Top
        
        'Width/height are even easier - just multiply by the current zoom
        dstRectF.Width = srcRectF.Width * zoomVal
        dstRectF.Height = srcRectF.Height * zoomVal
        
        'If the caller wants the coordinates bound-checked, apply them last
        If forceInBounds Then
        
            'Get a copy of the current viewport intersection rect, which determines bounds of this function
            Dim vIntersectRect As RECTF
            srcImage.ImgViewport.GetIntersectRectCanvas vIntersectRect
            
            If (dstRectF.Left < vIntersectRect.Left) Then dstRectF.Left = vIntersectRect.Left
            If (dstRectF.Top < vIntersectRect.Top) Then dstRectF.Top = vIntersectRect.Top
            If (dstRectF.Left + dstRectF.Width >= vIntersectRect.Left + vIntersectRect.Width) Then
                dstRectF.Width = (vIntersectRect.Left + vIntersectRect.Width - 1) - dstRectF.Left
                If dstRectF.Width < 0 Then dstRectF.Width = 0
            End If
            If (dstRectF.Top + dstRectF.Height >= vIntersectRect.Top + vIntersectRect.Height) Then
                dstRectF.Top = (vIntersectRect.Top + vIntersectRect.Height - 1) - dstRectF.Height
                If dstRectF.Height < 0 Then dstRectF.Height = 0
            End If
            
        End If
        
    End If
    
End Sub

'Given an (x,y) pair on the current image, convert the value to coordinates relative to the current layer.  This is especially relevant
' if the layer has one or more non-destructive affine transforms active.
Public Function ConvertImageCoordsToLayerCoords(ByRef srcImage As pdImage, ByRef srcLayer As pdLayer, ByVal imgX As Single, ByVal imgY As Single, ByRef layerX As Single, ByRef layerY As Single) As Boolean

    If (srcImage Is Nothing) Then Exit Function
    If (srcLayer Is Nothing) Then Exit Function
    
    'If the layer has one or more active affine transforms, this step becomes complicated.
    If srcLayer.AffineTransformsActive(False) Then
    
        'Create a copy of either the layer's transformation matrix, or a custom matrix if passed in
        Dim tmpMatrix As pd2DTransform
        srcLayer.GetCopyOfLayerTransformationMatrix tmpMatrix
        
        'Invert the matrix
        If tmpMatrix.InvertTransform() Then
            
            'We now need to convert the image coordinates against the layer transformation matrix
            tmpMatrix.ApplyTransformToXY imgX, imgY
            
            'In order for the matrix conversion to work, it has to offset coordinates by the current layer offset.  (Rotation is
            ' particularly important in that regard, as the center-point is crucial.)  As such, we now need to undo that translation.
            ' In rare circumstances the caller can disable this behavior, for example while transforming a layer, because the original
            ' rotation matrix must be used.
            layerX = imgX + srcLayer.GetLayerOffsetX
            layerY = imgY + srcLayer.GetLayerOffsetY
            
            ConvertImageCoordsToLayerCoords = True
        
        'If we can't invert the matrix, we're in trouble.  Copy out the layer coordinates as a failsafe.
        Else
            
            layerX = imgX
            layerY = imgY
            
            Debug.Print "WARNING! Transformation matrix could not be generated."
            
            ConvertImageCoordsToLayerCoords = False
            
        End If
    
    'If the layer doesn't have affine transforms active, this step is easy.
    Else
    
        'Layer coordinates are identical to image coordinates
        layerX = imgX
        layerY = imgY
        
        ConvertImageCoordsToLayerCoords = True
    
    End If
    
End Function

'Given an (x,y) pair on the current image, convert the value to coordinates relative to the current layer.  Note that *all*
' layer transform properties are considered (including x/y offsets, scaling, rotation, and skew).  As such, you should not
' handle any of these properties specially.
Public Function ConvertImageCoordsToLayerCoords_Full(ByRef srcImage As pdImage, ByRef srcLayer As pdLayer, ByVal imgX As Single, ByVal imgY As Single, ByRef layerX As Single, ByRef layerY As Single) As Boolean

    If (srcImage Is Nothing) Then Exit Function
    If (srcLayer Is Nothing) Then Exit Function
    
    'If the layer has one or more active affine transforms, this step becomes complicated.
    If srcLayer.AffineTransformsActive(True) Then
    
        'Create a copy of either the layer's transformation matrix, or a custom matrix if passed in
        Dim tmpMatrix As pd2DTransform
        srcLayer.GetCopyOfLayerTransformationMatrix_Full tmpMatrix
        
        'Invert the matrix
        If tmpMatrix.InvertTransform() Then
            
            'Apply the matrix to the incoming image coordinates, then return them!
            tmpMatrix.ApplyTransformToXY imgX, imgY
            layerX = imgX
            layerY = imgY
            
            ConvertImageCoordsToLayerCoords_Full = True
        
        'If we can't invert the matrix, we're in trouble.  Copy out the incoming image coordinates as a failsafe.
        Else
            
            layerX = imgX
            layerY = imgY
            
            Debug.Print "WARNING! Transformation matrix could not be generated."
            
            ConvertImageCoordsToLayerCoords_Full = False
            
        End If
    
    'If the layer doesn't have affine transforms active, this step is easy.  The only "transform" we need to consider are the
    ' layer's offsets (which may be non-zero).
    Else
        layerX = imgX - srcLayer.GetLayerOffsetX
        layerY = imgY - srcLayer.GetLayerOffsetY
        ConvertImageCoordsToLayerCoords_Full = True
    End If
    
End Function

'Given an array of (x,y) pairs set in the current image's coordinate space, convert each pair to the supplied viewport canvas space.
Public Sub ConvertListOfImageCoordsToCanvasCoords(ByRef srcCanvas As pdCanvas, ByRef srcImage As pdImage, ByRef listOfPoints() As POINTFLOAT, Optional ByVal forceInBounds As Boolean = False)

    If (srcImage.ImgViewport Is Nothing) Then Exit Sub
    
    'Get the current zoom value from the source image
    Dim zoomVal As Double
    zoomVal = g_Zoom.GetZoomValue(srcImage.GetZoom)
    
    'Get a copy of the translated image rect, in canvas coordinates.  If the canvas is a window, and the zoomed
    ' image is a poster sliding around behind it, the translate image rect contains the poster coordinates,
    ' relative to the window.  What's great about this rect is that it's already accounted for scroll bars,
    ' so we can ignore their value(s) here.
    Dim translatedImageRect As RECTF
    srcImage.ImgViewport.GetImageRectTranslated translatedImageRect
    
    'If the caller wants the coordinates bound-checked, we also need to grab a copy of the viewport
    ' intersection rect, which controls boundaries
    Dim vIntersectRect As RECTF
    If forceInBounds Then srcImage.ImgViewport.GetIntersectRectCanvas vIntersectRect
    
    Dim canvasX As Double, canvasY As Double
    
    'Iterate through each point in turn; note that bounds are automatically detected, and there is not currently a way to override
    ' this behavior.
    Dim i As Long
    For i = LBound(listOfPoints) To UBound(listOfPoints)
        
        'Translating the canvas coordinate pair back to the image is now easy.  Add the top/left offset,
        ' then multiply by zoom - that's all there is to it!
        canvasX = (listOfPoints(i).x * zoomVal) + translatedImageRect.Left
        canvasY = (listOfPoints(i).y * zoomVal) + translatedImageRect.Top
        
        'If the caller wants the coordinates bound-checked, apply it now
        If forceInBounds Then
            If (canvasX < vIntersectRect.Left) Then canvasX = vIntersectRect.Left
            If (canvasY < vIntersectRect.Top) Then canvasY = vIntersectRect.Top
            If (canvasX >= vIntersectRect.Left) + vIntersectRect.Width Then canvasX = vIntersectRect.Left + vIntersectRect.Width - 1
            If (canvasY >= vIntersectRect.Top) + vIntersectRect.Height Then canvasY = vIntersectRect.Top + vIntersectRect.Height - 1
        End If
        
        'Store the updated coordinate pair
        listOfPoints(i).x = canvasX
        listOfPoints(i).y = canvasY
    
    Next i
        
End Sub

'If you want to convert a position-agnostic size between image and canvas space, use this function
Public Function ConvertImageSizeToCanvasSize(ByVal srcSize As Double, ByRef srcImage As pdImage) As Double
    ConvertImageSizeToCanvasSize = srcSize * g_Zoom.GetZoomValue(srcImage.GetZoom)
End Function

'Given a source hWnd and a destination hWnd, translate a coordinate pair between their unique coordinate spaces.  Note that
' the screen coordinate space will be used as an intermediary in the conversion.
Public Sub ConvertCoordsBetweenHwnds(ByVal srcHwnd As Long, ByVal dstHwnd As Long, ByVal srcX As Long, ByVal srcY As Long, ByRef dstX As Long, ByRef dstY As Long)
    
    'This API requires POINTAPI structs
    Dim tmpPoint As POINTAPI
    
    With tmpPoint
        .x = srcX
        .y = srcY
    End With
    
    'Transform the coordinates
    MapWindowPoints srcHwnd, dstHwnd, tmpPoint, 1
    
    'Report the transformed points back to the user
    dstX = tmpPoint.x
    dstY = tmpPoint.y
    
End Sub

'Return an arbitrary conversion from image space to canvas space.  An optional image (x, y) can also passed; these will be added
' to the transform as source-image-space offsets.
Public Sub GetTransformFromImageToCanvas(ByRef dstTransform As pd2DTransform, ByRef srcCanvas As pdCanvas, ByRef srcImage As pdImage, Optional ByVal srcX As Single = 0#, Optional ByVal srcY As Single = 0#)

    If (dstTransform Is Nothing) Then Set dstTransform = New pd2DTransform

    'Get the current zoom value from the source image
    Dim zoomVal As Double
    zoomVal = g_Zoom.GetZoomValue(srcImage.GetZoom)
    
    'Get a copy of the translated image rect, in canvas coordinates.  If the canvas is a window, and the zoomed
    ' image is a poster sliding around behind it, the translate image rect contains the poster coordinates,
    ' relative to the window.  What's great about this rect is that it's already accounted for scroll bars,
    ' so we can ignore their value(s) here.
    Dim translatedImageRect As RECTF
    srcImage.ImgViewport.GetImageRectTranslated translatedImageRect
    
    'Apply scaling for zoom
    dstTransform.ApplyScaling zoomVal, zoomVal
    
    'Translate according to the current viewport setting, plus the original coordinates, if any
    dstTransform.ApplyTranslation (srcX * zoomVal) + translatedImageRect.Left, (srcY * zoomVal) + translatedImageRect.Top
    
End Sub

'Given a specific layer, return a RECT filled with that layer's corner coordinates -
' IN THE CANVAS COORDINATE SPACE (hence the function name).
Public Sub GetCanvasRectForLayer(ByVal layerIndex As Long, ByRef dstRect As RECT, Optional ByVal useCanvasModifiers As Boolean = False)

    Dim tmpX As Double, tmpY As Double
    
    With pdImages(g_CurrentImage).GetLayerByIndex(layerIndex)
        
        'Start with the top-left corner
        ConvertImageCoordsToCanvasCoords FormMain.mainCanvas(0), pdImages(g_CurrentImage), .GetLayerOffsetX, .GetLayerOffsetY, tmpX, tmpY
        dstRect.Left = tmpX
        dstRect.Top = tmpY
        
        'End with the bottom-right corner
        ConvertImageCoordsToCanvasCoords FormMain.mainCanvas(0), pdImages(g_CurrentImage), .GetLayerOffsetX + .GetLayerWidth(useCanvasModifiers), .GetLayerOffsetY + .GetLayerHeight(useCanvasModifiers), tmpX, tmpY
        
        'Because layers support sub-pixel positioning, but the canvas rect renderer *does not*, we must manually align the right/bottom coords
        dstRect.Right = Int(tmpX + 0.99)
        dstRect.Bottom = Int(tmpY + 0.99)
        
    End With

End Sub

'Same as above, but using floating-point values
Public Sub GetCanvasRectForLayerF(ByVal layerIndex As Long, ByRef dstRect As RECTF, Optional ByVal useCanvasModifiers As Boolean = False)

    Dim tmpX As Double, tmpY As Double
    
    With pdImages(g_CurrentImage).GetLayerByIndex(layerIndex)
        
        'Start with the top-left corner
        ConvertImageCoordsToCanvasCoords FormMain.mainCanvas(0), pdImages(g_CurrentImage), .GetLayerOffsetX, .GetLayerOffsetY, tmpX, tmpY
        dstRect.Left = tmpX
        dstRect.Top = tmpY
        
        'End with the bottom-right corner
        ConvertImageCoordsToCanvasCoords FormMain.mainCanvas(0), pdImages(g_CurrentImage), .GetLayerOffsetX + .GetLayerWidth(useCanvasModifiers), .GetLayerOffsetY + .GetLayerHeight(useCanvasModifiers), tmpX, tmpY
        dstRect.Width = tmpX - dstRect.Left
        dstRect.Height = tmpY - dstRect.Top
        
    End With

End Sub

'On the current viewport, render lines around the active layer
Public Sub DrawLayerBoundaries(ByRef dstCanvas As pdCanvas, ByRef srcImage As pdImage, ByRef srcLayer As pdLayer)

    'In the old days, we could get away with assuming layer boundaries form a rectangle, but as of PD 7.0, affine transforms
    ' mean this is no longer guaranteed.
    '
    'So instead of filling a rect, we must retrieve the four layer corner coordinates as floating-point pairs.
    Dim layerCorners() As POINTFLOAT
    ReDim layerCorners(0 To 3) As POINTFLOAT
    
    srcLayer.GetLayerCornerCoordinates layerCorners
    
    'Next, convert each corner from image coordinate space to the active viewport coordinate space
    Drawing.ConvertListOfImageCoordsToCanvasCoords dstCanvas, srcImage, layerCorners, False
    
    'Pass the list of coordinates to a pd2DPath object; it will handle the actual UI rendering
    Dim tmpPath As pd2DPath
    Set tmpPath = New pd2DPath
    
    'Note that we must add the layer boundary lines manually - otherwise, the top-right and bottom-left corners will connect
    ' due to the way srcLayer.getLayerCornerCoordinates returns the points!
    tmpPath.AddLine layerCorners(0).x, layerCorners(0).y, layerCorners(1).x, layerCorners(1).y
    tmpPath.AddLine layerCorners(1).x, layerCorners(1).y, layerCorners(3).x, layerCorners(3).y
    tmpPath.AddLine layerCorners(3).x, layerCorners(3).y, layerCorners(2).x, layerCorners(2).y
    tmpPath.CloseCurrentFigure
    
    'Render the final UI
    Dim cSurface As pd2DSurface
    Drawing2D.QuickCreateSurfaceFromDC cSurface, dstCanvas.hDC, True
    m_Painter.DrawPath cSurface, m_PenUIBase, tmpPath
    m_Painter.DrawPath cSurface, m_PenUITop, tmpPath
    Set cSurface = Nothing
    
End Sub

'On the current viewport, render standard PD transformation nodes (layer corners, currently) atop the active layer.
Public Sub DrawLayerCornerNodes(ByRef dstCanvas As pdCanvas, ByRef srcImage As pdImage, ByRef srcLayer As pdLayer, Optional ByVal curPOI As PD_PointOfInterest = poi_Undefined)

    'In the old days, we could get away with assuming layer boundaries form a rectangle, but as of PD 7.0, affine transforms
    ' mean this is no longer guaranteed.
    '
    'So instead of filling a rect, we must retrieve the four layer corner coordinates as floating-point pairs.
    Dim layerCorners() As POINTFLOAT
    ReDim layerCorners(0 To 3) As POINTFLOAT
    
    srcLayer.GetLayerCornerCoordinates layerCorners
    
    'Next, convert each corner from image coordinate space to the active viewport coordinate space
    Drawing.ConvertListOfImageCoordsToCanvasCoords dstCanvas, srcImage, layerCorners, False
    
    Dim cornerSize As Single, halfCornerSize As Single
    cornerSize = 12#
    halfCornerSize = cornerSize * 0.5
    
    Dim cSurface As pd2DSurface
    Drawing2D.QuickCreateSurfaceFromDC cSurface, dstCanvas.hDC, True
    
    'Convert the POI value, if any, to an index into our list of layer coordinates
    If (curPOI <> poi_Undefined) Then
        If (curPOI = poi_CornerNW) Then
            curPOI = 0
        ElseIf (curPOI = poi_CornerNE) Then
            curPOI = 1
        ElseIf (curPOI = poi_CornerSW) Then
            curPOI = 2
        ElseIf (curPOI = poi_CornerSE) Then
            curPOI = 3
        End If
    End If
    
    'Use GDI+ to render four corner nodes
    Dim i As Long
    For i = 0 To 3
        If (i = curPOI) Then
            m_Painter.DrawRectangleF cSurface, m_PenUIBaseHighlight, layerCorners(i).x - halfCornerSize, layerCorners(i).y - halfCornerSize, cornerSize, cornerSize
            m_Painter.DrawRectangleF cSurface, m_PenUITopHighlight, layerCorners(i).x - halfCornerSize, layerCorners(i).y - halfCornerSize, cornerSize, cornerSize
        Else
            m_Painter.DrawRectangleF cSurface, m_PenUIBase, layerCorners(i).x - halfCornerSize, layerCorners(i).y - halfCornerSize, cornerSize, cornerSize
            m_Painter.DrawRectangleF cSurface, m_PenUITop, layerCorners(i).x - halfCornerSize, layerCorners(i).y - halfCornerSize, cornerSize, cornerSize
        End If
    Next i
    
End Sub

'As of PD 7.0, on-canvas rotation is now supported.  Use this function to render the current rotation node.
Public Sub DrawLayerRotateNode(ByRef dstCanvas As pdCanvas, ByRef srcImage As pdImage, ByRef srcLayer As pdLayer, Optional ByVal curPOI As PD_PointOfInterest = poi_Undefined)
    
    'Retrieve the layer rotate node position from the specified layer, and convert it into the canvas coordinate space
    Dim layerRotateNodes() As POINTFLOAT
    ReDim layerRotateNodes(0 To 4) As POINTFLOAT
    
    srcLayer.GetLayerRotationNodeCoordinates layerRotateNodes
    Drawing.ConvertListOfImageCoordsToCanvasCoords dstCanvas, srcImage, layerRotateNodes, False
    
    Dim cSurface As pd2DSurface
    Drawing2D.QuickCreateSurfaceFromDC cSurface, dstCanvas.hDC, True
    
    'Convert the POI value, if any, to an index into our list of layer coordinates
    If (curPOI <> poi_Undefined) Then
        If (curPOI = poi_EdgeE) Then
            curPOI = 1
        ElseIf (curPOI = poi_EdgeS) Then
            curPOI = 2
        ElseIf (curPOI = poi_EdgeW) Then
            curPOI = 3
        ElseIf (curPOI = poi_EdgeN) Then
            curPOI = 4
        End If
    End If
    
    'As a convenience to the user, we draw some additional UI features if a rotation node is actively hovered by the mouse.
    If (curPOI >= 1) And (curPOI <= 4) Then
        
        'First, draw a line from the center of the layer to the rotation node, to provide visual feedback on where the rotation
        ' will actually occur.
        Dim tmpPath As pd2DPath
        Set tmpPath = New pd2DPath
        tmpPath.AddLine layerRotateNodes(0).x, layerRotateNodes(0).y, layerRotateNodes(curPOI).x, layerRotateNodes(curPOI).y
        
        m_Painter.DrawPath cSurface, m_PenUIBase, tmpPath
        m_Painter.DrawPath cSurface, m_PenUITop, tmpPath
        
        'Next, we are going to draw an arc with arrows on the end, to display where the actual rotation will occur.
        ' (At present, we skip this step if shearing is active, as I haven't figured out how to correctly skew the arc into the
        '  proper on-screen coordinate space.)
        If (srcLayer.GetLayerShearX = 0#) And (srcLayer.GetLayerShearY = 0#) Then
            
            tmpPath.ResetPath
        
            'Start by finding the distance of the rotation line.
            Dim rRadius As Double
            rRadius = PDMath.DistanceTwoPoints(layerRotateNodes(0).x, layerRotateNodes(0).y, layerRotateNodes(curPOI).x, layerRotateNodes(curPOI).y)
            
            'From there, bounds are easy-peasy
            Dim rotateBoundRect As RECTF
            With rotateBoundRect
                .Left = layerRotateNodes(0).x - rRadius
                .Top = layerRotateNodes(0).y - rRadius
                .Width = rRadius * 2
                .Height = rRadius * 2
            End With
            
            'Arc sweep and arc length are inter-related.  What we ultimately want is a (roughly) equal arc size regardless of zoom or
            ' the underlying image size.  This is difficult to predict as larger images and/or higher zoom will result in larger arc widths
            ' for an identical radius.  As such, we hard-code an approximate arc length, then generate an arc sweep from it.
            '
            'In my testing, 80-ish pixels is a reasonably good size across many image dimensions.  Note that we *do* correct for DPI here.
            Dim arcLength As Double
            arcLength = FixDPIFloat(70)
            
            'Switching between arc length and sweep is easy; see https://en.wikipedia.org/wiki/Arc_%28geometry%29#Length_of_an_arc_of_a_circle
            Dim arcSweep As Double
            arcSweep = (arcLength * 180) / (PI * rRadius)
            
            'Make sure the arc fits within a valid range (e.g. no complete circles or nearly-straight lines)
            If (arcSweep > 90) Then arcSweep = 90
            If (arcSweep < 30) Then arcSweep = 30
            
            'We need to modify the default layer angle depending on the current POI
            Dim relevantAngle As Double
            relevantAngle = srcLayer.GetLayerAngle + ((curPOI - 1) * 90)
            tmpPath.AddArc rotateBoundRect, relevantAngle - arcSweep / 2, arcSweep
            
            Dim prevLineCap As PD_2D_LineCap
            prevLineCap = m_PenUIBase.GetPenLineCap
            m_PenUIBase.SetPenLineCap P2_LC_ArrowAnchor
            m_PenUITop.SetPenLineCap P2_LC_ArrowAnchor
            
            cSurface.SetSurfacePixelOffset P2_PO_Half
            m_Painter.DrawPath cSurface, m_PenUIBase, tmpPath
            m_Painter.DrawPath cSurface, m_PenUITop, tmpPath
            cSurface.SetSurfacePixelOffset P2_PO_Normal
            
            m_PenUIBase.SetPenLineCap prevLineCap
            m_PenUITop.SetPenLineCap prevLineCap
            
        End If
        
    End If
    
    'Render the circles at each rotation point
    Dim circRadius As Single
    circRadius = 7#
    
    Dim i As Long
    For i = 1 To 4
        If (curPOI = i) Then
            m_Painter.DrawCircleF cSurface, m_PenUIBaseHighlight, layerRotateNodes(i).x, layerRotateNodes(i).y, circRadius
            m_Painter.DrawCircleF cSurface, m_PenUITopHighlight, layerRotateNodes(i).x, layerRotateNodes(i).y, circRadius
        Else
            m_Painter.DrawCircleF cSurface, m_PenUIBase, layerRotateNodes(i).x, layerRotateNodes(i).y, circRadius
            m_Painter.DrawCircleF cSurface, m_PenUITop, layerRotateNodes(i).x, layerRotateNodes(i).y, circRadius
        End If
    Next i
    
End Sub

'During startup, we cache a few different UI pens and brushes; this accelerates the process of viewport rendering.
' When the UI theme changes, this cache should be regenerated against any new colors.
'
'(Also, note the corresponding "release" function below.)
Public Sub CacheUIPensAndBrushes()
    If (m_Painter Is Nothing) Then Drawing2D.QuickCreatePainter m_Painter
    Drawing2D.QuickCreatePairOfUIPens m_PenUIBase, m_PenUITop
    Drawing2D.QuickCreatePairOfUIPens m_PenUIBaseHighlight, m_PenUITopHighlight, True
End Sub

Public Sub ReleaseUIPensAndBrushes()
    Set m_PenUIBase = Nothing
    Set m_PenUITop = Nothing
    Set m_PenUIBaseHighlight = Nothing
    Set m_PenUITopHighlight = Nothing
End Sub

Public Sub BorrowCachedUIPens(ByRef dstPenUIBase As pd2DPen, ByRef dstPenUITop As pd2DPen, Optional ByVal wantHighlightPens As Boolean = False)
    If wantHighlightPens Then
        Set dstPenUIBase = m_PenUIBaseHighlight
        Set dstPenUITop = m_PenUITopHighlight
    Else
        Set dstPenUIBase = m_PenUIBase
        Set dstPenUITop = m_PenUITop
    End If
End Sub
