Attribute VB_Name = "MainModule"
'***************************************************************************
'PhotoDemon Startup Module
'Copyright 2014-2017 by Tanner Helland
'Created: 03/March/14
'Last updated: 31/January/17
'Last update: continued work on improving program startup time
'
'The Main() sub in this module is the first thing invoked when PD begins (after VB's own internal startup processes,
' obviously).  I've also included some other crucial startup and shutdown functions in this module.
'
'Portions of the Main() process (related to manually initializing shell libraries) were adopted from a vbforums.com
' project by LaVolpe.  You can see his original work here: http://www.vbforums.com/showthread.php?t=606736
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'If critical errors are affecting PD at startup time, you can activate this constant to forcibly write incomplete debug
' data during the program intialization steps.
' (This constant should always be DISABLED, unless you are doing purely local testing on an egregious startup bug.)
Private Const ENABLE_EMERGENCY_DEBUGGER As Boolean = False

Private Declare Sub InitCommonControls Lib "comctl32" ()
Private Declare Function InitCommonControlsEx Lib "comctl32" (ByRef iccex As InitCommonControlsExStruct) As Long
Private Type InitCommonControlsExStruct
    lngSize As Long
    lngICC As Long
End Type

'As of September 2015, reordering the list of files in the master VBP caused unpredictable crashes when PD closes.
' (After the final line of PD code is run, no less.)  I spent two days bisecting commits and I can conclusively nail
' the problem down to
' https://github.com/tannerhelland/PhotoDemon/commit/293de1ba4f2d5bc3102304d0263af624e93b6093
'
'I eventually solved the problem by manually unloading all global class instances in a specific order, rather than
' leaving it to VB, but during testing, I still sometimes find it helpful to suppress the default Windows crash dialog.
' In case this proves useful in the future, I'll leave the declaration here.
Private Declare Function SetErrorMode Lib "kernel32" (ByVal wMode As Long) As Long
Private Const SEM_FAILCRITICALERRORS = &H1
Private Const SEM_NOGPFAULTERRORBOX = &H2
Private Const SEM_NOOPENFILEERRORBOX = &H8000&

Private m_hShellModule As Long

'This constant is the number of "discrete" loading steps involved in loading the program.
' It is relevant for displaying the progress bar on the initial splash screen; this value is the
' progress bar's maximum value.
Private Const NUMBER_OF_LOADING_STEPS As Long = 18

'After Main() has been invoked, this will be set to TRUE.  This is important in VBy as some functions (like those
' inside user controls) will be called during either design-time or compilation-time.  PD relies on this variable,
' accessed via the IsProgramRunning function, to forcibly suspend certain program operations.
Private m_IsProgramRunning As Boolean

'If the program was loaded successfully, this will be set to TRUE.  Various shutdown procedures check this before
' attempting to write data to file.
Private m_ProgramStartupSuccessful As Boolean

'PhotoDemon starts here.  Main() is necessary as a start point (vs a form) to make sure that theming is implemented
' correctly.  Note that this code is irrelevant within the IDE.
Public Sub Main()
    
    m_ProgramStartupSuccessful = False
    
    'InitCommonControlsEx requires IEv3 or above, which shouldn't be a problem on any modern system.  But just in case,
    ' continue loading even if the common control module load fails.
    On Error Resume Next
    
    'The following block of code prevents XP crashes when VB usercontrols are present in a project (as they are in PhotoDemon)
    
    'Make sure shell32 is loaded
    Dim strShellName As String
    strShellName = "shell32.dll"
    m_hShellModule = LoadLibrary(StrPtr(strShellName))
    
    'Make sure comctl32 is loaded.  (For details on these constants, visit http://msdn.microsoft.com/en-us/library/bb775507%28VS.85%29.aspx)
    Dim iccex As InitCommonControlsExStruct
    With iccex
        .lngSize = LenB(iccex)
        Const ICC_BAR_CLASSES As Long = &H4&
        Const ICC_STANDARD_CLASSES As Long = &H4000&
        Const ICC_WIN95_CLASSES As Long = &HFF&
        .lngICC = ICC_STANDARD_CLASSES Or ICC_BAR_CLASSES Or ICC_WIN95_CLASSES
    End With
    InitCommonControlsEx iccex
    
    'If an error occurs, attempt to initiate the Win9x version, then reset error handling
    If Err Then
        InitCommonControls
        Err.Clear
    End If
    
    On Error GoTo 0
    
    'Because Ambient.UserMode can produce unexpected behavior - see, for example, this link:
    ' http://www.vbforums.com/showthread.php?805711-VB6-UserControl-Ambient-UserMode-workaround
    ' - we manually track program run state.  See additional details at the top of this module,
    ' where m_IsProgramRunning is declared.
    m_IsProgramRunning = True
    
    'FormMain can now be loaded.  (We load it first, because many initialization steps silently interact with it,
    ' like loading menu icons or prepping toolboxes.)  That said, the first step of FormMain's load process is calling
    'the ContinueLoadingProgram sub, below, so look there for the next stages of the load process.
    On Error GoTo ExitMainImmediately
    If (Not g_ProgramShuttingDown) Then Load FormMain
    
ExitMainImmediately:

End Sub

'Note that this function is called AFTER FormMain has been loaded.  FormMain is loaded - but not visible - so it can be
' operated on by functions called from this routine.  (It is necessary to load the main window first, since a number of
' load operations - like decoding PNG menu icons from the resource file, then applying them to program menus - operate
' directly on the main window.)
Public Function ContinueLoadingProgram() As Boolean
    
    'We assume that the program will initialize correctly.  If for some reason it doesn't, it will return FALSE, and the
    ' program needs to be shut down accordingly, because it is catastrophically broken.
    ContinueLoadingProgram = True
    
    '*************************************************************************************************************************************
    ' Check the state of this build (alpha, beta, production, etc) and activate debug code as necessary
    '*************************************************************************************************************************************
    
    'Current build state is stored in the public const "PD_BUILD_QUALITY".  For non-production builds, a number of program-wide
    ' parameters are automatically set.
    
    'If the program is in pre-alpha or alpha state, enable timing reports.
    If (PD_BUILD_QUALITY = PD_PRE_ALPHA) Or (PD_BUILD_QUALITY = PD_ALPHA) Then g_DisplayTimingReports = True
    
    'Enable program-wide high-performance timer objects
    VBHacks.EnableHighResolutionTimers
    
    'Regardless of debug mode, we instantiate a pdDebug instance.  It will only be interacted with if the program is compiled
    ' with DEBUGMODE = 1, however.
    Set pdDebug = New pdDebugger
    
    'During development, I find it helpful to profile PhotoDemon's startup process (so I can watch for obvious regressions).
    ' PD utilizes several different profiler-types; the LT type is "long-term" profiling, where data is written to a persistent
    ' log file and measured over time.
    Dim perfCheck As pdProfilerLT
    Set perfCheck = New pdProfilerLT
    
    #If DEBUGMODE = 1 Then
        perfCheck.StartProfiling "PhotoDemon Startup", True
    #End If
    
    
    
    '*************************************************************************************************************************************
    ' With the debugger initialized, prep a few crucial variables
    '*************************************************************************************************************************************
    
    'Most importantly, we need to create a default pdImages() array, as some initialization functions may attempt to access that array
    ReDim pdImages(0 To 3) As pdImage
    
    
    
    '*************************************************************************************************************************************
    ' Prepare the splash screen (but don't display it yet)
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Prepare splash screen"
    #End If
    
    'Before doing any 2D rendering, we need to start at least one valid 2D rendering backend.
    ' (At present, only GDI+ is used)
    Interface.InitializeInterfaceBackend
    
    If Drawing2D.StartRenderingEngine(P2_DefaultBackend) Then
        
        #If DEBUGMODE = 1 Then
            Drawing2D.SetLibraryDebugMode True
        #End If
        
        'Load FormSplash into memory.  (Note that its .Visible property is set to FALSE, so it is not actually displayed here.)
        Load FormSplash
        
    End If
    
    
    '*************************************************************************************************************************************
    ' Determine which version of Windows the user is running (as other load functions rely on this)
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Check Windows version"
    #End If
    
    LoadMessage "Detecting Windows� version..."
    
    'If we are on Windows 7, prepare some Win7-specific features (like taskbar progress bars)
    If OS.IsWin7OrLater Then OS.StartWin7PlusFeatures
    
    
    '*************************************************************************************************************************************
    ' Initialize the user preferences (settings) handler
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Initialize preferences engine"
    #End If
    
    Set g_UserPreferences = New pdPreferences
    
    'Ask the preferences handler to generate key program folders.  (If these folders don't exist, the handler will create them.)
    ' Similarly, if the user has done something stupid, like unzip PD inside a system folder, the preferences manager will
    ' auto-detect this and silently redirect program settings to the appropriate user folder.  A flag will also be set, so we
    ' can warn the user about this behavior after the program finishes loading.)
    LoadMessage "Initializing all program directories..."
    
    'This is one of the few functions where a failure will cause PD to exit immediately.
    ContinueLoadingProgram = g_UserPreferences.InitializePaths()
    If (Not ContinueLoadingProgram) Then Exit Function
    
    'Now, ask the preferences handler to load all other user settings from the preferences file.
    ' IMPORTANTLY: note that loading all settings puts the preferences engine into "batch mode".  Normally, the preferences engine
    ' immediately writes all changes out to file, which preserves things like "last-used settings" if the program goes down
    ' prematurely (due to a crash or other problem).  Batch mode suspends this behavior.  At present, batch mode is turned off
    ' after FormMain successfully loads, initializes, and displays.
    LoadMessage "Loading all user settings..."
    
    g_UserPreferences.LoadUserSettings False
    
    'Mark the Macro recorder as "not recording"
    Macros.SetMacroStatus MacroSTOP
    
    'Note that no images have been loaded yet
    g_NumOfImagesLoaded = 0
    
    'Set the default active image index to 0
    g_CurrentImage = 0
    
    'Set the number of open image windows to 0
    g_OpenImageCount = 0
    
    'While here, also initialize the image format handler (as plugins and other load functions interact with it)
    Set g_ImageFormats = New pdFormats
    ImageImporter.ResetImageImportPreferenceCache
    
    
    '*************************************************************************************************************************************
    ' If this is an emergency debug session, write our first log
    '*************************************************************************************************************************************
    
    'Normally, PD logs a bunch of internal data before exporting its first debug log, but if things are really dire,
    ' we can forcibly initialize debugging here.  (Just note that things like plugin data will *not* be accurate,
    ' as they haven't been loaded yet!)
    #If DEBUGMODE = 1 Then
        If ENABLE_EMERGENCY_DEBUGGER Then pdDebug.InitializeDebugger True, False
    #End If
    
    
    '*************************************************************************************************************************************
    ' Initialize the plugin manager and load any high-priority plugins (e.g. those required to start the program successfully)
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Load high-priority plugins"
    #End If
    
    PluginManager.InitializePluginManager
    PluginManager.LoadPluginGroup True
    
    
    '*************************************************************************************************************************************
    ' Initialize our internal resources handler
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Initialize resource handler"
    #End If
    
    Set g_Resources = New pdResources
    g_Resources.LoadInitialResourceCollection
    
    
    '*************************************************************************************************************************************
    ' Initialize our internal menu manager
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Initialize menu manager"
    #End If
    
    Menus.InitializeMenus
    
    
    '*************************************************************************************************************************************
    ' Initialize the translation (language) engine
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Initialize translation engine"
    #End If
    
    'Initialize a new language engine.
    Set g_Language = New pdTranslate
        
    LoadMessage "Scanning for language files..."
    
    'Before doing anything else, check to see what languages are available in the language folder.
    ' (Note that this function will also populate the Languages menu, though it won't place a checkmark next to an entry yet.)
    g_Language.CheckAvailableLanguages
        
    LoadMessage "Determining which language to use..."
        
    'Next, determine which language to use.  (This function will take into account the system language at first-run, so it can
    ' estimate which language to present to the user.)
    g_Language.DetermineLanguage
    
    LoadMessage "Applying selected language..."
    
    'Apply that language to the program.  This involves loading the translation file into memory, which can take a bit of time,
    ' but it only needs to be done once.  From that point forward, any text requests will operate on the in-memory copy of the file.
    g_Language.ApplyLanguage False
    
    
    '*************************************************************************************************************************************
    ' Initialize the visual themes engine
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Initialize theme engine"
    #End If
    
    'Because this class controls the visual appearance of all forms in the project, it must be loaded early in the boot process
    LoadMessage "Initializing theme engine..."
    
    Set g_Themer = New pdTheme
    
    'Load and validate the user's selected theme file
    g_Themer.LoadDefaultPDTheme
    
    'Now that a theme has been loaded, we can initialize additional UI rendering elements
    g_Resources.NotifyThemeChange
    Drawing.CacheUIPensAndBrushes
    Paintbrush.InitializeBrushEngine
    Selections.InitializeSelectionRendering
    
    '*************************************************************************************************************************************
    ' PhotoDemon works well with multiple monitors.  Check for such a situation now.
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Detect displays"
    #End If
    
    LoadMessage "Analyzing current monitor setup..."
    
    Set g_Displays = New pdDisplays
    g_Displays.RefreshDisplays
    
    'While here, also cache various display-related settings; this is faster than constantly retrieving them via APIs
    Interface.CacheSystemDPI g_Displays.GetWindowsDPI
    
    
    '*************************************************************************************************************************************
    ' Now we have what we need to properly display the splash screen.  Do so now.
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Calculate splash screen coordinates"
    #End If
    
    'Determine the program's previous on-screen location.  We need that to determine where to display the splash screen.
    Dim wRect As RectL
    With wRect
        .Left = g_UserPreferences.GetPref_Long("Core", "Last Window Left", 1)
        .Top = g_UserPreferences.GetPref_Long("Core", "Last Window Top", 1)
        .Right = .Left + g_UserPreferences.GetPref_Long("Core", "Last Window Width", 1)
        .Bottom = .Top + g_UserPreferences.GetPref_Long("Core", "Last Window Height", 1)
    End With
    
    'Center the splash screen on whichever monitor the user previously used.
    g_Displays.CenterFormViaReferenceRect FormSplash, wRect
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Confirm UI font exists"
    #End If
    
    'If Segoe UI is available, we prefer to use it instead of Tahoma.  On XP this is not guaranteed, however, so we have to check.
    Dim tmpFontCheck As pdFont
    Set tmpFontCheck = New pdFont
    
    'If Segoe exists, we mark two variables: a String (which user controls use to create their own font objects), and a Boolean
    ' (which some dialogs use to slightly modify their layout for better alignments).
    If tmpFontCheck.DoesFontExist("Segoe UI") Then g_InterfaceFont = "Segoe UI" Else g_InterfaceFont = "Tahoma"
    Set tmpFontCheck = Nothing
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Retrieve splash logo"
    #End If
    
    'Ask the splash screen to finish whatever initializing it needs prior to displaying itself
    FormSplash.PrepareSplashLogo NUMBER_OF_LOADING_STEPS
    FormSplash.PrepareRestOfSplash
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Display splash screen"
    #End If
    
    'Display the splash screen, centered on whichever monitor the user previously used the program on.
    FormSplash.Show vbModeless
    
    '*************************************************************************************************************************************
    ' If this is not a production build, initialize PhotoDemon's central debugger
    '*************************************************************************************************************************************
    
    'We wait until after the translation and plugin engines are initialized; this allows us to report their information in the debug log
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Initialize debugger"
        pdDebug.InitializeDebugger True
    #End If
        
    
    '*************************************************************************************************************************************
    ' Based on available plugins, determine which image formats PhotoDemon can handle
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Load import and export libraries"
    #End If
    
    LoadMessage "Loading import/export libraries..."
    
    'The FreeImage.dll plugin provides most of PD's advanced image format support, but we can also fall back on GDI+.
    ' Prior to generating a list of supported formats, notify the image format class of GDI+ availability
    ' (which was determined earlier in this function, prior to loading the splash screen).
    g_ImageFormats.GDIPlusEnabled = Drawing2D.IsRenderingEngineActive(P2_GDIPlusBackend)
    
    'Generate a list of currently supported input/output formats, which may vary based on plugin version and availability
    g_ImageFormats.GenerateInputFormats
    g_ImageFormats.GenerateOutputFormats
    
    
    '*************************************************************************************************************************************
    ' Build a font cache for this system
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Build font cache"
    #End If
    
    LoadMessage "Building font cache..."
        
    'PD currently builds two font caches:
    ' 1) A name-only list of all fonts currently installed.  This is used to populate font dropdown boxes.
    ' 2) An pdFont-based cache of the current UI font, at various requested sizes.  This cache spares individual controls from needing
    '     to do their own font management; instead, they can simply request a matching object from the Fonts module.
    Fonts.BuildFontCaches
    
    'Next, build a list of font properties, like supported scripts
    Fonts.BuildFontCacheProperties
    
    
    
    '*************************************************************************************************************************************
    ' Initialize PD's central clipboard manager
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Initialize pdClipboardMain"
    #End If
    
    LoadMessage "Initializing clipboard interface..."
    
    Set g_Clipboard = New pdClipboardMain
    
    
    '*************************************************************************************************************************************
    ' Get the viewport engine ready
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Initialize viewport engine"
    #End If
    
    'Initialize our current zoom method
    LoadMessage "Initializing viewport engine..."
    
    'Create the program's primary zoom handler
    Set g_Zoom = New pdZoom
    g_Zoom.InitializeViewportEngine
    
    'Populate the main form's zoom drop-down
    g_Zoom.PopulateZoomComboBox FormMain.mainCanvas(0).GetZoomDropDownReference
    
    'Populate the main canvas's size unit dropdown
    FormMain.mainCanvas(0).PopulateSizeUnits
    
    
    '*************************************************************************************************************************************
    ' Finish loading low-priority plugins
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Load low-priority plugins"
    #End If
    
    PluginManager.LoadPluginGroup False
    PluginManager.ReportPluginLoadSuccess
    
    '*************************************************************************************************************************************
    ' Initialize the window manager (the class that synchronizes all toolbox and image window positions)
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Initialize window manager"
    #End If
    
    LoadMessage "Initializing window manager..."
    Set g_WindowManager = New pdWindowManager
    
    'Register the main form
    g_WindowManager.SetAutoRefreshMode False
    g_WindowManager.RegisterMainForm FormMain
    
    'As of 7.0, all we need to do here is initialize the new, lightweight toolbox handler.  This will load things
    ' like toolbox sizes and visibility from the previous session.
    Toolboxes.LoadToolboxData
    
    'With toolbox data assembled, we can now silently load each tool window.  Even though these windows may not
    ' be visible (as the user can elect to hide them), we still want them loaded so that we can activate them quickly
    ' if/when they are enabled.
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Window manager: load left toolbox"
    #End If
    Load toolbar_Toolbox
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Window manager: load right toolbox"
    #End If
    Load toolbar_Layers
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Window manager: load bottom toolbox"
    #End If
    Load toolbar_Options
    
    'Retrieve tool window visibility and mark those menus as well
    FormMain.MnuWindowToolbox(0).Checked = Toolboxes.GetToolboxVisibilityPreference(PDT_LeftToolbox)
    FormMain.MnuWindow(1).Checked = Toolboxes.GetToolboxVisibilityPreference(PDT_BottomToolbox)
    FormMain.MnuWindow(2).Checked = Toolboxes.GetToolboxVisibilityPreference(PDT_RightToolbox)
    
    'Retrieve two additional settings for the image tabstrip menu: when to display it, and its alignment
    ToggleImageTabstripVisibility g_UserPreferences.GetPref_Long("Core", "Image Tabstrip Visibility", 1), True
    ToggleImageTabstripAlignment g_UserPreferences.GetPref_Long("Core", "Image Tabstrip Alignment", vbAlignTop), True
    
    'The primary toolbox has some options of its own.  Load them now.
    FormMain.MnuWindowToolbox(2).Checked = g_UserPreferences.GetPref_Boolean("Core", "Show Toolbox Category Labels", True)
    toolbar_Toolbox.UpdateButtonSize g_UserPreferences.GetPref_Long("Core", "Toolbox Button Size", 1), True
    
    
    
    '*************************************************************************************************************************************
    ' Set all default tool values
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Initialize tools"
    #End If
    
    LoadMessage "Initializing image tools..."
    
    'As of May 2015, tool panels are now loaded on-demand.  This improves the program's startup performance, and it saves a bit of memory
    ' if a user doesn't use a tool during a given session.
    
    'Also, while here, prep the specialized non-destructive tool handler in the central processor
    Processor.InitializeProcessor
    
    
    '*************************************************************************************************************************************
    ' PhotoDemon's complex interface requires a lot of things to be generated at run-time.
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Initialize UI"
    #End If
    
    LoadMessage "Initializing user interface..."
    
    'Use the API to give PhotoDemon's main form a 32-bit icon (VB is too old to support 32bpp icons)
    IconsAndCursors.SetThunderMainIcon
    
    'Initialize all system cursors we rely on (hand, busy, resizing, etc)
    IconsAndCursors.InitializeCursors
    
    'Set up the program's title bar.  Odd-numbered releases are development releases.  Even-numbered releases are formal builds.
    If (Not g_WindowManager Is Nothing) Then
        g_WindowManager.SetWindowCaptionW FormMain.hWnd, Updates.GetPhotoDemonNameAndVersion()
    Else
        FormMain.Caption = Updates.GetPhotoDemonNameAndVersion()
    End If
    
    'PhotoDemon renders many of its own icons dynamically.  Initialize that engine now.
    InitializeIconHandler
    
    'Prepare a checkerboard pattern, which will be used behind any transparent objects.  Caching this is much more efficient.
    ' than re-creating it every time it's needed.  (Note that PD exposes two versions of the checkerboard pattern: a GDI version
    ' and a GDI+ version.)
    Set g_CheckerboardPattern = New pdDIB
    Drawing.CreateAlphaCheckerboardDIB g_CheckerboardPattern
    Set g_CheckerboardBrush = New pd2DBrush
    g_CheckerboardBrush.SetBrushMode P2_BM_Texture
    g_CheckerboardBrush.SetBrushTextureWrapMode P2_WM_Tile
    g_CheckerboardBrush.SetBrushTextureFromDIB g_CheckerboardPattern
    
    'Allow drag-and-drop operations
    g_AllowDragAndDrop = True
    
    'Throughout the program, g_MouseAccuracy is used to determine how close the mouse cursor must be to a point of interest to
    ' consider it "over" that point.  DPI must be accounted for when calculating this value (as it's calculated in pixels).
    g_MouseAccuracy = FixDPIFloat(7)
    
    'Allow main form components to load any control-specific preferences they may utilize
    FormMain.mainCanvas(0).ReadUserPreferences
    
    'Prep the color management pipeline
    ColorManagement.CacheDisplayCMMData
    
    
    '*************************************************************************************************************************************
    ' The program's menus support many features that VB can't do natively (like icons and custom shortcuts).  Load such things now.
    '*************************************************************************************************************************************
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Prep developer menus"
    #End If
    
    LoadMessage "Preparing program menus..."
    
    'In debug modes, certain developer and experimental menus will be enabled.
    Dim debugMenuVisibility As Boolean
    debugMenuVisibility = (PD_BUILD_QUALITY <> PD_PRODUCTION) And (PD_BUILD_QUALITY <> PD_BETA)
    FormMain.MnuTest.Visible = debugMenuVisibility
    FormMain.MnuTool(11).Visible = debugMenuVisibility
    FormMain.MnuTool(12).Visible = debugMenuVisibility
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Initialize hotkey manager"
    #End If
    
    'In the future, hotkeys really need to become user-editable, but for now, the list is hard-coded.
    Menus.InitializeAllHotkeys
            
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Prep MRU menus"
    #End If
    
    'Initialize the Recent Files manager and load the most-recently-used file list (MRU)
    Set g_RecentFiles = New pdRecentFiles
    g_RecentFiles.LoadListFromFile
    
    Set g_RecentMacros = New pdMRUManager
    g_RecentMacros.InitList New pdMRURecentMacros
    g_RecentMacros.MRU_LoadFromFile
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Load all menu icons"
    #End If
    
    'Load and draw all menu icons
    IconsAndCursors.LoadMenuIcons False
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Apply theme/language to FormMain"
    #End If
    
    'Finally, apply all of our various UI features
    FormMain.UpdateAgainstCurrentTheme False
    
    #If DEBUGMODE = 1 Then
        perfCheck.MarkEvent "Final interface sync"
    #End If
    
    'Synchronize all other interface elements to match the current program state (e.g. no images loaded).
    Interface.SyncInterfaceToCurrentImage
    
    'If we made it all the way here, startup can be considered successful!
    m_ProgramStartupSuccessful = True
    
    '*************************************************************************************************************************************
    ' Unload the splash screen and present the main form
    '*************************************************************************************************************************************
    
    'While in debug mode, copy a timing report of program startup to the debug folder
    #If DEBUGMODE = 1 Then
        perfCheck.StopProfiling
        perfCheck.GenerateProfileReport True
    #End If
    
    'If this is the first time the user has run PhotoDemon, resize the window a bit to make the default position nice.
    ' (If this is *not* the first time, the window manager will automatically restore the window's last-known position and state.)
    If g_IsFirstRun Then g_WindowManager.SetFirstRunMainWindowPosition
    
    'In debug mode, make a baseline memory reading here, before the main form is displayed.
    #If DEBUGMODE = 1 Then
        pdDebug.LogAction "LoadTheProgram() function complete.  Baseline memory reading:"
        pdDebug.LogAction "", PDM_Mem_Report
        pdDebug.LogAction "Proceeding to load main window..."
    #End If
    
    Unload FormSplash
    
End Function

'FormMain's Unload step calls this process as its final action.
Public Sub FinalShutdown()
    
    #If DEBUGMODE = 1 Then
        pdDebug.LogAction "FinalShutdown() reached."
    #End If
    
    #If DEBUGMODE = 1 Then
        pdDebug.LogAction "Manually unloading all remaining public class instances..."
    #End If
    
    Set g_RecentFiles = Nothing
    Set g_RecentMacros = Nothing
    Set g_Themer = Nothing
    Set g_Displays = Nothing
    Set g_CheckerboardPattern = Nothing
    Set g_Zoom = Nothing
    Set g_WindowManager = Nothing
    
    Dim i As Long
    For i = LBound(pdImages) To UBound(pdImages)
        If (Not pdImages(i) Is Nothing) Then
            pdImages(i).FreeAllImageResources
            Set pdImages(i) = Nothing
        End If
    Next i
    
    'Report final viewport profiling data
    ViewportEngine.ReportViewportProfilingData
    
    'Free any ugly VB-specific workaround data
    #If DEBUGMODE = 1 Then
        pdDebug.LogAction "Releasing VB-specific hackarounds..."
    #End If
    
    VBHacks.ShutdownCleanup
    
    'Delete any remaining temp files in the cache
    #If DEBUGMODE = 1 Then
        pdDebug.LogAction "Clearing temp file cache..."
    #End If
    
    Files.DeleteTempFiles
    
    'Release each potentially active plugin in turn
    PluginManager.TerminateAllPlugins
    
    'Release any active drawing backends
    Drawing.ReleaseUIPensAndBrushes
    Set g_CheckerboardPattern = Nothing
    Set g_CheckerboardBrush = Nothing
    If Drawing2D.StopRenderingEngine(P2_DefaultBackend) Then
        #If DEBUGMODE = 1 Then
            pdDebug.LogAction "GDI+ released"
        #End If
    End If
    
    'NOTE: in the future, any final user-preference actions could be handled here, as g_UserPreferences is still alive.
    Set g_UserPreferences = Nothing
    
    #If DEBUGMODE = 1 Then
        pdDebug.LogAction "Everything we can physically unload has been forcibly unloaded.  Releasing final library reference..."
    #End If
    
    'If the shell32 library was loaded successfully, once FormMain is closed, we need to unload the library handle.
    If (m_hShellModule <> 0) Then FreeLibrary m_hShellModule
    
    #If DEBUGMODE = 1 Then
        pdDebug.LogAction "All human-written code complete.  Shutting down pdDebug and exiting gracefully."
        pdDebug.LogAction "Final memory report", PDM_Mem_Report
        pdDebug.TerminateDebugger
        Set pdDebug = Nothing
    #End If
    
    m_IsProgramRunning = False
    
    'We have now terminated everything we can physically terminate.
    
    'Suppress any crashes caused by VB herself (which may be possible due to a variety of issues outside our control),
    ' then let the program go...
    SetErrorMode SEM_NOGPFAULTERRORBOX
    
End Sub

'Returns TRUE if Main() has been invoked
Public Function IsProgramRunning() As Boolean
    IsProgramRunning = m_IsProgramRunning
End Function

'Returns TRUE if PD's startup routines all triggered successfully.
Public Function WasStartupSuccessful() As Boolean
    WasStartupSuccessful = m_ProgramStartupSuccessful
End Function
