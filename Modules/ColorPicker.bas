Attribute VB_Name = "ColorPicker"
'***************************************************************************
'Color Picker Tool Manager
'Copyright 2017-2017 by Tanner Helland
'Created: 25/September/17
'Last updated: 27/September/17
'Last update: wrap up initial build
'
'At present, this module is just a thin wrapper to the toolpanel_ColorPicker form (where the *real* fun happens).
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'Current mouse/pen input values.  These are blindly relayed to us by the canvas, and it's up to us to perform
' any special tracking calculations.
'IMPORTANT NOTE: these coordinates have already been translated into the *image* coordinate space.
Private m_MouseDown As Boolean
Private m_MouseX As Single, m_MouseY As Single

'Custom cursor rendering uses pd2D
Private m_Painter As pd2DPainter

'Color-picker cursor, retrieved as a resource at run-time
Private m_ColorPickerCursor As pdDIB

'Similar to other tools, the color picker is notified of all mouse actions that occur while it is selected.
' At present, however, it only triggers a fill when the mouse is actually clicked.  (No action is taken on
' move events, unless the mouse button is down.)
Public Sub NotifyMouseXY(ByVal mouseButtonDown As Boolean, ByVal imgX As Single, ByVal imgY As Single, ByRef srcCanvas As pdCanvas)
    
    'Before doing anything else, cache the mouse coordinates in case we need them in the future
    Dim isFirstStroke As Boolean, isLastStroke As Boolean
    isFirstStroke = (Not m_MouseDown) And mouseButtonDown
    isLastStroke = m_MouseDown And (Not mouseButtonDown)
    
    m_MouseDown = mouseButtonDown
    m_MouseX = imgX
    m_MouseY = imgY
    
    'Because this tool is largely UI-centric, start by forwarding the mouse position to the toolbox itself.
    ' It will handle any required on-screen updates.
    toolpanel_ColorPicker.NotifyCanvasXY m_MouseDown, m_MouseX, m_MouseY, srcCanvas
    
End Sub

'Render a relevant fill cursor outline to the canvas, using the stored mouse coordinates as the cursor's position
Public Sub RenderColorPickerCursor(ByRef targetCanvas As pdCanvas)
    
    'Start by creating a transformation from the image space to the canvas space
    Dim canvasMatrix As pd2DTransform
    Drawing.GetTransformFromImageToCanvas canvasMatrix, targetCanvas, pdImages(g_CurrentImage), m_MouseX, m_MouseY
    
    'We also want to pinpoint the precise cursor position
    Dim cursX As Double, cursY As Double
    Drawing.ConvertImageCoordsToCanvasCoords targetCanvas, pdImages(g_CurrentImage), m_MouseX, m_MouseY, cursX, cursY
    
    'Borrow a pair of UI pens from the main rendering module
    Dim innerPen As pd2DPen, outerPen As pd2DPen
    Drawing.BorrowCachedUIPens outerPen, innerPen
    
    'Create other required pd2D drawing tools (a surface)
    Dim cSurface As pd2DSurface
    Drawing2D.QuickCreateSurfaceFromDC cSurface, targetCanvas.hDC, True
    
    'Paint a target cursor
    Dim crossLength As Single, outerCrossBorder As Single
    crossLength = 5#
    outerCrossBorder = 0.5
    
    If (m_Painter Is Nothing) Then Set m_Painter = New pd2DPainter
    m_Painter.DrawLineF cSurface, outerPen, cursX, cursY - crossLength - outerCrossBorder, cursX, cursY + crossLength + outerCrossBorder
    m_Painter.DrawLineF cSurface, outerPen, cursX - crossLength - outerCrossBorder, cursY, cursX + crossLength + outerCrossBorder, cursY
    m_Painter.DrawLineF cSurface, innerPen, cursX, cursY - crossLength, cursX, cursY + crossLength
    m_Painter.DrawLineF cSurface, innerPen, cursX - crossLength, cursY, cursX + crossLength, cursY
    
    'If we haven't loaded the fill cursor previously, do so now
    If (m_ColorPickerCursor Is Nothing) Then
        IconsAndCursors.LoadResourceToDIB "cursor_eyedropper", m_ColorPickerCursor, IconsAndCursors.GetSystemCursorSizeInPx(), IconsAndCursors.GetSystemCursorSizeInPx(), , , True
    End If
    
    'Paint the fill icon to the bottom-right of the actual cursor, Photoshop-style
    Dim icoSurface As pd2DSurface
    Drawing2D.QuickCreateSurfaceFromDIB icoSurface, m_ColorPickerCursor, True
    'icoSurface.SetSurfaceResizeQuality P2_RQ_Bilinear
    m_Painter.DrawSurfaceF cSurface, cursX + crossLength * 1.4!, cursY + crossLength * 1.4!, icoSurface
    
    Set cSurface = Nothing: Set icoSurface = Nothing
    Set innerPen = Nothing: Set outerPen = Nothing
    
End Sub
