Attribute VB_Name = "TextSupport"
'***************************************************************************
'Miscellaneous functions related to specialized text handling
'Copyright 2000-2017 by Tanner Helland
'Created: 6/12/01
'Last updated: 08/August/17
'Last update: remove legacy BuildParams() parameter system
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'Validate a given text box entry.
Public Sub TextValidate(ByRef srcTextBox As TextBox, Optional ByVal negAllowed As Boolean = False, Optional ByVal floatAllowed As Boolean = False)

    'Convert the input number to a string
    Dim numString As String
    numString = srcTextBox.Text
    
    'Remove any incidental white space before processing
    numString = Trim(numString)
    
    'Create a string of valid numerical characters, based on the input specifications
    Dim validChars As String
    validChars = "0123456789"
    If negAllowed Then validChars = validChars & "-"
    If floatAllowed Then validChars = validChars & "."
    
    'Make note of the cursor position so we can restore it after removing invalid text
    Dim cursorPos As Long
    cursorPos = srcTextBox.SelStart
    
    'Loop through the text box contents and remove any invalid characters
    Dim i As Long
    Dim invLoc As Long
    
    For i = 1 To Len(numString)
        
        'Compare a single character from the text box against our list of valid characters
        invLoc = InStr(validChars, Mid$(numString, i, 1))
        
        'If this character was NOT found in the list of valid characters, remove it from the string
        If invLoc = 0 Then
        
            numString = Left$(numString, i - 1) & Right$(numString, Len(numString) - i)
            
            'Modify the position of the cursor to match (so the text box maintains the same cursor position)
            If i >= (cursorPos - 1) Then cursorPos = cursorPos - 1
            
            'Move the loop variable back by 1 so the next character is properly checked
            i = i - 1
            
        End If
            
    Next i
        
    'Place the newly validated string back in the text box
    srcTextBox.Text = numString
    srcTextBox.Refresh
    srcTextBox.SelStart = cursorPos

End Sub

'Check a Long-type value to see if it falls within a given range
Public Function RangeValid(ByVal checkVal As Variant, ByVal cMin As Double, ByVal cMax As Double) As Boolean
    If (checkVal >= cMin) And (checkVal <= cMax) Then
        RangeValid = True
    Else
        PDMsgBox "%1 is not a valid entry." & vbCrLf & "Please enter a value between %2 and %3.", vbExclamation Or vbOKOnly, "Invalid entry", checkVal, cMin, cMax
        RangeValid = False
    End If
End Function

'Check a Variant-type value to see if it's numeric
Public Function NumberValid(ByVal checkVal As Variant) As Boolean
    If (Not IsNumeric(checkVal)) Then
        PDMsgBox "%1 is not a valid entry." & vbCrLf & "Please enter a numeric value.", vbExclamation Or vbOKOnly, "Invalid entry", checkVal
        NumberValid = False
    Else
        NumberValid = True
    End If
End Function

'A pleasant combination of RangeValid and NumberValid
Public Function EntryValid(ByVal checkVal As Variant, ByVal cMin As Double, ByVal cMax As Double, Optional ByVal displayNumError As Boolean = True, Optional ByVal displayRangeError As Boolean = True) As Boolean
    If Not IsNumeric(checkVal) Then
        If displayNumError Then PDMsgBox "%1 is not a valid entry." & vbCrLf & "Please enter a numeric value.", vbExclamation Or vbOKOnly, "Invalid entry", checkVal
        EntryValid = False
    Else
        If (checkVal >= cMin) And (checkVal <= cMax) Then
            EntryValid = True
        Else
            If displayRangeError Then PDMsgBox "%1 is not a valid entry." & vbCrLf & "Please enter a value between %2 and %3.", vbExclamation Or vbOKOnly, "Invalid entry", checkVal, cMin, cMax
            EntryValid = False
        End If
    End If
End Function

'A custom CDbl function that accepts both commas and decimals as a separator
Public Function CDblCustom(ByVal srcString As String) As Double

    'Replace commas with periods
    If (InStr(1, srcString, ",", vbBinaryCompare) > 0) Then srcString = Replace$(srcString, ",", ".", , , vbBinaryCompare)
    
    'We can now use Val() to convert to Double
    If IsNumberLocaleUnaware(srcString) Then
        CDblCustom = Val(srcString)
    Else
        CDblCustom = 0#
    End If

End Function

'Locale-unaware check for strings that can successfully be converted to numbers.  Thank you to
' http://stackoverflow.com/questions/18368680/vb6-isnumeric-behaviour-in-windows-8-windows-2012
' for the code.  (Note that the original function listed there is buggy!  I had to add some
' fixes for exponent strings, which the original code did not handle correctly.)
Public Function IsNumberLocaleUnaware(ByRef Expression As String) As Boolean
    
    Dim Negative As Boolean
    Dim Number As Boolean
    Dim Period As Boolean
    Dim Positive As Boolean
    Dim Exponent As Boolean
    Dim x As Long
    For x = 1& To Len(Expression)
        Select Case Mid$(Expression, x, 1&)
        Case "0" To "9"
            Number = True
        Case "-"
            If Period Or Number Or Negative Or Positive Then Exit Function
            Negative = True
        Case "."
            If Period Or Exponent Then Exit Function
            Period = True
        Case "E", "e"
            If Not Number Then Exit Function
            If Exponent Then Exit Function
            Exponent = True
            Number = False
            Negative = False
            Period = False
        Case "+"
            If Not Exponent Then Exit Function
            If Number Or Negative Or Positive Then Exit Function
            Positive = True
        Case " ", vbTab, vbVerticalTab, vbCr, vbLf, vbFormFeed
            If Period Or Number Or Exponent Or Negative Then Exit Function
        Case Else
            Exit Function
        End Select
    Next x
        
    IsNumberLocaleUnaware = Number
    
End Function

'For a given string, see if it has a trailing number value in parentheses (e.g. "Image (2)").  If it does have a
' trailing number, return the string with the number incremented by one.  If there is no trailing number, apply one.
Public Function IncrementTrailingNumber(ByVal srcString As String) As String

    'Start by figuring out if the string is already in the format: "text (#)"
    srcString = Trim$(srcString)
    
    Dim numToAppend As Long
    
    'Check the trailing character.  If it is a closing parentheses ")", we need to analyze more
    If Strings.StringsEqual(Right$(srcString, 1), ")", False) Then
    
        Dim i As Long
        For i = Len(srcString) - 2 To 1 Step -1
            
            'If this char isn't a number, see if it's an initial parentheses: "("
            If Not (IsNumeric(Mid$(srcString, i, 1))) Then
                
                'If it is a parentheses, then this string already has a "(#)" appended to it.  Figure out what
                ' the number inside the parentheses is, and strip that entire block from the string.
                If Strings.StringsEqual(Mid$(srcString, i, 1), "(", False) Then
                
                    numToAppend = CLng(Mid$(srcString, i + 1, Len(srcString) - i - 1))
                    srcString = Left$(srcString, i - 2)
                    Exit For
                
                'If this character is non-numeric and NOT an initial parentheses, this string does not already have a
                ' number appended (in the expected format). Treat it like any other string and append " (2)" to it
                Else
                    numToAppend = 2
                    Exit For
                End If
                
            End If
        
        'If this character IS a number, keep scanning.
        Next i
    
    'If the string is not already in the format "text (#)", append a " (2)" to it
    Else
        numToAppend = 2
    End If
    
    IncrementTrailingNumber = srcString & " (" & CStr(numToAppend) & ")"

End Function

'As of PD 7.0, XML strings are universally used for parameter parsing.  The old pipe-delimited system is currently being
' replaced in favor of this lovely little helper function.
Public Function BuildParamList(ParamArray allParams() As Variant) As String
    
    'pdParamXML handles all the messy work for us
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    
    On Error GoTo BuildParamListFailure
    
    If UBound(allParams) >= LBound(allParams) Then
    
        Dim tmpName As String, tmpValue As Variant
        
        Dim i As Long
        For i = LBound(allParams) To UBound(allParams) Step 2
            
            'Parameters must be passed in a strict name/value order.  An odd number of parameters will cause crashes.
            tmpName = allParams(i)
            
            If (i + 1) <= UBound(allParams) Then
                tmpValue = allParams(i + 1)
            Else
                Err.Raise 9
            End If
            
            'Add this key/value pair to the current running param string
            cParams.AddParam tmpName, tmpValue
            
        Next i
    
    End If
    
    BuildParamList = cParams.GetParamString
    
    Exit Function
    
BuildParamListFailure:
        
    #If DEBUGMODE = 1 Then
        pdDebug.LogAction "WARNING!  buildParamList failed to create a parameter string!"
    #End If
    
    BuildParamList = ""
    
End Function

'Given two strings - a test candidate string, and a string comprised only of valid characters - return TRUE if the
' test string is comprised only of characters from the valid character list.
Public Function ValidateCharacters(ByVal srcText As String, ByVal listOfValidChars As String, Optional ByVal compareCaseInsensitive As Boolean = True) As Boolean
    
    ValidateCharacters = True
    
    'For case-insensitive comparisons, lcase both strings in advance
    If compareCaseInsensitive Then
        srcText = LCase$(srcText)
        listOfValidChars = LCase$(listOfValidChars)
    End If
    
    'I'm not sure if there's a better way to do this, but basically, we need to individually check each character
    ' in the string against the valid char list.  If a character is NOT located in the valid char list, return FALSE,
    ' and if the whole string checks out, return TRUE.
    Dim i As Long
    For i = 1 To Len(srcText)
        
        'If this invalid character exists in the target string, replace it with whatever the user specified
        If (InStr(1, listOfValidChars, Mid$(srcText, i, 1), vbBinaryCompare) = 0) Then
            ValidateCharacters = False
            Exit For
        End If
        
    Next i
    
End Function
