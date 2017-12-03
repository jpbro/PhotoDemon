Attribute VB_Name = "Plugin_FreeImage"
'***************************************************************************
'FreeImage Interface (Advanced)
'Copyright 2012-2017 by Tanner Helland
'Created: 3/September/12
'Last updated: 08/August/17
'Last update: migrate all tone-mapping code to XML params; new performance improvements for tone-mapping
'
'This module represents a new - and significantly more comprehensive - approach to loading images via the
' FreeImage libary. It handles a variety of decisions on a per-format basis to ensure optimal load speed
' and quality.
'
'Please note that this module relies heavily on Carsten Klein's FreeImage wrapper for VB (included in this project
' as Outside_FreeImageV3; see that file for license details).  Thank you to Carsten for his work on simplifying
' FreeImage usage from classic VB.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

Private Type BITMAPINFOHEADER
    biSize As Long
    biWidth As Long
    biHeight As Long
    biPlanes As Integer
    biBitCount As Integer
    biCompression As Long
    biSizeImage As Long
    biXPelsPerMeter As Long
    biYPelsPerMeter As Long
    biClrUsed As Long
    biClrImportant As Long
End Type

Private Type BITMAPINFO
    bmiHeader As BITMAPINFOHEADER
    bmiColors As Long
End Type

Private Declare Function AlphaBlend Lib "msimg32" (ByVal hDestDC As Long, ByVal x As Long, ByVal y As Long, ByVal nWidth As Long, ByVal nHeight As Long, ByVal hSrcDC As Long, ByVal xSrc As Long, ByVal ySrc As Long, ByVal WidthSrc As Long, ByVal HeightSrc As Long, ByVal blendFunct As Long) As Boolean

'DLL handle; if it is zero, FreeImage is not available
Private m_FreeImageHandle As Long

'Additional variables for PD-specific tone-mapping functions
Private m_shoulderStrength As Double, m_linearStrength As Double, m_linearAngle As Double, m_linearWhitePoint As Single
Private m_toeStrength As Double, m_toeNumerator As Double, m_toeDenominator As Double, m_toeAngle As Double

'Cache(s) for post-export image previews.  These objects can be safely freed, as they will be properly initialized on-demand.
Private m_ExportPreviewBytes() As Byte
Private m_ExportPreviewDIB As pdDIB

'Initialize FreeImage.  Do not call this until you have verified FreeImage's existence (typically via the PluginManager module)
Public Function InitializeFreeImage() As Boolean
    
    'Manually load the DLL from the plugin folder (should be App.Path\Data\Plugins)
    Dim fiPath As String
    fiPath = PluginManager.GetPluginPath & "FreeImage.dll"
    m_FreeImageHandle = LoadLibrary(StrPtr(fiPath))
    InitializeFreeImage = (m_FreeImageHandle <> 0)
    
    If (Not InitializeFreeImage) Then
        FI_DebugMsg "WARNING!  LoadLibrary failed to load FreeImage.  Last DLL error: " & Err.LastDllError
        FI_DebugMsg "(FYI, the attempted path was: " & fiPath & ")"
    End If
    
End Function

Public Function ReleaseFreeImage() As Boolean
    
    If (m_FreeImageHandle <> 0) Then
        FreeLibrary m_FreeImageHandle
        m_FreeImageHandle = 0
    End If
    
    ReleaseFreeImage = True
    
End Function

'Load a given file.  If successful, returns a non-zero FreeImage handle.  Multi-page files will also fill a multipage DIB handle,
' which must also be freed post-load (in addition to the default handle returned by this function).
'
'On success, the target DIB object will also have its OriginalColorSpace member filled.
Private Function FI_LoadImageU(ByVal srcFilename As String, ByVal fileFIF As FREE_IMAGE_FORMAT, ByVal fi_ImportFlags As FREE_IMAGE_LOAD_OPTIONS, ByRef dstDIB As pdDIB, ByRef fi_multi_hDIB As Long, Optional ByVal pageToLoad As Long = 0&, Optional ByVal suppressDebugData As Boolean = False) As Long

    'FreeImage uses separate import behavior for single-page and multi-page files.  As such, we may need to track
    ' multiple handles (e.g. a handle to the master image, and a handle to the current page).  If fi_multi_hDIB is non-zero,
    ' this is a multipage image.
    Dim fi_hDIB As Long
    If (pageToLoad <= 0) Then
        FI_DebugMsg "Invoking FreeImage_LoadUInt...", suppressDebugData
        fi_hDIB = FreeImage_LoadUInt(fileFIF, StrPtr(srcFilename), fi_ImportFlags)
    Else
        
        'Multipage support can be finicky, so it reports more debug info than PD usually prefers
        If (fileFIF = PDIF_GIF) Then
            FI_DebugMsg "Importing frame # " & CStr(pageToLoad + 1) & " from animated GIF file...", suppressDebugData
        ElseIf (fileFIF = FIF_ICO) Then
            FI_DebugMsg "Importing icon # " & CStr(pageToLoad + 1) & " from ICO file...", suppressDebugData
        Else
            FI_DebugMsg "Importing page # " & CStr(pageToLoad + 1) & " from multipage TIFF file...", suppressDebugData
        End If
        
        If (fileFIF = PDIF_GIF) Then
            fi_multi_hDIB = FreeImage_OpenMultiBitmap(PDIF_GIF, srcFilename, , , , fi_ImportFlags Or FILO_GIF_PLAYBACK)
        ElseIf (fileFIF = FIF_ICO) Then
            fi_multi_hDIB = FreeImage_OpenMultiBitmap(FIF_ICO, srcFilename, , , , fi_ImportFlags)
        Else
            fi_multi_hDIB = FreeImage_OpenMultiBitmap(PDIF_TIFF, srcFilename, , , , fi_ImportFlags)
        End If
        
        fi_hDIB = FreeImage_LockPage(fi_multi_hDIB, pageToLoad)
        
    End If
    
    'Store the original, untouched color depth now.  (We may modify this depth in the future, so this is our first and
    ' last chance to grab the original value.)
    If (fi_hDIB <> 0) Then dstDIB.SetOriginalFreeImageColorDepth FreeImage_GetBPP(fi_hDIB)
    
    'Icon files may use a simple mask for their alpha channel; in this case, re-load the icon with the FILO_ICO_MAKEALPHA flag
    If (fileFIF = FIF_ICO) Then
        
        'Check the bit-depth
        If (FreeImage_GetBPP(fi_hDIB) < 32) Then
        
            'If this is the first frame of the icon, unload it and try again
            If (pageToLoad <= 0) Then
                If (fi_hDIB <> 0) Then FreeImage_UnloadEx fi_hDIB
                fi_hDIB = FreeImage_LoadUInt(fileFIF, StrPtr(srcFilename), FILO_ICO_MAKEALPHA)
            
            'If this is not the first frame, the required load code is a bit different.
            Else
                
                'Unlock this page and close the multi-page bitmap
                FreeImage_UnlockPage fi_multi_hDIB, fi_hDIB, False
                FreeImage_CloseMultiBitmap fi_multi_hDIB
                
                'Now re-open it with the proper flags
                fi_multi_hDIB = FreeImage_OpenMultiBitmap(FIF_ICO, srcFilename, , , , FILO_ICO_MAKEALPHA)
                fi_hDIB = FreeImage_LockPage(fi_multi_hDIB, pageToLoad)
                
            End If
            
        End If
        
    End If
    
    FI_LoadImageU = fi_hDIB
    
End Function

'Load an image via FreeImage.  It is assumed that the source file has already been vetted for things like "does it exist?"
Public Function FI_LoadImage_V5(ByVal srcFilename As String, ByRef dstDIB As pdDIB, Optional ByVal pageToLoad As Long = 0, Optional ByVal showMessages As Boolean = True, Optional ByRef targetImage As pdImage = Nothing, Optional ByVal suppressDebugData As Boolean = False) As PD_OPERATION_OUTCOME

    On Error GoTo FreeImageV5_Error
    
    '****************************************************************************
    ' Make sure FreeImage exists and is usable
    '****************************************************************************
    
    'Ensure that a FreeImage instance is available
    If (Not g_ImageFormats.FreeImageEnabled) Then
        FI_LoadImage_V5 = PD_FAILURE_GENERIC
        Exit Function
    End If
    
    '****************************************************************************
    ' Determine image format
    '****************************************************************************
    
    If (dstDIB Is Nothing) Then Set dstDIB = New pdDIB
    
    FI_DebugMsg "Running filetype heuristics...", suppressDebugData
    
    Dim fileFIF As FREE_IMAGE_FORMAT
    fileFIF = FI_DetermineFiletype(srcFilename, dstDIB)
    
    'If FreeImage doesn't recognize the filetype, abandon the import attempt.
    If (fileFIF = FIF_UNKNOWN) Then
    
        #If DEBUGMODE = 1 Then
            pdDebug.LogAction "Filetype not supported by FreeImage.  Import abandoned."
        #End If
        
        FI_LoadImage_V5 = PD_FAILURE_GENERIC
        Exit Function
        
    End If
    
    
    '****************************************************************************
    ' Based on the detected format, prepare any necessary load flags
    '****************************************************************************
    
    FI_DebugMsg "Preparing FreeImage import flags...", suppressDebugData
    
    Dim fi_ImportFlags As FREE_IMAGE_LOAD_OPTIONS
    fi_ImportFlags = FI_DetermineImportFlags(srcFilename, fileFIF, Not showMessages)
    
    
    '****************************************************************************
    ' Load the image into a FreeImage container
    '****************************************************************************
    
    'FreeImage uses separate import behavior for single-page and multi-page files.  As such, we may need to track
    ' multiple handles (e.g. a handle to the master image, and a handle to the current page).  If fi_multi_hDIB is non-zero,
    ' this is a multipage image.
    Dim fi_hDIB As Long, fi_multi_hDIB As Long
    fi_hDIB = FI_LoadImageU(srcFilename, fileFIF, fi_ImportFlags, dstDIB, fi_multi_hDIB, pageToLoad, suppressDebugData)
    
    'If an empty handle is returned, abandon the import attempt.
    If (fi_hDIB = 0) Then
        FI_DebugMsg "Import via FreeImage failed (blank handle).", suppressDebugData
        FI_LoadImage_V5 = PD_FAILURE_GENERIC
        Exit Function
    End If
    
        
    '****************************************************************************
    ' Retrieve generic metadata, like color depth and resolution (if available)
    '****************************************************************************
    
    Dim fi_BPP As Long, fi_DataType As FREE_IMAGE_TYPE
    fi_BPP = FreeImage_GetBPP(fi_hDIB)
    fi_DataType = FreeImage_GetImageType(fi_hDIB)
    FI_DebugMsg "Heuristics show image bit-depth: " & fi_BPP & ", pixel type: " & FI_GetImageTypeAsString(fi_DataType), suppressDebugData
    
    dstDIB.SetDPI FreeImage_GetResolutionX(fi_hDIB), FreeImage_GetResolutionY(fi_hDIB), True
    FI_LoadBackgroundColor fi_hDIB, dstDIB
    dstDIB.SetOriginalColorDepth FreeImage_GetBPP(fi_hDIB)
    
    
    '****************************************************************************
    ' Retrieve any attached ICC profiles
    '****************************************************************************
    
    If FreeImage_HasICCProfile(fi_hDIB) Then FI_LoadICCProfile fi_hDIB, dstDIB
    
    
    '****************************************************************************
    ' Copy/transform the FreeImage object into the destination pdDIB object
    '****************************************************************************
    
    'Converting any arbitrary chunk of image bytes into a valid 24- or 32-bpp image is a non-trivial task.
    ' As such, we split this specialized handling into its own function.
    
    '(Also, I know it seems weird, but the target function needs to run some heuristics on the incoming data to see if it
    ' came from the Windows clipboard.  If it did, we have to apply some special post-processing to the image data,
    ' to compensate for GDI's propensity to strip alpha data.)
    Dim specialClipboardHandlingRequired As Boolean
    
    FI_LoadImage_V5 = FI_GetFIObjectIntoDIB(fi_hDIB, fi_multi_hDIB, fileFIF, fi_DataType, specialClipboardHandlingRequired, srcFilename, dstDIB, pageToLoad, showMessages, targetImage, suppressDebugData)
    If (FI_LoadImage_V5 = PD_SUCCESS) Then
    
        'The FI data now exists inside a pdDIB object, at 24- or 32-bpp.
        
        '****************************************************************************
        ' Release all remaining FreeImage-specific structures and links
        '****************************************************************************
        
        FI_Unload fi_hDIB, fi_multi_hDIB
        FI_DebugMsg "Image load successful.  FreeImage handle released.", suppressDebugData
        
        
        '****************************************************************************
        ' Finalize alpha values in the target image
        '****************************************************************************
        
        'If this image came from the clipboard, and its alpha state is unknown, we're going to force all alpha values
        ' to 255 to avoid potential driver-specific issues with the PrtScrn key.
        If specialClipboardHandlingRequired Then
            FI_DebugMsg "Image came from the clipboard; finalizing alpha now...", suppressDebugData
            dstDIB.ForceNewAlpha 255
        End If
        
        'Regardless of original bit-depth, the final PhotoDemon image will always be 32-bits, with pre-multiplied alpha.
        dstDIB.SetInitialAlphaPremultiplicationState True
        
        
        '****************************************************************************
        ' Load complete
        '****************************************************************************
        
        'Confirm this load as successful
        FI_LoadImage_V5 = PD_SUCCESS
    
    'If the source function failed, there's nothing we can do here; the incorrect error code will have already been set,
    ' so we can simply bail.
    End If
    
    
    Exit Function
    
    '****************************************************************************
    ' Error handling
    '****************************************************************************
    
FreeImageV5_Error:
    
    FI_DebugMsg "VB-specific error occurred inside FI_LoadImage_V5.  Err #: " & Err.Number & ", " & Err.Description, suppressDebugData
    If showMessages Then Message "Import via FreeImage failed (Err # %1)", Err.Number
    FI_Unload fi_hDIB, fi_multi_hDIB
    FI_LoadImage_V5 = PD_FAILURE_GENERIC
    
End Function

'Given a valid handle to a FreeImage object (and/or multipage object, as relevant), get the FreeImage object into a pdDIB object.
' While this sounds simple, it really isn't, primarily because we have to deal with all possible color depths, alpha-channel
' encodings, ICC profile behaviors, etc.
'
'RETURNS: PD_SUCCESS if successful; some other code if the load fails.  Review debug messages for additional info.
Private Function FI_GetFIObjectIntoDIB(ByRef fi_hDIB As Long, ByRef fi_multi_hDIB As Long, ByVal fileFIF As FREE_IMAGE_FORMAT, ByVal fi_DataType As FREE_IMAGE_TYPE, ByRef specialClipboardHandlingRequired As Boolean, ByVal srcFilename As String, ByRef dstDIB As pdDIB, Optional ByVal pageToLoad As Long = 0, Optional ByVal showMessages As Boolean = True, Optional ByRef targetImage As pdImage = Nothing, Optional ByVal suppressDebugData As Boolean = False, Optional ByRef multiDibIsDetached As Boolean = False) As PD_OPERATION_OUTCOME
    
    On Error GoTo FiObject_Error
    
    '****************************************************************************
    ' If the image is in an unacceptable bit-depth, start by converting it to a standard 24 or 32bpp image.
    '****************************************************************************
    
    'As much as possible, we prefer to convert bit-depth using the existing FreeImage handle as the source, and the target
    ' pdDIB object as the destination.  This lets us skip a redundant allocation for a destination FreeImage handle.
    ' If the image has successfully been moved into the target pdDIB object, this *must* be set to TRUE.  (Otherwise, a
    ' failsafe check at the end of this function will perform an auto-copy.)
    Dim dstDIBFinished As Boolean: dstDIBFinished = False
    
    'When working with a multipage image, we may need to "detach" the current page DIB from its parent multipage handle.
    ' (This happens if an intermediate copy of the FI object is required.)
    ' If we detach an individual page DIB from it parent, this variable will note it, so we know to use the standalone
    ' unload function before exiting (instead of the multipage-specific one).
    multiDibIsDetached = False
    
    'Intermediate FreeImage objects may also be required during the transform process
    Dim new_hDIB As Long
    
    
    '****************************************************************************
    ' CMYK images are handled first, as they require special treatment
    '****************************************************************************
    
    'Note that all "continue loading" checks start with "If (Not dstDIBFinished)".  When various conditions are met,
    ' this function may attempt to shortcut the load process.  If this occurs, "dstDIBFinished" will be set to TRUE,
    ' allowing subsequent checks to be skipped.
    If (Not dstDIBFinished) And (FreeImage_GetColorType(fi_hDIB) = FIC_CMYK) Then
        
        FI_DebugMsg "CMYK image detected.  Preparing transform into RGB space...", suppressDebugData
        
        'Proper CMYK conversions require an ICC profile.  If this image doesn't have one, it's a pointless image
        ' (it's impossible to construct a "correct" copy since CMYK is device-specific), but we'll of course try
        ' to load it anyway.
        Dim cmykConversionSuccessful As Boolean: cmykConversionSuccessful = False
        
        If dstDIB.ICCProfile.HasICCData Then
            cmykConversionSuccessful = ConvertCMYKFiDIBToRGB(fi_hDIB, dstDIB)
            If cmykConversionSuccessful Then FI_Unload fi_hDIB, fi_multi_hDIB, True, multiDibIsDetached
            dstDIBFinished = True
        End If
        
        'If CMYK conversion failed, re-load the image and use FreeImage to apply a generic CMYK -> RGB transform.
        If (Not cmykConversionSuccessful) Then
            FI_DebugMsg "ICC-based CMYK transformation failed.  Falling back to default CMYK conversion...", suppressDebugData
            FI_Unload fi_hDIB, fi_multi_hDIB
            fi_hDIB = FreeImage_LoadUInt(fileFIF, StrPtr(srcFilename), FILO_JPEG_ACCURATE Or FILO_JPEG_EXIFROTATE)
        End If
        
    End If
    
    'Between attempted conversions, we typically reset the BPP tracker (as it may have changed due to internal
    ' FreeImage handling)
    Dim fi_BPP As Long
    If (fi_hDIB <> 0) Then fi_BPP = FreeImage_GetBPP(fi_hDIB)
    
    
    '****************************************************************************
    ' With CMYK images out of the way, deal with high bit-depth images in normal color spaces
    '****************************************************************************
    
    'FIT_BITMAP refers to any image with channel data <= 8 bits per channel.  We want to check for images that do *not*
    ' fit this definition, e.g. images ranging from 16-bpp grayscale images to 128-bpp RGBA images.
    If (Not dstDIBFinished) And (fi_DataType <> FIT_BITMAP) Then
        
        'We have two mechanisms for downsampling a high bit-depth image:
        ' 1) Using an embedded ICC profile (the preferred mechanism)
        ' 2) Using a generic tone-mapping algorithm to estimate conversion parameters
        '
        'If at all possible, we will try to use (1) before (2).  Success is noted by the following variable.
        Dim hdrICCSuccess As Boolean: hdrICCSuccess = False
        
        'If an ICC profile exists, attempt to use it
        If (FreeImage_HasICCProfile(fi_hDIB) And dstDIB.ICCProfile.HasICCData) Then
            
            FI_DebugMsg "HDR image identified.  ICC profile found; attempting to convert automatically...", suppressDebugData
            hdrICCSuccess = GenerateICCCorrectedFIDIB(fi_hDIB, dstDIB, dstDIBFinished, new_hDIB)
            
            'Some esoteric color-depths may require us to use a temporary FreeImage handle instead of copying
            ' the color-managed result directly into a pdDIB object.
            If hdrICCSuccess Then
                If (Not dstDIBFinished) And (new_hDIB <> 0) Then
                    FI_Unload fi_hDIB, fi_multi_hDIB, True, multiDibIsDetached
                    fi_hDIB = new_hDIB
                    new_hDIB = 0
                End If
            Else
                FI_DebugMsg "ICC transformation unsuccessful; dropping back to tone-mapping...", suppressDebugData
            End If
        
        End If
        
        'If we can't find an ICC profile, we have no choice but to use tone-mapping to generate a 24/32-bpp image
        If (Not hdrICCSuccess) Then
        
            FI_DebugMsg "HDR image identified.  Raising tone-map dialog...", suppressDebugData
            
            'Use the central tone-map handler to apply further tone-mapping
            Dim toneMappingOutcome As PD_OPERATION_OUTCOME
            toneMappingOutcome = RaiseToneMapDialog(fi_hDIB, new_hDIB, (Not showMessages) Or (Macros.GetMacroStatus = MacroBATCH))
            
            'A non-zero return signifies a successful tone-map operation.  Unload our old handle, and proceed with the new handle
            If (toneMappingOutcome = PD_SUCCESS) And (new_hDIB <> 0) Then
                
                'Add a note to the target image that tone-mapping was forcibly applied to the incoming data
                If (Not targetImage Is Nothing) Then targetImage.ImgStorage.AddEntry "Tone-mapping", True
                
                'Replace the primary FI_DIB handle with the new one, then carry on with loading
                If (new_hDIB <> fi_hDIB) Then FI_Unload fi_hDIB, fi_multi_hDIB, True, multiDibIsDetached
                fi_hDIB = new_hDIB
                FI_DebugMsg "Tone mapping complete.", suppressDebugData
                
            'The tone-mapper will return 0 if it failed.  If this happens, we cannot proceed with loading.
            Else
                FI_Unload fi_hDIB, fi_multi_hDIB, True, multiDibIsDetached
                If (toneMappingOutcome <> PD_SUCCESS) Then FI_GetFIObjectIntoDIB = toneMappingOutcome Else FI_GetFIObjectIntoDIB = PD_FAILURE_GENERIC
                FI_DebugMsg "Tone-mapping canceled due to user request or error.  Abandoning image import.", suppressDebugData
                Exit Function
            End If
            
        End If
    
    End If
    
    'Between attempted conversions, we reset the BPP tracker (as it may have changed)
    If (fi_hDIB <> 0) Then fi_BPP = FreeImage_GetBPP(fi_hDIB)
    
    
    '****************************************************************************
    ' If the image is < 32bpp, upsample it to 32bpp
    '****************************************************************************
    
    'The source image should now be in one of two bit-depths:
    ' 1) 32-bpp RGBA
    ' 2) Some bit-depth less than 32-bpp RGBA
    '
    'In the second case, we want to upsample the data to 32-bpp RGBA, adding an opaque alpha channel as necessary.
    ' (In the past, this block only triggered if the BPP was below 24, but I'm now relying on FreeImage to apply
    '  any necessary 24- to 32-bpp conversions as well.)
    If (Not dstDIBFinished) And (fi_BPP < 32) Then
        
        'If the image is grayscale, and it has an ICC profile, we need to apply that prior to continuing.
        ' (Grayscale images have grayscale ICC profiles which the default ICC profile handler can't address.)
        If (fi_BPP = 8) And (FreeImage_HasICCProfile(fi_hDIB)) Then
            
            'In the future, 8-bpp RGB/A conversion could be handled here.
            ' (Note that you need to up-sample the source image prior to conversion, however, as LittleCMS doesn't work with palettes.)
            
            'At present, we only cover grayscale ICC profiles in indexed images
            If ((FreeImage_GetColorType(fi_hDIB) = FIC_MINISBLACK) Or (FreeImage_GetColorType(fi_hDIB) = FIC_MINISWHITE)) Then
                
                FI_DebugMsg "8bpp grayscale image with ICC profile identified.  Applying color management now...", suppressDebugData
                new_hDIB = 0
                
                If GenerateICCCorrectedFIDIB(fi_hDIB, dstDIB, dstDIBFinished, new_hDIB) Then
                    If (Not dstDIBFinished) And (new_hDIB <> 0) Then
                        FI_Unload fi_hDIB, fi_multi_hDIB, True, multiDibIsDetached
                        fi_hDIB = new_hDIB
                        new_hDIB = 0
                    End If
                End If
            End If
            
        End If
        
        If (Not dstDIBFinished) Then
        
            'In the past, we would check for an alpha channel here (something like "fi_hasTransparency = FreeImage_IsTransparent(fi_hDIB)"),
            ' but that is no longer necessary.  We instead rely on FreeImage to convert to 32-bpp regardless of transparency status.
            new_hDIB = FreeImage_ConvertColorDepth(fi_hDIB, FICF_RGB_32BPP, False)
            
            If (new_hDIB <> fi_hDIB) Then
                FI_Unload fi_hDIB, fi_multi_hDIB, True, multiDibIsDetached
                fi_hDIB = new_hDIB
            End If
            
        End If
            
    End If
    
    'By this point, we have loaded the image, and it is guaranteed to be at 32 bit color depth.  Verify it one final time.
    If (fi_hDIB <> 0) Then fi_BPP = FreeImage_GetBPP(fi_hDIB)
    
    
    '****************************************************************************
    ' If the image has an ICC profile but we haven't yet applied it, do so now.
    '****************************************************************************
    
    If (Not dstDIBFinished) And (dstDIB.ICCProfile.HasICCData) And (Not dstDIB.ICCProfile.HasProfileBeenApplied) Then
        
        FI_DebugMsg "Applying final color management operation...", suppressDebugData
        
        new_hDIB = 0
        If GenerateICCCorrectedFIDIB(fi_hDIB, dstDIB, dstDIBFinished, new_hDIB) Then
            If (Not dstDIBFinished) And (new_hDIB <> 0) Then
                FI_Unload fi_hDIB, fi_multi_hDIB, True, multiDibIsDetached
                fi_hDIB = new_hDIB
                new_hDIB = 0
            End If
        End If
        
    End If
    
    'Between attempted conversions, we reset the BPP tracker (as it may have changed)
    If (fi_hDIB <> 0) Then fi_BPP = FreeImage_GetBPP(fi_hDIB)
    
    
    
    '****************************************************************************
    ' PD's current rendering engine requires pre-multiplied alpha values.  Apply premultiplication now - but ONLY if
    ' the image did not come from the clipboard.  (Clipboard images requires special treatment.)
    '****************************************************************************
    
    Dim tmpClipboardInfo As PD_Clipboard_Info
    specialClipboardHandlingRequired = False
    
    If (Not dstDIBFinished) And (fi_BPP = 32) Then
        
        'If the clipboard is active, this image came from a Paste operation.  It may require extra alpha heuristics.
        If g_Clipboard.IsClipboardOpen Then
        
            'Retrieve a local copy of PD's clipboard info struct.  We're going to analyze it, to see if we need to
            ' run some alpha heuristics (because the clipboard is shit when it comes to handling alpha correctly.)
            tmpClipboardInfo = g_Clipboard.GetClipboardInfo
            
            'If the clipboard image was originally placed on the clipboard as a DDB, a whole variety of driver-specific
            ' issues may be present.
            If (tmpClipboardInfo.pdci_OriginalFormat = CF_BITMAP) Then
            
                'Well, this sucks.  The original owner of this clipboard data (maybe even Windows itself, in the case
                ' of PrtScrn) placed an image on the clipboard in the ancient CF_BITMAP format, which is a DDB with
                ' device-specific coloring.  In the age of 24/32-bit displays, we don't care about color issues so
                ' much, but alpha is whole other mess.  For performance reasons, most display drivers run in 32-bpp
                ' mode, with the alpha values typically ignored.  Unfortunately, some drivers (*cough* INTEL *cough*)
                ' may leave junk in the 4th bytes instead of wiping them clean, preventing us from easily telling
                ' if the source data has alpha values filled intentionally, or by accident.
                
                'Because there is no foolproof way to know if the alpha values are valid, we should probably prompt
                ' the user for feedback on how to proceed.  For now, however, simply wipe the alpha bytes of anything
                ' placed on the clipboard in CF_BITMAP format.
                
                '(The image is still in FreeImage format at this point, so we set a flag and will apply the actual
                ' alpha transform later.)
                specialClipboardHandlingRequired = True
            
            'The image was originally placed on the clipboard as a DIB.  Assume the caller knew what they were doing
            ' with their own alpha bytes, and apply premultiplication now.
            Else
                FreeImage_PreMultiplyWithAlpha fi_hDIB
            End If
        
        'This is a normal image - carry on!
        Else
            FreeImage_PreMultiplyWithAlpha fi_hDIB
        End If
        
    End If
    
    
    '****************************************************************************
    ' Copy the data from the FreeImage object to the target pdDIB object
    '****************************************************************************
    
    'Note that certain code paths may have already populated the pdDIB object.  We only need to perform this step if the image
    ' data still resides inside a FreeImage handle.
    If (Not dstDIBFinished) And (fi_hDIB <> 0) Then
        
        'Get width and height from the file, and create a new DIB to match
        Dim fi_Width As Long, fi_Height As Long
        fi_Width = FreeImage_GetWidth(fi_hDIB)
        fi_Height = FreeImage_GetHeight(fi_hDIB)
        
        'Update Dec '12: certain faulty TIFF files can confuse FreeImage and cause it to report wildly bizarre height and width
        ' values; check for this, and if it happens, abandon the load immediately.  (This is not ideal, because it leaks memory
        ' - but it prevents a hard program crash, so I consider it the lesser of two evils.)
        If (fi_Width > 1000000) Or (fi_Height > 1000000) Then
            FI_GetFIObjectIntoDIB = PD_FAILURE_GENERIC
            Exit Function
        Else
        
            'Our caller may be reusing the same image across multiple loads.  To improve performance, only create a new
            ' object if necessary; otherwise, reuse the previous instance.
            Dim dibReady As Boolean
            If (dstDIB.GetDIBWidth = fi_Width) And (dstDIB.GetDIBHeight = fi_Height) And (dstDIB.GetDIBColorDepth = fi_BPP) Then
                dstDIB.ResetDIB 0
                dibReady = True
            Else
                FI_DebugMsg "Requesting memory for final image transfer...", suppressDebugData
                dibReady = dstDIB.CreateBlank(fi_Width, fi_Height, fi_BPP, 0, 0)
                If dibReady Then FI_DebugMsg "Memory secured.  Finalizing image load...", suppressDebugData
            End If
            
            If dibReady Then
                SetDIBitsToDevice dstDIB.GetDIBDC, 0, 0, fi_Width, fi_Height, 0, 0, 0, fi_Height, ByVal FreeImage_GetBits(fi_hDIB), ByVal FreeImage_GetInfo(fi_hDIB), 0&
            Else
                FI_DebugMsg "Import via FreeImage failed (couldn't create DIB).", suppressDebugData
                FI_Unload fi_hDIB, fi_multi_hDIB, True, multiDibIsDetached
                FI_GetFIObjectIntoDIB = PD_FAILURE_GENERIC
                Exit Function
            End If
        End If
        
    End If
    
    'If we made it all the way here, we have successfully moved the original FreeImage object into the destination pdDIB object.
    FI_GetFIObjectIntoDIB = PD_SUCCESS
    
    Exit Function
    
FiObject_Error:
    
    FI_DebugMsg "VB-specific error occurred inside FI_GetFIObjectIntoDIB.  Err #: " & Err.Number & ", " & Err.Description, suppressDebugData
    If showMessages Then Message "Import via FreeImage failed (Err # %1)", Err.Number
    FI_Unload fi_hDIB, fi_multi_hDIB, True, multiDibIsDetached
    FI_GetFIObjectIntoDIB = PD_FAILURE_GENERIC
    
End Function

'After the first page of a multipage image has been loaded successfully, call this function to load the remaining pages into the
' destination object.
Public Function FinishLoadingMultipageImage(ByVal srcFilename As String, ByRef dstDIB As pdDIB, Optional ByVal numOfPages As Long = 0, Optional ByVal showMessages As Boolean = True, Optional ByRef targetImage As pdImage = Nothing, Optional ByVal suppressDebugData As Boolean = False, Optional ByVal suggestedFilename As String = vbNullString) As PD_OPERATION_OUTCOME

    If (dstDIB Is Nothing) Then Set dstDIB = New pdDIB
    
    'Get a multipage handle to the source file
    Dim fileFIF As FREE_IMAGE_FORMAT
    fileFIF = FI_DetermineFiletype(srcFilename, dstDIB)
    
    Dim fi_ImportFlags As FREE_IMAGE_LOAD_OPTIONS
    fi_ImportFlags = FI_DetermineImportFlags(srcFilename, fileFIF, Not showMessages)
    
    Dim fi_hDIB As Long, fi_multi_hDIB As Long
    If (fileFIF = PDIF_GIF) Then
        fi_multi_hDIB = FreeImage_OpenMultiBitmap(PDIF_GIF, srcFilename, , , , fi_ImportFlags Or FILO_GIF_PLAYBACK)
    ElseIf (fileFIF = FIF_ICO) Then
        fi_multi_hDIB = FreeImage_OpenMultiBitmap(FIF_ICO, srcFilename, , , , fi_ImportFlags)
    Else
        fi_multi_hDIB = FreeImage_OpenMultiBitmap(PDIF_TIFF, srcFilename, , , , fi_ImportFlags)
    End If
    
    'FreeImage handles icon files poorly; a workaround is required to get them to return any masks as pre-built alpha channels.
    If (fileFIF = FIF_ICO) Then
        If (FreeImage_GetBPP(fi_hDIB) < 32) Then
            FreeImage_UnlockPage fi_multi_hDIB, fi_hDIB, False
            FreeImage_CloseMultiBitmap fi_multi_hDIB
            fi_multi_hDIB = FreeImage_OpenMultiBitmap(FIF_ICO, srcFilename, , , , FILO_ICO_MAKEALPHA)
        End If
    End If
    
    'We are now going to keep that source file open for the duration of the load process.
    Dim fi_BPP As Long, fi_DataType As FREE_IMAGE_TYPE
    Dim specialClipboardHandlingRequired As Boolean, loadSuccess As Boolean
    Dim newLayerID As Long, newLayerName As String
    Dim multiDibIsDetached As Boolean
    
    'Start iterating pages!
    Dim pageToLoad As Long
    For pageToLoad = 1 To numOfPages - 1
        
        Message "Multipage image found.  Loading page #%1 of %2...", CStr(pageToLoad + 1), numOfPages
        If ((pageToLoad And 7) = 0) Then ProgressBars.Replacement_DoEvents FormMain.hWnd
        
        'Lock the current page
        fi_hDIB = FreeImage_LockPage(fi_multi_hDIB, pageToLoad)
        If (fi_hDIB <> 0) Then
            
            'Store various bits of file metadata before proceeding
            dstDIB.SetOriginalFreeImageColorDepth FreeImage_GetBPP(fi_hDIB)
            fi_BPP = FreeImage_GetBPP(fi_hDIB)
            fi_DataType = FreeImage_GetImageType(fi_hDIB)
            dstDIB.SetDPI FreeImage_GetResolutionX(fi_hDIB), FreeImage_GetResolutionY(fi_hDIB), True
            FI_LoadBackgroundColor fi_hDIB, dstDIB
            dstDIB.SetOriginalColorDepth FreeImage_GetBPP(fi_hDIB)
            
            'Retrieve a matching ICC profile, if any
            If FreeImage_HasICCProfile(fi_hDIB) Then FI_LoadICCProfile fi_hDIB, dstDIB
            
            'Copy/transform the FreeImage object into a guaranteed 24- or 32-bpp destination DIB
            specialClipboardHandlingRequired = False
            loadSuccess = (FI_GetFIObjectIntoDIB(fi_hDIB, fi_multi_hDIB, fileFIF, fi_DataType, specialClipboardHandlingRequired, srcFilename, dstDIB, pageToLoad, showMessages, targetImage, suppressDebugData, multiDibIsDetached) = PD_SUCCESS)
            
            'Regardless of outcome, free ("unlock" in FI parlance) FreeImage's copy of this page
            FI_Unload fi_hDIB, fi_multi_hDIB, True, multiDibIsDetached
            
            If loadSuccess Then
            
                'Make sure the DIB meets new v7.0 requirements (including premultiplied alpha)
                If specialClipboardHandlingRequired Then dstDIB.ForceNewAlpha 255
                dstDIB.SetInitialAlphaPremultiplicationState True
                ImageImporter.ForceTo32bppMode dstDIB
                
                'Create a blank layer in the receiving image, and retrieve a pointer to it
                newLayerID = targetImage.CreateBlankLayer
                newLayerName = Layers.GenerateInitialLayerName(srcFilename, suggestedFilename, True, targetImage, dstDIB, pageToLoad)
                targetImage.GetLayerByID(newLayerID).InitializeNewLayer PDL_IMAGE, newLayerName, dstDIB, True
                
            End If
            
        Else
            #If DEBUGMODE = 1 Then
                pdDebug.LogAction "WARNING!  Failed to lock page #" & pageToLoad
            #End If
        End If
    
    Next pageToLoad
    
    'Release our original multipage image handle, then exit
    FI_Unload fi_hDIB, fi_multi_hDIB
    FI_DebugMsg "Multipage image load successful.  Original FreeImage handle released.", suppressDebugData
    
    FinishLoadingMultipageImage = PD_SUCCESS

End Function

'Given a path to a file and a destination pdDIB object, detect the file's type and store it inside the target DIB.
' (Knowing the source of a DIB allows us to run better heuristics on various image attributes.)
' On success, returns the detected FIF; on failure, returns FIF_UNKNOWN.  Note that the dstDIB's format may vary
' from the returned format, as part of the translation process between FreeImage format IDs, and PhotoDemon format IDs.
Private Function FI_DetermineFiletype(ByVal srcFilename As String, ByRef dstDIB As pdDIB) As FREE_IMAGE_FORMAT

    'While we could manually test our extension against the FreeImage database, it is capable of doing so itself.
    'First, check the file header to see if it matches a known head type
    Dim fileFIF As FREE_IMAGE_FORMAT
    fileFIF = FreeImage_GetFileTypeU(StrPtr(srcFilename))
    
    'For certain filetypes (CUT, MNG, PCD, TARGA and WBMP, according to the FreeImage documentation), the lack of a reliable
    ' header may prevent GetFileType from working.  As a result, double-check the file using its file extension.
    If (fileFIF = FIF_UNKNOWN) Then fileFIF = FreeImage_GetFIFFromFilenameU(StrPtr(srcFilename))
    
    'By this point, if the file still doesn't show up in FreeImage's database, abandon the import attempt.
    If (fileFIF <> FIF_UNKNOWN) Then
        If (Not FreeImage_FIFSupportsReading(fileFIF)) Then fileFIF = FIF_UNKNOWN
    End If
    
    'Store this file format inside the DIB
    Dim internalFIF As PD_IMAGE_FORMAT
    internalFIF = fileFIF
    
    'All pixmap formats are condensed down to PNM, which greatly simplifies internal tracking
    Select Case internalFIF
        Case PDIF_PBM, PDIF_PBMRAW, PDIF_PFM, PDIF_PGM, PDIF_PGMRAW, PDIF_PNM, PDIF_PPM, PDIF_PPMRAW
            internalFIF = PDIF_PNM
    End Select
    
    If (Not dstDIB Is Nothing) Then dstDIB.SetOriginalFormat internalFIF
    
    FI_DetermineFiletype = fileFIF
    
End Function

'Given a path to an incoming file, the file's format, and an optional "use preview" setting (which will grab thumbnails only),
' determine the correct load-time flags for FreeImage.
Private Function FI_DetermineImportFlags(ByVal srcFilename As String, ByVal fileFIF As FREE_IMAGE_FORMAT, Optional ByVal usePreviewIfAvailable As Boolean = False) As FREE_IMAGE_LOAD_OPTIONS

    'Certain filetypes offer import options.  Check the FreeImage type to see if we want to enable any optional flags.
    Dim fi_ImportFlags As FREE_IMAGE_LOAD_OPTIONS
    fi_ImportFlags = 0
    
    Select Case fileFIF
        
        Case FIF_ICO
            
            'For icons, we prefer a white background (default is black).
            ' NOTE: this check is now disabled, because it uses the AND mask incorrectly for mixed-format icons.  A better fix is
            ' provided below - see the section starting with "If (fileFIF = FIF_ICO) Then..."
            'fi_ImportFlags = FILO_ICO_MAKEALPHA
            
        Case FIF_JPEG
            
            'For JPEGs, specify a preference for accuracy and quality over import speed.
            fi_ImportFlags = fi_ImportFlags Or FILO_JPEG_ACCURATE
            
            'The user can modify EXIF auto-rotation behavior
            If ImageImporter.GetImportPref_JPEGOrientation() Then fi_ImportFlags = fi_ImportFlags Or FILO_JPEG_EXIFROTATE
            
            'CMYK files are fully supported
            fi_ImportFlags = fi_ImportFlags Or FILO_JPEG_CMYK
        
        Case FIF_PNG
            
            'For PNGs, embedded gamma is ignored (we handle this manually, later in the load process)
            fi_ImportFlags = fi_ImportFlags Or FILO_PNG_IGNOREGAMMA
        
        Case FIF_PSD
            
            'CMYK files are fully supported
            fi_ImportFlags = fi_ImportFlags Or FILO_PSD_CMYK
        
        Case FIF_RAW
            
            'If this is not a primary image, RAW format files can load just their thumbnail.  This is significantly faster.
            If usePreviewIfAvailable Then fi_ImportFlags = fi_ImportFlags Or FILO_RAW_PREVIEW
        
        Case FIF_TIFF
            
            'CMYK files are fully supported
            fi_ImportFlags = fi_ImportFlags Or TIFF_CMYK
    
    End Select
        
    FI_DetermineImportFlags = fi_ImportFlags
    
End Function

Private Function FI_LoadICCProfile(ByVal fi_Bitmap As Long, ByRef dstDIB As pdDIB) As Boolean
    
    If (FreeImage_GetICCProfileSize(fi_Bitmap) > 0) Then
        Dim fiProfileHeader As FIICCPROFILE
        fiProfileHeader = FreeImage_GetICCProfile(fi_Bitmap)
        FI_LoadICCProfile = dstDIB.ICCProfile.LoadICCFromPtr(fiProfileHeader.Size, fiProfileHeader.Data)
    Else
        FI_DebugMsg "WARNING!  ICC profile size is invalid (<=0)."
    End If
    
End Function

Private Function FI_LoadBackgroundColor(ByVal fi_Bitmap As Long, ByRef dstDIB As pdDIB) As Boolean

    'Check to see if the image has a background color embedded
    If FreeImage_HasBackgroundColor(fi_Bitmap) Then
                
        'FreeImage will pass the background color to an RGBquad type-variable
        Dim rQuad As RGBQuad
        If FreeImage_GetBackgroundColor(fi_Bitmap, rQuad) Then
        
            'Normally, we can reassemble the .r/g/b values in the object, but paletted images work a bit differently - the
            ' palette index is stored in .rgbReserved.  Check for that, and if it's non-zero, retrieve the palette value instead.
            If (rQuad.Alpha <> 0) Then
                Dim fi_Palette() As Long
                fi_Palette = FreeImage_GetPaletteExLong(fi_Bitmap)
                dstDIB.SetBackgroundColor fi_Palette(rQuad.Alpha)
                
            'Otherwise it's easy - just reassemble the RGB values from the quad
            Else
                dstDIB.SetBackgroundColor RGB(rQuad.Red, rQuad.Green, rQuad.Blue)
            End If
            
            FI_LoadBackgroundColor = True
        
        End If
    
    End If
    
    'No background color found; write -1 to notify of this.
    If (Not FI_LoadBackgroundColor) Then dstDIB.SetBackgroundColor -1
    
End Function

Private Function FI_GetImageTypeAsString(ByVal fi_DataType As FREE_IMAGE_TYPE) As String

    Select Case fi_DataType
        Case FIT_UNKNOWN
            FI_GetImageTypeAsString = "Unknown"
        Case FIT_BITMAP
            FI_GetImageTypeAsString = "Standard bitmap (1 to 32bpp)"
        Case FIT_UINT16
            FI_GetImageTypeAsString = "HDR Grayscale (Unsigned int)"
        Case FIT_INT16
            FI_GetImageTypeAsString = "HDR Grayscale (Signed int)"
        Case FIT_UINT32
            FI_GetImageTypeAsString = "HDR Grayscale (Unsigned long)"
        Case FIT_INT32
            FI_GetImageTypeAsString = "HDR Grayscale (Signed long)"
        Case FIT_FLOAT
            FI_GetImageTypeAsString = "HDR Grayscale (Float)"
        Case FIT_DOUBLE
            FI_GetImageTypeAsString = "HDR Grayscale (Double)"
        Case FIT_COMPLEX
            FI_GetImageTypeAsString = "Complex (2xDouble)"
        Case FIT_RGB16
            FI_GetImageTypeAsString = "HDR RGB (3xInteger)"
        Case FIT_RGBA16
            FI_GetImageTypeAsString = "HDR RGBA (4xInteger)"
        Case FIT_RGBF
            FI_GetImageTypeAsString = "HDR RGB (3xFloat)"
        Case FIT_RGBAF
            FI_GetImageTypeAsString = "HDR RGBA (4xFloat)"
    End Select

End Function

'Unload a FreeImage handle.  If the handle is to a multipage object, pass that handle, too; this function will automatically switch
' to multipage behavior if the multipage handle is non-zero.
'
'On success, any unloaded handles will be forcibly reset to zero.
Private Sub FI_Unload(ByRef srcFIHandle As Long, Optional ByRef srcFIMultipageHandle As Long = 0, Optional ByVal leaveMultiHandleOpen As Boolean = False, Optional ByRef fiDibIsDetached As Boolean = False)
    If ((srcFIMultipageHandle = 0) Or fiDibIsDetached) Then
        If (srcFIHandle <> 0) Then FreeImage_UnloadEx srcFIHandle
        srcFIHandle = 0
    Else
        
        If (srcFIHandle <> 0) Then
            FreeImage_UnlockPage srcFIMultipageHandle, srcFIHandle, False
            srcFIHandle = 0
        End If
        
        'Now comes a weird bit of special handling.  It may be desirable to unlock a page, but leave the base multipage image open.
        ' (When loading a multipage image, this yields much better performance.)  However, we need to note that the resulting
        ' DIB handle is now "detached", meaning we can't use UnlockPage on it in the future.
        If (Not leaveMultiHandleOpen) Then
            FreeImage_CloseMultiBitmap srcFIMultipageHandle
            srcFIMultipageHandle = 0
        Else
            fiDibIsDetached = True
        End If
        
    End If
End Sub

'See if an image file is actually comprised of multiple files (e.g. animated GIFs, multipage TIFs).
' Input: file name to be checked
' Returns: 0 if only one image is found.  Page (or frame) count if multiple images are found.
Public Function IsMultiImage(ByVal srcFilename As String) As Long

    On Error GoTo isMultiImage_Error
    
    'Double-check that FreeImage.dll was located at start-up
    If (Not g_ImageFormats.FreeImageEnabled) Then
        IsMultiImage = 0
        Exit Function
    End If
        
    'Determine the file type.  (Currently, this feature only works on animated GIFs, multipage TIFFs, and icons.)
    Dim fileFIF As FREE_IMAGE_FORMAT
    fileFIF = FreeImage_GetFileTypeU(StrPtr(srcFilename))
    If (fileFIF = FIF_UNKNOWN) Then fileFIF = FreeImage_GetFIFFromFilenameU(StrPtr(srcFilename))
    
    'If FreeImage can't determine the file type, or if the filetype is not GIF or TIF, return False
    If (Not FreeImage_FIFSupportsReading(fileFIF)) Or ((fileFIF <> PDIF_GIF) And (fileFIF <> PDIF_TIFF) And (fileFIF <> FIF_ICO)) Then
        IsMultiImage = 0
        Exit Function
    End If
    
    'At this point, we are guaranteed that the image is a GIF, TIFF, or icon file.
    ' Open the file using the multipage function
    Dim fi_multi_hDIB As Long
    If (fileFIF = PDIF_GIF) Then
        fi_multi_hDIB = FreeImage_OpenMultiBitmap(PDIF_GIF, srcFilename)
    ElseIf (fileFIF = FIF_ICO) Then
        fi_multi_hDIB = FreeImage_OpenMultiBitmap(FIF_ICO, srcFilename)
    Else
        fi_multi_hDIB = FreeImage_OpenMultiBitmap(PDIF_TIFF, srcFilename)
    End If
    
    'Get the page count, then close the file
    Dim pageCheck As Long
    pageCheck = FreeImage_GetPageCount(fi_multi_hDIB)
    FreeImage_CloseMultiBitmap fi_multi_hDIB
    
    'Return the page count (which will be zero if only a single page or frame is present)
    IsMultiImage = pageCheck
    
    Exit Function
    
isMultiImage_Error:

    IsMultiImage = 0

End Function

'Given a source FreeImage handle, and a destination pdDIB that contains a valid ICC profile, create a new, ICC-corrected version of the
' image and place it inside the destination DIB if at all possible.  The byref parameter pdDIBIsDestination will be set to TRUE if this
' approach succeeds; if it is set to FALSE, you must use the fallbackFIHandle, instead, which will point to a newly allocated
' FreeImage object.
'
'IMPORTANT NOTE: the source handle *will not be freed*, even if the transformation is successful.  The caller must do this manually.
Private Function GenerateICCCorrectedFIDIB(ByVal srcFIHandle As Long, ByRef dstDIB As pdDIB, ByRef pdDIBIsDestination As Boolean, ByRef fallbackFIHandle As Long) As Boolean
    
    GenerateICCCorrectedFIDIB = False
    pdDIBIsDestination = False
    fallbackFIHandle = 0
    
    'Retrieve the source image's bit-depth and data type.
    Dim fi_BPP As Long
    fi_BPP = FreeImage_GetBPP(srcFIHandle)
    
    Dim fi_DataType As FREE_IMAGE_TYPE
    fi_DataType = FreeImage_GetImageType(srcFIHandle)
    
    'FreeImage provides a bunch of custom identifiers for various grayscale types.  When one of these is found, we can
    ' skip further heuristics.
    Dim isGrayscale As Boolean
    Select Case fi_DataType
    
        Case FIT_DOUBLE, FIT_FLOAT, FIT_INT16, FIT_UINT16, FIT_INT32, FIT_UINT32
            isGrayscale = True
        
        'Note that a lack of identifiers *doesn't necessarily mean* the image is not grayscale.  It simply means the image is
        ' not in a FreeImage-specific grayscale format.  (Some formats, like 16-bit grayscale + 16-bit alpha are not supported
        ' by FreeImage, and will be returned as 64-bpp RGBA instead.)
        Case Else
            isGrayscale = False
    
    End Select
    
    'Check for 8-bpp grayscale images now; they use a separate detection technique
    If (Not isGrayscale) Then
        If (fi_BPP = 8) Then
            If ((FreeImage_GetColorType(srcFIHandle) = FIC_MINISBLACK) Or (FreeImage_GetColorType(srcFIHandle) = FIC_MINISWHITE)) Then isGrayscale = True
        End If
    End If
        
    'Also, check for transparency in the source image.  Color-management will generally ignore alpha values, but we need to
    ' supply a flag telling the ICC engine to mirror alpha bytes to the new DIB copy.
    Dim hasTransparency As Boolean, transparentEntries As Long
    hasTransparency = FreeImage_IsTransparent(srcFIHandle)
    If (Not hasTransparency) Then
    
        transparentEntries = FreeImage_GetTransparencyCount(srcFIHandle)
        hasTransparency = (transparentEntries > 0)
        
        '32-bpp images with a fully opaque alpha channel may return FALSE; this is a stupid FreeImage issue.
        ' Check for such a mismatch, and forcibly mark the data as 32-bpp RGBA.  (Otherwise we will get stride issues when
        ' applying the color management transform.)
        If (fi_BPP = 32) Then
            If ((FreeImage_GetColorType(srcFIHandle) = FIC_RGB) Or (FreeImage_GetColorType(srcFIHandle) = FIC_RGBALPHA)) Then hasTransparency = True
        End If
        
    End If
    
    'Allocate a destination FI DIB object in default BGRA order.  Note that grayscale images specifically use an 8-bpp target;
    ' this is by design, as the ICC engine cannot perform grayscale > RGB expansion.  (Instead, we must perform the ICC transform
    ' in pure grayscale space, *then* translate the result to RGB.)
    '
    'Note also that we still have not addressed the problem where "isGrayscale = True" but FreeImage has mis-detected color.
    ' We will deal with this in a subsequent step.
    Dim targetBitDepth As Long
    If isGrayscale Then
        targetBitDepth = 8
    Else
        If hasTransparency Then targetBitDepth = 32 Else targetBitDepth = 24
    End If
    
    '8-bpp grayscale images will use a FreeImage container instead of a pdDIB.  (pdDIB objects only support 24- and 32-bpp targets.)
    Dim newFIDIB As Long
    If (targetBitDepth = 8) Then
        newFIDIB = FreeImage_Allocate(FreeImage_GetWidth(srcFIHandle), FreeImage_GetHeight(srcFIHandle), targetBitDepth)
    Else
        dstDIB.CreateBlank FreeImage_GetWidth(srcFIHandle), FreeImage_GetHeight(srcFIHandle), 32, 0, 255
    End If
    
    'We now want to use LittleCMS to perform an immediate ICC correction.
    
    'Start by creating two LCMS profile handles:
    ' 1) a source profile (the in-memory copy of the ICC profile associated with this DIB)
    ' 2) a destination profile (the current PhotoDemon working space)
    Dim srcProfile As pdLCMSProfile, dstProfile As pdLCMSProfile
    Set srcProfile = New pdLCMSProfile
    Set dstProfile = New pdLCMSProfile
    
    If srcProfile.CreateFromPDDib(dstDIB) Then
        
        Dim specialGrayscaleRequired As Boolean: specialGrayscaleRequired = False
        
        'We now need to perform a special check for grayscale image data in formats that FreeImage does not support.
        ' Start by querying the colorspace of the source ICC profile.
        If (srcProfile.GetColorSpace = cmsSigGray) Then
        
            'This is a grayscale profile.  If the source image is *not* grayscale, we need to create a grayscale copy now.
            If (Not isGrayscale) Then
            
                'The source image is in a grayscale format that FreeImage does not support, yet it has a grayscale ICC
                ' profile attached.  This is a big problem because we cannot pass a grayscale ICC profile and RGBA data
                ' to the ICC engine and expect it to work.  The ICC profile color space and image color space must match.
                
                'Because we have no control over the color profile, we must modify the image bits instead.  Set a matching
                ' flag, which will divert the subsequent profile handler.
                isGrayscale = True
                specialGrayscaleRequired = True
                
            End If
            
        End If
        
        #If DEBUGMODE = 1 Then
            pdDebug.LogAction "Preparing to color-manage incoming image; grayscale=" & UCase$(CStr(isGrayscale)) & ", specialHandling=" & UCase$(CStr(specialGrayscaleRequired)) & ", transparency=" & UCase$(CStr(hasTransparency))
        #End If
        
        Dim dstProfileSuccess As Long
        If isGrayscale Then
            dstProfileSuccess = dstProfile.CreateGenericGrayscaleProfile
        Else
            dstProfileSuccess = dstProfile.CreateSRGBProfile
        End If
        
        If dstProfileSuccess Then
            
            'DISCLAIMER! Until rendering intent has a dedicated preference, PD defaults to perceptual render intent.
            ' This provides better results on most images, it correctly preserves gamut, and it is the standard
            ' behavior for PostScript workflows.  See http://fieryforums.efi.com/showthread.php/835-Rendering-Intent-Control-for-Embedded-Profiles
            ' Also see: https://developer.mozilla.org/en-US/docs/ICC_color_correction_in_Firefox)
            '
            'For future reference, I've left the code below for retrieving rendering intent from the source profile
            Dim targetRenderingIntent As LCMS_RENDERING_INTENT
            targetRenderingIntent = INTENT_PERCEPTUAL
            'targetRenderingIntent = srcProfile.GetRenderingIntent
            
            'Now, we need to create a transform between the two bit-depths.  This involves mapping the FreeImage bit-depth constants
            ' to compatible LCMS ones.
            Dim srcPixelFormat As LCMS_PIXEL_FORMAT, dstPixelFormat As LCMS_PIXEL_FORMAT
            
            'FreeImage does not natively support grayscale+alpha images.  These will be implicitly mapped to RGBA, so we only
            ' need to check grayscale formats if hasTransparency = FALSE.
            Dim transformImpossible As Boolean: transformImpossible = False
            
            If isGrayscale Then
                
                'Regardless of alpha, we want to map the grayscale data to an 8-bpp target.  (If alpha is present, we will
                ' manually back up the current alpha-bytes, then re-apply them after the ICC transform completes.)
                dstPixelFormat = TYPE_GRAY_8
                
                If (fi_DataType = FIT_DOUBLE) Then
                    srcPixelFormat = TYPE_GRAY_DBL
                ElseIf (fi_DataType = FIT_FLOAT) Then
                    srcPixelFormat = TYPE_GRAY_FLT
                ElseIf (fi_DataType = FIT_INT16) Then
                    srcPixelFormat = TYPE_GRAY_16
                ElseIf (fi_DataType = FIT_UINT16) Then
                    srcPixelFormat = TYPE_GRAY_16
                ElseIf (fi_DataType = FIT_INT32) Then
                    transformImpossible = True
                ElseIf (fi_DataType = FIT_UINT32) Then
                    transformImpossible = True
                Else
                    
                    'Special pixel formats will be pre-converted to a valid source format
                    If specialGrayscaleRequired Then
                        If (fi_DataType = FIT_RGB16) Then
                            srcPixelFormat = TYPE_GRAY_16
                        ElseIf (fi_DataType = FIT_RGBA16) Then
                            srcPixelFormat = TYPE_GRAY_16
                        Else
                            srcPixelFormat = TYPE_GRAY_8
                        End If
                    Else
                        srcPixelFormat = TYPE_GRAY_8
                    End If
                    
                End If
                
            Else
                
                'Regardless of source transparency, we *always* map the image to a 32-bpp target
                dstPixelFormat = TYPE_BGRA_8
                    
                If hasTransparency Then
                
                    If (fi_DataType = FIT_BITMAP) Then
                        If (FreeImage_GetRedMask(srcFIHandle) > FreeImage_GetBlueMask(srcFIHandle)) Then
                            srcPixelFormat = TYPE_BGRA_8
                        Else
                            srcPixelFormat = TYPE_RGBA_8
                        End If
                        
                    ElseIf (fi_DataType = FIT_RGBA16) Then
                        If (FreeImage_GetRedMask(srcFIHandle) > FreeImage_GetBlueMask(srcFIHandle)) Then
                            srcPixelFormat = TYPE_BGRA_16
                        Else
                            srcPixelFormat = TYPE_RGBA_16
                        End If
                        
                    'The only other possibility is RGBAF; LittleCMS supports this format, but we'd have to construct our own macro
                    ' to define it.  Just skip it at present.
                    Else
                        transformImpossible = True
                    End If
                    
                Else
                    
                    If (fi_DataType = FIT_BITMAP) Then
                        If (FreeImage_GetRedMask(srcFIHandle) > FreeImage_GetBlueMask(srcFIHandle)) Then
                            srcPixelFormat = TYPE_BGR_8
                        Else
                            srcPixelFormat = TYPE_RGB_8
                        End If
                    ElseIf (fi_DataType = FIT_RGB16) Then
                        If (FreeImage_GetRedMask(srcFIHandle) > FreeImage_GetBlueMask(srcFIHandle)) Then
                            srcPixelFormat = TYPE_BGR_16
                        Else
                            srcPixelFormat = TYPE_RGB_16
                        End If
                        
                    'The only other possibility is RGBF; LittleCMS supports this format, but we'd have to construct our own macro
                    ' to define it.  Just skip it at present.
                    Else
                        transformImpossible = True
                    End If
                    
                End If
            
            End If
            
            'Some color spaces may not be supported; that's okay - we'll use tone-mapping to handle them.
            If (Not transformImpossible) Then
                
                'Create a transform that uses the target DIB as both the source and destination
                Dim cTransform As pdLCMSTransform
                Set cTransform = New pdLCMSTransform
                If cTransform.CreateTwoProfileTransform(srcProfile, dstProfile, srcPixelFormat, dstPixelFormat, targetRenderingIntent) Then
                    
                    'LittleCMS 2.0 allows us to free our source profiles immediately after a transform is created.
                    ' (Note that we don't *need* to do this, nor does this code leak if we don't manually free both
                    '  profiles, but as we're about to do an energy- and memory-intensive operation, it doesn't
                    '  hurt to free the profiles now.)
                    Set srcProfile = Nothing: Set dstProfile = Nothing
                    
                    'At present, grayscale images will be converted into a destination FreeImage handle
                    Dim transformSuccess As Boolean
                    
                    If isGrayscale Then
                        
                        'If the source image uses a grayscale+alpha format, we need to handle it specially
                        If specialGrayscaleRequired Then
                            
                            'Release the temporary FreeImage DIB we initialized; we're going to circumvent the need for it
                            FI_Unload newFIDIB
                            newFIDIB = 0
                            
                            'Pass control to a dedicated ICC handler
                            transformSuccess = HandleSpecialGrayscaleICC(srcFIHandle, dstDIB, pdDIBIsDestination, newFIDIB, cTransform)
                        
                        Else
                            transformSuccess = cTransform.ApplyTransformToArbitraryMemory(FreeImage_GetScanline(srcFIHandle, 0), FreeImage_GetScanline(newFIDIB, 0), FreeImage_GetPitch(srcFIHandle), FreeImage_GetPitch(newFIDIB), FreeImage_GetHeight(srcFIHandle), FreeImage_GetWidth(srcFIHandle))
                        End If
                        
                    Else
                        transformSuccess = cTransform.ApplyTransformToArbitraryMemory(FreeImage_GetScanline(srcFIHandle, 0), dstDIB.GetDIBScanline(0), FreeImage_GetPitch(srcFIHandle), dstDIB.GetDIBStride, FreeImage_GetHeight(srcFIHandle), FreeImage_GetWidth(srcFIHandle), True)
                    End If
                    
                    If transformSuccess Then
                    
                        FI_DebugMsg "Color-space transformation successful."
                        dstDIB.ICCProfile.MarkSuccessfulProfileApplication
                        GenerateICCCorrectedFIDIB = True
                        
                        'We now need to clarify for the caller where the ICC-transformed data sits.  8-bpp grayscale *without* alpha
                        ' will be stored in a new 8-bpp FreeImage object.  Other formats have likely been placed directly into
                        ' the target pdDIB object (which means the FreeImage loader can skip subsequent steps).
                        If isGrayscale Then
                            
                            If specialGrayscaleRequired Then
                                pdDIBIsDestination = True
                                fallbackFIHandle = 0
                                If (targetBitDepth = 24) Then dstDIB.SetInitialAlphaPremultiplicationState True Else dstDIB.SetAlphaPremultiplication True
                            Else
                                pdDIBIsDestination = False
                                fallbackFIHandle = newFIDIB
                            End If
                            
                        'Non-grayscale images *always* get converted directly into a pdDIB object.
                        Else
                            pdDIBIsDestination = True
                            fallbackFIHandle = 0
                            If (targetBitDepth = 24) Then dstDIB.SetInitialAlphaPremultiplicationState True Else dstDIB.SetAlphaPremultiplication True
                        End If
                        
                    End If
                    
                    'Note that we could free the transform here, but it's unnecessary.  (The pdLCMSTransform class
                    ' is self-freeing upon destruction.)
                    
                Else
                    FI_DebugMsg "WARNING!  Plugin_FreeImage.GenerateICCCorrectedFIDIB failed to create a valid transformation handle!"
                End If
            
            'Impossible transformations return a null handle
            Else
                FI_DebugMsg "WARNING!  Plugin_FreeImage.GenerateICCCorrectedFIDIB is functional, but the source pixel format is incompatible with the current ICC engine."
            End If
        
        Else
            FI_DebugMsg "WARNING!  Plugin_FreeImage.GenerateICCCorrectedFIDIB failed to create a valid destination profile handle."
        End If
    
    Else
        FI_DebugMsg "WARNING!  Plugin_FreeImage.GenerateICCCorrectedFIDIB failed to create a valid source profile handle."
    End If
    
    'If the transformation failed, free our temporarily allocated FreeImage DIB
    If (Not GenerateICCCorrectedFIDIB) And (newFIDIB <> 0) Then FI_Unload newFIDIB

End Function

'Because FreeImage doesn't support grayscale+alpha image formats, we have to jump through ugly hoops to handle these manually.
' The exact workaround varies by file type, as some files will be expanded to RGBA (e.g. PNG), while others will simply be dumped
' into arbitrary containers (e.g. 16-bpp grayscale + 16-bpp alpha TIFFs are unceremoniously dumped into 32-bpp RGBA).
'
'If successful, this function will *always* return a finished result inside the target pdDIB object.
Private Function HandleSpecialGrayscaleICC(ByVal srcFIHandle As Long, ByRef dstDIB As pdDIB, ByRef pdDIBIsDestination As Boolean, ByRef newFIDIB As Long, ByRef cTransform As pdLCMSTransform) As Boolean
    
    'Grayscale+alpha PNG files are expanded to RGBA; this actually makes them relatively easy to compensate for
    If (dstDIB.GetOriginalFormat = FIF_PNG) Then
    
        'Make sure the pdDIB object exists at the correct dimensions
        If (dstDIB.GetDIBWidth <> FreeImage_GetWidth(srcFIHandle)) Or (dstDIB.GetDIBHeight <> FreeImage_GetHeight(srcFIHandle)) Then
            dstDIB.CreateBlank FreeImage_GetWidth(srcFIHandle), FreeImage_GetHeight(srcFIHandle), 32, 0, 255
        End If
        
        'We are now going to do several things simultaneously:
        ' 1) manually copy all alpha bytes from the FreeImage object to the destination DIB
        ' 2) manually copy all grayscale values into a dedicated integer array
        Dim fi_DataType As FREE_IMAGE_TYPE
        fi_DataType = FreeImage_GetImageType(srcFIHandle)
        
        'This array will consistently be updated to point to the current line of pixels in the FreeImage object
        Dim srcImageDataInt() As Integer, srcImageDataByte() As Byte
        Dim srcSA As SafeArray1D
        
        'Same, but for the destination pdDIB object.
        Dim dstImageData() As Byte
        Dim dstSA As SafeArray2D
        dstDIB.WrapArrayAroundDIB dstImageData, dstSA
        
        'Scanline access variables
        Dim iWidth As Long, iHeight As Long, iHeightInv As Long, iScanWidth As Long
        iWidth = FreeImage_GetWidth(srcFIHandle) - 1
        iHeight = FreeImage_GetHeight(srcFIHandle) - 1
        iScanWidth = FreeImage_GetPitch(srcFIHandle)
        
        Dim x As Long, y As Long
        Dim tmpInt As Integer, tmpByte As Byte
        Dim cmBytes() As Byte
        
        Dim srcGraysInt() As Integer, srcGraysByte() As Byte
        
        'Currently, only 16-bit PNGs are handled manually
        If (fi_DataType = FIT_RGBA16) Then
            
            'Temporary 16-bpp int array for storing grayscale values
            ReDim srcGraysInt(0 To iWidth, 0 To iHeight) As Integer
            
            For y = 0 To iHeight
            
                'FreeImage DIBs are stored bottom-up; we invert them during processing
                iHeightInv = iHeight - y
                
                'Point a 1D VB array at this scanline
                With srcSA
                    
                    'Size of individual elements (integers, in our case)
                    .cbElements = 2
                    .cDims = 1
                    .lBound = 0
                    
                    'Number of entries in each x-line of the array (4, for RGBA)
                    .cElements = iScanWidth * 4
                    .pvData = FreeImage_GetScanline(srcFIHandle, iHeightInv)
                    
                End With
                CopyMemory ByVal VarPtrArray(srcImageDataInt), VarPtr(srcSA), 4
                    
                'Iterate through this line, converting values as we go
                For x = 0 To iWidth
                    
                    'First, extract the target gray value and shove it into the destination integer array
                    tmpInt = srcImageDataInt(x * 4)
                    srcGraysInt(x, y) = tmpInt
                    
                    'Next, retrieve the source alpha value and copy the most-significant bit directly into the destination DIB
                    tmpInt = srcImageDataInt(x * 4 + 3)
                    dstImageData(x * 4 + 3, y) = (tmpInt And 255)
                    
                Next x
                
            Next y
            
            'Free our array references
            CopyMemory ByVal VarPtrArray(srcImageDataInt), 0&, 4
            dstDIB.UnwrapArrayFromDIB dstImageData
            
            'Next, perform ICC correction on the integer array, and place the result inside a custom byte array
            ReDim cmBytes(0 To iWidth, 0 To iHeight) As Byte
            HandleSpecialGrayscaleICC = cTransform.ApplyTransformToArbitraryMemory(VarPtr(srcGraysInt(0, 0)), VarPtr(cmBytes(0, 0)), dstDIB.GetDIBWidth * 2, dstDIB.GetDIBWidth, dstDIB.GetDIBHeight, dstDIB.GetDIBWidth)
            Erase srcGraysInt
            
            #If DEBUGMODE = 1 Then
                pdDebug.LogAction "Special grayscale+alpha ICC handler reported " & UCase$(CStr(HandleSpecialGrayscaleICC)) & " for custom transform process"
            #End If
            
            If HandleSpecialGrayscaleICC Then
                
                'We now have an ICC-transformed grayscale DIB sitting inside newFIDIB.  Repeat the previous steps of parsing out
                ' the grayscale bytes, and storing them directly inside the destination DIB.
                dstDIB.WrapArrayAroundDIB dstImageData, dstSA
                
                For y = 0 To iHeight
                        
                    'Iterate through this line, converting values as we go
                    For x = 0 To iWidth
                        tmpByte = cmBytes(x, y)
                        dstImageData(x * 4, y) = tmpByte
                        dstImageData(x * 4 + 1, y) = tmpByte
                        dstImageData(x * 4 + 2, y) = tmpByte
                    Next x
                    
                Next y
                
                dstDIB.UnwrapArrayFromDIB dstImageData
                
                'Note that the destination DIB is already prepped and ready to go!
                pdDIBIsDestination = True
                
            End If
                
        '/End RGBA16 handling
        
        'The only other possibility is RGBA8 handling
        Else
            
            'Temporary 8-bpp byte array for storing grayscale values
            ReDim srcGraysByte(0 To iWidth, 0 To iHeight) As Byte
            
            For y = 0 To iHeight
            
                'FreeImage DIBs are stored bottom-up; we invert them during processing
                iHeightInv = iHeight - y
                
                'Point a 1D VB array at this scanline
                With srcSA
                    
                    'Size of individual elements (bytes, in our case)
                    .cbElements = 1
                    .cDims = 1
                    .lBound = 0
                    
                    'Number of entries in each x-line of the array (4, for RGBA)
                    .cElements = iScanWidth * 4
                    .pvData = FreeImage_GetScanline(srcFIHandle, iHeightInv)
                    
                End With
                CopyMemory ByVal VarPtrArray(srcImageDataByte), VarPtr(srcSA), 4
                    
                'Iterate through this line, converting values as we go
                For x = 0 To iWidth
                    
                    'First, extract the target gray value and shove it into the destination integer array
                    tmpByte = srcImageDataByte(x * 4)
                    srcGraysByte(x, y) = tmpByte
                    
                    'Next, retrieve the source alpha value and copy the most-significant bit directly into the destination DIB
                    tmpByte = srcImageDataByte(x * 4 + 3)
                    dstImageData(x * 4 + 3, y) = tmpByte
                    
                Next x
                
            Next y
            
            'Free our array references
            CopyMemory ByVal VarPtrArray(srcImageDataByte), 0&, 4
            dstDIB.UnwrapArrayFromDIB dstImageData
            
            'Next, perform ICC correction on the integer array, and place the result inside a custom byte array
            ReDim cmBytes(0 To iWidth, 0 To iHeight) As Byte
            HandleSpecialGrayscaleICC = cTransform.ApplyTransformToArbitraryMemory(VarPtr(srcGraysByte(0, 0)), VarPtr(cmBytes(0, 0)), dstDIB.GetDIBWidth, dstDIB.GetDIBWidth, dstDIB.GetDIBHeight, dstDIB.GetDIBWidth)
            Erase srcGraysByte
            
            #If DEBUGMODE = 1 Then
                pdDebug.LogAction "Special grayscale+alpha ICC handler reported " & UCase$(CStr(HandleSpecialGrayscaleICC)) & " for custom transform process"
            #End If
            
            If HandleSpecialGrayscaleICC Then
                
                'We now have an ICC-transformed grayscale DIB sitting inside newFIDIB.  Repeat the previous steps of parsing out
                ' the grayscale bytes, and storing them directly inside the destination DIB.
                dstDIB.WrapArrayAroundDIB dstImageData, dstSA
                
                For y = 0 To iHeight
                        
                    'Iterate through this line, converting values as we go
                    For x = 0 To iWidth
                        tmpByte = cmBytes(x, y)
                        dstImageData(x * 4, y) = tmpByte
                        dstImageData(x * 4 + 1, y) = tmpByte
                        dstImageData(x * 4 + 2, y) = tmpByte
                    Next x
                    
                Next y
                
                dstDIB.UnwrapArrayFromDIB dstImageData
                
                'Note that the destination DIB is already prepped and ready to go!
                pdDIBIsDestination = True
                
            End If
                
        '/End RGBA8 handling
        End If
        
    '/End PNG handling
    End If

End Function

'Given a source FreeImage handle in CMYK format, and a destination pdDIB that contains a valid ICC profile, create a new, ICC-corrected
' version of the image, in RGB format, and stored inside the destination pdDIB.
'
'IMPORTANT NOTE: the source handle *will not be freed*, even if the transformation is successful.  The caller must free it manually.
Private Function ConvertCMYKFiDIBToRGB(ByVal srcFIHandle As Long, ByRef dstDIB As pdDIB) As Boolean
    
    'As a failsafe, confirm that the incoming image is CMYK format
    If (FreeImage_GetColorType(srcFIHandle) = FIC_CMYK) Then
    
        'Prep the source DIB
        If dstDIB.CreateBlank(FreeImage_GetWidth(srcFIHandle), FreeImage_GetHeight(srcFIHandle), 32, 0, 255) Then
            
            'We now want to use LittleCMS to perform an immediate ICC correction.
            
            'Start by creating two LCMS profile handles:
            ' 1) a source profile (the in-memory copy of the ICC profile associated with this DIB)
            ' 2) a destination profile (the current PhotoDemon working space)
            Dim srcProfile As pdLCMSProfile, dstProfile As pdLCMSProfile
            Set srcProfile = New pdLCMSProfile
            Set dstProfile = New pdLCMSProfile
            
            If srcProfile.CreateFromPDDib(dstDIB) Then
                
                If dstProfile.CreateSRGBProfile Then
                    
                    'DISCLAIMER! Until rendering intent has a dedicated preference, PD defaults to perceptual render intent.
                    ' This provides better results on most images, it correctly preserves gamut, and it is the standard
                    ' behavior for PostScript workflows.  See http://fieryforums.efi.com/showthread.php/835-Rendering-Intent-Control-for-Embedded-Profiles
                    ' Also see: https://developer.mozilla.org/en-US/docs/ICC_color_correction_in_Firefox)
                    '
                    'For future reference, I've left the code below for retrieving rendering intent from the source profile
                    Dim targetRenderingIntent As LCMS_RENDERING_INTENT
                    targetRenderingIntent = INTENT_PERCEPTUAL
                    'targetRenderingIntent = srcProfile.GetRenderingIntent
                    
                    'Now, we need to create a transform between the two bit-depths.  This involves mapping the FreeImage bit-depth constants
                    ' to compatible LCMS ones.
                    Dim srcPixelFormat As LCMS_PIXEL_FORMAT, dstPixelFormat As LCMS_PIXEL_FORMAT
                    If (FreeImage_GetBPP(srcFIHandle) = 64) Then
                        srcPixelFormat = TYPE_CMYK_16
                    Else
                        srcPixelFormat = TYPE_CMYK_8
                    End If
                    
                    dstPixelFormat = TYPE_BGRA_8
                    
                    'Create a transform that uses the target DIB as both the source and destination
                    Dim cTransform As pdLCMSTransform
                    Set cTransform = New pdLCMSTransform
                    If cTransform.CreateTwoProfileTransform(srcProfile, dstProfile, srcPixelFormat, dstPixelFormat, targetRenderingIntent) Then
                        
                        'LittleCMS 2.0 allows us to free our source profiles immediately after a transform is created.
                        ' (Note that we don't *need* to do this, nor does this code leak if we don't manually free both
                        '  profiles, but as we're about to do an energy- and memory-intensive operation, it doesn't
                        '  hurt to free the profiles now.)
                        Set srcProfile = Nothing: Set dstProfile = Nothing
                        
                        If cTransform.ApplyTransformToArbitraryMemory(FreeImage_GetScanline(srcFIHandle, 0), dstDIB.GetDIBScanline(0), FreeImage_GetPitch(srcFIHandle), dstDIB.GetDIBStride, FreeImage_GetHeight(srcFIHandle), FreeImage_GetWidth(srcFIHandle), True) Then
                            FI_DebugMsg "ICC profile transformation successful.  New FreeImage handle now lives in the current RGB working space."
                            dstDIB.ICCProfile.MarkSuccessfulProfileApplication
                            dstDIB.SetInitialAlphaPremultiplicationState True
                            ConvertCMYKFiDIBToRGB = True
                        End If
                    
                    'Note that we could free the transform here, but it's unnecessary.  (The pdLCMSTransform class
                    ' is self-freeing upon destruction.)
                    
                    Else
                        FI_DebugMsg "WARNING!  Plugin_FreeImage.ConvertCMYKFiDIBToRGB failed to create a valid transformation handle!"
                    End If
                    
                Else
                    FI_DebugMsg "WARNING!  Plugin_FreeImage.ConvertCMYKFiDIBToRGB failed to create a valid destination profile handle."
                End If
            
            Else
                FI_DebugMsg "WARNING!  Plugin_FreeImage.ConvertCMYKFiDIBToRGB failed to create a valid source profile handle."
            End If
            
        Else
            FI_DebugMsg "WARNING!  Destination DIB could not be allocated - is the source image corrupt?"
        End If
    
    Else
        FI_DebugMsg "WARNING!  Don't call ConvertCMYKFiDIBToRGB() if the source object is not CMYK format!"
    End If

End Function

'Given a FreeImage handle, return a 24 or 32bpp pdDIB object, as relevant.  Note that this function does not modify premultiplication
' status of 32bpp images.  The caller is responsible for applying that (as necessary).
'
'NOTE!  This function requires the FreeImage DIB to already be in 24 or 32bpp format.  It will fail if another bit-depth is used.
'ALSO NOTE!  This function does not set alpha premultiplication.  It's assumed that the caller knows that value in advance.
'ALSO NOTE!  This function does not free the incoming FreeImage handle, by design.
Public Function GetPDDibFromFreeImageHandle(ByVal srcFI_Handle As Long, ByRef dstDIB As pdDIB) As Boolean
    
    Dim fiHandleBackup As Long
    fiHandleBackup = srcFI_Handle
    
    'Double-check the FreeImage handle's bit depth
    Dim fiBPP As Long
    fiBPP = FreeImage_GetBPP(srcFI_Handle)
    
    If (fiBPP <> 24) And (fiBPP <> 32) Then
        
        'If the DIB is less than 24 bpp, upsample now
        If (fiBPP < 24) Then
            
            'Conversion to higher bit depths is contingent on the presence of an alpha channel
            If FreeImage_IsTransparent(srcFI_Handle) Or (FreeImage_GetTransparentIndex(srcFI_Handle) <> -1) Then
                srcFI_Handle = FreeImage_ConvertColorDepth(srcFI_Handle, FICF_RGB_32BPP, False)
            Else
                srcFI_Handle = FreeImage_ConvertColorDepth(srcFI_Handle, FICF_RGB_24BPP, False)
            End If
            
            'Verify the new bit-depth
            fiBPP = FreeImage_GetBPP(srcFI_Handle)
            
            If (fiBPP <> 24) And (fiBPP <> 32) Then
                
                'If a new DIB was created, release it now.  (Note that the caller must still free the original handle.)
                If (srcFI_Handle <> 0) And (srcFI_Handle <> fiHandleBackup) Then FreeImage_Unload srcFI_Handle
                
                GetPDDibFromFreeImageHandle = False
                Exit Function
            End If
            
        Else
            GetPDDibFromFreeImageHandle = False
            Exit Function
        End If
        
    End If
    
    'Proceed with DIB copying
    Dim fi_Width As Long, fi_Height As Long
    fi_Width = FreeImage_GetWidth(srcFI_Handle)
    fi_Height = FreeImage_GetHeight(srcFI_Handle)
    dstDIB.CreateBlank fi_Width, fi_Height, fiBPP, 0
    SetDIBitsToDevice dstDIB.GetDIBDC, 0, 0, fi_Width, fi_Height, 0, 0, 0, fi_Height, ByVal FreeImage_GetBits(srcFI_Handle), ByVal FreeImage_GetInfo(srcFI_Handle), 0&
    
    'If we created a temporary DIB, free it now
    If srcFI_Handle <> fiHandleBackup Then
        FreeImage_Unload srcFI_Handle
        srcFI_Handle = fiHandleBackup
    End If
    
    GetPDDibFromFreeImageHandle = True
    
End Function

'Given a PD DIB, return a 24 or 32bpp FreeImage handle that simply WRAPS the DIB without copying it.  This is much faster (and less
' resource-intensive) than copying of the entire pixel array.  For situations where you only need non-destructive FreeImage behavior
' (like saving a DIB to file in some non-BMP format), please use this function.
'
'ALSO NOTE!  This function does not affect alpha premultiplication.  It's assumed that the caller sets that value in advance.
'ALSO NOTE!  The forciblyReverseScanlines parameter will be applied to the underlying pdDIB object - plan accordingly!
'ALSO NOTE!  This function does not free the outgoing FreeImage handle, by design.  Make sure to free it manually!
'ALSO NOTE!  The function returns zero for failure state; please check the return value before trying to use it!
Public Function GetFIHandleFromPDDib_NoCopy(ByRef srcDIB As pdDIB, Optional ByVal forciblyReverseScanlines As Boolean = False) As Long
    With srcDIB
        GetFIHandleFromPDDib_NoCopy = Outside_FreeImageV3.FreeImage_ConvertFromRawBitsEx(False, .GetDIBPointer, FIT_BITMAP, .GetDIBWidth, .GetDIBHeight, .GetDIBStride, .GetDIBColorDepth, , , , forciblyReverseScanlines)
    End With
End Function

'Paint a FreeImage DIB to an arbitrary clipping rect on some target pdDIB.  This does not free or otherwise modify the source FreeImage object
Public Function PaintFIDibToPDDib(ByRef dstDIB As pdDIB, ByVal fi_Handle As Long, ByVal dstX As Long, ByVal dstY As Long, ByVal dstWidth As Long, ByVal dstHeight As Long) As Boolean
    
    If (Not (dstDIB Is Nothing)) And (fi_Handle <> 0) Then
        Dim bmpInfo As BITMAPINFO
        Outside_FreeImageV3.FreeImage_GetInfoHeaderEx fi_Handle, VarPtr(bmpInfo.bmiHeader)
        If dstDIB.IsDIBTopDown Then bmpInfo.bmiHeader.biHeight = -1 * (bmpInfo.bmiHeader.biHeight)
        
        Dim iHeight As Long: iHeight = Abs(bmpInfo.bmiHeader.biHeight)
        PaintFIDibToPDDib = (SetDIBitsToDevice(dstDIB.GetDIBDC, dstX, dstY, dstWidth, dstHeight, 0, 0, 0, iHeight, ByVal FreeImage_GetBits(fi_Handle), bmpInfo, 0&) <> 0)
        
        'When painting from a 24-bpp source to a 32-bpp target, the destination alpha channel will be ignored by GDI.
        ' We must forcibly fill it with opaque alpha values, or the resulting image will retain its existing alpha (typically 0!)
        If (dstDIB.GetDIBColorDepth = 32) And (FreeImage_GetBPP(fi_Handle) = 24) Then dstDIB.ForceNewAlpha 255
        
    Else
        FI_DebugMsg "WARNING!  Destination DIB is empty or FreeImage handle is null.  Cannot proceed with painting."
    End If
    
End Function

'Convert a 32- or 24-bpp pdDIB object to its 8-bpp equivalent, but paint the 8-bpp results into some other pdDIB suitable for screen display.
Public Sub ConvertPDDibToIndexedColor(ByRef srcDIB As pdDIB, ByRef dstDIB As pdDIB, Optional ByVal numOfColors As Long = 256, Optional ByVal quantMethod As FREE_IMAGE_QUANTIZE = FIQ_WUQUANT)

    If (srcDIB.GetDIBColorDepth = 32) Then srcDIB.ConvertTo24bpp
    
    Dim fi_DIB As Long
    fi_DIB = GetFIHandleFromPDDib_NoCopy(srcDIB, False)
    
    Dim fi_DIB8 As Long
    fi_DIB8 = FreeImage_ColorQuantizeEx(fi_DIB, quantMethod, True, numOfColors)
    If (fi_DIB8 <> 0) Then
        
        fi_DIB = FreeImage_ConvertTo32Bits(fi_DIB8)
        FreeImage_Unload fi_DIB8
        
        If (dstDIB Is Nothing) Then Set dstDIB = New pdDIB
        If (dstDIB.GetDIBWidth = srcDIB.GetDIBWidth) And (dstDIB.GetDIBHeight = srcDIB.GetDIBHeight) Then
            dstDIB.ResetDIB 255
        Else
            dstDIB.CreateBlank srcDIB.GetDIBWidth, srcDIB.GetDIBHeight, 32, vbWhite, 255
        End If
        
        Plugin_FreeImage.PaintFIDibToPDDib dstDIB, fi_DIB, 0, 0, dstDIB.GetDIBWidth, dstDIB.GetDIBHeight
        
        FreeImage_Unload fi_DIB
        
    End If
    
End Sub

'Prior to applying tone-mapping settings, query the user for their preferred behavior.  If the user doesn't want this dialog raised, this
' function will silently retrieve the proper settings from the preference file, and proceed with tone-mapping automatically.
' (This silent behavior can also be enforced by setting the noUIMode parameter to TRUE.)
'
'Returns: fills dst_fiHandle with a non-zero FreeImage 24 or 32bpp image handle if successful.  0 if unsuccessful.
'         The function itself will return a PD_OPERATION_OUTCOME value; this is important for determining if the user canceled the dialog.
'
'IMPORTANT NOTE!  If this function fails, further loading of the image must be halted.  PD cannot yet operate on anything larger than 32bpp,
' so if tone-mapping fails, we must abandon loading completely.  (A failure state can also be triggered by the user canceling the
' tone-mapping dialog.)
Private Function RaiseToneMapDialog(ByRef fi_Handle As Long, ByRef dst_fiHandle As Long, Optional ByVal noUIMode As Boolean = False) As PD_OPERATION_OUTCOME

    'Ask the user how they want to proceed.  Note that the dialog wrapper automatically handles the case of "do not prompt;
    ' use previous settings."  If that happens, it will retrieve the proper conversion settings for us, and return a dummy
    ' value of OK (as if the dialog were actually raised).
    Dim howToProceed As VbMsgBoxResult, ToneMapSettings As String
    If noUIMode Then
        howToProceed = vbOK
        ToneMapSettings = vbNullString
    Else
        howToProceed = DialogManager.PromptToneMapSettings(fi_Handle, ToneMapSettings)
    End If
    
    'Check for a cancellation state; if encountered, abandon ship now.
    If (howToProceed = vbOK) Then
        
        'The ToneMapSettings string will now contain all the information we need to proceed with the tone-map.  Forward it to the
        ' central tone-mapping handler and use its success/fail state for this function as well.
        FI_DebugMsg "Tone-map dialog appears to have been successful; result = " & howToProceed
        If (Not noUIMode) Then Message "Applying tone-mapping..."
        dst_fiHandle = ApplyToneMapping(fi_Handle, ToneMapSettings)
        
        If (dst_fiHandle = 0) Then
            FI_DebugMsg "WARNING!  ApplyToneMapping() failed for reasons unknown."
            RaiseToneMapDialog = PD_FAILURE_GENERIC
        Else
            RaiseToneMapDialog = PD_SUCCESS
        End If
        
    Else
        FI_DebugMsg "Tone-map dialog appears to have been cancelled; result = " & howToProceed
        dst_fiHandle = 0
        RaiseToneMapDialog = PD_FAILURE_USER_CANCELED
    End If

End Function

'Apply tone-mapping to a FreeImage DIB.  All valid FreeImage data types are supported, but for performance reasons, an intermediate cast to
' RGBF or RGBAF may be applied (because VB doesn't provide unsigned Int datatypes).
'
'Returns: a non-zero FreeImage 24 or 32bpp image handle if successful.  0 if unsuccessful.
'
'IMPORTANT NOTE!  This function always releases the incoming FreeImage handle, regardless of success or failure state.  This is
' to ensure proper load behavior (e.g. loading can't continue after a failed conversion, because we've forcibly killed the image handle),
' and to reduce resource usage (as the source handle is likely enormous, and we don't want it sitting around any longer than is
' absolutely necessary).
Public Function ApplyToneMapping(ByRef fi_Handle As Long, ByVal inputSettings As String) As Long
    
    'Retrieve the source image's bit-depth and data type.  These are crucial to successful tone-mapping operations.
    Dim fi_BPP As Long
    fi_BPP = FreeImage_GetBPP(fi_Handle)
    
    Dim fi_DataType As FREE_IMAGE_TYPE
    fi_DataType = FreeImage_GetImageType(fi_Handle)
    
    'Also, check for transparency in the source image.
    Dim hasTransparency As Boolean, transparentEntries As Long
    hasTransparency = FreeImage_IsTransparent(fi_Handle)
    transparentEntries = FreeImage_GetTransparencyCount(fi_Handle)
    If (transparentEntries > 0) Then hasTransparency = True
    
    Dim newHandle As Long, rgbfHandle As Long
    
    'toneMapSettings contains all conversion instructions.  Parse it to determine which tone-map function to use.
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString inputSettings
    
    'The first parameter contains the requested tone-mapping operation.
    Select Case cParams.GetLong("method", PDTM_DRAGO)
    
        'Linear map
        Case PDTM_LINEAR
                
            newHandle = fi_Handle
            
            'For performance reasons, I've only written a single RGBF/RGBAF-based linear transform.  If the image is not in one
            ' of these formats, convert it now.
            If ((fi_DataType <> FIT_RGBF) And (fi_DataType <> FIT_RGBAF)) Then
                
                'In the future, a transparency-friendly conversion may become available.  For now, however, transparency
                ' is sacrificed as part of the conversion function (as FreeImage does not provide an RGBAF cast).
                If hasTransparency Then
                    rgbfHandle = FreeImage_ConvertToRGBAF(fi_Handle)
                Else
                    rgbfHandle = FreeImage_ConvertToRGBF(fi_Handle)
                End If
                
                If (rgbfHandle = 0) Then
                    FI_DebugMsg "WARNING!  FreeImage_ConvertToRGBA/F failed for reasons unknown."
                    ApplyToneMapping = 0
                    Exit Function
                Else
                    FI_DebugMsg "FreeImage_ConvertToRGBA/F successful.  Proceeding with manual tone-mapping operation."
                End If
                
                newHandle = rgbfHandle
                
            End If
            
            'At this point, fi_Handle now represents a 32-bpc RGBF (or RGBAF) type FreeImage DIB.  Apply manual tone-mapping now.
            newHandle = ConvertFreeImageRGBFTo24bppDIB(newHandle, cParams.GetLong("normalize", PD_BOOL_TRUE), cParams.GetBool("ignorenegative", PD_BOOL_TRUE), cParams.GetDouble("gamma", 2.2))
            
            'Unload the intermediate RGBF handle as necessary
            If (rgbfHandle <> 0) Then FreeImage_Unload rgbfHandle
            
            ApplyToneMapping = newHandle
            
        'Filmic tone-map; basically a nice S-curve with an emphasis on rich blacks
        Case PDTM_FILMIC
            
            newHandle = fi_Handle
            
            'For performance reasons, I've only written a single RGBF/RGBAF-based linear transform.  If the image is not in one
            ' of these formats, convert it now.
            If (fi_DataType <> FIT_RGBF) And (fi_DataType <> FIT_RGBAF) Then
                
                'In the future, a transparency-friendly conversion may become available.  For now, however, transparency
                ' is sacrificed as part of the conversion function (as FreeImage does not provide an RGBAF cast).
                If hasTransparency Then
                    rgbfHandle = FreeImage_ConvertToRGBAF(fi_Handle)
                Else
                    rgbfHandle = FreeImage_ConvertToRGBF(fi_Handle)
                End If
                
                If (rgbfHandle = 0) Then
                    FI_DebugMsg "WARNING!  FreeImage_ConvertToRGBA/F failed for reasons unknown."
                    ApplyToneMapping = 0
                    Exit Function
                Else
                    FI_DebugMsg "FreeImage_ConvertToRGBA/F successful.  Proceeding with manual tone-mapping operation."
                End If
                
                newHandle = rgbfHandle
                
            End If
            
            'At this point, fi_Handle now represents a 24bpp RGBF type FreeImage DIB.  Apply manual tone-mapping now.
            newHandle = ToneMapFilmic_RGBFTo24bppDIB(newHandle, cParams.GetDouble("gamma", 2.2), cParams.GetDouble("exposure", 2#), , , , , , , cParams.GetDouble("whitepoint", 11.2))
            
            'Unload the intermediate RGBF handle as necessary
            If (rgbfHandle <> 0) Then FreeImage_Unload rgbfHandle
            
            ApplyToneMapping = newHandle
        
        'Adaptive logarithmic map
        Case PDTM_DRAGO
            ApplyToneMapping = FreeImage_TmoDrago03(fi_Handle, cParams.GetDouble("gamma", 2.2), cParams.GetDouble("exposure", 0#))
            
        'Photoreceptor map
        Case PDTM_REINHARD
            ApplyToneMapping = FreeImage_TmoReinhard05Ex(fi_Handle, cParams.GetDouble("intensity", 0#), ByVal 0#, cParams.GetDouble("adaptation", 1#), cParams.GetDouble("colorcorrection", 0#))
        
    End Select
    
End Function

'Perform linear scaling of a 96bpp RGBF image to standard 24bpp.  Note that an intermediate pdDIB object is used for convenience, but the returned
' handle is to a FREEIMAGE DIB.
'
'Returns: a non-zero FreeImage 24bpp image handle if successful.  0 if unsuccessful.
'
'IMPORTANT NOTE: REGARDLESS OF SUCCESS, THIS FUNCTION DOES NOT FREE THE INCOMING fi_Handle PARAMETER.  If the function fails (returns 0),
' I assume the caller still wants the original handle so it can proceed accordingly.  Similarly, because this function is used to render
' tone-mapping previews, it doesn't make sense to free the handle upon success, either.
'
'OTHER IMPORTANT NOTE: it's probably obvious, but the 24bpp handle this function returns (if successful) must also be freed by the caller.
' Forget this, and the function will leak.
Private Function ConvertFreeImageRGBFTo24bppDIB(ByVal fi_Handle As Long, Optional ByVal toNormalize As PD_BOOL = PD_BOOL_AUTO, Optional ByVal ignoreNegative As Boolean = False, Optional ByVal newGamma As Double = 2.2) As Long
    
    'Before doing anything, check the incoming fi_Handle.  For performance reasons, this function only handles RGBF and RGBAF formats.
    ' Other formats are invalid.
    Dim fi_DataType As FREE_IMAGE_TYPE
    fi_DataType = FreeImage_GetImageType(fi_Handle)
    
    If (fi_DataType <> FIT_RGBF) And (fi_DataType <> FIT_RGBAF) Then
        FI_DebugMsg "Tone-mapping request invalid"
        ConvertFreeImageRGBFTo24bppDIB = 0
        Exit Function
    End If
    
    'Here's how this works: basically, we must manually convert the image, one scanline at a time, into 24bpp RGB format.
    ' In the future, it might be nice to provide different conversion algorithms, but for now, linear scaling is assumed.
    ' Some additional options can be set by the caller (like normalization)
    
    'Start by determining if normalization is required for this image.
    Dim mustNormalize As Boolean
    Dim minR As Double, maxR As Double, minG As Double, maxG As Double, minB As Double, maxB As Double
    Dim rDist As Double, gDist As Double, bDist As Double
    
    'The toNormalize input has three possible values: false, true, or "decide for yourself".  In the last case, the image will be scanned,
    ' and normalization will only be enabled if values fall outside the [0, 1] range.  (Files written by PhotoDemon will always be normalized
    ' at write-time, so this technique works well when moving images into and out of PD.)
    If toNormalize = PD_BOOL_AUTO Then
        mustNormalize = IsNormalizeRequired(fi_Handle, minR, maxR, minG, maxG, minB, maxB)
    Else
        mustNormalize = (toNormalize = PD_BOOL_TRUE)
        If mustNormalize Then IsNormalizeRequired fi_Handle, minR, maxR, minG, maxG, minB, maxB
    End If
    
    'I have no idea if normalization is supposed to include negative numbers or not; each high-bit-depth format has its own quirks,
    ' and none are clear on preferred defaults, so I'll leave this as manually settable for now.
    If ignoreNegative Then
        
        rDist = maxR
        gDist = maxG
        bDist = maxB
        
        minR = 0
        minG = 0
        minB = 0
    
    'If negative values are considered valid, calculate a normalization distance between the max and min values of each channel
    Else
    
        rDist = maxR - minR
        gDist = maxG - minG
        bDist = maxB - minB
    
    End If
    
    If (rDist <> 0#) Then rDist = 1# / rDist Else rDist = 0#
    If (gDist <> 0#) Then gDist = 1# / gDist Else gDist = 0#
    If (bDist <> 0#) Then bDist = 1# / bDist Else bDist = 0#
    
    'This Single-type array will consistently be updated to point to the current line of pixels in the image (RGBF format, remember!)
    Dim srcImageData() As Single
    Dim srcSA As SafeArray1D
    
    'Create a 24bpp or 32bpp DIB at the same size as the image
    Dim tmpDIB As pdDIB
    Set tmpDIB = New pdDIB
    
    If fi_DataType = FIT_RGBF Then
        tmpDIB.CreateBlank FreeImage_GetWidth(fi_Handle), FreeImage_GetHeight(fi_Handle), 24
    Else
        tmpDIB.CreateBlank FreeImage_GetWidth(fi_Handle), FreeImage_GetHeight(fi_Handle), 32
    End If
    
    'Point a byte array at the temporary DIB
    Dim dstImageData() As Byte
    Dim tmpSA As SafeArray2D
    PrepSafeArray tmpSA, tmpDIB
    CopyMemory ByVal VarPtrArray(dstImageData()), VarPtr(tmpSA), 4
        
    'Iterate through each scanline in the source image, copying it to destination as we go.
    Dim iWidth As Long, iHeight As Long, iHeightInv As Long, iScanWidth As Long
    iWidth = FreeImage_GetWidth(fi_Handle) - 1
    iHeight = FreeImage_GetHeight(fi_Handle) - 1
    iScanWidth = FreeImage_GetPitch(fi_Handle)
    
    Dim qvDepth As Long
    If fi_DataType = FIT_RGBF Then qvDepth = 3 Else qvDepth = 4
    
    'Prep any other post-processing adjustments
    Dim gammaCorrection As Double
    gammaCorrection = 1# / newGamma
    
    'Due to the potential math involved in conversion (if gamma and other settings are being toggled), we need a lot of intermediate variables.
    ' Depending on the user's settings, some of these may go unused.
    Dim rSrcF As Double, gSrcF As Double, bSrcF As Double
    Dim rDstF As Double, gDstF As Double, bDstF As Double
    Dim rDstL As Long, gDstL As Long, bDstL As Long
    
    'Alpha is also a possibility, but unlike RGB values, we assume it is always normalized.  This allows us to skip any intermediate processing,
    ' and simply copy the value directly into the destination (after redistributing to the proper range, of course).
    Dim aDstF As Double, aDstL As Long
    
    Dim x As Long, y As Long, quickX As Long
    
    'Point a 1D VB array at the first scanline
    With srcSA
        .cbElements = 4
        .cDims = 1
        .lBound = 0
        .cElements = iScanWidth
        .pvData = FreeImage_GetScanline(fi_Handle, 0)
    End With
    CopyMemory ByVal VarPtrArray(srcImageData), VarPtr(srcSA), 4
        
    For y = 0 To iHeight
    
        'FreeImage DIBs are stored bottom-up; we invert them during processing
        iHeightInv = iHeight - y
        
        'Update the current scanline pointer
        srcSA.pvData = FreeImage_GetScanline(fi_Handle, y)
        
        'Iterate through this line, converting values as we go
        For x = 0 To iWidth
            
            'Retrieve the source values.  This includes an implicit cast to Double, which I've done because some formats support
            ' IEEE constants like NaN or Infinity.  VB doesn't deal with these gracefully, and an implicit cast to Double seems
            ' to reduce unpredictable errors, possibly by giving any range-check code some breathing room.
            quickX = x * qvDepth
            rSrcF = CDbl(srcImageData(quickX))
            gSrcF = CDbl(srcImageData(quickX + 1))
            bSrcF = CDbl(srcImageData(quickX + 2))
            If (qvDepth = 4) Then aDstF = CDbl(srcImageData(quickX + 3))
            
            'If normalization is required, apply it now
            If mustNormalize Then
                
                'If the caller has requested that we ignore negative values, clamp negative values to zero
                If ignoreNegative Then
                
                    If (rSrcF < 0#) Then rSrcF = 0#
                    If (gSrcF < 0#) Then gSrcF = 0#
                    If (bSrcF < 0#) Then bSrcF = 0#
                
                'If negative values are considered valid, redistribute them on the range [0, Dist[Min, Max]]
                Else
                    rSrcF = rSrcF - minR
                    gSrcF = gSrcF - minG
                    bSrcF = bSrcF - minB
                End If
                
                rDstF = rSrcF * rDist
                gDstF = gSrcF * gDist
                bDstF = bSrcF * bDist
                
            'If an image does not need to be normalized, this step is much easier
            Else
                
                rDstF = rSrcF
                gDstF = gSrcF
                bDstF = bSrcF
                
            End If
            
            'FYI, alpha is always un-normalized
                        
            'Apply gamma now (if any).  Unfortunately, lookup tables aren't an option because we're dealing with floating-point input,
            ' so this step is a little slow due to the exponent operator.
            If (newGamma <> 1#) Then
                If (rDstF > 0#) Then rDstF = rDstF ^ gammaCorrection
                If (gDstF > 0#) Then gDstF = gDstF ^ gammaCorrection
                If (bDstF > 0#) Then bDstF = bDstF ^ gammaCorrection
            End If
            
            'In the future, additional corrections could be applied here.
            
            'Apply failsafe range checks now
            If (rDstF < 0#) Then
                rDstF = 0#
            ElseIf (rDstF > 1#) Then
                rDstF = 1#
            End If
                
            If (gDstF < 0#) Then
                gDstF = 0#
            ElseIf (gDstF > 1#) Then
                gDstF = 1#
            End If
                
            If (bDstF < 0#) Then
                bDstF = 0#
            ElseIf (bDstF > 1#) Then
                bDstF = 1#
            End If
            
            'Handle alpha, if necessary
            If (qvDepth = 4) Then
                If (aDstF > 1#) Then aDstF = 1#
                If (aDstF < 0#) Then aDstF = 0#
                aDstL = aDstF * 255
            End If
            
            'Calculate corresponding integer values on the range [0, 255]
            rDstL = Int(rDstF * 255#)
            gDstL = Int(gDstF * 255#)
            bDstL = Int(bDstF * 255#)
                        
            'Copy the final, safe values into the destination
            dstImageData(quickX, iHeightInv) = bDstL
            dstImageData(quickX + 1, iHeightInv) = gDstL
            dstImageData(quickX + 2, iHeightInv) = rDstL
            If (qvDepth = 4) Then dstImageData(quickX + 3, iHeightInv) = aDstL
            
        Next x
        
    Next y
    
    'Free our 1D array reference
    CopyMemory ByVal VarPtrArray(srcImageData), 0&, 4
        
    'Point dstImageData() away from the DIB and deallocate it
    CopyMemory ByVal VarPtrArray(dstImageData), 0&, 4
    
    'Create a FreeImage object from our pdDIB object, then release our pdDIB copy
    Dim fi_DIB As Long
    fi_DIB = FreeImage_CreateFromDC(tmpDIB.GetDIBDC)
    
    'Success!
    ConvertFreeImageRGBFTo24bppDIB = fi_DIB

End Function

'Perform so-called "Filmic" tone-mapping of a 96bpp RGBF image to standard 24bpp.  Note that an intermediate pdDIB object is used
' for convenience, but the returned handle is to a FREEIMAGE DIB.
'
'Returns: a non-zero FreeImage 24bpp image handle if successful.  0 if unsuccessful.
'
'IMPORTANT NOTE: REGARDLESS OF SUCCESS, THIS FUNCTION DOES NOT FREE THE INCOMING fi_Handle PARAMETER.  If the function fails (returns 0),
' I assume the caller still wants the original handle so it can proceed accordingly.  Similarly, because this function is used to render
' tone-mapping previews, it doesn't make sense to free the handle upon success, either.
'
'OTHER IMPORTANT NOTE: it's probably obvious, but the 24bpp handle this function returns (if successful) must also be freed by the caller.
' Forget this, and the function will leak.
Private Function ToneMapFilmic_RGBFTo24bppDIB(ByVal fi_Handle As Long, Optional ByVal newGamma As Single = 2.2, Optional ByVal exposureCompensation As Single = 2#, Optional ByVal shoulderStrength As Single = 0.22, Optional ByVal linearStrength As Single = 0.3, Optional ByVal linearAngle As Single = 0.1, Optional ByVal toeStrength As Single = 0.2, Optional ByVal toeNumerator As Single = 0.01, Optional ByVal toeDenominator As Single = 0.3, Optional ByVal linearWhitePoint As Single = 11.2) As Long
    
    'Before doing anything, check the incoming fi_Handle.  For performance reasons, this function only handles RGBF and RGBAF formats.
    ' Other formats are invalid.
    Dim fi_DataType As FREE_IMAGE_TYPE
    fi_DataType = FreeImage_GetImageType(fi_Handle)
    
    If (fi_DataType <> FIT_RGBF) And (fi_DataType <> FIT_RGBAF) Then
        FI_DebugMsg "Tone-mapping request invalid"
        ToneMapFilmic_RGBFTo24bppDIB = 0
        Exit Function
    End If
    
    'This Single-type array will consistently be updated to point to the current line of pixels in the image (RGBF format, remember!)
    Dim srcImageData() As Single
    Dim srcSA As SafeArray1D
    
    'Create a 24bpp or 32bpp DIB at the same size as the image
    Dim tmpDIB As pdDIB
    Set tmpDIB = New pdDIB
    
    If fi_DataType = FIT_RGBF Then
        tmpDIB.CreateBlank FreeImage_GetWidth(fi_Handle), FreeImage_GetHeight(fi_Handle), 24
    Else
        tmpDIB.CreateBlank FreeImage_GetWidth(fi_Handle), FreeImage_GetHeight(fi_Handle), 32
    End If
    
    'Point a byte array at the temporary DIB
    Dim dstImageData() As Byte
    Dim tmpSA As SafeArray2D
    PrepSafeArray tmpSA, tmpDIB
    CopyMemory ByVal VarPtrArray(dstImageData()), VarPtr(tmpSA), 4
        
    'Iterate through each scanline in the source image, copying it to destination as we go.
    Dim iWidth As Long, iHeight As Long, iHeightInv As Long, iScanWidth As Long
    iWidth = FreeImage_GetWidth(fi_Handle) - 1
    iHeight = FreeImage_GetHeight(fi_Handle) - 1
    iScanWidth = FreeImage_GetPitch(fi_Handle)
    
    Dim qvDepth As Long
    If fi_DataType = FIT_RGBF Then qvDepth = 3 Else qvDepth = 4
    
    'Shift the parameter values into module-level variables; this is necessary because the actual filmic tone-map function
    ' is standalone, and we don't want to be passing a crapload of Double-type variables to it for every channel of
    ' every pixel in the (presumably large) image.
    m_shoulderStrength = shoulderStrength
    m_linearStrength = linearStrength
    m_linearAngle = linearAngle
    m_toeStrength = toeStrength
    m_toeNumerator = toeNumerator
    m_toeDenominator = toeDenominator
    m_linearWhitePoint = linearWhitePoint
    m_toeAngle = toeNumerator / toeDenominator
    
    'In advance, calculate the filmic function for the white point
    Dim fWhitePoint As Double
    fWhitePoint = fFilmicTonemap(m_linearWhitePoint)
    If (fWhitePoint <> 0#) Then fWhitePoint = 1# / fWhitePoint
    
    'Prep any other post-processing adjustments
    Dim gammaCorrection As Double
    gammaCorrection = 1# / newGamma
    
    'Due to the potential math involved in conversion (if gamma and other settings are being toggled), we need a lot of intermediate variables.
    ' Depending on the user's settings, some of these may go unused.
    Dim rSrcF As Single, gSrcF As Single, bSrcF As Single
    Dim rDstF As Single, gDstF As Single, bDstF As Single
    Dim rDstL As Long, gDstL As Long, bDstL As Long
    
    'Alpha is also a possibility, but unlike RGB values, we assume it is always normalized.  This allows us to skip any intermediate processing,
    ' and simply copy the value directly into the destination (after redistributing to the proper range, of course).
    Dim aDstF As Double, aDstL As Long
    
    Dim x As Long, y As Long, quickX As Long
    
    'Point a 1D VB array at the first scanline
    With srcSA
        .cbElements = 4
        .cDims = 1
        .lBound = 0
        .cElements = iScanWidth
        .pvData = FreeImage_GetScanline(fi_Handle, 0)
    End With
    CopyMemory ByVal VarPtrArray(srcImageData), VarPtr(srcSA), 4
    
    For y = 0 To iHeight
    
        'FreeImage DIBs are stored bottom-up; we invert them during processing
        iHeightInv = iHeight - y
    
        'Update our scanline pointer
        srcSA.pvData = FreeImage_GetScanline(fi_Handle, y)
        
        'Iterate through this line, converting values as we go
        For x = 0 To iWidth
            
            'Retrieve the source values.
            quickX = x * qvDepth
            rSrcF = srcImageData(quickX)
            gSrcF = srcImageData(quickX + 1)
            bSrcF = srcImageData(quickX + 2)
            If (qvDepth = 4) Then aDstF = srcImageData(quickX + 3)
            
            'Apply filmic tone-mapping.  See http://fr.slideshare.net/ozlael/hable-john-uncharted2-hdr-lighting for details
            rDstF = fFilmicTonemap(exposureCompensation * rSrcF) * fWhitePoint
            gDstF = fFilmicTonemap(exposureCompensation * gSrcF) * fWhitePoint
            bDstF = fFilmicTonemap(exposureCompensation * bSrcF) * fWhitePoint
                                    
            'Apply gamma now (if any).  Unfortunately, lookup tables aren't an option because we're dealing with floating-point input,
            ' so this step is a little slow due to the exponent operator.
            If (newGamma <> 1#) Then
                If (rDstF > 0#) Then rDstF = rDstF ^ gammaCorrection
                If (gDstF > 0#) Then gDstF = gDstF ^ gammaCorrection
                If (bDstF > 0#) Then bDstF = bDstF ^ gammaCorrection
            End If
            
            'Apply failsafe range checks
            If (rDstF < 0#) Then
                rDstF = 0#
            ElseIf (rDstF > 1#) Then
                rDstF = 1#
            End If
                
            If (gDstF < 0#) Then
                gDstF = 0#
            ElseIf (gDstF > 1#) Then
                gDstF = 1#
            End If
                
            If (bDstF < 0#) Then
                bDstF = 0#
            ElseIf (bDstF > 1#) Then
                bDstF = 1#
            End If
            
            'Handle alpha, if necessary
            If (qvDepth = 4) Then
                If (aDstF > 1#) Then aDstF = 1#
                If (aDstF < 0#) Then aDstF = 0#
                aDstL = aDstF * 255
            End If
            
            'Calculate corresponding integer values on the range [0, 255]
            rDstL = Int(rDstF * 255#)
            gDstL = Int(gDstF * 255#)
            bDstL = Int(bDstF * 255#)
                        
            'Copy the final, safe values into the destination
            dstImageData(quickX, iHeightInv) = bDstL
            dstImageData(quickX + 1, iHeightInv) = gDstL
            dstImageData(quickX + 2, iHeightInv) = rDstL
            If (qvDepth = 4) Then dstImageData(quickX + 3, iHeightInv) = aDstL
            
        Next x
        
    Next y
    
    'Free our 1D array reference
    CopyMemory ByVal VarPtrArray(srcImageData), 0&, 4
        
    'Point dstImageData() away from the DIB and deallocate it
    CopyMemory ByVal VarPtrArray(dstImageData), 0&, 4
    
    'Create a FreeImage object from our pdDIB object, then release our pdDIB copy
    Dim fi_DIB As Long
    fi_DIB = FreeImage_CreateFromDC(tmpDIB.GetDIBDC)
    
    'Success!
    ToneMapFilmic_RGBFTo24bppDIB = fi_DIB

End Function

'Filmic tone-map function
Private Function fFilmicTonemap(ByVal x As Single) As Single
    
    'In advance, calculate the filmic function for the white point
    Dim numFunction As Double, denFunction As Double
    
    numFunction = x * (m_shoulderStrength * x + m_linearStrength * m_linearAngle) + m_toeStrength * m_toeNumerator
    denFunction = x * (m_shoulderStrength * x + m_linearStrength) + m_toeStrength * m_toeDenominator
    
    'Failsafe check for DBZ errors
    If (denFunction > 0#) Then
        fFilmicTonemap = (numFunction / denFunction) - m_toeAngle
    Else
        fFilmicTonemap = 1#
    End If
    
End Function

'Returns TRUE if an RGBF format FreeImage DIB contains values outside the [0, 1] range (meaning normalization is required).
' If normalization is required, the various min and max parameters will be filled for each channel.  It is up to the caller to determine how
' these values are used; this function is only diagnostic.
Private Function IsNormalizeRequired(ByVal fi_Handle As Long, ByRef dstMinR As Double, ByRef dstMaxR As Double, ByRef dstMinG As Double, ByRef dstMaxG As Double, ByRef dstMinB As Double, ByRef dstMaxB As Double) As Boolean
    
    'Before doing anything, check the incoming fi_Handle.  If alpha is present, pixel alignment calculations must be modified.
    Dim fi_DataType As FREE_IMAGE_TYPE
    fi_DataType = FreeImage_GetImageType(fi_Handle)
    
    'Values within the [0, 1] range are considered normal.  Values outside this range are not normal, and normalization is thus required.
    ' Because an image does not have to include 0 or 1 values specifically, we return TRUE exclusively; e.g. if any value falls outside
    ' the [0, 1] range, normalization is required.
    Dim minR As Single, maxR As Single, minG As Single, maxG As Single, minB As Single, maxB As Single
    minR = 1: minG = 1: minB = 1
    maxR = 0: maxG = 0: maxB = 0
    
    'This Single-type array will consistently be updated to point to the current line of pixels in the image (RGBF format, remember!)
    Dim srcImageData() As Single
    Dim srcSA As SafeArray1D
    
    'Iterate through each scanline in the source image, checking normalize parameters as we go.
    Dim iWidth As Long, iHeight As Long, iScanWidth As Long
    iWidth = FreeImage_GetWidth(fi_Handle) - 1
    iHeight = FreeImage_GetHeight(fi_Handle) - 1
    iScanWidth = FreeImage_GetPitch(fi_Handle)
    
    Dim qvDepth As Long
    If fi_DataType = FIT_RGBF Then qvDepth = 3 Else qvDepth = 4
    
    Dim srcR As Single, srcG As Single, srcB As Single
    Dim x As Long, y As Long, quickX As Long
    
    'Point a 1D VB array at this scanline
    With srcSA
        .cbElements = 4
        .cDims = 1
        .lBound = 0
        .cElements = iScanWidth
        .pvData = FreeImage_GetScanline(fi_Handle, 0)
    End With
    CopyMemory ByVal VarPtrArray(srcImageData()), VarPtr(srcSA), 4
        
    For y = 0 To iHeight
        
        'Update the scanline pointer
        srcSA.pvData = FreeImage_GetScanline(fi_Handle, y)
        
        'Iterate through this line, checking values as we go
        For x = 0 To iWidth
            
            quickX = x * qvDepth
            
            srcR = srcImageData(quickX)
            srcG = srcImageData(quickX + 1)
            srcB = srcImageData(quickX + 2)
            
            'Check max/min values independently for each channel
            If (srcR < minR) Then
                minR = srcR
            ElseIf (srcR > maxR) Then
                maxR = srcR
            End If
            
            If (srcG < minG) Then
                minG = srcG
            ElseIf (srcG > maxG) Then
                maxG = srcG
            End If
            
            If (srcB < minB) Then
                minB = srcB
            ElseIf (srcB > maxB) Then
                maxB = srcB
            End If
            
        Next x
        
    Next y
    
    'Free our 1D array reference
    CopyMemory ByVal VarPtrArray(srcImageData()), 0&, 4
    
    'Fill min/max RGB values regardless of normalization
    dstMinR = minR
    dstMaxR = maxR
    dstMinG = minG
    dstMaxG = maxG
    dstMinB = minB
    dstMaxB = maxB
    
    'If the max or min lie outside the image, notify the caller that normalization is required on this image
    If (minR < 0#) Or (maxR > 1#) Or (minG < 0#) Or (maxG > 1#) Or (minB < 0#) Or (maxB > 1#) Then
        IsNormalizeRequired = True
    Else
        IsNormalizeRequired = False
    End If
    
End Function

'Use FreeImage to resize a DIB.  (Technically, to copy a resized portion of a source image into a destination image.)
' The call is formatted similar to StretchBlt, as it used to replace StretchBlt when working with 32bpp data.
' This function is also declared identically to PD's GDI+ equivalent, specifically GDIPlusResizeDIB.  This was done
' so that the two functions can be used interchangeably.
Public Function FreeImageResizeDIB(ByRef dstDIB As pdDIB, ByVal dstX As Long, ByVal dstY As Long, ByVal dstWidth As Long, ByVal dstHeight As Long, ByRef srcDIB As pdDIB, ByVal srcX As Long, ByVal srcY As Long, ByVal srcWidth As Long, ByVal srcHeight As Long, ByVal interpolationType As FREE_IMAGE_FILTER, Optional ByVal destinationIsBlank As Boolean = False) As Boolean

    'Because this function is such a crucial part of PD's render chain, I occasionally like to profile it against
    ' viewport engine changes.  Uncomment the two lines below, and the reporting line at the end of the sub to
    ' have timing reports sent to the debug window.
    'Dim profileTime As Double
    'profileTime = Timer

    FreeImageResizeDIB = True

    'Double-check that FreeImage exists
    If g_ImageFormats.FreeImageEnabled Then
                
        'Create a temporary DIB at the size of the source image
        Dim tmpDIB As pdDIB
        Set tmpDIB = New pdDIB
        tmpDIB.CreateBlank srcWidth, srcHeight, srcDIB.GetDIBColorDepth, 0
        
        'Copy the relevant source portion of the image into the temporary DIB
        BitBlt tmpDIB.GetDIBDC, 0, 0, srcWidth, srcHeight, srcDIB.GetDIBDC, srcX, srcY, vbSrcCopy
        
        'Create a FreeImage copy of the temporary DIB
        Dim fi_DIB As Long
        fi_DIB = Plugin_FreeImage.GetFIHandleFromPDDib_NoCopy(tmpDIB)
        
        'Use that handle to request an image resize
        If fi_DIB <> 0 Then
            
            Dim returnDIB As Long
            returnDIB = FreeImage_RescaleByPixel(fi_DIB, dstWidth, dstHeight, True, interpolationType)
                        
            'Copy the bits from the FreeImage DIB to our DIB
            tmpDIB.CreateBlank dstWidth, dstHeight, 32, 0
            Plugin_FreeImage.PaintFIDibToPDDib tmpDIB, returnDIB, 0, 0, dstWidth, dstHeight
            
            'If the destinationIsBlank flag is true, we can use BitBlt in place of AlphaBlend to copy the result
            ' onto the destination DIB; this shaves off a tiny bit of time.
            If destinationIsBlank Then
                BitBlt dstDIB.GetDIBDC, dstX, dstY, dstWidth, dstHeight, tmpDIB.GetDIBDC, 0, 0, vbSrcCopy
            Else
                AlphaBlend dstDIB.GetDIBDC, dstX, dstY, dstWidth, dstHeight, tmpDIB.GetDIBDC, 0, 0, dstWidth, dstHeight, 255 * &H10000 Or &H1000000
            End If
            
            'With the transfer complete, release the FreeImage DIB and unload the library
            If returnDIB <> 0 Then FreeImage_UnloadEx returnDIB
            
        End If
                
    Else
        FreeImageResizeDIB = False
    End If
    
    'Uncomment the line below to receive timing reports
    'Debug.Print Format(CStr((Timer - profileTime) * 1000), "0000.00")
    
End Function

'Use FreeImage to resize a DIB, optimized against the use case where the full source image is being used.
' (Basically, something closer to BitBlt than StretchBlt, but without sourceX/Y parameters for an extra boost.)
Public Function FreeImageResizeDIBFast(ByRef dstDIB As pdDIB, ByVal dstX As Long, ByVal dstY As Long, ByVal dstWidth As Long, ByVal dstHeight As Long, ByRef srcDIB As pdDIB, ByVal interpolationType As FREE_IMAGE_FILTER, Optional ByVal destinationIsBlank As Boolean = False) As Boolean

    'Because this function is such a crucial part of PD's render chain, I occasionally like to profile it against
    ' viewport engine changes.  Uncomment the two lines below, and the reporting line at the end of the sub to
    ' have timing reports sent to the debug window.
    'Dim profileTime As Double
    'profileTime = Timer

    FreeImageResizeDIBFast = True

    'Double-check that FreeImage exists
    If g_ImageFormats.FreeImageEnabled Then
        
        'Create a FreeImage copy of the source DIB
        Dim fi_DIB As Long
        fi_DIB = Plugin_FreeImage.GetFIHandleFromPDDib_NoCopy(srcDIB)
        
        'Use that handle to request an image resize
        If fi_DIB <> 0 Then
            
            Dim returnDIB As Long
            returnDIB = FreeImage_RescaleByPixel(fi_DIB, dstWidth, dstHeight, True, interpolationType)
            
            'If the destinationIsBlank flag is TRUE, we can copy the bits directly from the FreeImage bytes to the
            ' destination bytes, skipping the need for an intermediary DIB.
            If destinationIsBlank Then
                Plugin_FreeImage.PaintFIDibToPDDib dstDIB, returnDIB, dstX, dstY, dstWidth, dstHeight
            Else
                Dim tmpDIB As pdDIB
                Set tmpDIB = New pdDIB
                tmpDIB.CreateBlank dstWidth, dstHeight, 32, 0
                Plugin_FreeImage.PaintFIDibToPDDib tmpDIB, returnDIB, 0, 0, dstWidth, dstHeight
                AlphaBlend dstDIB.GetDIBDC, dstX, dstY, dstWidth, dstHeight, tmpDIB.GetDIBDC, 0, 0, dstWidth, dstHeight, 255 * &H10000 Or &H1000000
                Set tmpDIB = Nothing
            End If
            
            'With the transfer complete, release the FreeImage DIB and unload the library
            If returnDIB <> 0 Then FreeImage_UnloadEx returnDIB
            
        End If
                
    Else
        FreeImageResizeDIBFast = False
    End If
    
    'If alpha is present, copy the alpha parameters between DIBs, as it will not have changed
    dstDIB.SetInitialAlphaPremultiplicationState srcDIB.GetAlphaPremultiplication
    
    'Uncomment the line below to receive timing reports
    'Debug.Print Format(CStr((Timer - profileTime) * 1000), "0000.00")
    
End Function

'Use FreeImage to rotate a DIB, optimized against the use case where the full source image is being used.
Public Function FreeImageRotateDIBFast(ByRef srcDIB As pdDIB, ByRef dstDIB As pdDIB, ByRef rotationAngle As Double, Optional ByVal enlargeCanvasToFit As Boolean = True, Optional ByVal applyPostAlphaPremultiplication As Boolean = True) As Boolean

    'Uncomment the two lines below, and the reporting line at the end of the sub, to send timing reports to the debug window.
    'Dim profileTime As Double
    'profileTime = Timer
    
    'Double-check that FreeImage exists
    If g_ImageFormats.FreeImageEnabled Then
    
        'FreeImage uses positive values to indicate counter-clockwise rotation.  While mathematically correct, I find this
        ' unintuitive for casual users.  PD reverses the rotationAngle value so that POSITIVE values indicate CLOCKWISE rotation.
        rotationAngle = -rotationAngle
        
        'Rotation requires quite a few variables, including a number of handles for passing data back-and-forth with FreeImage.
        Dim fi_DIB As Long, returnDIB As Long
        Dim nWidth As Long, nHeight As Long
        
        'One of the FreeImage rotation variants requires an explicit center point; calculate one in advance.
        Dim cx As Double, cy As Double
        
        cx = srcDIB.GetDIBWidth / 2
        cy = srcDIB.GetDIBHeight / 2
            
        'Give FreeImage a handle to our temporary rotation image
        fi_DIB = Plugin_FreeImage.GetFIHandleFromPDDib_NoCopy(srcDIB)
        
        If fi_DIB <> 0 Then
            
            'There are two ways to rotate an image - enlarging the canvas to receive the fully rotated copy, or
            ' leaving the image the same size and truncating corners.  These require two different FreeImage functions.
            If enlargeCanvasToFit Then
                
                returnDIB = FreeImage_Rotate(fi_DIB, rotationAngle, 0)
                nWidth = FreeImage_GetWidth(returnDIB)
                nHeight = FreeImage_GetHeight(returnDIB)
                
            'Leave the canvas the same size
            Else
               
               returnDIB = FreeImage_RotateEx(fi_DIB, rotationAngle, 0, 0, cx, cy, True)
               nWidth = FreeImage_GetWidth(returnDIB)
               nHeight = FreeImage_GetHeight(returnDIB)
            
            End If
            
            'Unload the original FreeImage source
            FreeImage_UnloadEx fi_DIB
            
            If returnDIB <> 0 Then
            
                'Ask FreeImage to premultiply the image's alpha data, as necessary
                If applyPostAlphaPremultiplication Then FreeImage_PreMultiplyWithAlpha returnDIB
                
                'Create a blank DIB to receive the rotated image from FreeImage
                dstDIB.CreateBlank nWidth, nHeight, 32
                            
                'Copy the bits from the FreeImage DIB to our DIB
                Plugin_FreeImage.PaintFIDibToPDDib dstDIB, returnDIB, 0, 0, nWidth, nHeight
                
                'With the transfer complete, release any remaining FreeImage DIBs and exit
                FreeImage_UnloadEx returnDIB
                FreeImageRotateDIBFast = True
                
            Else
                FreeImageRotateDIBFast = False
            End If
            
        Else
            FreeImageRotateDIBFast = False
        End If
                
    Else
        FreeImageRotateDIBFast = False
    End If
    
    'If alpha is present, copy the alpha parameters between DIBs, as it will not have changed
    dstDIB.SetInitialAlphaPremultiplicationState srcDIB.GetAlphaPremultiplication
    
    'Uncomment the line below to receive timing reports
    'Debug.Print Format(CStr((Timer - profileTime) * 1000), "0000.00")
    
End Function

Public Function FreeImageErrorState() As Boolean
    FreeImageErrorState = CBool(Len(g_FreeImageErrorMessages(UBound(g_FreeImageErrorMessages))) <> 0)
End Function

Public Function GetFreeImageErrors(Optional ByVal eraseListUponReturn As Boolean = True) As String
    
    Dim listOfFreeImageErrors As String
    listOfFreeImageErrors = """"
    
    'Condense all recorded errors into a single string
    If UBound(g_FreeImageErrorMessages) > 0 Then
        Dim i As Long
        For i = 0 To UBound(g_FreeImageErrorMessages)
            listOfFreeImageErrors = listOfFreeImageErrors & g_FreeImageErrorMessages(i)
            If i < UBound(g_FreeImageErrorMessages) Then listOfFreeImageErrors = listOfFreeImageErrors & vbCrLf
        Next i
    Else
        listOfFreeImageErrors = listOfFreeImageErrors & g_FreeImageErrorMessages(0)
    End If
    
    listOfFreeImageErrors = listOfFreeImageErrors & """"
    GetFreeImageErrors = listOfFreeImageErrors
    
    If eraseListUponReturn Then ReDim g_FreeImageErrorMessage(0) As String
    
End Function

'Need a FreeImage object at a specific color depth?  Use this function.
'
'The source DIB will not be modified by this function, but some settings require us to make a copy of the source DIB.
' (Non-standard alpha settings are the primary culprit, as we have to handle those conversions internally.)
'
'Obviously, you must manually free the returned FreeImage handle when you're done with it.
'
'Some combinations of parameters are not valid; for example, alphaState and outputColorDepth must be mixed carefully
' (you cannot set binary or color-based alpha for 32-bpp color mode).  For additional details, please refer to the
' ImageExporter module, which goes over these limitations in detail.
'
'Also, please note that this function does not change alpha premultiplication.  The caller needs to handle this in advance.
'
'Finally, this function does not run heuristics on the incoming image.  For example, if you tell it to create a
' grayscale image, it *will* create a grayscale image, regardless of the input.  As such, you must run any
' "auto-convert to best depth" heuristics *prior* to calling this function!
'
'Returns: a non-zero FI handle if successful; 0 if something goes horribly wrong.
Public Function GetFIDib_SpecificColorMode(ByRef srcDIB As pdDIB, ByVal outputColorDepth As Long, Optional ByVal desiredAlphaState As PD_ALPHA_STATUS = PDAS_ComplicatedAlpha, Optional ByVal currentAlphaState As PD_ALPHA_STATUS = PDAS_ComplicatedAlpha, Optional ByVal alphaCutoffOrColor As Long = 127, Optional ByVal finalBackColor As Long = vbWhite, Optional ByVal forceGrayscale As Boolean = False, Optional ByVal paletteCount As Long = 256, Optional ByVal RGB16bppUse565 As Boolean = True, Optional ByVal doNotUseFIGrayscale As Boolean = False, Optional ByVal quantMethod As FREE_IMAGE_QUANTIZE = FIQ_WUQUANT) As Long
    
    'If FreeImage is not enabled, exit immediately
    If (Not g_ImageFormats.FreeImageEnabled) Then
        GetFIDib_SpecificColorMode = 0
        Exit Function
    End If
    
    Dim fi_DIB As Long, tmpFIHandle As Long
    
    'Perform a quick check for 32-bpp images with complex alpha; we can return those immediately!
    If (outputColorDepth = 32) And (desiredAlphaState = PDAS_ComplicatedAlpha) And (srcDIB.GetDIBColorDepth = 32) And (Not forceGrayscale) Then
        GetFIDib_SpecificColorMode = FreeImage_CreateFromDC(srcDIB.GetDIBDC)
        Exit Function
    End If
    
    'Before proceeding, we first need to manually correct conditions that FreeImage cannot currently meet.
    ' Most significant among these is the combination of grayscale images + alpha channels; these must be forcibly expanded
    ' to RGBA at a matching bit-depth.
    If forceGrayscale And (desiredAlphaState <> PDAS_NoAlpha) Then
        
        'FreeImage supports the notion of 8-bpp images with a single transparent color.
        If (outputColorDepth <= 8) And ((desiredAlphaState = PDAS_BinaryAlpha) Or (desiredAlphaState = PDAS_NewAlphaFromColor)) Then
            
            'This output is now supported.  We just need to make sure we don't use FreeImage's default grayscale path
            ' (as it can't handle alpha correctly).
            doNotUseFIGrayscale = True
            
        'Other gray + transparency options are not currently supported.
        Else
        
            If (outputColorDepth <= 8) And (desiredAlphaState = PDAS_ComplicatedAlpha) Then
                
                'Make sure we do not use the default FreeImage grayscale path; instead, we'll use PD's custom-managed solution
                doNotUseFIGrayscale = True
            
            Else
                'Expand to full RGBA color depths as necessary.
                If outputColorDepth = 16 Then
                    outputColorDepth = 64
                ElseIf outputColorDepth = 32 Then
                    outputColorDepth = 128
                End If
            End If
        
        End If
        
    End If
    
    'Some modifications require us to preprocess the incoming image; because this function cannot modify the
    ' incoming DIB, we must use a temporary copy.
    Dim tmpDIBRequired As Boolean: tmpDIBRequired = False
    
    'Some modifications require us to generate a temporary transparency table.  This byte array contains new alpha
    ' values for a given image.  We do not apply these values until *after* an image has been converted to 8-bpp.
    Dim transparencyTableActive As Boolean: transparencyTableActive = False
    Dim transparencyTableBackup As PD_ALPHA_STATUS: transparencyTableBackup = PDAS_ComplicatedAlpha
    Dim tmpTransparencyTable() As Byte
    
    'The order of operations here is a bit tricky.  First, we need to deal with the problem of specialized alpha modes.
    
    'If the caller does not want alpha in the final image, composite against the given backcolor now
    If (desiredAlphaState = PDAS_NoAlpha) Then
        ResetExportPreviewDIB tmpDIBRequired, srcDIB
        m_ExportPreviewDIB.CompositeBackgroundColor Colors.ExtractRed(finalBackColor), Colors.ExtractGreen(finalBackColor), Colors.ExtractBlue(finalBackColor)
    
    'The color-based alpha mode requires us to leave the image in 32-bpp mode, but force it to use only "0" or "255"
    ' alpha values, with a specified transparent color providing the guide for which pixels get turned transparent.
    ' As part of this process, we will create a new transparency map for the image, but when that map gets applied
    ' to the image varies depending on the output color depth.
    
    'This mode must be handled early, because it requires custom PD code, and subsequent quantization (e.g. 8-bit mode) will
    ' yield incorrect results if we attempt to process the transparent color post-quantization (as multiple pixels
    ' may get forced to the same color value, creating new areas of unwanted transparency!).
    ElseIf (desiredAlphaState = PDAS_NewAlphaFromColor) Then
        
        'Apply new alpha.  (This function will return TRUE if the color match is found, and the resulting image thus
        ' contains some amount of transparency.)
        If DIBs.MakeColorTransparent_Ex(srcDIB, tmpTransparencyTable, alphaCutoffOrColor) Then
            
            'If the output color depth is 32-bpp, apply the new transparency table immediately
            If (outputColorDepth > 8) Then
                ResetExportPreviewDIB tmpDIBRequired, srcDIB
                DIBs.ApplyBinaryTransparencyTable m_ExportPreviewDIB, tmpTransparencyTable, finalBackColor
                currentAlphaState = PDAS_BinaryAlpha
            
            'If the output color depth is 8-bpp, note that we need to re-apply the transparency table *after* quantization
            Else
                transparencyTableActive = True
            End If
        
        'If the MakeColorTransparent_Ex function failed, no color matches are found; this lets us use 24-bpp output.
        Else
            ResetExportPreviewDIB tmpDIBRequired, srcDIB
            m_ExportPreviewDIB.CompositeBackgroundColor Colors.ExtractRed(finalBackColor), Colors.ExtractGreen(finalBackColor), Colors.ExtractBlue(finalBackColor)
            desiredAlphaState = PDAS_NoAlpha
        End If
        
    'Binary alpha values require us to leave the image in 32-bpp mode, but force it to use only "0" or "255" alpha values.
    ' Depending on the output color depth, we may not apply the new alpha until after subsequent steps.
    ElseIf (desiredAlphaState = PDAS_BinaryAlpha) Then
        
        'A cutoff of zero means all pixels are gonna be opaque
        If (alphaCutoffOrColor = 0) Then
            ResetExportPreviewDIB tmpDIBRequired, srcDIB
            m_ExportPreviewDIB.CompositeBackgroundColor Colors.ExtractRed(finalBackColor), Colors.ExtractGreen(finalBackColor), Colors.ExtractBlue(finalBackColor)
            desiredAlphaState = PDAS_NoAlpha
        Else
            
            'If the image doesn't already have binary alpha, apply it now
            If (currentAlphaState <> PDAS_BinaryAlpha) Or (outputColorDepth < 32) Then
                
                DIBs.ApplyAlphaCutoff_Ex srcDIB, tmpTransparencyTable, alphaCutoffOrColor
                
                'If the output color depth is 32-bpp, apply the new transparency table immediately
                If (outputColorDepth > 8) Then
                    ResetExportPreviewDIB tmpDIBRequired, srcDIB
                    DIBs.ApplyBinaryTransparencyTable m_ExportPreviewDIB, tmpTransparencyTable, finalBackColor
                    currentAlphaState = PDAS_BinaryAlpha
                
                'If the output color depth is 8-bpp, note that we need to re-apply the transparency table *after* quantization
                Else
                    transparencyTableActive = True
                End If
                
            End If
            
        End If
        
    End If
    
    'If the caller wants a grayscale image AND an alpha channel, we must apply a grayscale conversion now,
    ' as FreeImage does not internally support the notion of 8-bpp grayscale + alpha.
    '
    '(If the caller does not want alpha in the final image, FreeImage will handle the grayscale conversion
    ' internally, so we can skip this step entirely.)
    If forceGrayscale And ((desiredAlphaState <> PDAS_NoAlpha) Or (paletteCount <> 256) Or (outputColorDepth > 16) Or (doNotUseFIGrayscale)) Then
        ResetExportPreviewDIB tmpDIBRequired, srcDIB
        DIBs.MakeDIBGrayscale m_ExportPreviewDIB, paletteCount
    End If
    
    'Next, figure out scenarios where we can pass FreeImage a 24-bpp image.  This is helpful because FreeImage is
    ' unreliable when working with certain types of 32-bpp data (e.g. downsampling 32-bpp data to 8-bpp).
    Dim reduceTo24bpp As Boolean: reduceTo24bpp = False
    If (desiredAlphaState = PDAS_NoAlpha) Then reduceTo24bpp = True
    If (outputColorDepth = 24) Or (outputColorDepth = 48) Or (outputColorDepth = 96) Then reduceTo24bpp = True
    
    'We will also forcibly reduce the incoming image to 24bpp if it doesn't contain any meaningful alpha values
    If (Not reduceTo24bpp) Then
        If tmpDIBRequired Then
            If (m_ExportPreviewDIB.GetDIBColorDepth = 32) Then reduceTo24bpp = DIBs.IsDIBAlphaBinary(m_ExportPreviewDIB, False)
        Else
            If (srcDIB.GetDIBColorDepth = 32) Then reduceTo24bpp = DIBs.IsDIBAlphaBinary(srcDIB, False)
        End If
    End If
    
    'Finally, binary alpha modes + indexed color modes also require us to perform a 24-bpp reduction now.
    If ((desiredAlphaState = PDAS_BinaryAlpha) Or (desiredAlphaState = PDAS_NewAlphaFromColor)) And (outputColorDepth <= 8) And transparencyTableActive Then
        transparencyTableBackup = desiredAlphaState
        reduceTo24bpp = True
    End If
    
    'If any of the 24-bpp criteria are met, apply a forcible conversion now
    If reduceTo24bpp Then
        
        ResetExportPreviewDIB tmpDIBRequired, srcDIB
        
        'Forcibly remove alpha from the image
        If (outputColorDepth < 32) Or (outputColorDepth = 48) Or (outputColorDepth = 96) Then
            If Not m_ExportPreviewDIB.ConvertTo24bpp(finalBackColor) Then FI_DebugMsg "WARNING!  GetFIDib_SpecificColorMode could not convert the incoming DIB to 24-bpp."
        Else
            m_ExportPreviewDIB.CompositeBackgroundColor Colors.ExtractRed(finalBackColor), Colors.ExtractGreen(finalBackColor), Colors.ExtractBlue(finalBackColor)
        End If
        
        'Reset the target alpha mode, so we can tell FreeImage that alpha handling is not required for this image
        desiredAlphaState = PDAS_NoAlpha
        
    End If
    
    'If binary alpha is in use, we must forcibly reset the desired alpha tracker to our desired mode (which will have
    ' been reset by the 24-bpp reduction section, above)
    If transparencyTableActive Then desiredAlphaState = transparencyTableBackup
    
    'Create a FreeImage handle that points to our source image
    If tmpDIBRequired Then
        fi_DIB = FreeImage_CreateFromDC(m_ExportPreviewDIB.GetDIBDC)
    Else
        fi_DIB = FreeImage_CreateFromDC(srcDIB.GetDIBDC)
    End If
    
    If (fi_DIB = 0) Then FI_DebugMsg "WARNING!  Plugin_FreeImage.GetFIDib_SpecificColorMode() failed to create a valid handle from the incoming image!"
    
    'From this point forward, we must operate *only* on this fi_DIB handle.
    
    '1-bpp is easy; handle it now
    If (outputColorDepth = 1) Then
        tmpFIHandle = FreeImage_Dither(fi_DIB, FID_FS)
        If (tmpFIHandle <> fi_DIB) Then
            FreeImage_Unload fi_DIB
            fi_DIB = tmpFIHandle
        End If
    
    'Non-1-bpp is harder
    Else
        
        'Handle grayscale, non-alpha variants first; they use their own dedicated conversion functions
        If (forceGrayscale And (desiredAlphaState = PDAS_NoAlpha) And (Not doNotUseFIGrayscale)) Then
            fi_DIB = GetGrayscaleFIDib(fi_DIB, outputColorDepth)
        
        'Non-grayscale variants (or grayscale variants + alpha) are more complicated
        Else
        
            'Start with non-alpha color modes.  They are easier to handle.
            ' (Also note that this step will *only* be triggered if forceGrayscale = False; the combination of
            '  "forceGrayscale = True" and "PDAS_NoAlpha" is handled by its own If branch, above.)
            If (desiredAlphaState = PDAS_NoAlpha) Then
                
                'Walk down the list of valid outputs, starting at the low end
                If (outputColorDepth <= 8) Then
                    
                    'FreeImage supports a new "lossless" quantization method that is perfect for images that already
                    ' have 256 colors or less.  This method is basically just a hash table, and it lets us avoid
                    ' lossy quantization if at all possible.
                    If (paletteCount = 256) Then
                        tmpFIHandle = FreeImage_ColorQuantize(fi_DIB, FIQ_LFPQUANT)
                    Else
                        tmpFIHandle = FreeImage_ColorQuantizeExInt(fi_DIB, FIQ_LFPQUANT, paletteCount)
                    End If
                    
                    '0 means the image has > 256 colors, and must be quantized via lossy means
                    If (tmpFIHandle = 0) Then
                        
                        If (quantMethod = FIQ_LFPQUANT) Then quantMethod = FIQ_WUQUANT
                        
                        'If we're going straight to 4-bits, ignore the user's palette count in favor of a 16-color one.
                        If (outputColorDepth = 4) Then
                            tmpFIHandle = FreeImage_ColorQuantizeEx(fi_DIB, quantMethod, False, 16)
                        Else
                            If (paletteCount = 256) Then
                                tmpFIHandle = FreeImage_ColorQuantize(fi_DIB, quantMethod)
                            Else
                                tmpFIHandle = FreeImage_ColorQuantizeExInt(fi_DIB, quantMethod, paletteCount)
                            End If
                        End If
                        
                    End If
                    
                    If (tmpFIHandle <> fi_DIB) Then
                        
                        If (tmpFIHandle <> 0) Then
                            FreeImage_Unload fi_DIB
                            fi_DIB = tmpFIHandle
                        Else
                            FI_DebugMsg "WARNING!  tmpFIHandle is zero!"
                        End If
                        
                    End If
                    
                    'We now have an 8-bpp image.  Forcibly convert to 4-bpp if necessary.
                    If (outputColorDepth = 4) Then
                        tmpFIHandle = FreeImage_ConvertTo4Bits(fi_DIB)
                        If (tmpFIHandle <> fi_DIB) And (tmpFIHandle <> 0) Then
                            FreeImage_Unload fi_DIB
                            fi_DIB = tmpFIHandle
                        End If
                    End If
                    
                'Some bit-depth > 8
                Else
                
                    '15- and 16- are handled similarly
                    If (outputColorDepth = 15) Or (outputColorDepth = 16) Then
                        
                        If (outputColorDepth = 15) Then
                            tmpFIHandle = FreeImage_ConvertTo16Bits555(fi_DIB)
                        Else
                            If RGB16bppUse565 Then
                                tmpFIHandle = FreeImage_ConvertTo16Bits565(fi_DIB)
                            Else
                                tmpFIHandle = FreeImage_ConvertTo16Bits555(fi_DIB)
                            End If
                        End If
                        
                        If (tmpFIHandle <> fi_DIB) Then
                            FreeImage_Unload fi_DIB
                            fi_DIB = tmpFIHandle
                        End If
                        
                    'Some bit-depth > 16
                    Else
                        
                        '24-bpp doesn't need to be handled, because it is the default entry point for PD images
                        If (outputColorDepth > 24) And (outputColorDepth <> 32) Then
                        
                            'High bit-depth variants are covered last
                            If (outputColorDepth = 48) Then
                                tmpFIHandle = FreeImage_ConvertToRGB16(fi_DIB)
                                If (tmpFIHandle <> fi_DIB) Then
                                    FreeImage_Unload fi_DIB
                                    fi_DIB = tmpFIHandle
                                End If
                                
                            '96-bpp is the only other possibility
                            Else
                                tmpFIHandle = FreeImage_ConvertToRGBF(fi_DIB)
                                If (tmpFIHandle <> fi_DIB) Then
                                    FreeImage_Unload fi_DIB
                                    fi_DIB = tmpFIHandle
                                End If
                            End If
                        
                        End If
                        
                    End If
                
                End If
            
            'The image contains alpha, and the caller wants alpha in the final image.
            
            '(Note also that forceGrayscale may or may not be TRUE, but a grayscale conversion will have been applied by a
            ' previous step, so we can safely ignore its value here.  This is necessary because FreeImage does not internally
            ' support the concept of gray+alpha images - they must be expanded to RGBA.)
            Else
                
                'Skip 32-bpp outputs, as the image will already be in that depth by default!
                If (outputColorDepth <> 32) Then
                
                    '(FYI: < 32-bpp + alpha is the ugliest conversion we handle)
                    If (outputColorDepth < 32) Then
                        
                        Dim paletteCheck() As Byte
                        ReDim paletteCheck(0 To 255) As Byte
                        
                        Dim fiPixels() As Byte
                        Dim srcSA As SafeArray1D
                        
                        Dim iWidth As Long, iHeight As Long, iScanWidth As Long
                        Dim x As Long, y As Long, transparentIndex As Long
                        
                        'PNG is the output format that gives us the most grief here, because it supports so many different
                        ' transparency formats.  We have to manually work around formats not supported by FreeImage,
                        ' which means an unpleasant amount of custom code.
                        
                        'First, we start by getting the image into 8-bpp color mode.  How we do this varies by transparency type.
                        ' 1) Images with full transparency need to be quantized, then converted to back to 32-bpp mode.
                        '    We will manually plug-in the correct alpha bytes post-quantization.
                        ' 2) Images with binary transparency need to be quantized to 255 colors or less.  The image can stay
                        '    in 8-bpp mode; we will fill the first empty palette index with transparency, and update the
                        '    image accordingly.
                        
                        'Full transparency is desired in the final image
                        If (desiredAlphaState = PDAS_ComplicatedAlpha) Then
                            
                            'Start by backing up the image's current transparency data.
                            DIBs.RetrieveTransparencyTable srcDIB, tmpTransparencyTable
                            
                            'Fix premultiplication
                            ResetExportPreviewDIB tmpDIBRequired, srcDIB
                            Dim resetAlphaPremultiplication As Boolean: resetAlphaPremultiplication = False
                            If m_ExportPreviewDIB.GetAlphaPremultiplication Then
                                resetAlphaPremultiplication = True
                                m_ExportPreviewDIB.ConvertTo24bpp finalBackColor
                            End If
                            
                            FreeImage_Unload fi_DIB
                            fi_DIB = FreeImage_CreateFromDC(m_ExportPreviewDIB.GetDIBDC)
                            
                            'Quantize the image (using lossless means, if possible)
                            tmpFIHandle = FreeImage_ColorQuantizeEx(fi_DIB, FIQ_LFPQUANT, False, paletteCount)
                            
                            '0 means the image has > 255 colors, and must be quantized via lossy means
                            If (quantMethod = FIQ_LFPQUANT) Then quantMethod = FIQ_WUQUANT
                            If (tmpFIHandle = 0) Then tmpFIHandle = FreeImage_ColorQuantizeEx(fi_DIB, quantMethod, False, paletteCount)
                            
                            'Regardless of what quantization method was applied, update our pointer to point at the new
                            ' 8-bpp copy of the source image.
                            If (tmpFIHandle <> fi_DIB) Then
                                If (tmpFIHandle <> 0) Then
                                    FreeImage_Unload fi_DIB
                                    fi_DIB = tmpFIHandle
                                Else
                                    FI_DebugMsg "WARNING!  FreeImage failed to quantize the original fi_DIB into a valid 8-bpp version."
                                End If
                            End If
                            
                            'fi_DIB now points at an 8-bpp image.  Upsample it to 32-bpp.
                            tmpFIHandle = FreeImage_ConvertTo32Bits(fi_DIB)
                            If (tmpFIHandle <> fi_DIB) Then
                                If (tmpFIHandle <> 0) Then
                                    FreeImage_Unload fi_DIB
                                    fi_DIB = tmpFIHandle
                                Else
                                    FI_DebugMsg "WARNING!  FreeImage failed to convert the quantized fi_DIB into a valid 32-bpp version."
                                End If
                            End If
                            
                            'Next, we need to copy our 32-bpp data over FreeImage's 32-bpp data.
                            iWidth = FreeImage_GetWidth(fi_DIB) - 1
                            iHeight = FreeImage_GetHeight(fi_DIB) - 1
                            iScanWidth = FreeImage_GetPitch(fi_DIB)
                            
                            With srcSA
                                .cbElements = 1
                                .cDims = 1
                                .lBound = 0
                                .cElements = iScanWidth
                            End With
                            
                            For y = 0 To iHeight
                                
                                'Point a 1D VB array at this scanline
                                srcSA.pvData = FreeImage_GetScanline(fi_DIB, y)
                                CopyMemory ByVal VarPtrArray(fiPixels()), VarPtr(srcSA), 4
                                
                                'Iterate through this line, copying over new transparency indices as we go
                                For x = 0 To iWidth
                                    fiPixels(x * 4 + 3) = tmpTransparencyTable(x, iHeight - y)
                                Next x
                                
                                'Free our 1D array reference
                                CopyMemory ByVal VarPtrArray(fiPixels()), 0&, 4
                                
                            Next y
                            
                            'We now have a 32-bpp image with quantized RGB values, but intact A values.
                            If resetAlphaPremultiplication Then FreeImage_PreMultiplyWithAlpha (fi_DIB)
                            
                        'Binary transparency is desired in the final image
                        Else
                            
                            'FreeImage supports a new "lossless" quantization method that is perfect for images that already
                            ' have 255 colors or less.  This method is basically just a hash table, and it lets us avoid
                            ' lossy quantization if at all possible.
                            ' (Note that we must forcibly request 255 colors; one color is reserved for the transparent index.)
                            If (paletteCount >= 256) Then paletteCount = 255
                            tmpFIHandle = FreeImage_ColorQuantizeEx(fi_DIB, FIQ_LFPQUANT, False, paletteCount)
                            
                            '0 means the image has > 255 colors, and must be quantized via lossy means
                            If (tmpFIHandle = 0) Then
                                If (quantMethod = FIQ_LFPQUANT) Then quantMethod = FIQ_WUQUANT
                                tmpFIHandle = FreeImage_ColorQuantizeEx(fi_DIB, quantMethod, False, paletteCount)
                            End If
                            
                            'Regardless of what quantization method was applied, update our pointer to point at the new
                            ' 8-bpp copy of the source image.
                            If (tmpFIHandle <> fi_DIB) Then
                                If (tmpFIHandle <> 0) Then
                                    FreeImage_Unload fi_DIB
                                    fi_DIB = tmpFIHandle
                                Else
                                    FI_DebugMsg "WARNING!  FreeImage failed to quantize the original fi_DIB into a valid 8-bpp version."
                                End If
                            End If
                            
                            'fi_DIB now points at an 8-bpp image.
                            
                            'Next, we need to create our transparent index in the palette.  FreeImage won't reliably tell
                            ' us how much of a palette is currently in use (ugh), so instead, we must manually scan the
                            ' image, looking for unused palette entries.
                            iWidth = FreeImage_GetWidth(fi_DIB) - 1
                            iHeight = FreeImage_GetHeight(fi_DIB) - 1
                            iScanWidth = FreeImage_GetPitch(fi_DIB)
                            
                            With srcSA
                                .cbElements = 1
                                .cDims = 1
                                .lBound = 0
                                .cElements = iScanWidth
                            End With
                            
                            For y = 0 To iHeight
                                
                                'Point a 1D VB array at this scanline
                                srcSA.pvData = FreeImage_GetScanline(fi_DIB, y)
                                CopyMemory ByVal VarPtrArray(fiPixels()), VarPtr(srcSA), 4
                                
                                'Iterate through this line, checking values as we go
                                For x = 0 To iWidth
                                    paletteCheck(fiPixels(x)) = 1
                                Next x
                                
                                'Free our 1D array reference
                                CopyMemory ByVal VarPtrArray(fiPixels()), 0&, 4
                                
                            Next y
                            
                            'Scan through the palette array, looking for the first 0 entry (which means that value was not
                            ' found in the source image).
                            transparentIndex = -1
                            For x = 0 To 255
                                If paletteCheck(x) = 0 Then
                                    transparentIndex = x
                                    Exit For
                                End If
                            Next x
                            
                            'It shouldn't be possible for a 256-entry palette to exist, but if it does, we have no choice
                            ' but to "steal" a palette index for transparency.
                            If transparentIndex = -1 Then
                                FI_DebugMsg "WARNING!  FreeImage returned a full palette, so transparency will have to steal an existing entry!"
                                transparentIndex = 255
                            End If
                            
                            'Tell FreeImage which palette index we want to use for transparency
                            FreeImage_SetTransparentIndex fi_DIB, transparentIndex
                            
                            'Now that we have a transparent index, we need to update the target image to be transparent
                            ' in all the right locations.  Use our previously generated transparency table for this.
                            For y = 0 To iHeight
                                
                                'Point a 1D VB array at this scanline
                                srcSA.pvData = FreeImage_GetScanline(fi_DIB, y)
                                CopyMemory ByVal VarPtrArray(fiPixels()), VarPtr(srcSA), 4
                                
                                'The FreeImage DIB will be upside-down at this point
                                For x = 0 To iWidth
                                    If tmpTransparencyTable(x, iHeight - y) = 0 Then fiPixels(x) = transparentIndex
                                Next x
                                
                                'Free our 1D array reference
                                CopyMemory ByVal VarPtrArray(fiPixels()), 0&, 4
                                
                            Next y
                        
                            'We now have an < 8-bpp image with a transparent index correctly marked.  Whew!
                            
                        End If
                    
                    'Output is > 32-bpp with transparency
                    Else
                        
                        '64-bpp is 16-bits per channel RGBA
                        If (outputColorDepth = 64) Then
                            tmpFIHandle = FreeImage_ConvertToRGBA16(fi_DIB)
                            If (tmpFIHandle <> fi_DIB) Then
                                FreeImage_Unload fi_DIB
                                fi_DIB = tmpFIHandle
                            End If
                            
                        '128-bpp is the only other possibility (32-bits per channel RGBA, specifically)
                        Else
                            tmpFIHandle = FreeImage_ConvertToRGBAF(fi_DIB)
                            If (tmpFIHandle <> fi_DIB) Then
                                FreeImage_Unload fi_DIB
                                fi_DIB = tmpFIHandle
                            End If
                        End If
                        
                    End If
                
                'End 32-bpp requests
                End If
            'End alpha vs non-alpha
            End If
        'End grayscale vs non-grayscale
        End If
    'End 1-bpp vs > 1-bpp
    End If
    
    GetFIDib_SpecificColorMode = fi_DIB
    
End Function

'Given an 8-bpp FreeImage handle, return said image's palette.
' RETURNS: image's palette (inside the dstPalette() RGBQuad array), and the number of colors inside said palette.
'          0 if the source image is not 8bpp.
Public Function GetFreeImagePalette(ByVal srcFIHandle As Long, ByRef dstPalette() As RGBQuad) As Long
    
    'Make sure the source image is using a palette
    GetFreeImagePalette = FreeImage_GetColorsUsed(srcFIHandle)
    If (GetFreeImagePalette <> 0) Then
        
        'Retrieve a pointer to the source palette
        Dim ptrPalette As Long
        ptrPalette = FreeImage_GetPalette(srcFIHandle)
        
        If (ptrPalette <> 0) Then
        
            'Copy the source palette into the destination array
            ReDim dstPalette(0 To GetFreeImagePalette - 1) As RGBQuad
            CopyMemory ByVal VarPtr(dstPalette(0)), ByVal ptrPalette, (GetFreeImagePalette - 1) * 4
            
        Else
            GetFreeImagePalette = 0
            Erase dstPalette
        End If
        
    Else
        Erase dstPalette
    End If
    
End Function

Private Sub ResetExportPreviewDIB(ByRef trackerBool As Boolean, ByRef srcDIB As pdDIB)
    If (Not trackerBool) Then
        If (m_ExportPreviewDIB Is Nothing) Then Set m_ExportPreviewDIB = New pdDIB
        m_ExportPreviewDIB.CreateFromExistingDIB srcDIB
        trackerBool = True
    End If
End Sub

'Convert an incoming FreeImage handle to a grayscale FI variant.  The source handle will be unloaded as necessary.
Private Function GetGrayscaleFIDib(ByVal fi_DIB As Long, ByVal outputColorDepth As Long) As Long
    
    Dim tmpFIHandle As Long
    
    'Output color depth is important here.  16-bpp and 32-bpp grayscale are actually high bit-depth modes!
    If (outputColorDepth <= 8) Then
        
        'Create an 8-bpp palette
        tmpFIHandle = FreeImage_ConvertToGreyscale(fi_DIB)
        If (tmpFIHandle <> fi_DIB) And (tmpFIHandle <> 0) Then
            FreeImage_Unload fi_DIB
            fi_DIB = tmpFIHandle
        End If
        
        'If the caller wants a 4-bpp palette, do that now.
        If (outputColorDepth = 4) And (tmpFIHandle <> 0) Then
            tmpFIHandle = FreeImage_ConvertTo4Bits(fi_DIB)
                If (tmpFIHandle <> fi_DIB) Then
                FreeImage_Unload fi_DIB
                fi_DIB = tmpFIHandle
            End If
        End If
    
    'Forcing to grayscale and using an outputColorDepth > 8 means you want a high bit-depth copy!
    Else
    
        '32-bpp
        If (outputColorDepth = 32) Then
            tmpFIHandle = FreeImage_ConvertToFloat(fi_DIB)
            If (tmpFIHandle <> fi_DIB) And (tmpFIHandle <> 0) Then
                FreeImage_Unload fi_DIB
                fi_DIB = tmpFIHandle
            End If
        
        'Output color-depth must be 16; any other values are invalid
        Else
            tmpFIHandle = FreeImage_ConvertToUINT16(fi_DIB)
            If (tmpFIHandle <> fi_DIB) And (tmpFIHandle <> 0) Then
                FreeImage_Unload fi_DIB
                fi_DIB = tmpFIHandle
            End If
        End If
        
    End If
    
    GetGrayscaleFIDib = fi_DIB
    
End Function

'Given a source FreeImage handle and FI format, fill a destination DIB with a post-"exported-to-that-format" version of the image.
' This is used to generate the "live previews" used in various "export to lossy format" dialogs.
'
'(Note that you could technically pass a bare DIB to this function, but because different dialogs provide varying levels of control
' over the source image, it's often easier to let the caller handle that step.  That way, they can cache a FI handle in the most
' relevant color depth, shaving previous ms off the actual export+import step.)
Public Function GetExportPreview(ByRef srcFI_Handle As Long, ByRef dstDIB As pdDIB, ByVal dstFormat As PD_IMAGE_FORMAT, Optional ByVal fi_SaveFlags As Long = 0, Optional ByVal fi_LoadFlags As Long = 0)
    
    Dim fi_Size As Long
    If FreeImage_SaveToMemoryEx(dstFormat, srcFI_Handle, m_ExportPreviewBytes, fi_SaveFlags, False, fi_Size) Then
        
        Dim fi_DIB As Long
        fi_DIB = FreeImage_LoadFromMemoryEx(Nothing, fi_LoadFlags, fi_Size, dstFormat, VarPtr(m_ExportPreviewBytes(0)))
        
        If (fi_DIB <> 0) Then
        
            'Because we're going to do a fast copy operation, we need to flip the FreeImage DIB to match DIB orientation
            FreeImage_FlipVertically fi_DIB
            
            'If a format requires special handling, trigger it here
            If (dstFormat = PDIF_PBM) Or (dstFormat = PDIF_PBMRAW) And (FreeImage_GetBPP(fi_DIB) = 1) Then
                FreeImage_Invert fi_DIB
            End If
            
            'Convert the incoming DIB to a 24-bpp or 32-bpp representation
            If (FreeImage_GetBPP(fi_DIB) <> 24) And (FreeImage_GetBPP(fi_DIB) <> 32) Then
                
                Dim newFI_Handle As Long
                If FreeImage_IsTransparent(fi_DIB) Or (FreeImage_GetTransparentIndex(fi_DIB) <> -1) Then
                    newFI_Handle = FreeImage_ConvertColorDepth(fi_DIB, FICF_RGB_32BPP, False)
                Else
                    newFI_Handle = FreeImage_ConvertColorDepth(fi_DIB, FICF_RGB_24BPP, False)
                End If
                
                If (newFI_Handle <> fi_DIB) Then
                    FreeImage_Unload fi_DIB
                    fi_DIB = newFI_Handle
                End If
                
            End If
            
            'Copy the DIB into a PD DIB object
            If Not Plugin_FreeImage.PaintFIDibToPDDib(dstDIB, fi_DIB, 0, 0, dstDIB.GetDIBWidth, dstDIB.GetDIBHeight) Then
                FI_DebugMsg "WARNING!  Plugin_FreeImage.PaintFIDibToPDDib failed for unknown reasons."
            End If
            
            FreeImage_Unload fi_DIB
            GetExportPreview = True
        Else
            FI_DebugMsg "WARNING!  Plugin_FreeImage.GetExportPreview failed to generate a valid fi_Handle."
            GetExportPreview = False
        End If
        
    Else
        FI_DebugMsg "WARNING!  Plugin_FreeImage.GetExportPreview failed to save the requested handle to an array."
        GetExportPreview = False
    End If
    
End Function

'PD uses a persistent cache for generating post-export preview images.  This costs several MB of memory but greatly improves
' responsiveness of export dialogs.  When such a dialog is unloaded, you can call this function to forcibly reclaim the memory
' associated with that cache.
Public Sub ReleasePreviewCache(Optional ByVal unloadThisFIHandleToo As Long = 0)
    Erase m_ExportPreviewBytes
    Set m_ExportPreviewDIB = Nothing
    If (unloadThisFIHandleToo <> 0) Then ReleaseFreeImageObject unloadThisFIHandleToo
End Sub

Public Sub ReleaseFreeImageObject(ByVal srcFIHandle As Long)
    FreeImage_Unload srcFIHandle
End Sub

Private Sub FI_DebugMsg(ByVal debugMsg As String, Optional ByVal suppressDebugData As Boolean = False)
    #If DEBUGMODE = 1 Then
        If (Not suppressDebugData) Then pdDebug.LogAction debugMsg, PDM_External_Lib
    #End If
End Sub
