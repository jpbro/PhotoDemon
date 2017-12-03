Attribute VB_Name = "Public_Variables"

'Contains any and all publicly-declared variables.  I am trying to move
' all public variables here (for obvious reasons), but the transition may
' not be completely done as long as this comment remains!

Option Explicit


'The number of images PhotoDemon has loaded this session (always goes up, never down; starts at zero when the program is loaded).
' This value correlates to the upper bound of the primary pdImages array.  For performance reasons, that array is not dynamically
' resized when images are loaded - the array stays the same size, and entries are deactivated as needed.  Thus, WHENEVER YOU
' NEED TO ITERATE THROUGH ALL LOADED IMAGES, USE THIS VALUE INSTEAD OF g_OpenImageCount.
Public g_NumOfImagesLoaded As Long

'The ID number (e.g. index in the pdImages array) of image the user is currently interacting with (e.g. the currently active image
' window).  Whenever a function needs to access the current image, use pdImages(g_CurrentImage).
Public g_CurrentImage As Long

'Number of image windows CURRENTLY OPEN.  This value goes up and down as images are opened or closed.  Use it to test for no open
' images (e.g. If g_OpenImageCount = 0...).  Note that this value SHOULD NOT BE USED FOR ITERATING OPEN IMAGES.  Instead, use
' g_NumOfImagesLoaded, which will always match the upper bound of the pdImages() array, and never decrements, even when images
' are unloaded.
Public g_OpenImageCount As Long

'This array is the heart and soul of a given PD session.  Every time an image is loaded, all of its relevant data is stored within
' a new entry in this array.
Public pdImages() As pdImage

'Main user preferences and settings handler
Public g_UserPreferences As pdPreferences

'Main resource handler
Public g_Resources As pdResources

'Main file format compatibility handler
Public g_ImageFormats As pdFormats

'Main language and translation handler
Public g_Language As pdTranslate

'Main clipboard handler
Public g_Clipboard As pdClipboardMain

'Currently selected tool, previous tool
Public g_CurrentTool As PDTools
Public g_PreviousTool As PDTools

'Primary zoom handler for the program
Public g_Zoom As pdZoom

'Does the user want us to prompt them when they try to close unsaved images?
Public g_ConfirmClosingUnsaved As Boolean

'For the Open and Save common dialog boxes, it's polite to remember what format the user used last, then default
' the boxes to that.  (Note that these values are stored in the preferences file as well, but that is only accessed
' upon program load and unload.)
Public g_LastOpenFilter As Long
Public g_LastSaveFilter As Long

'DIB that contains a 2x2 pattern of the alpha checkerboard.  Use it with CreatePatternBrush to paint the alpha
' checkerboard prior to rendering.
Public g_CheckerboardPattern As pdDIB

'Copy of g_CheckerboardPattern, above, but in pd2DBrush format.  The brush is pre-built as a GDI+ texture brush,
' which makes it preferable for painting on 32-bpp surfaces.
Public g_CheckerboardBrush As pd2DBrush

'Is theming enabled?  (Used to handle some menu icon rendering quirks)
Public g_IsThemingEnabled As Boolean

'Render the interface using Segoe UI if available; g_InterfaceFont will be set to something else (most likely Tahoma)
' if Segoe UI doesn't exist on this system.
Public g_InterfaceFont As String

'This g_Displays object contains data on all display devices on this system.  It includes a ton of code to assist the program
' with managing multiple monitors and other display-related issues.
Public g_Displays As pdDisplays

'If the user attempts to close the program while multiple unsaved images are present, these values allow us to count
' a) how many unsaved images are present
' b) if the user wants to deal with all the images (if the "Repeat this action..." box is checked on the unsaved
'     image confirmation prompt) in the same fashion
' c) what the user's preference is for dealing with all the unsaved images
Public g_NumOfUnsavedImages As Long
Public g_DealWithAllUnsavedImages As Boolean
Public g_HowToDealWithAllUnsavedImages As VbMsgBoxResult

'When the entire program is being shut down, this variable is set
Public g_ProgramShuttingDown As Boolean

'The user is attempting to close all images (necessary for handling the "repeat for all images" check box)
Public g_ClosingAllImages As Boolean

'If this is the first time the user has run PhotoDemon (as determined by the lack of a preferences XML file), this
' variable will be set to TRUE early in the load process.  Other routines can then modify their behavior accordingly.
Public g_IsFirstRun As Boolean

'Drag and drop operations are allowed at certain times, but not others.  Any time a modal form is displayed, drag-and-drop
' must be disallowed - with the exception of common dialog boxes.  To make sure this behavior is carefully maintained,
' we track drag-and-drop enabling ourselves
Public g_AllowDragAndDrop As Boolean

'This window manager handles positioning, layering, and sizing of the main canvas and all toolbars
Public g_WindowManager As pdWindowManager

'UI theme engine.
Public g_Themer As pdTheme

'"File > Open Recent" and "Tools > Recent Macros" dynamic menu managers
Public g_RecentFiles As pdRecentFiles
Public g_RecentMacros As pdMRUManager

'Mouse accuracy for collision detection with on-screen objects.  This is typically 6 pixels, but it's re-calculated
' at run-time to account for high-DPI screens.  (It may even be worthwhile to let users adjust this value, or to
' retrieve some system metric for it... if such a thing exists.)
Public g_MouseAccuracy As Double

'If a double-click action closes a window (e.g. double-clicking a file from a common dialog), Windows incorrectly
' forwards the second click to the window behind the closed dialog.  To avoid this "click-through" behavior,
' this variable can be set to TRUE, which will prevent the underlying canvas from accepting input.  Just make sure
' to restore this variable to FALSE when you're done, including catching any error states!
Public g_DisableUserInput As Boolean

'As of v6.4, PhotoDemon supports a number of performance-related preferences.  Because performance settings (obviously)
' affect performance-sensitive parts of the program, these preferences are cached to global variables (rather than
' constantly pulled on-demand from file, which is unacceptably slow for performance-sensitive pipelines).
Public g_ViewportPerformance As PD_PerformanceSetting
Public g_InterfacePerformance As PD_PerformanceSetting

'As of v6.4, PhotoDemon allows the user to specify compression settings for Undo/Redo data.  By default, Undo/Redo data is
' uncompressed, which takes up a lot of (cheap) disk space but provides excellent performance.  The user can modify this
' setting to their liking, but they'll have to live with the performance implications.  The default setting for this value
' is 0, for no compression.
Public g_UndoCompressionLevel As Long

'Set this value to TRUE if you want PhotoDemon to report time-to-completion for various program actions.
' NOTE: this value is currently set automatically, in the LoadTheProgram sub.  PRE-ALPHA and ALPHA builds will report
'       timing for a variety of actions; BETA and PRODUCTION builds will not.  This can be overridden by changing the
'       activation code in LoadTheProgram.
Public g_DisplayTimingReports As Boolean

'PhotoDemon's central debugger.  This class is accessed by pre-alpha, alpha, and beta builds, and it is used to log
' generic debug messages on client PCs, which we can (hopefully) use to recreate crashes as necessary.
Public pdDebug As pdDebugger

'If FreeImage throws an error, the error string(s) will be stored here.  Make sure to clear it after reading to prevent future
' functions from mistakenly displaying the same message!
Public g_FreeImageErrorMessages() As String

'As part of an improved memory efficiency initiative, some global variables are used (during debug mode) to track how many
' GDI objects PD creates and destroys.
Public g_DIBsCreated As Long
Public g_DIBsDestroyed As Long
Public g_FontsCreated As Long
Public g_FontsDestroyed As Long
Public g_DCsCreated As Long
Public g_DCsDestroyed As Long

'If a modal window is active, this value will be set to TRUE.  This is helpful for controlling certain program flow issues.
Public g_ModalDialogActive As Boolean

'If an update notification is ready, but we can't display it (for example, because a modal dialog is active) this flag will
' be set to TRUE.  PD's central processor uses this to display the update notification as soon as it reasonably can.
Public g_ShowUpdateNotification As Boolean

'If an update has been successfully applied, the user is given the option to restart PD immediately.  If the user chooses
' to restart, this global value will be set to TRUE.
Public g_UserWantsRestart As Boolean

'If this PhotoDemon session was started by a restart (because an update patch was applied), this will be set to TRUE.
' PD uses this value to suspend any other automatic updates, as a precaution against any bugs in the updater.
Public g_ProgramStartedViaRestart As Boolean

'Asynchronous tasks may require a modal wait screen.  To unload them successfully, we use a global flag that other
' asynchronous methods (like timers) can trigger.
Public g_UnloadWaitWindow As Boolean
