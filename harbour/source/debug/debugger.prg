/*
 * $Id$
 */

/*
 * Harbour Project source code:
 * The Debugger
 *
 * Copyright 1999 Antonio Linares <alinares@fivetechsoft.com>
 * www - http://www.harbour-project.org
 *
 * Copyright 2003-2006 Phil Krylov <phil@newstar.rinet.ru>
 * www - http://www.xharbour.org
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version, with one exception:
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this software; see the file COPYING.  If not, write to
 * the Free Software Foundation, Inc., 59 Temple Place, Suite 330,
 * Boston, MA 02111-1307 USA (or visit the web site http://www.gnu.org/).
 *
 * As a special exception, the Harbour Project gives permission for
 * additional uses of the text contained in its release of Harbour.
 *
 * The exception is that, if you link the Harbour libraries with other
 * files to produce an executable, this does not by itself cause the
 * resulting executable to be covered by the GNU General Public License.
 * Your use of that executable is in no way restricted on account of
 * linking the Harbour library code into it.
 *
 * This exception does not however invalidate any other reasons why
 * the executable file might be covered by the GNU General Public License.
 *
 * This exception applies only to the code released by the Harbour
 * Project under the name Harbour.  If you copy code from other
 * Harbour Project or Free Software Foundation releases into a copy of
 * Harbour, as the General Public License permits, the exception does
 * not apply to the code that you add in this way.  To avoid misleading
 * anyone as to the status of such modified files, you must delete
 * this exception notice from them.
 *
 * If you write modifications of your own for Harbour, it is your choice
 * whether to permit this exception to apply to your modifications.
 * If you do not wish that, delete this exception notice.
 *
 */

/* NOTE: Don't use SAY/DevOut()/DevPos() for screen output, otherwise
         the debugger output may interfere with the applications output
         redirection, and is also slower. [vszakats] */

#include "hbclass.ch"
#include "hbdebug.ch"   // for "nMode" of __dbgEntry
#include "hbgtinfo.ch"
#include "hbmemvar.ch"

#include "box.ch"
#include "common.ch"
#include "getexit.ch"
#include "inkey.ch"
#include "set.ch"
#include "setcurs.ch"

/* A macro to compare filenames on different platforms. */
#if defined(__PLATFORM__DOS) || defined(__PLATFORM__OS2) || defined(__PLATFORM__WINDOWS)
   #define FILENAME_EQUAL( s1, s2 ) ( Lower( s1 ) == Lower( s2 ) )
#else
   #define FILENAME_EQUAL( s1, s2 ) ( s1 == s2 )
#endif


/* Information structure stored in DATA aCallStack */
#define CSTACK_MODULE           1  // module name (.prg file)
#define CSTACK_FUNCTION         2  // function name
#define CSTACK_LINE             3  // start line
#define CSTACK_LEVEL            4  // eval stack level of the function
#define CSTACK_LOCALS           5  // an array with local variables
#define CSTACK_STATICS          6  // an array with static variables

/* Information structure stored in aCallStack[ n ][ CSTACK_LOCALS ]
   { cLocalName, nLocalIndex, "Local", ProcName( 1 ), nLevel } */
#define VAR_NAME                1
#define VAR_POS                 2
#define VAR_TYPE                3
#define VAR_LEVEL               4  // eval stack level of the function

/* Information structure stored in ::aWatch (watchpoints) */
#define WP_TYPE                 1  // wp = watchpoint, tr = tracepoint
#define WP_EXPR                 2  // source of an expression

/* Information structure stored in ::aModules */
#define MODULE_NAME             1
#define MODULE_STATICS          2
#define MODULE_GLOBALS          3
#define MODULE_EXTERNGLOBALS    4

/* The dimensions of the debugger window */
#define DEBUGGER_MINROW         0
#define DEBUGGER_MINCOL         0
#define DEBUGGER_MAXROW         22
#define DEBUGGER_MAXCOL         77

STATIC s_oDebugger

PROCEDURE __dbgAltDEntry()

   /* do not activate the debugger imediatelly because the module
      where ALTD() was called can have no debugger info - stop
      on first LINE with debugged info
    */
   hb_DBG_INVOKEDEBUG( Set( _SET_DEBUG ) )

   RETURN

/* debugger entry point */
PROCEDURE __dbgEntry( nMode, uParam1, uParam2, uParam3, uParam4, uParam5 )

   LOCAL lStartup

   DO CASE
   CASE nMode == HB_DBG_GETENTRY

      hb_DBG_SetEntry()

   CASE nMode == HB_DBG_ACTIVATE

      IF ( lStartup := ( s_oDebugger == NIL ) )
         s_oDebugger := HBDebugger():New()
         s_oDebugger:pInfo := uParam1
      ENDIF
      s_oDebugger:nProcLevel := uParam2
      s_oDebugger:aCallStack := uParam3
      s_oDebugger:aModules := uParam4
      s_oDebugger:aBreakPoints := uParam5
      IF lStartup
         IF s_oDebugger:lRunAtStartup
            hb_DBG_SetGo( uParam1 )
            RETURN
         ENDIF
      ENDIF
      s_oDebugger:lGo := .F.
      s_oDebugger:Activate()

   ENDCASE

   RETURN

CREATE CLASS HBDebugger

   VAR pInfo
   VAR aWindows          INIT {}
   VAR nCurrentWindow    INIT 1
   VAR oPullDown

   VAR oWndCode
   VAR oWndCommand
   VAR oWndStack
   VAR oWndVars

   VAR oBar
   VAR oBrwText
   VAR cPrgName
   VAR oBrwStack
   VAR oBrwVars
   VAR aVars             INIT {}

   VAR nAppDispCount
   VAR nAppLastKey
   VAR bAppInkeyAfter
   VAR bAppInkeyBefore
   VAR bAppClassScope

   VAR nAppDirCase
   VAR nAppFileCase
   VAR oAppGetList
   VAR nAppTypeAhead

   VAR nMaxRow
   VAR nMaxCol

   VAR hUserWindow
   VAR hDebuggerWindow
   VAR lDebuggerWindowIsOpen INIT .F.

   VAR aBreakPoints      INIT {}
   VAR aCallStack        INIT {}    // stack of procedures with debug info
   VAR aProcStack        INIT {}    // stack of all procedures
   VAR nProcLevel                   // procedure level where the debugger is currently
   VAR aModules          INIT {}    // array of modules with static and GLOBAL variables
   VAR aWatch            INIT {}
   VAR aColors           INIT { "W+/BG", "N/BG", "R/BG", "N+/BG", "W+/B", "GR+/B", "W/B", "N/W", "R/W", "N/BG", "R/BG" }

   VAR aLastCommands
   VAR nCommand
   VAR oGetListCommand

   VAR lAnimate          INIT .F.
   VAR lEnd              INIT .F.
   VAR lCaseSensitive    INIT .F.
   VAR lMonoDisplay      INIT .F.
   VAR lSortVars         INIT .F.

   VAR cSearchString     INIT ""
   VAR cPathForFiles
   VAR cSettingsFileName INIT "init.cld"
   VAR aPathDirs

   VAR nTabWidth         INIT 4
   VAR nSpeed            INIT 0

   VAR lShowPublics      INIT .F.
   VAR lShowPrivates     INIT .F.
   VAR lShowStatics      INIT .F.
   VAR lShowLocals       INIT .F.
   VAR lShowGlobals      INIT .F.
   VAR lShowAllGlobals   INIT .F.
   VAR lAll              INIT .F.
   VAR lShowCallStack    INIT .F.
   VAR lGo                          // stores if GO was requested
   VAR lActive           INIT .F.
   VAR lCBTrace          INIT .T.   // stores if codeblock tracing is allowed
   VAR oBrwPnt
   VAR oWndPnt
   VAR lPPO              INIT .F.
   VAR lRunAtStartup     INIT .T.   // Clipper compatible
   VAR lLineNumbers      INIT .T.

   METHOD New()
   METHOD Activate()

   METHOD All()

   METHOD Animate() INLINE iif( ::lAnimate, ::Step(), NIL )

   METHOD BarDisplay()
   METHOD BuildCommandWindow()
   METHOD BuildBrowseStack()

   METHOD CallStackProcessKey( nKey )
   METHOD ClrModal() INLINE iif( ::lMonoDisplay, "N/W, W+/W, W/N, W+/N",;
                                "N/W, R/W, N/BG, R/BG" )

   METHOD CodeblockTrace()
   METHOD CodeWindowProcessKey( nKey )
   METHOD Colors()
   METHOD CommandWindowProcessKey( nKey )
   METHOD DoCommand( cCommand )
   METHOD DoScript( cFileName )
   METHOD EditColor( nColor, oBrwColors )
   METHOD EditSet( nSet, oBrwSets )
   METHOD EditVar( nVar )
   METHOD Exit() INLINE ::lEnd := .T.
   METHOD FindNext()
   METHOD FindPrevious()
   METHOD GetExprValue( xExpr, lValid )
   METHOD GetSourceFiles()

   METHOD Global()

   METHOD Go()
   METHOD GoToLine( nLine )
   METHOD HandleEvent()
   METHOD Hide()
   METHOD HideCallStack()
   METHOD HideVars()
   METHOD InputBox( cMsg, uValue, bValid, lEditable )
   METHOD Inspect( uValue, cValueName )
   METHOD IsValidStopLine( cName, nLine )
   METHOD ListBox( cCaption, aItems )
   METHOD LoadColors()
   METHOD LoadSettings()
   METHOD LoadVars()
   METHOD LoadCallStack()

   METHOD Local()

   METHOD Locate( nMode, cValue )

   METHOD MonoDisplay()
   METHOD NextWindow()
   METHOD Open()
   METHOD OpenPPO()
   METHOD Resume() INLINE ::ShowCodeLine( 1 )
   METHOD OSShell()
   METHOD PathForFiles( cPathForFiles )

   METHOD PrevWindow()
   METHOD Private()
   METHOD Public()
   METHOD Quit()
   METHOD RefreshVars()
   METHOD RestoreAppScreen()
   METHOD RestoreAppState()
   METHOD RestoreSettings()
   METHOD RunAtStartup() INLINE ::lRunAtStartup := ::oPullDown:GetItemByIdent( "ALTD" ):checked := !::lRunAtStartup
   METHOD SaveAppScreen()
   METHOD SaveAppState()
   METHOD SaveSettings()
   METHOD Show()
   METHOD ShowAllGlobals()
   METHOD ShowAppScreen()
   METHOD ShowCallStack()
   METHOD ShowCodeLine( nProc )
   METHOD ShowHelp( nTopic )
   METHOD ShowVars()
   METHOD RedisplayBreakpoints()
   METHOD LocatePrgPath( cPrgName )
   METHOD Sort() INLINE ASort( ::aVars,,, { | x, y | x[ 1 ] < y[ 1 ] } ),;
                        ::lSortVars := .T.,;
                        iif( ::oBrwVars != NIL, ::oBrwVars:RefreshAll(), NIL ),;
                        iif( ::oWndVars != NIL .AND. ::oWndVars:lVisible, iif( !::lGo, ::oBrwVars:ForceStable(), NIL ), NIL )

   METHOD Speed() INLINE ::nSpeed := ::InputBox( "Step delay (in tenths of a second)", ::nSpeed )

   METHOD Stack()
   METHOD Static()

   METHOD Step()

   METHOD TabWidth() INLINE ;
          ::nTabWidth := ::InputBox( "Tab width", ::nTabWidth ),;
          ::oBrwText:nTabWidth := ::nTabWidth, ::oBrwText:RefreshAll()

   METHOD ToggleBreakPoint()

   METHOD Trace()

   METHOD ToCursor()
   METHOD NextRoutine()
   METHOD ViewSets()
   METHOD WndVarsLButtonDown( nMRow, nMCol )
   METHOD LineNumbers( lLineNumbers ) // Toggles numbering of source code lines
   METHOD RemoveWindow()
   METHOD SearchLine()
   METHOD ToggleAnimate() INLINE ::oPullDown:GetItemByIdent( "ANIMATE" ):checked := ::lAnimate := ! ::lAnimate
   METHOD ToggleCaseSensitive() INLINE ::oPullDown:GetItemByIdent( "CASE" ):checked := ::lCaseSensitive := ! ::lCaseSensitive
   METHOD ShowWorkAreas() INLINE __dbgShowWorkAreas( Self )

   METHOD TracepointAdd( cExpr )
   METHOD WatchpointAdd( cExpr )
   METHOD WatchpointDel( nPos )
   METHOD WatchpointsShow()
   METHOD WatchpointsHide()
   METHOD WatchpointEdit( nVar )
   METHOD WatchpointInspect( nPos )
   METHOD WatchGetInfo( nWatch )

   METHOD VarGetInfo( aVar )
   METHOD VarGetValue( aVar )
   METHOD VarSetValue( aVar, uValue )

   METHOD ResizeWindows( oWindow )
   METHOD NotSupported() INLINE Alert( "Not implemented yet!" )

   METHOD OpenDebuggerWindow()
   METHOD CloseDebuggerWindow()

ENDCLASS


METHOD New() CLASS HBDebugger

   s_oDebugger := Self

   /* default the search path for files to the current directory
      that way if the source is in the same directory it will still be found even if the application
      changes the current directory with the SET DEFAULT command. */
   ::cPathForFiles := GetEnv( "HB_DBG_PATH" )
   IF Empty( ::cPathForFiles )
      ::cPathForFiles := GetEnv( "PATH" )
   ENDIF
   ::aPathDirs := PathToArray( ::cPathForFiles )

   ::lGo := ::lRunAtStartup

   /* Store the initial screen dimensions for now */
   ::nMaxRow := MaxRow()
   ::nMaxCol := MaxCol()

   ::oPullDown := __dbgBuildMenu( Self )

   ::oWndCode             := HBDbWindow():New( 1, 0, ::nMaxRow - 6, ::nMaxCol )
   ::oWndCode:Cargo       := { ::oWndCode:nTop, ::oWndCode:nLeft }
   ::oWndCode:bKeyPressed := { | nKey | ::CodeWindowProcessKey( nKey ) }
   ::oWndCode:bGotFocus   := { || ::oGetListCommand:SetFocus(), SetCursor( SC_SPECIAL1 ), ;
                                  SetPos( ::oWndCode:Cargo[ 1 ],::oWndCode:Cargo[ 2 ] ) }
   ::oWndCode:bLostFocus  := { || ::oWndCode:Cargo[ 1 ] := Row(), ::oWndCode:Cargo[ 2 ] := Col(), ;
                                  SetCursor( SC_NONE ) }

   AAdd( ::aWindows, ::oWndCode )

   ::BuildCommandWindow()
   ::BuildBrowseStack()

   IF File( ::cSettingsFileName )
      ::LoadSettings()
      ::lGo := ::lRunAtStartup // Once again after settings file is loaded
   ENDIF

   RETURN Self

METHOD OpenDebuggerWindow() CLASS HBDebugger

   IF !::lDebuggerWindowIsOpen
      ::hUserWindow := hb_gtInfo( GTI_GETWIN )
      IF ::hDebuggerWindow == NIL
         ::hDebuggerWindow := hb_gtInfo( GTI_GETWIN, ;
                                 { "Debugger", DEBUGGER_MINROW, DEBUGGER_MINCOL, ;
                                   DEBUGGER_MAXROW, DEBUGGER_MAXCOL } )
      ELSE
         hb_gtInfo( GTI_SETWIN, ::hDebuggerWindow )
      ENDIF
      ::lDebuggerWindowIsOpen := .T.
   ENDIF

   RETURN NIL


METHOD CloseDebuggerWindow() CLASS HBDebugger

   IF ::lDebuggerWindowIsOpen
      ::hDebuggerWindow := hb_gtInfo( GTI_GETWIN )
      hb_gtInfo( GTI_SETWIN, ::hUserWindow )
      ::lDebuggerWindowIsOpen := .F.
   ENDIF

   RETURN NIL


METHOD Activate() CLASS HBDebugger

   ::LoadCallStack()
   ::SaveAppState()

   IF ! ::lActive
      ::lActive := .T.
      ::Show()
      IF ::lShowCallStack
         ::ShowCallStack()
      ENDIF
   ELSE
      ::SaveAppScreen()
   ENDIF

   ::LoadVars()
   ::ShowVars()

   IF ::oWndPnt != NIL
      ::WatchpointsShow()
   ENDIF

   // show the topmost procedure
   ::ShowCodeLine( 1 ) // ::aCallStack[ 1 ][ CSTACK_LINE ], ::aCallStack[ 1 ][ CSTACK_MODULE ] )
   ::HandleEvent()

   RETURN NIL


METHOD All() CLASS HBDebugger

   ::lShowPublics := ::lShowPrivates := ::lShowStatics := ;
   ::lShowLocals := ::lShowGlobals := ::lAll := ! ::lAll

   ::RefreshVars()

   RETURN NIL

METHOD BarDisplay() CLASS HBDebugger

   LOCAL cClrItem   := __DbgColors()[ 8 ]
   LOCAL cClrHotKey := __DbgColors()[ 9 ]

   DispBegin()

   SetColor( cClrItem )

   @ ::nMaxRow, 0 CLEAR TO ::nMaxRow, ::nMaxCol

   DispOutAt( ::nMaxRow,  0, "F1-Help F2-Zoom F3-Repeat F4-User F5-Go F6-WA F7-Here F8-Step F9-BkPt F10-Trace", cClrItem )
   DispOutAt( ::nMaxRow,  0, "F1", cClrHotKey )
   DispOutAt( ::nMaxRow,  8, "F2", cClrHotKey )
   DispOutAt( ::nMaxRow, 16, "F3", cClrHotKey )
   DispOutAt( ::nMaxRow, 26, "F4", cClrHotKey )
   DispOutAt( ::nMaxRow, 34, "F5", cClrHotKey )
   DispOutAt( ::nMaxRow, 40, "F6", cClrHotKey )
   DispOutAt( ::nMaxRow, 46, "F7", cClrHotKey )
   DispOutAt( ::nMaxRow, 54, "F8", cClrHotKey )
   DispOutAt( ::nMaxRow, 62, "F9", cClrHotKey )
   DispOutAt( ::nMaxRow, 70, "F10", cClrHotKey )

   DispEnd()

   RETURN NIL


METHOD BuildBrowseStack() CLASS HBDebugger

   IF ::oBrwStack == NIL
      ::oBrwStack := HBDbBrowser():New( 2, ::nMaxCol - 14, ::nMaxRow - 7, ::nMaxCol - 1 )
      ::oBrwStack:ColorSpec := ::aColors[ 3 ] + "," + ::aColors[ 4 ] + "," + ::aColors[ 5 ]
      ::oBrwStack:goTopBlock := { || ::oBrwStack:Cargo := 1 }
      ::oBrwStack:goBottomBlock := { || ::oBrwStack:Cargo := Len( ::aProcStack ) }
      ::oBrwStack:skipBlock := { | nSkip, nOld | nOld := ::oBrwStack:Cargo,;
                              ::oBrwStack:Cargo += nSkip,;
                              ::oBrwStack:Cargo := Min( Max( ::oBrwStack:Cargo, 1 ),;
                              Len( ::aProcStack ) ), ::oBrwStack:Cargo - nOld }

      ::oBrwStack:Cargo := 1 // Actual highligthed row

      ::oBrwStack:AddColumn( TBColumnNew( "", { || iif( Len( ::aProcStack ) > 0,;
            PadC( ::aProcStack[ ::oBrwStack:Cargo ][ CSTACK_FUNCTION ], 14 ), Space( 14 ) ) } ) )
   ENDIF

   RETURN NIL


METHOD BuildCommandWindow() CLASS HBDebugger

   LOCAL GetList := {}
   LOCAL oGet
   LOCAL cCommand

   ::oWndCommand := HBDbWindow():New( ::nMaxRow - 5, 0, ::nMaxRow - 1, ::nMaxCol, "Command" )

   ::oWndCommand:bGotFocus   := { || ::oGetListCommand:SetFocus(), SetCursor( SC_NORMAL ) }
   ::oWndCommand:bLostFocus  := { || SetCursor( SC_NONE ) }
   ::oWndCommand:bKeyPressed := { | nKey | ::CommandWindowProcessKey( nKey ) }
   ::oWndCommand:bPainted    := { || DispOutAt( ::oWndCommand:nBottom - 1,;
                             ::oWndCommand:nLeft + 1, "> ", __DbgColors()[ 2 ] ),;
                             oGet:ColorDisp( Replicate( __DbgColors()[ 2 ] + ",", 5 ) ),;
                             hb_ClrArea( ::oWndCommand:nTop + 1, ::oWndCommand:nLeft + 1,;
                             ::oWndCommand:nBottom - 2, ::oWndCommand:nRight - 1,;
                             iif( ::lMonoDisplay, 15, hb_ColorToN( __DbgColors()[ 2 ] ) ) ) }
   AAdd( ::aWindows, ::oWndCommand )

   ::aLastCommands := { "" }
   ::nCommand := 1

   cCommand := Space( ::oWndCommand:nRight - ::oWndCommand:nLeft - 3 )
   // We don't use the GET command here to avoid the painting of the GET
   AAdd( GetList, oGet := Get():New( ::oWndCommand:nBottom - 1, ::oWndCommand:nLeft + 3,;
         { | u | iif( PCount() > 0, cCommand := u, cCommand ) }, "cCommand" ) )
   oGet:ColorSpec := Replicate( __DbgColors()[ 2 ] + ",", 5 )
   ::oGetListCommand := HBGetList():New( GetList )

   RETURN NIL


METHOD CallStackProcessKey( nKey ) CLASS HBDebugger

   LOCAL n
   LOCAL nSkip
   LOCAL lUpdate := .F.

   DO CASE
   CASE nKey == K_HOME .OR. nKey == K_CTRL_PGUP .OR. nKey == K_CTRL_HOME

      IF ::oBrwStack:Cargo > 1
         ::oBrwStack:GoTop()
         ::oBrwStack:ForceStable()
         lUpdate := .T.
      ENDIF

   CASE nKey == K_END .OR. nKey == K_CTRL_PGDN .OR. nKey == K_CTRL_END

      IF ::oBrwStack:Cargo < Len( ::aProcStack )
         ::oBrwStack:GoBottom()
         ::oBrwStack:ForceStable()
         lUpdate := .T.
      ENDIF

   CASE nKey == K_UP

      IF ::oBrwStack:Cargo > 1
         ::oBrwStack:Up()
         ::oBrwStack:ForceStable()
         lUpdate := .T.
      ENDIF

   CASE nKey == K_DOWN

      IF ::oBrwStack:Cargo < Len( ::aProcStack )
         ::oBrwStack:Down()
         ::oBrwStack:ForceStable()
         lUpdate := .T.
      ENDIF

   CASE nKey == K_PGUP

      ::oBrwStack:PageUp()
      ::oBrwStack:ForceStable()
      lUpdate := .T.

   CASE nKey == K_PGDN

      ::oBrwStack:PageDown()
      ::oBrwStack:ForceStable()
      lUpdate := .T.

   CASE nKey == K_LBUTTONDOWN

      IF ( nSkip := MRow() - ::oWndStack:nTop - ::oBrwStack:RowPos ) != 0
         IF nSkip > 0
            FOR n := 1 TO nSkip
               ::oBrwStack:Down()
               ::oBrwStack:Stabilize()
            NEXT
         ELSE
            FOR n := 1 TO nSkip + 2 STEP -1
               ::oBrwStack:Up()
               ::oBrwStack:Stabilize()
            NEXT
         ENDIF
         ::oBrwStack:ForceStable()
      ENDIF
      lUpdate := .T.

   ENDCASE

   IF lUpdate
      IF ::oWndVars != NIL .AND. ::oWndVars:lVisible
         ::LoadVars()
         ::ShowVars()
      ENDIF

      // jump to source line for a function

      /*
      IF ::aCallStack[ ::oBrwStack:Cargo ][ CSTACK_LINE ] != NIL
         ::ShowCodeLine( ::aCallStack[ ::oBrwStack:Cargo ][ CSTACK_LINE ], ::aCallStack[ ::oBrwStack:Cargo ][ CSTACK_MODULE ] )
      ELSE
         ::GotoLine( 1 )
      ENDIF
      */

      ::ShowCodeLine( ::oBrwStack:Cargo )
   ENDIF

   RETURN NIL


METHOD CodeblockTrace()

   ::oPullDown:GetItemByIdent( "CODEBLOCK" ):checked := ::lCBTrace := ! ::lCBTrace
   hb_DBG_SetCBTrace( ::pInfo, ::lCBTrace )

   RETURN NIL


METHOD CodeWindowProcessKey( nKey ) CLASS HBDebugger

   IF ::oBrwText != NIL

      DO CASE
      CASE nKey == K_HOME .OR. nKey == K_CTRL_PGUP .OR. nKey == K_CTRL_HOME

         ::oBrwText:GoTop()
         IF ::oWndCode:lFocused
            SetCursor( SC_SPECIAL1 )
         ENDIF

      CASE nKey == K_END .OR. nKey == K_CTRL_PGDN .OR. nKey == K_CTRL_END

         ::oBrwText:GoBottom()
         ::oBrwText:nCol := ::oWndCode:nLeft + 1
         ::oBrwText:nFirstCol := ::oWndCode:nLeft + 1
         SetPos( Row(), ::oWndCode:nLeft + 1 )
         IF ::oWndCode:lFocused
            SetCursor( SC_SPECIAL1 )
         ENDIF

      CASE nKey == K_LEFT
         ::oBrwText:Left()

      CASE nKey == K_RIGHT
         ::oBrwText:Right()

      CASE nKey == K_UP
         ::oBrwText:Up()

      CASE nKey == K_DOWN
         ::oBrwText:Down()

      CASE nKey == K_PGUP
         ::oBrwText:PageUp()

      CASE nKey == K_PGDN
         ::oBrwText:PageDown()

      ENDCASE
   ENDIF

   RETURN NIL


METHOD Colors() CLASS HBDebugger

   LOCAL oWndColors := HBDbWindow():New( 4, 5, 16, ::nMaxCol - 5,;
                                        "Debugger Colors[1..11]", ::ClrModal() )
   LOCAL aColors := { "Border", "Text", "Text High", "Text PPO", "Text Selected",;
                      "Text High Sel.", "Text PPO Sel.", "Menu", "Menu High",;
                      "Menu Selected", "Menu High Sel." }

   LOCAL oBrwColors := HBDbBrowser():New( oWndColors:nTop + 1, oWndColors:nLeft + 1,;
                                          oWndColors:nBottom - 1, oWndColors:nRight - 1 )
   LOCAL nWidth := oWndColors:nRight - oWndColors:nLeft - 1
   LOCAL oCol

   IF ::lMonoDisplay
      Alert( "Monochrome display" )
      RETURN NIL
   ENDIF

   oBrwColors:Cargo := { 1, {} } // Actual highligthed row
   oBrwColors:ColorSpec := ::ClrModal()
   oBrwColors:goTopBlock := { || oBrwColors:cargo[ 1 ] := 1 }
   oBrwColors:goBottomBlock := { || oBrwColors:cargo[ 1 ] := Len( oBrwColors:cargo[ 2 ][ 1 ] ) }
   oBrwColors:skipBlock := { | nPos | ( nPos := ArrayBrowseSkip( nPos, oBrwColors ), oBrwColors:cargo[ 1 ] := ;
   oBrwColors:cargo[ 1 ] + nPos, nPos ) }

   oBrwColors:AddColumn( oCol := TBColumnNew( "", { || PadR( aColors[ oBrwColors:Cargo[ 1 ] ], 14 ) } ) )
   oCol:defColor := { 1, 2 }
   AAdd( oBrwColors:Cargo[ 2 ], aColors )
   oBrwColors:AddColumn( oCol := TBColumnNew( "",;
                       { || PadR( '"' + ::aColors[ oBrwColors:Cargo[ 1 ] ] + '"', nWidth - 15 ) } ) )
   AAdd( oBrwColors:Cargo[ 2 ], aColors )
   oCol:defColor := { 1, 3 }
   ocol:width := 50
   oBrwColors:autolite := .F.

   oWndColors:bPainted    := { || oBrwColors:ForceStable(), RefreshVarsS( oBrwColors ) }

   oWndColors:bKeyPressed := { | nKey | SetsKeyPressed( nKey, oBrwColors,;
                               Len( aColors ), oWndColors, "Debugger Colors",;
                               { || ::EditColor( oBrwColors:Cargo[ 1 ], oBrwColors ) } ) }
   oWndColors:ShowModal()

   ::LoadColors()

   RETURN NIL


METHOD CommandWindowProcessKey( nKey ) CLASS HBDebugger

   LOCAL cCommand
   LOCAL n
   LOCAL nWidth := ::oWndCommand:nRight - ::oWndCommand:nLeft - 3

   DO CASE
   CASE nKey == K_UP .OR. nKey == K_F3

      IF ::nCommand > 1
         ::oGetListCommand:Get():Assign()
         ::aLastCommands[ ::nCommand ] := Trim( ::oGetListCommand:Get():VarGet() )
         ::nCommand--
         cCommand := PadR( ::aLastCommands[ ::nCommand ], nWidth )
         ::oGetListCommand:Get():VarPut( cCommand )
         ::oGetListCommand:Get():Buffer := cCommand
         ::oGetListCommand:Get():Pos := Len( ::aLastCommands[ ::nCommand ] ) + 1
         ::oGetListCommand:Get():Display()
      ENDIF

   CASE nKey == K_DOWN

      IF ::nCommand < Len( ::aLastCommands )
         ::oGetListCommand:Get():Assign()
         ::aLastCommands[ ::nCommand ] := Trim( ::oGetListCommand:Get():VarGet() )
         ::nCommand++
         cCommand := PadR( ::aLastCommands[ ::nCommand ], nWidth )
         ::oGetListCommand:Get():VarPut( cCommand )
         ::oGetListCommand:Get():Buffer := cCommand
         ::oGetListCommand:Get():Pos := Len( ::aLastCommands[ ::nCommand ] ) + 1
         ::oGetListCommand:Get():Display()
      ENDIF

   CASE nKey == K_ENTER

      /* We must call :Assign() before :VarGet(), because it's no longer
       * called on every change */
      ::oGetListCommand:Get():Assign()
      cCommand := Trim( ::oGetListCommand:Get():VarGet() )

      IF ! Empty( cCommand )
         IF ( n := AScan( ::aLastCommands, cCommand ) ) > 0 .AND. n < Len( ::aLastCommands )
            ADel( ::aLastCommands, n, .T. )
         ENDIF
         ::nCommand := Len( ::aLastCommands )
         ::aLastCommands[ ::nCommand ] := cCommand
         AAdd( ::aLastCommands, "" )
         ::nCommand := Len( ::aLastCommands )
         ::oWndCommand:ScrollUp( 1 )
         ::DoCommand( cCommand )
      ENDIF

      DispOutAt( ::oWndCommand:nBottom - 1, ::oWndCommand:nLeft + 1, "> ",;
         __DbgColors()[ 2 ] )
      cCommand := Space( nWidth )
      ::oGetListCommand:Get():VarPut( cCommand )
      ::oGetListCommand:Get():Buffer := cCommand
      ::oGetListCommand:Get():Pos := 1
      ::oGetListCommand:Get():Display()

   OTHERWISE
      ::oGetListCommand:GetApplyKey( nKey )
   ENDCASE

   RETURN NIL


/*
 * ?? <expr>
 *      displays inspect window with value or display nothing on error
 * ? <expr>
 *      displays either result or error description in command window
 */
METHOD DoCommand( cCommand ) CLASS HBDebugger

   LOCAL aCmnd[ 3 ]
   LOCAL cParam
   LOCAL cParam1 := ""
   LOCAL cResult
   LOCAL lValid
   LOCAL n

   cCommand := AllTrim( cCommand )

   DO CASE
   CASE Empty( cCommand )
      RETURN ""

   CASE starts( cCommand, "??" )
      cParam := AllTrim( SubStr( cCommand, 3 ) )
      cCommand := "??"

   CASE starts( cCommand, "?" )
      cParam := SubStr( cCommand, 2 )
      cCommand := "?"

   OTHERWISE
      IF ( n := At( " ", cCommand ) ) > 0
         cParam := AllTrim( SubStr( cCommand, n + 1 ) )
         cCommand := Left( cCommand, n - 1 )
      ENDIF
      cCommand := Upper( cCommand )

   ENDCASE

   DO CASE
   CASE cCommand == "??" .OR. cCommand == "?"
      aCmnd[ WP_TYPE ] := cCommand
      aCmnd[ WP_EXPR ] := cParam

      ::RestoreAppState()
      cResult := ::GetExprValue( cParam, @lValid )
      ::SaveAppState()

      IF aCmnd[ WP_TYPE ] == "??"
         IF lValid
            ::Inspect( aCmnd[ WP_EXPR ], cResult )
         ENDIF
         cResult := ""  //discard result
      ELSE
         IF lValid
            cResult := __dbgValToStr( cResult )
         ENDIF
      ENDIF
      ::RefreshVars()

   CASE starts( "ANIMATE", cCommand )
      IF ::lActive
         ::lAnimate := .T.
         ::Animate()
         SetCursor( SC_NORMAL )
      ENDIF

   CASE starts( "BP", cCommand )
      /* TODO: Support BP <cFuncName> */
      IF !Empty( cParam )
         IF ( n := At( " ", cParam ) ) > 0
            cParam1 := AllTrim( SubStr( cParam, n + 1 ) )
            cParam := Left( cParam, n - 1 )
         ELSE
            cParam1 := ::cPrgName
         ENDIF
         ::ToggleBreakPoint( Val( cParam ), strip_path( cParam1 ) )
      ELSE
         ::ToggleBreakPoint()
      ENDIF

   CASE starts( "CALLSTACK", cCommand )
      ::Stack( Upper( cParam ) == "ON" )

   /* TODO: Support DELETE ALL [TP|BP|WP], DELETE WP|TP|BP <nNumber> */

   CASE starts( "DOS", cCommand )
      ::OsShell()
      SetCursor( SC_NORMAL )

   CASE starts( "FIND", cCommand )
      ::Locate( 0, cParam )

   CASE starts( "GO", cCommand )
      ::Go()

   CASE starts( "GOTO", cCommand ) .AND. Val( cParam ) > 0
      ::GoToLine( Val( cParam ) )

   CASE starts( "HELP", cCommand )
      ::ShowHelp()

   CASE starts( "INPUT", cCommand ) .AND. !Empty( cParam )
      ::DoScript( cParam )

   /* TODO: Support LIST BP|WP|TP */

   CASE starts( "MONITOR", cCommand )

      cParam := Upper( cParam )

      DO CASE
      CASE starts( "GLOBAL", cParam )
         ::Global()
      CASE starts( "LOCAL", cParam )
         ::Local()
      CASE starts( "PRIVATE", cParam )
         ::Private()
      CASE starts( "PUBLIC", cParam )
         ::Public()
      CASE starts( "SORT", cParam )
         ::Sort()
      CASE starts( "STATIC", cParam )
         ::Static()
      OTHERWISE
         cResult := "Command error"
      ENDCASE

   CASE starts( "NEXT", cCommand )
      ::FindNext()

   CASE starts( "NUM", cCommand )
      IF Upper( cParam ) == "OFF"
         ::LineNumbers( .F. )
      ELSEIF Upper( cParam ) == "ON"
         ::LineNumbers( .T. )
      ELSE
         cResult := "Command error"
      ENDIF

   CASE starts( "OPTIONS", cCommand )

      IF ( n := At( " ", cParam ) ) > 0
         cParam1 := AllTrim( SubStr( cParam, n + 1 ) )
         cParam := Left( cParam, n - 1 )
      ENDIF

      cParam := Upper( cParam )

      DO CASE
      CASE starts( "COLORS", cParam )

         IF Empty( cParam1 )
            ::Colors()
         ELSE
            cParam1 := SubStr( cParam1, At( "{", cParam1 ) + 1 )
            FOR n := 1 TO 11
               IF At( ",", cParam1 ) != 0
                  ::aColors[ n ] := ;
                     StrTran( Left( cParam1, At( ",", cParam1 ) - 1 ), '"', "" )
                  cParam1 := SubStr( cParam1, At( ",", cParam1 ) + 1 )
               ELSE
                  ::aColors[ n ] := ;
                     StrTran( Left( cParam1, At( "}", cParam1 ) - 1 ), '"', "" )
               ENDIF
            NEXT
            ::LoadColors()
         ENDIF
      CASE starts( "NORUNATSTARTUP", cParam )
         ::lRunAtStartup := .F.
      CASE starts( "PATH", cParam )
         ::PathForFiles( AllTrim( cParam1 ) )
      CASE starts( "TAB", cParam )
         ::nTabWidth := Val( Left( cParam1, 3 ) )
      OTHERWISE
         cResult := "Command error"
      ENDCASE

   CASE starts( "OUTPUT", cCommand )
      SetCursor( SC_NONE )
      ::ShowAppScreen()
      SetCursor( SC_NORMAL )

   CASE starts( "PREV", cCommand )
      ::FindPrevious()

   CASE starts( "QUIT", cCommand )
      ::Quit()

   /* TODO: Support RESTART */

   CASE starts( "RESUME", cCommand )
      ::Resume()

   CASE starts( "SPEED", cCommand )
      IF !Empty( cParam )
         ::nSpeed := Val( cParam )
      ELSE
         ::nSpeed := 0
      ENDIF

   CASE starts( "STEP", cCommand )
      ::Step()

   CASE starts( "TP", cCommand )
      ::TracepointAdd( cParam )

   CASE starts( "VIEW", cCommand )
      IF !Empty( cParam ) .AND. starts( "CALLSTACK", Upper( cParam ) )
         ::Stack()
      ELSE
         cResult := "Command error"
      ENDIF

   CASE starts( "WINDOW", cCommand )

      IF ( n := At( " ", cParam ) ) > 0
         cParam1 := AllTrim( SubStr( cParam, n + 1 ) )
         cParam := Left( cParam, n - 1 )
      ENDIF

      DO CASE
      CASE starts( "MOVE", cParam )
         WITH OBJECT ::aWindows[ ::nCurrentWindow ]
            n := At( " ", cParam1 )
            IF n > 0
               n := Val( SubStr( cParam1, n ) )
            ENDIF
            :Resize( Val( cParam1 ), n, ;
                     :nBottom + Val( cParam1 ) - :nTop, :nRight + n - :nLeft )
         ENDWITH
      CASE starts( "NEXT", cParam )
         ::NextWindow()
      CASE starts( "SIZE", cParam )
         WITH OBJECT ::aWindows[ ::nCurrentWindow ]
            n := At( " ", cParam1 )
            IF Val( cParam1 ) >= 2 .AND. n > 0 .AND. Val( SubStr( cParam1, n ) ) > 0
               :Resize( :nTop, :nLeft, Val( cParam1 ) - 1 + :nTop, ;
                        Val( SubStr( cParam1, n ) ) - 1 + :nLeft )
            ENDIF
         ENDWITH
      ENDCASE

   CASE starts( "WP", cCommand )
      ::WatchpointAdd( cParam )

   OTHERWISE
      cResult := "Command error"

   ENDCASE

   IF ::lActive
      DispOutAt( ::oWndCommand:nBottom - 1, ::oWndCommand:nLeft + 1, ;
                 Space( ::oWndCommand:nRight - ::oWndCommand:nLeft - 1 ), ;
                 __DbgColors()[ 2 ] )
      IF !Empty( cResult )
         DispOutAt( ::oWndCommand:nBottom - 1, ::oWndCommand:nLeft + 3, ;
                     cResult, __DbgColors()[ 2 ] )
         ::oWndCommand:ScrollUp( 1 )
      ENDIF
   ENDIF

   RETURN cResult


METHOD DoScript( cFileName ) CLASS HBDebugger

   LOCAL cInfo
   LOCAL n
   LOCAL cLine
   LOCAL nLen

   IF File( cFileName )
      cInfo := MemoRead( cFileName )
      nLen := MLCount( cInfo, NIL, NIL, .F. )
      FOR n := 1 TO nLen
         cLine := MemoLine( cInfo, 16384, n, NIL, .F., .T. )
         ::DoCommand( cLine )
      NEXT
   ENDIF

   RETURN NIL


METHOD EditColor( nColor, oBrwColors ) CLASS HBDebugger

   LOCAL GetList    := {}
   LOCAL lPrevScore := Set( _SET_SCOREBOARD, .F. )
   LOCAL lPrevExit  := Set( _SET_EXIT, .T. )
   LOCAL cColor     := PadR( '"' + ::aColors[ nColor ] + '"',;
                             oBrwColors:getColumn( 2 ):Width )

   oBrwColors:RefreshCurrent()
   oBrwColors:ForceStable()

#ifndef HB_NO_READDBG
   SetCursor( SC_NORMAL )
   @ Row(), Col() + 15 GET cColor COLOR SubStr( ::ClrModal(), 5 ) ;
      VALID iif( Type( cColor ) != "C", ( Alert( "Must be string" ), .F. ), .T. )

   READ
   SetCursor( SC_NONE )
#else
   cColor := getdbginput( Row(), Col() + 15, cColor, ;
                           { | cColor | iif( Type( cColor ) != "C", ;
                                 ( Alert( "Must be string" ), .F. ), .T. ) }, ;
                           SubStr( ::ClrModal(), 5 ) )
#endif

   Set( _SET_SCOREBOARD, lPrevScore )
   Set( _SET_EXIT, lPrevExit )

   IF LastKey() != K_ESC
      ::aColors[ nColor ] := &cColor
   ENDIF

   oBrwColors:RefreshCurrent()
   oBrwColors:ForceStable()

   RETURN NIL

METHOD EditSet( nSet, oBrwSets ) CLASS HBDebugger

   LOCAL GetList    := {}
   LOCAL lPrevScore := Set( _SET_SCOREBOARD, .F. )
   LOCAL lPrevExit  := Set( _SET_EXIT, .T. )
   LOCAL cSet       := PadR( __dbgValToStr( Set( nSet ) ), oBrwSets:getColumn( 2 ):Width )
   LOCAL cType      := ValType( Set( nSet ) )

   oBrwSets:RefreshCurrent()
   oBrwSets:ForceStable()

#ifndef HB_NO_READDBG
   SetCursor( SC_NORMAL )
   @ Row(), Col() + 13 GET cSet COLOR SubStr( ::ClrModal(), 5 ) ;
      VALID iif( Type( cSet ) != cType, ( Alert( "Must be of type '" + cType + "'" ), .F. ), .T. )

   READ
   SetCursor( SC_NONE )
#else
   cSet := getdbginput( Row(), Col() + 13, cSet, ;
               { | cSet | iif( Type( cSet ) != cType,
                  ( Alert( "Must be of type '" + cType + "'" ), .F. ), .T. ) }, ;
               SubStr( ::ClrModal(), 5 ) )
#endif

   Set( _SET_SCOREBOARD, lPrevScore )
   Set( _SET_EXIT, lPrevExit )

   IF LastKey() != K_ESC
      Set( nSet, &cSet )
   ENDIF

   oBrwSets:RefreshCurrent()
   oBrwSets:ForceStable()

   RETURN NIL


METHOD EditVar( nVar ) CLASS HBDebugger

   LOCAL cVarName   := ::aVars[ nVar ][ 1 ]
   LOCAL uVarValue  := ::aVars[ nVar ][ 2 ]
   LOCAL cVarType   := ::aVars[ nVar ][ 3 ]
   LOCAL cVarStr
   LOCAL oErr

   uVarValue := ::VarGetValue( ::aVars[ nVar ] )

   IF ValType( uVarValue ) $ "AHOP"
      ::InputBox( cVarName, uVarValue, NIL, .F. )
   ELSE
      cVarStr := ::InputBox( cVarName, __dbgValToStr( uVarValue ),;
                { | u | iif( Type( u ) == "UE", ( Alert( "Expression error" ), .F. ), .T. ) } )
   ENDIF

   IF LastKey() != K_ESC

      DO CASE
      CASE cVarStr == "{ ... }"
         //aArray := ::VarGetValue( ::aVars[ nVar ] )
         IF Len( uVarValue ) > 0
            __DbgArrays( uVarValue, cVarName )
         ELSE
            Alert( "Array is empty" )
         ENDIF

      CASE Upper( Left( cVarStr, 5 ) ) == "CLASS"
         __DbgObject( uVarValue, cVarName )

      OTHERWISE
         BEGIN SEQUENCE WITH {|oErr| break( oErr ) }
            ::VarSetValue( ::aVars[ nVar ], &cVarStr )
         RECOVER USING oErr
            Alert( oErr:description )
         END SEQUENCE
      ENDCASE
   ENDIF

   ::oBrwVars:RefreshCurrent()
   ::oBrwVars:ForceStable()

   RETURN NIL


METHOD FindNext() CLASS HBDebugger
   RETURN ::Locate( 1, ::cSearchString )


METHOD FindPrevious() CLASS HBDebugger
   RETURN ::Locate( 2, ::cSearchString )


METHOD GetExprValue( xExpr, lValid ) CLASS HBDebugger

   LOCAL xResult
   LOCAL oErr
   LOCAL bOldErrorBlock := ErrorBlock( { | oErr | Break( oErr ) } )

   lValid := .F.

   BEGIN SEQUENCE
      xResult := hb_DBG_GetExprValue( ::pInfo, xExpr, @lValid )
      IF !lValid
         xResult := "Syntax error"
      ENDIF
   RECOVER USING oErr
      xResult := oErr:operation + ": " + oErr:description
      IF ISARRAY( oErr:args )
         xResult += "; arguments:"
         AEval( oErr:args, { | x | xResult += " " + AllTrim( hb_CStr( x ) ) } )
      ENDIF
      lValid := .F.
   END SEQUENCE

   ErrorBlock( bOldErrorBlock )

   RETURN xResult


METHOD GetSourceFiles() CLASS HBDebugger
   RETURN hb_DBG_GetSourceFiles( ::pInfo )


METHOD Global() CLASS HBDebugger
   ::lShowGlobals := ! ::lShowGlobals
   ::RefreshVars()
   RETURN NIL


METHOD Go() CLASS HBDebugger
   // we are starting to run again so reset to the deepest call if
   // displaying stack
   IF ! ::oBrwStack == NIL
      ::oBrwStack:GoTop()
   ENDIF
   ::RestoreAppScreen()
   ::RestoreAppState()
   hb_DBG_SetGo( ::pInfo )
   ::Exit()
   RETURN NIL


METHOD GotoLine( nLine ) CLASS HBDebugger

   LOCAL nRow
   LOCAL nCol

   /*
   IF ::oBrwVars != NIL
      ::ShowVars()
   ENDIF
   */

   ::oBrwText:GotoLine( nLine )
   nRow := Row()
   nCol := Col()

   // no source code line stored yet

   /*
   IF ::oBrwStack != NIL .AND. Len( ::aCallStack ) > 0 .AND. ;
      ::aCallStack[ ::oBrwStack:Cargo ][ CSTACK_LINE ] == NIL
      ::aCallStack[ ::oBrwStack:Cargo ][ CSTACK_LINE ] := nLine
   ENDIF
   */

   IF ::oWndStack != NIL .AND. ! ::oBrwStack:Stable
      ::oBrwStack:ForceStable()
   ENDIF

   IF ::oWndCode:lFocused .AND. SetCursor() != SC_SPECIAL1
      SetPos( nRow, nCol )
      SetCursor( SC_SPECIAL1 )
   ENDIF
   SetPos( nRow, nCol )

   // Store cursor position to be restored by ::oWndCode:bGotFocus
   ::oWndCode:cargo[ 1 ] := nRow
   ::oWndCode:cargo[ 2 ] := nCol

   RETURN NIL


METHOD HandleEvent() CLASS HBDebugger

   LOCAL nPopup
   LOCAL oWnd
   LOCAL nKey
   LOCAL nMRow
   LOCAL nMCol
   LOCAL n

   IF ::lAnimate
      IF ::nSpeed != 0
         Inkey( ::nSpeed / 10 )
      ENDIF
      IF hb_DBG_INVOKEDEBUG()  //NextKey() == K_ALT_D
         ::lAnimate := .F.
      ELSE
         ::Step()
         RETURN NIL
      ENDIF
   ENDIF

   ::lEnd := .F.

   DO WHILE ! ::lEnd

      nKey := Inkey( 0, INKEY_ALL )

      DO CASE
      CASE nKey == K_ALT_X
         s_oDebugger:Quit()

      CASE ::oPullDown:IsOpen()
         ::oPullDown:ProcessKey( nKey )
         IF ::oPullDown:nOpenPopup == 0 // Closed
            ::aWindows[ ::nCurrentWindow ]:Show( .T. )
         ENDIF

      CASE nKey == K_LDBLCLK

         IF MRow() != 0 .AND. MRow() != ::nMaxRow

            nMRow := MRow()
            nMCol := MCol()
            FOR n := 1 TO Len( ::aWindows )
               IF ::aWindows[ n ]:IsOver( nMRow, nMCol )
                  IF ! ::aWindows[ n ]:lFocused
                     ::aWindows[ ::nCurrentWindow ]:Show( .F. )
                     ::nCurrentWindow := n
                     ::aWindows[ n ]:Show( .T. )
                  ENDIF
                  ::aWindows[ n ]:LDblClick( nMRow, nMCol )
                  exit
               ENDIF
            NEXT
         ENDIF

      CASE nKey == K_LBUTTONDOWN

         IF MRow() == 0

            IF ( nPopup := ::oPullDown:GetItemOrdByCoors( 0, MCol() ) ) != 0
               IF ! ::oPullDown:IsOpen()
                  IF ::oWndCode:lFocused
                     Eval( ::oWndCode:bLostFocus )
                  ENDIF
                  SetCursor( SC_NONE )
               ENDIF
               ::oPullDown:ShowPopup( nPopup )
            ENDIF

         ELSEIF MRow() != ::nMaxRow

            nMRow := MRow()
            nMCol := MCol()
            FOR n := 1 TO Len( ::aWindows )
               IF ::aWindows[ n ]:IsOver( nMRow, nMCol )
                  IF ! ::aWindows[ n ]:lFocused
                     ::aWindows[ ::nCurrentWindow ]:Show( .F. )
                     ::nCurrentWindow := n
                     ::aWindows[ n ]:Show( .T. )
                  ENDIF
                  ::aWindows[ n ]:LButtonDown( nMRow, nMCol )
                  exit
               ENDIF
            NEXT
         ENDIF

      CASE nKey == K_RBUTTONDOWN
/*
      CASE nKey == K_ESC
         ::RestoreAppStatus()
         s_oDebugger := NIL
         s_lExit := .T.
         DispEnd()
         ::Exit()
*/

      CASE nKey == K_UP .OR. nKey == K_DOWN .OR. nKey == K_HOME .OR. ;
           nKey == K_END .OR. nKey == K_ENTER .OR. nKey == K_PGDN .OR. ;
           nKey == K_PGUP .OR. nKey == K_DEL .OR. nKey == K_LEFT .OR. ;
           nKey == K_RIGHT .OR. nKey == K_CTRL_ENTER

         oWnd := ::aWindows[ ::nCurrentWindow ]
         oWnd:KeyPressed( nKey )

      CASE nKey == K_F1
         ::ShowHelp()

      CASE nKey == K_F4
         ::ShowAppScreen()

      CASE nKey == K_F5
         ::Go()

      CASE nKey == K_CTRL_F5
         ::NextRoutine()

      CASE nKey == K_F6
         ::ShowWorkAreas()

      CASE nKey == K_F7
         ::ToCursor()

      CASE nKey == K_F8
         ::Step()

      CASE nKey == K_F9
         ::ToggleBreakPoint()

      CASE nKey == K_F10
         ::Trace()

      CASE nKey == K_TAB
         ::NextWindow()

      CASE nKey == K_SH_TAB
         ::PrevWindow()

      CASE ::oWndCommand:lFocused .AND. nKey < 272 // Alt
         ::oWndCommand:KeyPressed( nKey )

      OTHERWISE
         IF ( nPopup := ::oPullDown:GetHotKeyPos( __dbgAltToKey( nKey ) ) ) != 0
            IF ::oPullDown:nOpenPopup != nPopup
               IF ::oWndCode:lFocused
                  Eval( ::oWndCode:bLostFocus )
               ENDIF
               SetCursor( SC_NONE )
               ::oPullDown:ShowPopup( nPopup )
            ENDIF
         ENDIF
      ENDCASE
   ENDDO

   RETURN NIL

METHOD Hide() CLASS HBDebugger
   ::CloseDebuggerWindow()
   RETURN NIL


METHOD HideCallStack() CLASS HBDebugger

   ::lShowCallStack := .F.

   IF ::oWndStack != NIL
      DispBegin()
      ::oWndStack:Hide()
      IF ::aWindows[ ::nCurrentWindow ] == ::oWndStack
        ::NextWindow()
      ENDIF
      ::RemoveWindow( ::oWndStack )
      ::oWndStack := NIL

      ::oWndCode:Resize(,,, ::oWndCode:nRight + 16 )
      IF ::oWndVars != NIL
         ::oWndVars:Resize(,,, ::oWndVars:nRight + 16 )
      ENDIF
      IF ::oWndPnt != NIL
         ::oWndPnt:Resize(,,, ::oWndPnt:nRight + 16 )
      ENDIF
      DispEnd()
   ENDIF

   RETURN NIL


METHOD HideVars() CLASS HBDebugger
   LOCAL nTop

   IF ::oWndVars == NIL
      RETURN NIL
   ENDIF

   ::oWndVars:Hide()
   IF ::oWndPnt == NIL
      nTop := 1
   ELSE
      ::oWndPnt:Resize( 1, , ::oWndPnt:nBottom - ( ::oWndPnt:nTop - 1 ) )
      ::oBrwPnt:Resize( 2, , ::oWndPnt:nBottom - 1 )
      nTop := ::oWndPnt:nBottom + 1
   ENDIF
   ::oWndCode:Resize( nTop )
   ::oBrwText:Resize( ::oWndCode:nTop + 1 )
   IF ::oWndCode:lFocused
      ::oWndCode:cargo[ 1 ] := Row()
      ::oWndCode:cargo[ 2 ] := Col()
   ENDIF

   IF ::aWindows[ ::nCurrentWindow ] == ::oWndVars
      ::NextWindow()
   ENDIF

   RETURN NIL


METHOD InputBox( cMsg, uValue, bValid, lEditable ) CLASS HBDebugger

   LOCAL nTop    := Int( ( ::nMaxRow / 2 ) - 5 )
   LOCAL nLeft   := Int( ( ::nMaxCol / 2 ) - 25 )
   LOCAL nBottom := nTop + 2
   LOCAL nRight  := nLeft + 50
   LOCAL cType   := ValType( uValue )
   LOCAL nWidth  := nRight - nLeft - 1
   LOCAL cPicture
   LOCAL uTemp
   LOCAL nOldCursor
   LOCAL lScoreBoard := Set( _SET_SCOREBOARD, .F. )
   LOCAL lExit
   LOCAL oWndInput := HBDbWindow():New( nTop, nLeft, nBottom, nRight, cMsg,;
                                       ::oPullDown:cClrPopup )
#ifndef HB_NO_READDBG
   LOCAL GetList := {}
   LOCAL bMouseSave
   LOCAL oGet
#endif

   DEFAULT lEditable TO .T.

   IF cType == "C" .AND. Len( uValue ) > nWidth
      uTemp := uValue
      cPicture := "@s" + LTrim( Str( nWidth ) )
   ELSE
      uTemp := PadR( uValue, nWidth )
   ENDIF

   oWndInput:lShadow := .T.
   oWndInput:Show()

   IF lEditable
#ifndef HB_NO_READDBG
      IF bValid == NIL
         @ nTop + 1, nLeft + 1 GET uTemp PICTURE cPicture COLOR "," + __DbgColors()[ 5 ]
      ELSE
         @ nTop + 1, nLeft + 1 GET uTemp PICTURE cPicture VALID Eval( bValid, uTemp ) ;
           COLOR "," + __DbgColors()[ 5 ]
      ENDIF

      nOldCursor := SetCursor( SC_NORMAL )
      oGet := ATail( GetList )
      bMouseSave := SetKey( K_LBUTTONDOWN, { || iif( MRow() == nTop .AND. MCol() == nLeft + 2,;
         ( oGet:undo(), oGet:exitState := GE_ESCAPE, .T. ), .F. ) } )
      READ
      SetKey( K_LBUTTONDOWN, bMouseSave)
      SetCursor( nOldCursor )
#else
      uTemp := getdbginput( nTop + 1, nLeft + 1, uTemp, bValid, __DbgColors()[ 5 ] )
#endif
   ELSE
      DispOutAt( nTop + 1, nLeft + 1, __dbgValToStr( uValue ), "," + __DbgColors()[ 5 ] )
      SetPos( nTop + 1, nLeft + 1 )
      nOldCursor := SetCursor( SC_NONE )

      lExit := .F.

      DO WHILE ! lExit
         Inkey( 0 )

         DO CASE
         CASE LastKey() == K_ESC
            lExit := .T.

         CASE LastKey() == K_ENTER
            IF cType == "A"
               IF Len( uValue ) == 0
                  Alert( "Array is empty" )
               ELSE
                  __DbgArrays( uValue, cMsg )
               ENDIF

            ELSEIF cType == "H"
               IF Len( uValue ) == 0
                  Alert( "Hash is empty" )
               ELSE
                  __DbgHashes( uValue, cMsg )
               ENDIF

            ELSEIF cType == "O"
               __DbgObject( uValue, cMsg )

            ELSE
               Alert( "Value cannot be edited" )
            ENDIF

         OTHERWISE
            Alert( "Value cannot be edited" )
         ENDCASE
      ENDDO

      SetCursor( nOldCursor )
   ENDIF

#ifndef HB_NO_READDBG
   nOldCursor := SetCursor( SC_NORMAL )
   READ
   SetCursor( nOldCursor )
#endif

   oWndInput:Hide()
   Set( _SET_SCOREBOARD, lScoreBoard )

   DO CASE
   CASE cType == "C" ; uTemp := AllTrim( uTemp )
   CASE cType == "D" ; uTemp := CToD( uTemp )
   CASE cType == "N" ; uTemp := Val( uTemp )
   ENDCASE

   RETURN iif( LastKey() != K_ESC, uTemp, uValue )


METHOD Inspect( uValue, cValueName ) CLASS HBDebugger

   uValue := ::InputBox( uValue, cValueName,, .F. )

   RETURN NIL


METHOD IsValidStopLine( cName, nLine ) CLASS HBDebugger
   RETURN hb_DBG_IsValidStopLine( ::pInfo, cName, nLine )


METHOD LineNumbers( lLineNumbers ) CLASS HBDebugger

   DEFAULT lLineNumbers TO !::lLineNumbers

   ::lLineNumbers := lLineNumbers
   ::oPulldown:GetItemByIdent( "LINE" ):checked := ::lLineNumbers
   IF ::oBrwText != NIL
      ::oBrwText:lLineNumbers := lLineNumbers
      ::oBrwText:RefreshAll()
   ENDIF

   RETURN Self


METHOD ListBox( cCaption, aItems ) CLASS HBDebugger

   LOCAL nItems
   LOCAL nMaxWid
   LOCAL nLeft
   LOCAL nTop
   LOCAL nBottom
   LOCAL nRight
   LOCAL oWndList
   LOCAL cSelected := ""
   LOCAL cColors
   LOCAL n

   nItems := Len( aItems )
   nMaxWid := Len( cCaption ) + 2
   AEval( aItems, { | x | nMaxWid := Max( Len( x ), nMaxWid ) } )
   nMaxWid += 2

   nTop    := ( ::nMaxRow / 2 ) - Min( nItems, ::nMaxRow - 5 ) / 2
   nBottom := ( ::nMaxRow / 2 ) + Min( nItems, ::nMaxRow - 5 ) / 2 + 1
   nLeft   := ( ::nMaxCol / 2 ) - Min( nMaxWid, ::nMaxCol * 3 / 2 ) / 2
   nRight  := ( ::nMaxCol / 2 ) + Min( nMaxWid, ::nMaxCol * 3 / 2 ) / 2
   oWndList := HBDbWindow():new( nTop, nLeft, nBottom, nRight, cCaption, ;
                                ::oPullDown:cClrPopup )
   oWndList:lShadow := .T.
   oWndList:Show()

   cColors := SetColor( ::aColors[ 8 ] + "," + ::aColors[ 10 ] )
   n := AChoice( nTop + 1, nLeft + 1, nBottom - 1, nRight - 1, aItems )
   SetColor( cColors )

   oWndList:Hide()
   RETURN n


METHOD LoadCallStack() CLASS HBDebugger

   LOCAL i
   LOCAL nDebugLevel
   LOCAL nCurrLevel
   LOCAL nlevel
   LOCAL nPos

   ::aProcStack := Array( ::nProcLevel )

   nCurrLevel := hb_dbg_ProcLevel() - 1
   nDebugLevel := nCurrLevel - ::nProcLevel + 1

   FOR i := nDebugLevel TO nCurrLevel
      nLevel := nCurrLevel - i + 1
      nPos := AScan( ::aCallStack, { | a | a[ CSTACK_LEVEL ] == nLevel } )
      IF nPos > 0
         // a procedure with debug info
         ::aProcStack[ i - nDebugLevel + 1 ] := ::aCallStack[ nPos ]
      ELSE
         ::aProcStack[ i - nDebugLevel + 1 ] := { , ProcName( i ) + "(" + LTrim( Str( ProcLine( i ) ) ) + ")", , nLevel, , }
      ENDIF
   NEXT

   RETURN NIL


METHOD LoadColors() CLASS HBDebugger

   LOCAL n

   ::oPullDown:LoadColors()
   IF ::lActive
      ::oPullDown:Refresh()
      ::BarDisplay()
   ENDIF
   FOR n := 1 TO Len( ::aWindows )
      ::aWindows[ n ]:LoadColors()
      IF ::lActive
         ::aWindows[ n ]:Refresh()
      ENDIF
   NEXT

   RETURN NIL


METHOD LoadSettings() CLASS HBDebugger
   ::DoScript( ::cSettingsFileName )
   RETURN NIL


METHOD LoadVars() CLASS HBDebugger // updates monitored variables

   LOCAL nCount
   LOCAL n
   LOCAL m
   LOCAL xValue
   LOCAL cName
   LOCAL aVars
   LOCAL aBVars

   aBVars := {}

   IF ::lShowPublics
      nCount := __mvDbgInfo( HB_MV_PUBLIC )
      FOR n := nCount TO 1 STEP -1
         xValue := __mvDbgInfo( HB_MV_PUBLIC, n, @cName )
         AAdd( aBVars, { cName, xValue, "Public" } )
      NEXT
   ENDIF

   IF ::lShowPrivates
      nCount := __mvDbgInfo( HB_MV_PRIVATE )
      FOR n := nCount TO 1 STEP -1
         xValue := __mvDbgInfo( HB_MV_PRIVATE, n, @cName )
         AAdd( aBVars, { cName, xValue, "Private" } )
      NEXT
   ENDIF

   IF ::aProcStack[ ::oBrwStack:Cargo ][ CSTACK_LINE ] != NIL
      IF ::lShowGlobals
         cName := ::aProcStack[ ::oBrwStack:Cargo ][ CSTACK_MODULE ]
         FOR n := 1 TO Len( ::aModules )
            IF !::lShowAllGlobals
               IF !FILENAME_EQUAL( ::aModules[ n ][ MODULE_NAME ], cName )
                  LOOP
               ENDIF
            ENDIF
            aVars := ::aModules[ n ][ MODULE_GLOBALS ]
            FOR m := 1 TO Len( aVars )
               AAdd( aBVars, aVars[ m ] )
            NEXT
            IF !::lShowAllGlobals
               aVars := ::aModules[ n ][ MODULE_EXTERNGLOBALS ]
               FOR m := 1 TO Len( aVars )
                  AAdd( aBVars, aVars[ m ] )
               NEXT
            ENDIF
         NEXT
      ENDIF

      IF ::lShowStatics
         cName := ::aProcStack[ ::oBrwStack:Cargo ][ CSTACK_MODULE ]
         n := AScan( ::aModules, { | a | FILENAME_EQUAL( a[ MODULE_NAME ], cName ) } )
         IF n > 0
            aVars := ::aModules[ n ][ MODULE_STATICS ]
            FOR m := 1 TO Len( aVars )
               AAdd( aBVars, aVars[ m ] )
            NEXT
         ENDIF
         aVars := ::aProcStack[ ::oBrwStack:Cargo ][ CSTACK_STATICS ]
         FOR n := 1 TO Len( aVars )
            AAdd( aBVars, aVars[ n ] )
         NEXT
      ENDIF

      IF ::lShowLocals
         aVars := ::aProcStack[ ::oBrwStack:Cargo ][ CSTACK_LOCALS ]
         FOR n := 1 TO Len( aVars )
            cName := aVars[ n ][ VAR_NAME ]
            m := AScan( aBVars,; // Is there another var with this name ?
                        { | aVar | aVar[ VAR_NAME ] == cName .AND. Left( aVar[ VAR_TYPE ], 1 ) == "S" } )
            IF m > 0
               aBVars[ m ] := aVars[ n ]
            ELSE
               AAdd( aBVars, aVars[ n ] )
            ENDIF
         NEXT
      ENDIF
   ENDIF

   IF ::oBrwVars != NIL .AND. ::oBrwVars:cargo[ 1 ] > Len( aBVars )
      ::oBrwVars:GoTop()
   ENDIF
   ::aVars := aBVars
   IF ::lSortVars
      ::Sort()
   ENDIF

   RETURN NIL


METHOD Local() CLASS HBDebugger
   ::lShowLocals := ! ::lShowLocals
   ::RefreshVars()
   RETURN NIL


METHOD Locate( nMode, cValue ) CLASS HBDebugger

   LOCAL lFound

   DEFAULT nMode TO 0

   IF Empty( cValue )
      ::cSearchString := PadR( ::cSearchString, 256 )
      cValue := ::InputBox( "Search string", ::cSearchString )
      IF Empty( cValue )
         RETURN NIL
      ENDIF
   ENDIF

   ::cSearchString := cValue

   lFound := ::oBrwText:Search( ::cSearchString, ::lCaseSensitive, nMode )

   // Save cursor position to be restored by ::oWndCode:bGotFocus
   ::oWndCode:cargo[ 1 ] := Row()
   ::oWndCode:cargo[ 2 ] := Col()
   RETURN lFound


METHOD LocatePrgPath( cPrgName ) CLASS HBDebugger

   LOCAL aPaths := ::aPathDirs
   LOCAL iMax := Len( aPaths )
   LOCAL cSep := hb_OSPathSeparator()
   LOCAL cRetPrgName
   LOCAL i

   FOR i := 1 TO iMax
      cRetPrgName := aPaths[ i ] + cSep + cPrgName
      IF File( cRetPrgName )
         RETURN cRetPrgName
      ENDIF
   NEXT

   RETURN NIL


METHOD MonoDisplay() CLASS HBDebugger

   ::lMonoDisplay := ! ::lMonoDisplay
   ::oPullDown:GetItemByIdent( "MONO" ):checked := ::lMonoDisplay
   ::LoadColors()

   RETURN NIL


METHOD NextRoutine() CLASS HBDebugger
   ::RestoreAppScreen()
   ::RestoreAppState()
   hb_DBG_SetNextRoutine( ::pInfo )
   ::Exit()
   RETURN Self


METHOD NextWindow() CLASS HBDebugger

   LOCAL oWnd

   IF Len( ::aWindows ) > 0
      oWnd := ::aWindows[ ::nCurrentWindow++ ]
      oWnd:Show( .F. )
      IF ::nCurrentWindow > Len( ::aWindows )
         ::nCurrentWindow := 1
      ENDIF
      DO WHILE ! ::aWindows[ ::nCurrentWindow ]:lVisible
         ::nCurrentWindow++
         IF ::nCurrentWindow > Len( ::aWindows )
            ::nCurrentWindow := 1
         ENDIF
      ENDDO
      oWnd := ::aWindows[ ::nCurrentWindow ]
      oWnd:Show( .T. )
   ENDIF

   RETURN NIL


METHOD Open() CLASS HBDebugger

   LOCAL nFileName
   LOCAL cFileName
   LOCAL cRealName
   LOCAL aFiles := ::GetSourceFiles()
   LOCAL cExt

   ASort( aFiles )
   ASize( aFiles, Len( aFiles ) + 1 )
   AIns( aFiles, 1, "(Another file)" )

   nFileName := ::ListBox( "Please choose a source file", aFiles )
   IF nFileName == 0
      RETURN NIL
   ELSEIF nFileName == 1
      cFileName := ::InputBox( "Please enter the filename", Space( 255 ) )
      cFileName := AllTrim( cFileName )
   ELSE
      cFileName := aFiles[ nFileName ]
   ENDIF

   IF !Empty( cFileName ) ;
        .AND. ( ValType( ::cPrgName ) == "U" .OR. !FILENAME_EQUAL( cFileName, ::cPrgName ) )

      IF ! File( cFileName ) .AND. ! Empty( ::cPathForFiles )
         cRealName := ::LocatePrgPath( cFileName )
         IF Empty( cRealName )
           Alert( "File '" + cFileName + "' not found!" )
           RETURN NIL
         ENDIF
         cFileName := cRealName
      ENDIF
      ::cPrgName := cFileName
      hb_FNameSplit( cFileName, NIL, NIL, @cExt )
      ::lPPO := ( Lower( cExt ) == ".ppo" )
      ::oPulldown:GetItemByIdent( "PPO" ):Checked := ::lPPO
      ::oBrwText := HBBrwText():New( ::oWndCode:nTop + 1, ::oWndCode:nLeft + 1,;
                    ::oWndCode:nBottom - 1, ::oWndCode:nRight - 1, cFileName,;
                    __DbgColors()[ 2 ] + "," + __DbgColors()[ 5 ] + "," + ;
                    __DbgColors()[ 3 ] + "," + __DbgColors()[ 6 ], ;
                    ::lLineNumbers, ::nTabWidth )
      ::oWndCode:Browser := ::oBrwText
      ::RedisplayBreakpoints()               // check for breakpoints in this file and display them
      ::oWndCode:SetCaption( ::cPrgName )
      ::oWndCode:Refresh()       // to force the window caption to update
   ENDIF
   RETURN NIL


METHOD OpenPPO() CLASS HBDebugger

   LOCAL lSuccess := .F.
   LOCAL cDir
   LOCAL cName
   LOCAL cExt

   IF Empty( ::cPrgName )
      RETURN .F.
   ENDIF

   hb_FNameSplit( ::cPrgName, @cDir, @cName, @cExt )

   IF Lower( cExt ) == ".ppo"
      ::cPrgName := hb_FNameMerge( cDir, cName, ".prg" )
      lSuccess := File( ::cPrgName )
      ::lPPO := !lSuccess
   ELSE
      ::cPrgName := hb_FNameMerge( cDir, cName, ".ppo" )
      lSuccess := File( ::cPrgName )
      ::lPPO := lSuccess
   ENDIF

   IF lSuccess
      ::oBrwText := HBBrwText():New( ::oWndCode:nTop + 1, ::oWndCode:nLeft + 1,;
        ::oWndCode:nBottom - 1, ::oWndCode:nRight - 1, ::cPrgName,;
        __DbgColors()[ 2 ] + "," + __DbgColors()[ 5 ] + "," + ;
        __DbgColors()[ 3 ] + "," + __DbgColors()[ 6 ], ::lLineNumbers, ::nTabWidth )
      ::oWndCode:Browser := ::oBrwText
      ::RedisplayBreakpoints()               // check for breakpoints in this file and display them
      ::oWndCode:SetCaption( ::cPrgName )
      ::oWndCode:Refresh() // to force the window caption to update
   ENDIF

   ::oPullDown:GetItemByIdent( "PPO" ):checked := ::lPPO

   RETURN lSuccess


METHOD OSShell() CLASS HBDebugger

   LOCAL cImage := SaveScreen()
   LOCAL cColors := SetColor()
   LOCAL cOs := Upper( OS() )
   LOCAL cShell
   LOCAL bLastHandler := ErrorBlock( { | objErr | Break( objErr ) } )
   LOCAL oE

   SetColor( "W/N" )
   CLS
   ? "Type 'exit' to RETURN to the Debugger"
   SetCursor( SC_NORMAL )

   BEGIN SEQUENCE

      IF At( "WINDOWS", cOs ) != 0 .OR. At( "DOS", cOs ) != 0 .OR. At( "OS/2", cOs ) != 0
         cShell := GetEnv( "COMSPEC" )
         RUN ( cShell )
      ELSEIF At( "LINUX", cOs ) != 0 .OR. At( "BSD", cOs ) != 0 .OR. At( "DARWIN", cOs ) != 0
         cShell := GetEnv( "SHELL" )
         RUN ( cShell )
      ELSE
         Alert( "Not implemented yet!" )
      ENDIF

   RECOVER USING oE

      Alert( "Error: " + oE:description )

   END SEQUENCE

   ErrorBlock( bLastHandler )

   SetCursor( SC_NONE )
   RestScreen( ,,,, cImage )
   SetColor( cColors )

   RETURN NIL


METHOD Quit() CLASS HBDebugger

   ::Exit()
   ::Hide()
   hb_DBG_SetQuit( ::pInfo )
   s_oDebugger := NIL

   __QUIT()

   RETURN NIL


METHOD PathForFiles( cPathForFiles ) CLASS HBDebugger

   IF cPathForFiles == NIL
      cPathForFiles := ::InputBox( "Search path for source files:", ::cPathForFiles )
   ENDIF
   ::cPathForFiles := cPathForFiles
   ::aPathDirs := PathToArray( ::cPathForFiles )

   ::Resume()
   RETURN Self


METHOD PrevWindow() CLASS HBDebugger

   LOCAL oWnd

   IF Len( ::aWindows ) > 0

      oWnd := ::aWindows[ ::nCurrentWindow-- ]
      oWnd:Show( .F. )
      IF ::nCurrentWindow < 1
         ::nCurrentWindow := Len( ::aWindows )
      ENDIF
      DO WHILE ! ::aWindows[ ::nCurrentWindow ]:lVisible
         ::nCurrentWindow--
         IF ::nCurrentWindow < 1
            ::nCurrentWindow := Len( ::aWindows )
         ENDIF
      ENDDO
      oWnd := ::aWindows[ ::nCurrentWindow ]
      oWnd:Show( .T. )

   ENDIF

   RETURN NIL


METHOD Private() CLASS HBDebugger

   ::lShowPrivates := ! ::lShowPrivates
   ::RefreshVars()

   RETURN NIL


METHOD Public() CLASS HBDebugger

   ::lShowPublics := ! ::lShowPublics
   ::RefreshVars()

   RETURN NIL


// check for breakpoints in the current file and display them
METHOD RedisplayBreakPoints() CLASS HBDebugger

   LOCAL n

   FOR n := 1 TO Len( ::aBreakpoints )
      IF FILENAME_EQUAL( ::aBreakpoints[ n ][ 2 ], strip_path( ::cPrgName ) )
         ::oBrwText:ToggleBreakPoint( ::aBreakpoints[ n ][ 1 ], .T.)
      ENDIF
   NEXT

   RETURN NIL


METHOD RefreshVars() CLASS HBDebugger

   ::oPulldown:GetItemByIdent( "GLOBAL" ):checked := ::lShowGlobals
   ::oPulldown:GetItemByIdent( "LOCAL" ):checked := ::lShowLocals
   ::oPulldown:GetItemByIdent( "PRIVATE" ):checked := ::lShowPrivates
   ::oPulldown:GetItemByIdent( "PUBLIC" ):checked := ::lShowPublics
   ::oPulldown:GetItemByIdent( "STATIC" ):checked := ::lShowStatics
   ::oPulldown:GetItemByIdent( "ALL" ):checked := ::lAll
   ::oPulldown:GetItemByIdent( "SHOWALLGLOBALS" ):checked := ::lShowAllGlobals

   IF ::lActive
      IF ::lShowGlobals .OR. ::lShowPublics .OR. ::lShowPrivates .OR. ::lShowStatics .OR. ::lShowLocals
         ::LoadVars()
         ::ShowVars()
      ELSE
         ::HideVars()
      ENDIF
   ENDIF

   RETURN NIL


METHOD RemoveWindow( oWnd ) CLASS HBDebugger

   LOCAL n := AScan( ::aWindows, { | o | o == oWnd } )

   IF n != 0
      ::aWindows := ADel( ::aWindows, n )
      ::aWindows := ASize( ::aWindows, Len( ::aWindows ) - 1 )
   ENDIF

   ::nCurrentWindow := 1

   RETURN NIL


METHOD ResizeWindows( oWindow ) CLASS HBDebugger

   LOCAL oWindow2
   LOCAL nTop
   LOCAL lVisible2 := .F.

   IF oWindow == ::oWndVars
      oWindow2 := ::oWndPnt
   ELSEIF oWindow == ::oWndPnt
      oWindow2 := ::oWndVars
   ENDIF

   DispBegin()
   IF oWindow2 == NIL
      nTop := oWindow:nBottom + 1
   ELSE
      lVisible2 := oWindow2:lVisible
      IF oWindow2:lVisible
         IF oWindow:nTop < oWindow2:nTop
            nTop := oWindow2:nBottom - oWindow2:nTop + 1
            oWindow2:Resize( oWindow:nBottom + 1,, oWindow:nBottom + nTop )
         ELSE
            nTop := oWindow:nBottom - oWindow:nTop + 1
            oWindow:Resize( oWindow2:nBottom + 1,, oWindow2:nBottom + nTop )
         ENDIF
         nTop := Max( oWindow:nBottom, oWindow2:nBottom ) + 1
      ELSE
         IF oWindow:nTop > 1
            nTop := oWindow:nBottom - oWindow:nTop + 1
            oWindow:Resize( 1, NIL, nTop )
         ENDIF
         nTop := oWindow:nBottom + 1
      ENDIF
   ENDIF

   oWindow:hide()
   IF oWindow2 != NIL
      oWindow2:hide()
   ENDIF

   ::oWndCode:Resize( nTop )
   IF ::oWndCode:lFocused
      ::oWndCode:cargo[ 1 ] := Row()
      ::oWndCode:cargo[ 2 ] := Col()
   ENDIF

   IF oWindow2 != NIL .AND. lVisible2
      oWindow2:show()
   ENDIF
   oWindow:show()
   DispEnd()

   RETURN Self


METHOD RestoreAppScreen() CLASS HBDebugger

   LOCAL i

   ::CloseDebuggerWindow()

   FOR i := 1 TO ::nAppDispCount
      DispBegin()
   NEXT

   RETURN NIL


METHOD RestoreAppState() CLASS HBDebugger
   Set( _SET_DIRCASE, ::nAppDirCase )
   Set( _SET_FILECASE, ::nAppFileCase )
   Set( _SET_TYPEAHEAD, ::nAppTypeAhead )
   hb_SetLastKey( ::nAppLastKey )
#ifdef __XHARBOUR__
   SetInkeyAfterBlock( ::bAppInkeyAfter )
   SetInkeyBeforeBlock( ::bAppInkeyBefore )
   __SetClassScope( ::bAppClassScope )
#endif
   __GetListSetActive( ::oAppGetList )
   RETURN NIL


METHOD RestoreSettings() CLASS HBDebugger

   ::cSettingsFileName := ::InputBox( "File name", ::cSettingsFileName )

   IF LastKey() != K_ESC
      ::LoadSettings()
      ::ShowVars()
   ENDIF

   RETURN NIL


METHOD SaveAppScreen() CLASS HBDebugger

   LOCAL nRight
   LOCAL nTop
   LOCAL i
  
   ::nAppDispCount := DispCount()
   FOR i := 1 TO ::nAppDispCount
      DispEnd()
   NEXT
  
   ::OpenDebuggerWindow()
  
   IF ::nMaxRow != MaxRow() .OR. ::nMaxCol != MaxCol()
      DispBegin()
      ::nMaxRow := MaxRow()
      ::nMaxCol := MaxCol()
      nTop := 1
      nRight := ::nMaxCol
      ::oWndCommand:Resize( ::nMaxRow - 5, 0, ::nMaxRow - 1, ::nMaxCol )
      ::oGetListCommand:Get():Row := ::oWndCommand:nBottom - 1
      ::oGetListCommand:Get():Col := ::oWndCommand:nLeft + 3
      ::oBrwStack:nTop := 2
      ::oBrwStack:nLeft := ::nMaxCol - 14
      ::oBrwStack:nRight := ::nMaxCol - 1
      ::oBrwStack:nBottom := ::nMaxRow - 7
      IF ::oWndStack != NIL
         nRight -= 16
         ::oWndStack:Resize( , nRight + 1, ::nMaxRow - 6, ::nMaxCol )
      ENDIF
      IF ::oWndVars != NIL
         ::oWndVars:Resize( , , , nRight )
         nTop := Max( nTop, ::oWndVars:nBottom + 1 )
      ENDIF
      IF ::oWndPnt != NIL
         ::oWndPnt:Resize( , , , nRight )
         nTop := Max( nTop, ::oWndPnt:nBottom + 1 )
      ENDIF
      ::oWndCode:Resize( nTop, 0, ::nMaxRow - 6, nRight )
      ::oPullDown:Refresh()
      ::BarDisplay()
      DispEnd()
   ENDIF
   RETURN NIL


METHOD SaveAppState() CLASS HBDebugger
   ::nAppDirCase := Set( _SET_DIRCASE, 0 )
   ::nAppFileCase := Set( _SET_FILECASE, 0 )
   ::nAppTypeAhead := Set( _SET_TYPEAHEAD, 16 )
   ::nAppLastKey := LastKey()
#ifdef __XHARBOUR__
   ::bAppInkeyAfter := SetInkeyAfterBlock( NIL )
   ::bAppInkeyBefore := SetInkeyBeforeBlock( NIL )
   ::bAppClassScope := __SetClassScope( .F. )
#endif
   ::oAppGetList := __GetListActive()
   RETURN NIL


METHOD SaveSettings() CLASS HBDebugger

   LOCAL cInfo := ""
   LOCAL n
   LOCAL oWnd

   ::cSettingsFileName := ::InputBox( "File name", ::cSettingsFileName )

   IF LastKey() != K_ESC

      IF ! Empty( ::cPathForFiles )
         cInfo += "Options Path " + ::cPathForFiles + hb_OSNewLine()
      ENDIF

      cInfo += "Options Colors {"
      FOR n := 1 TO Len( ::aColors )
         cInfo += '"' + ::aColors[ n ] + '"'
         IF n < Len( ::aColors )
            cInfo += ","
         ENDIF
      NEXT
      cInfo += "}" + hb_OSNewLine()

      IF ::lMonoDisplay
         cInfo += "Options mono " + hb_OSNewLine()
      ENDIF

      IF !::lRunAtStartup
         cInfo += "Options NoRunAtStartup " + hb_OSNewLine()
      ENDIF

      IF ::nSpeed != 0
         cInfo += "Run Speed " + LTrim( Str( ::nSpeed ) ) + hb_OSNewLine()
      ENDIF

      IF ::nTabWidth != 4
         cInfo += "Options Tab " + LTrim( Str( ::nTabWidth ) ) + hb_OSNewLine()
      ENDIF

      IF ::lShowStatics
         cInfo += "Monitor Static" + hb_OSNewLine()
      ENDIF

      IF ::lShowPublics
         cInfo += "Monitor Public" + hb_OSNewLine()
      ENDIF

      IF ::lShowLocals
         cInfo += "Monitor Local" + hb_OSNewLine()
      ENDIF

      IF ::lShowPrivates
         cInfo += "Monitor Private" + hb_OSNewLine()
      ENDIF

      IF ::lShowGlobals
         cInfo += "Monitor Global" + hb_OSNewLine()
      ENDIF

      IF ::lSortVars
         cInfo += "Monitor Sort" + hb_OSNewLine()
      ENDIF

      IF ::lShowCallStack
         cInfo += "View CallStack" + hb_OSNewLine()
      ENDIF

      IF ! ::lLineNumbers
         cInfo += "Num Off" + hb_OSNewLine()
      ENDIF

      IF ! Empty( ::aBreakPoints )
         FOR n := 1 TO Len( ::aBreakPoints )
            cInfo += "BP " + LTrim( Str( ::aBreakPoints[ n ][ 1 ] ) ) + " " + ;
                     AllTrim( ::aBreakPoints[ n ][ 2 ] ) + hb_OSNewLine()
         NEXT
      ENDIF

      /* This part of the script must be executed after all windows are created */
      FOR n := 1 TO Len( ::aWindows )
         oWnd := ::aWindows[ n ]
         cInfo += "Window Size " + LTrim( Str( oWnd:nBottom - oWnd:nTop + 1 ) ) + " "
         cInfo += LTrim( Str( oWnd:nRight - oWnd:nLeft + 1 ) ) + hb_OSNewLine()
         cInfo += "Window Move " + LTrim( Str( oWnd:nTop ) ) + " "
         cInfo += LTrim( Str( oWnd:nLeft ) ) + hb_OSNewLine()
         cInfo += "Window Next" + hb_OSNewLine()
      NEXT

      MemoWrit( ::cSettingsFileName, cInfo )
   ENDIF

   RETURN NIL


METHOD SearchLine() CLASS HBDebugger

   LOCAL cLine := ::InputBox( "Line number", "1" )

   IF Val( cLine ) > 0
      ::GotoLine ( Val( cLine ) )
   ENDIF

   RETURN NIL


METHOD Show() CLASS HBDebugger

   ::SaveAppScreen()
   ::oPullDown:Display()
   ::oWndCode:Show( .T. )
   ::oWndCommand:Show()
   DispOutAt( ::oWndCommand:nBottom - 1, ::oWndCommand:nLeft + 1, ">" )

   ::BarDisplay()

   RETURN NIL


METHOD ShowAllGlobals() CLASS HBDebugger

   ::lShowAllGlobals := ! ::lShowAllGlobals
   ::RefreshVars()

   RETURN NIL


METHOD ShowAppScreen() CLASS HBDebugger

   ::CloseDebuggerWindow()

   IF LastKey() == K_LBUTTONDOWN
      Inkey( 0, INKEY_ALL )
   ENDIF
   DO WHILE Inkey( 0, INKEY_ALL ) == K_MOUSEMOVE
   ENDDO

   ::OpenDebuggerWindow()

   RETURN NIL


METHOD ShowCallStack() CLASS HBDebugger

   ::lShowCallStack := .T.

   IF ::oWndStack == NIL

      SetCursor( SC_NONE )

      DispBegin()
      // Resize code window
      ::oWndCode:Resize(,,, ::oWndCode:nRight - 16 )
      // Resize vars window
      IF ::oWndVars != NIL
         ::oWndVars:Resize(,,, ::oWndVars:nRight - 16 )
      ENDIF
      // Resize watchpoints window
      IF ::oWndPnt != NIL
         ::oWndPnt:Resize(,,, ::oWndPnt:nRight - 16)
      ENDIF
      DispEnd()

      IF ::aWindows[ ::nCurrentWindow ]:lFocused
         ::aWindows[ ::nCurrentWindow ]:Show( .F. )
      ENDIF

      ::oWndStack := HBDbWindow():New( 1, ::nMaxCol - 15, ::nMaxRow - 6, ::nMaxCol,;
                                     "Calls" )
      ::oWndStack:bKeyPressed  := { | nKey | ::CallStackProcessKey( nKey ) }
      ::oWndStack:bLButtonDown := { || ::CallStackProcessKey( K_LBUTTONDOWN ) }

      AAdd( ::aWindows, ::oWndStack )
      //::nCurrentWindow := Len( ::aWindows )

      IF ::oBrwStack == NIL
         ::BuildBrowseStack()
      ENDIF

      ::oWndStack:bPainted := { || ::oBrwStack:ColorSpec := __DbgColors()[ 2 ] + "," + ;
                                  __DbgColors()[ 5 ] + "," + __DbgColors()[ 4 ],;
                                  ::oBrwStack:RefreshAll(), ::oBrwStack:ForceStable() }
      ::oWndStack:bGotFocus := { || SetCursor( SC_NONE ) }

      ::oWndStack:Show( .F. )
   ENDIF

   RETURN NIL


METHOD ShowCodeLine( nProc ) CLASS HBDebugger

   LOCAL cDir
   LOCAL cName
   LOCAL nLine
   LOCAL cPrgName

   // we only update the stack window and up a new browse
   // to view the code if we have just broken execution
   IF !::lGo
      IF ::oWndStack != NIL
         ::oBrwStack:RefreshAll()
      ENDIF

      nLine := ::aProcStack[ nProc ][ CSTACK_LINE ]
      cPrgName := ::aProcStack[ nProc ][ CSTACK_MODULE ]
      IF nLine == NIL
         ::oBrwText := NIL
         ::oWndCode:Browser := NIL
         ::oWndCode:SetCaption( ::aProcStack[ nProc ][ CSTACK_FUNCTION ] +;
                                ": Code not available" )
         ::oWndCode:Refresh() // to force the window caption to update
         RETURN NIL
      ENDIF

      IF ::lPPO
         hb_FNameSplit( cPrgName, @cDir, @cName, NIL )
         cPrgName := hb_FNameMerge( cDir, cName, ".ppo" )
      ENDIF

      IF ! Empty( cPrgName )

         IF !FILENAME_EQUAL( strip_path( cPrgName ), strip_path( ::cPrgName ) ) ;
              .OR. ::oBrwText == NIL

            IF ! File( cPrgName ) .AND. !Empty( ::cPathForFiles )
               cPrgName := ::LocatePrgPath( cPrgName )
            ENDIF

            ::cPrgName := cPrgName

            IF !File( cPrgName )
               ::oBrwText := NIL
               ::oWndCode:Browser := NIL
               ::oWndCode:SetCaption( ::aProcStack[ nProc ][ CSTACK_MODULE ] + ;
                                     "  File not found" )
               ::oWndCode:Refresh()
               RETURN NIL
            ENDIF

            IF ::oBrwText == NIL
               ::oBrwText := HBBrwText():New( ::oWndCode:nTop + 1, ::oWndCode:nLeft + 1,;
                                              ::oWndCode:nBottom - 1, ::oWndCode:nRight - 1, cPrgName,;
                                              __DbgColors()[ 2 ] + "," + __DbgColors()[ 5 ] + "," + ;
                                              __DbgColors()[ 3 ] + "," + __DbgColors()[ 6 ], ;
                                              ::lLineNumbers, ::nTabWidth )

               ::oWndCode:Browser := ::oBrwText

            ELSE
               ::oBrwText:LoadFile(cPrgName)
            ENDIF

            ::oWndCode:bPainted := { || iif( ::oBrwText != NIL, ::oBrwText:RefreshAll():ForceStable(), ::oWndCode:Clear() ) }
            ::RedisplayBreakpoints()               // check for breakpoints in this file and display them
            ::oWndCode:SetCaption( ::cPrgName )
            ::oWndCode:Refresh()       // to force the window caption to update
         ENDIF
         ::oBrwText:SetActiveLine( nLine )
         ::GotoLine( nLine )
      ENDIF

   ENDIF

   RETURN NIL


METHOD ShowHelp( nTopic ) CLASS HBDebugger

   LOCAL nCursor := SetCursor( SC_NONE )

   __dbgHelp( nTopic )
   SetCursor( nCursor )

   RETURN NIL


#define MAX_VARS_HEIGHT 7

METHOD ShowVars() CLASS HBDebugger

   LOCAL nWidth
   LOCAL oCol
   LOCAL lRepaint := .F.
   LOCAL nTop
   LOCAL nBottom
   LOCAL lWindowCreated := .F.

   IF ::lGo
      RETURN NIL
   ENDIF

   IF ! ( ::lShowLocals .OR. ::lShowStatics .OR. ::lShowPrivates .OR. ;
          ::lShowPublics .OR. ::lShowGlobals )
      RETURN NIL
   ENDIF

   DispBegin()

   IF ::oWndVars == NIL

      nTop := iif( ::oWndPnt != NIL .AND. ::oWndPnt:lVisible, ::oWndPnt:nBottom + 1,1)
      nBottom := nTop + Min( MAX_VARS_HEIGHT, Len( ::aVars ) + 1 )

      ::oWndVars := HBDbWindow():New( nTop, 0, nBottom,;
         ::nMaxCol - iif( ::oWndStack != NIL, ::oWndStack:nWidth(), 0 ),;
         "Monitor:" + ;
         iif( ::lShowGlobals, " Global", "" ) + iif( ::lShowLocals, " Local", "" ) + ;
         iif( ::lShowStatics, " Static", "" ) + iif( ::lShowPrivates, " Private", "" ) + ;
         iif( ::lShowPublics, " Public", "" ) )

      ::oWndVars:bLButtonDown := { | nMRow, nMCol | ::WndVarsLButtonDown( nMRow, nMCol ) }
      ::oWndVars:bLDblClick   := { || ::EditVar( ::oBrwVars:Cargo[ 1 ] ) }
      ::oWndVars:bPainted     := { || iif(Len( ::aVars ) > 0, ( ::oBrwVars:RefreshAll():ForceStable(),RefreshVarsS(::oBrwVars) ),) }

      ::oWndVars:bKeyPressed := { | nKey | iif( Len( ::aVars ) == 0, NIL, ( ;
      iif( nKey == K_DOWN, ::oBrwVars:Down(), NIL ) ;
      , iif( nKey == K_UP, ::oBrwVars:Up(), NIL ) ;
      , iif( nKey == K_PGDN, ::oBrwVars:PageDown(), NIL ) ;
      , iif( nKey == K_PGUP, ::oBrwVars:PageUp(), NIL ) ;
      , iif( nKey == K_HOME, ::oBrwVars:GoTop(), NIL ) ;
      , iif( nKey == K_END, ::oBrwVars:GoBottom(), NIL ) ;
      , iif( nKey == K_ENTER, ::EditVar( ::oBrwVars:Cargo[ 1 ] ), NIL ), ;
      iif(Len(::aVars)>0, ::oBrwVars:ForceStable(), NIL) ) ) }

      AAdd( ::aWindows, ::oWndVars )
      lWindowCreated := .T.
   ELSE

      nTop := ::oWndVars:nTop
      ::oWndVars:cCaption := "Monitor:" + ;
      iif( ::lShowGlobals, " Global", "" ) + ;
      iif( ::lShowLocals, " Local", "" ) + ;
      iif( ::lShowStatics, " Static", "" ) + ;
      iif( ::lShowPrivates, " Private", "" ) + ;
      iif( ::lShowPublics, " Public", "" )

      nBottom := ::oWndVars:nBottom
      IF Len( ::aVars ) == 0
         IF ::oWndVars:nBottom - ::oWndVars:nTop > 1
            nBottom := nTop + 1
         ENDIF
      ELSEIF Len( ::aVars ) > ::oWndVars:nBottom - ::oWndVars:nTop - 1
         nBottom := nTop + Min( Len( ::aVars ) + 1, MAX_VARS_HEIGHT )
      ELSEIF Len( ::aVars ) < ::oWndVars:nBottom - ::oWndVars:nTop - 1
         nBottom := nTop + Len( ::aVars ) + 1
      ELSE
         nBottom := ::oWndVars:nBottom
      ENDIF
   ENDIF

   IF Len( ::aVars ) > 0 .AND. ::oBrwVars == NIL
      ::oBrwVars := HBDbBrowser():New( nTop + 1, 1, nBottom - 1, ;
                                       ::nMaxCol - iif( ::oWndStack != NIL, ::oWndStack:nWidth(), 0 ) - 1 )

      ::oBrwVars:Cargo := { 1, {} } // Actual highlighted row
      ::oBrwVars:ColorSpec := ::aColors[ 2 ] + "," + ::aColors[ 5 ] + "," + ::aColors[ 3 ]
      ::oBrwVars:goTopBlock := { || ::oBrwVars:cargo[ 1 ] := Min( 1, Len( ::aVars ) ) }
      ::oBrwVars:goBottomBlock := { || ::oBrwVars:cargo[ 1 ] := Max( 1, Len( ::aVars ) ) }
      ::oBrwVars:skipBlock := { | nSkip, nOld | ;
                               nOld := ::oBrwVars:Cargo[ 1 ],;
                               ::oBrwVars:Cargo[ 1 ] += nSkip,;
                               ::oBrwVars:Cargo[ 1 ] := Min( Max( ::oBrwVars:Cargo[ 1 ], 1 ), Len( ::aVars ) ),;
                               ::oBrwVars:Cargo[ 1 ] - nOld }

      nWidth := ::oWndVars:nWidth() - 1
      oCol := TBColumnNew( "", ;
           { || PadR( LTrim( Str( ::oBrwVars:Cargo[ 1 ] - 1 ) ) + ") " + ;
                      ::VarGetInfo( ::aVars[ Max( ::oBrwVars:Cargo[ 1 ], 1 ) ] ), ;
                      ::oWndVars:nWidth() - 2 ) } )
      ::oBrwVars:AddColumn( oCol )
      AAdd( ::oBrwVars:Cargo[ 2 ], ::aVars )
      oCol:DefColor := { 1, 2 }
      ::oBrwVars:ForceStable()
   ELSEIF Len( ::aVars ) == 0
      ::oBrwVars := NIL
      ::oWndVars:Browser := NIL
   ENDIF

   ::oWndVars:Browser := ::oBrwVars

   IF lWindowCreated
      ::oWndVars:Show()
      ::ResizeWindows( ::oWndVars )

   ELSE

      IF ::oBrwVars != NIL
         IF ::oBrwVars:cargo[ 1 ] <= 0
            ::oBrwVars:cargo[ 1 ] := 1
         ENDIF
      ENDIF

      IF Len( ::aVars ) == 0
         IF nBottom == ::oWndVars:nBottom
            /* We still need to redraw window caption, it could have changed */
            ::oWndVars:Refresh()
         ENDIF
      ENDIF
      IF nBottom != ::oWndVars:nBottom
         ::oWndVars:Resize( ,, nBottom )
         lRepaint := .T.
      ELSE
         IF ::oBrwVars != NIL
           ::oBrwVars:RefreshAll():ForceStable()
         ENDIF
         ::oWndVars:Refresh()
      ENDIF
      IF ! ::oWndVars:lVisible .OR. lRepaint
         ::ResizeWindows( ::oWndVars )
      ENDIF
   ENDIF

   DispEnd()

   RETURN NIL


METHOD Stack() CLASS HBDebugger

   ::lShowCallStack := ! ::lShowCallStack
   ::oPulldown:GetItemByIdent( "CALLSTACK" ):checked := ::lShowCallStack

   IF ::lActive
      IF ::lShowCallStack
         ::ShowCallStack()
      ELSE
         ::HideCallStack()
      ENDIF
   ENDIF

   RETURN NIL


METHOD Static() CLASS HBDebugger

   ::lShowStatics := ! ::lShowStatics
   ::RefreshVars()

   RETURN NIL


METHOD Step() CLASS HBDebugger

   // we are starting to run again so reset to the deepest call if displaying stack
   IF ! ::oBrwStack == NIL
      ::oBrwStack:GoTop()
   ENDIF

   ::RestoreAppScreen()
   ::RestoreAppState()
   ::Exit()

   RETURN NIL


METHOD ToCursor() CLASS HBDebugger

   IF ::IsValidStopLine( strip_path( ::cPrgName ), ::oBrwText:RowPos() )
      hb_DBG_SetToCursor( ::pInfo, strip_path( ::cPrgName ), ::oBrwText:RowPos() )
      ::RestoreAppScreen()
      ::RestoreAppState()
      ::Exit()
   ENDIF

   RETURN Self


// Toggle a breakpoint at the cursor position in the currently viewed file
// which may be different from the file in which execution was broken
METHOD ToggleBreakPoint( nLine, cFileName ) CLASS HBDebugger

   // look for a breakpoint which matches both line number and program name

   LOCAL nAt

   IF !::lActive
      RETURN NIL
   ENDIF

   IF nLine == NIL
      cFileName := strip_path( ::cPrgName )
      nLine := ::oBrwText:RowPos()
   ENDIF

   IF !::IsValidStopLine( cFileName, nLine )
      RETURN NIL
   ENDIF

   nAt := AScan( ::aBreakPoints, { | aBreak | aBreak[ 1 ] == nLine ;
                                     .AND. FILENAME_EQUAL( aBreak[ 2 ], cFileName ) } )

   IF nAt == 0
      AAdd( ::aBreakPoints, { nLine, cFileName } )     // it was nLine
      hb_DBG_AddBreak( ::pInfo, cFileName, nLine )
      IF FILENAME_EQUAL( cFileName, strip_path( ::cPrgName ) )
         ::oBrwText:ToggleBreakPoint( nLine, .T. )
      ENDIF
   ELSE
      ADel( ::aBreakPoints, nAt )
      ASize( ::aBreakPoints, Len( ::aBreakPoints ) - 1 )
      hb_DBG_DelBreak( ::pInfo, nAt - 1 )
      IF FILENAME_EQUAL( cFileName, strip_path( ::cPrgName ) )
         ::oBrwText:ToggleBreakPoint( nLine, .F. )
      ENDIF
   ENDIF

   ::oBrwText:RefreshCurrent()

   RETURN NIL


METHOD Trace() CLASS HBDebugger

   hb_DBG_SetTrace( ::pInfo )
   ::Step() //forces a Step()

   RETURN Self


METHOD TracepointAdd( cExpr ) CLASS HBDebugger

   LOCAL aWatch

   IF cExpr == NIL
      cExpr := Space( 255 )
      cExpr := AllTrim( ::InputBox( "Enter Tracepoint", cExpr ) )
      IF LastKey() == K_ESC
         RETURN Self
      ENDIF
   ENDIF
   cExpr := AllTrim( cExpr )
   IF Empty( cExpr )
      RETURN Self
   ENDIF
   aWatch := { "tp", cExpr, NIL }
   ::RestoreAppState()
   hb_DBG_AddWatch( ::pInfo, cExpr, .T. )
   ::SaveAppState()
   AAdd( ::aWatch, aWatch )
   ::WatchpointsShow()

   RETURN Self


METHOD VarGetInfo( aVar ) CLASS HBDebugger

   LOCAL cType := Left( aVar[ VAR_TYPE ], 1 )
   LOCAL uValue := ::VarGetValue( aVar )

   DO CASE
   CASE cType == "G" ; RETURN aVar[ VAR_NAME ] + " <Global, " + ValType( uValue ) + ">: " + __dbgValToStr( uValue )
   CASE cType == "L" ; RETURN aVar[ VAR_NAME ] + " <Local, " + ValType( uValue ) + ">: " + __dbgValToStr( uValue )
   CASE cType == "S" ; RETURN aVar[ VAR_NAME ] + " <Static, " + ValType( uValue ) + ">: " + __dbgValToStr( uValue )
   OTHERWISE         ; RETURN aVar[ VAR_NAME ] + " <" + aVar[ VAR_TYPE ] + ", " + ValType( uValue ) + ">: " + __dbgValToStr( uValue )
   ENDCASE

   // ; Never reached

   RETURN ""


METHOD VarGetValue( aVar ) CLASS HBDebugger

   LOCAL cType := Left( aVar[ VAR_TYPE ], 1 )

   DO CASE
   CASE cType == "G" ; RETURN hb_dbg_vmVarGGet( aVar[ VAR_LEVEL ], aVar[ VAR_POS ] )
   CASE cType == "L" ; RETURN hb_dbg_vmVarLGet( hb_dbg_procLevel() - aVar[ VAR_LEVEL ], aVar[ VAR_POS ] )
   CASE cType == "S" ; RETURN hb_dbg_vmVarSGet( aVar[ VAR_LEVEL ], aVar[ VAR_POS ] )
   OTHERWISE         ; RETURN aVar[ VAR_POS ] // Public or Private
   ENDCASE

   // ; Never reached

   RETURN NIL


METHOD VarSetValue( aVar, uValue ) CLASS HBDebugger

   LOCAL nProcLevel
   LOCAL cType := Left( aVar[ VAR_TYPE ], 1 )

   IF cType == "G"
     hb_dbg_vmVarGSet( aVar[ VAR_LEVEL ], aVar[ VAR_POS ], uValue )

   ELSEIF cType == "L"
     nProcLevel := hb_dbg_procLevel() - aVar[ VAR_LEVEL ]   //skip debugger stack
     hb_dbg_vmVarLSet( nProcLevel, aVar[ VAR_POS ], uValue )

   ELSEIF cType == "S"
     hb_dbg_vmVarSSet( aVar[ VAR_LEVEL ], aVar[ VAR_POS ], uValue )

   ELSE
     // Public or Private
     aVar[ VAR_POS ] := uValue
     &( aVar[ VAR_NAME ] ) := uValue

   ENDIF

   RETURN Self


METHOD ViewSets() CLASS HBDebugger

   LOCAL oWndSets := HBDbWindow():New( 1, 8, ::nMaxRow - 2, ::nMaxCol - 8,;
                                      "System Settings[1..47]", ::ClrModal() )
   LOCAL aSets := { "Exact", "Fixed", "Decimals", "DateFormat", "Epoch", "Path",;
                    "Default", "Exclusive", "SoftSeek", "Unique", "Deleted",;
                    "Cancel", "Debug", "TypeAhead", "Color", "Cursor", "Console",;
                    "Alternate", "AltFile", "Device", "Extra", "ExtraFile",;
                    "Printer", "PrintFile", "Margin", "Bell", "Confirm", "Escape",;
                    "Insert", "Exit", "Intensity", "ScoreBoard", "Delimeters",;
                    "DelimChars", "Wrap", "Message", "MCenter", "ScrollBreak",;
                    "EventMask", "VideoMode", "MBlockSize", "MFileExt",;
                    "StrictRead", "Optimize", "Autopen", "Autorder", "AutoShare" }

   LOCAL oBrwSets := HBDbBrowser():new( oWndSets:nTop + 1, oWndSets:nLeft + 1,;
                                        oWndSets:nBottom - 1, oWndSets:nRight - 1 )
   LOCAL nWidth := oWndSets:nRight - oWndSets:nLeft - 1
   LOCAL oCol

   oBrwSets:Cargo := { 1, {} } // Actual highlighted row
   oBrwSets:autolite := .F.
   oBrwSets:ColorSpec := ::ClrModal()
   oBrwSets:goTopBlock := { || oBrwSets:cargo[ 1 ] := 1 }
   oBrwSets:goBottomBlock := { || oBrwSets:cargo[ 1 ] := Len( oBrwSets:cargo[ 2 ][ 1 ] ) }
   oBrwSets:skipBlock := { | nPos | ( nPos := ArrayBrowseSkip( nPos, oBrwSets ), oBrwSets:cargo[ 1 ] := ;
   oBrwSets:cargo[ 1 ] + nPos, nPos ) }
   oBrwSets:AddColumn( oCol := TBColumnNew( "", { || PadR( aSets[ oBrwSets:cargo[ 1 ] ], 12 ) } ) )
   AAdd( oBrwSets:Cargo[ 2 ], aSets )
   ocol:defcolor := { 1, 2 }
   oBrwSets:AddColumn( oCol := TBColumnNew( "",;
                       { || PadR( __dbgValToStr( Set( oBrwSets:cargo[ 1 ]  ) ), nWidth - 13 ) } ) )
   ocol:defcolor := { 1, 3 }
   ocol:width := 40
   oWndSets:bPainted := { || oBrwSets:ForceStable(), RefreshVarsS( oBrwSets ) }
   oWndSets:bKeyPressed := { | nKey | SetsKeyPressed( nKey, oBrwSets, Len( aSets ),;
                            oWndSets, "System Settings",;
                            { || ::EditSet( oBrwSets:Cargo[ 1 ], oBrwSets ) } ) }

   SetCursor( SC_NONE )
   oWndSets:ShowModal()

   RETURN NIL


METHOD WatchGetInfo( nWatch ) CLASS HBDebugger

   LOCAL xVal
   LOCAL cType
   LOCAL lValid
   LOCAL aWatch := ::aWatch[ nWatch ]

   ::RestoreAppState()
   xVal := ::GetExprValue( nWatch, @lValid )
   ::SaveAppState()

   IF lValid
      cType := ValType( xVal )
      xVal  := __dbgValToStr( xVal )
   ELSE
      // xVal contains error description
      cType := "U"
      // xVal := "Undefined"
   ENDIF

   RETURN aWatch[ WP_EXPR ] + " <" + aWatch[ WP_TYPE ] + ", " + cType + ">: " + xVal


METHOD WatchpointAdd( cExpr ) CLASS HBDebugger

   LOCAL aWatch

   IF cExpr == NIL

      cExpr := Space( 255 )
      cExpr := AllTrim( ::InputBox( "Enter Watchpoint", cExpr ) )

      IF LastKey() == K_ESC
         RETURN Self
      ENDIF
   ENDIF

   cExpr := AllTrim( cExpr )

   IF Empty( cExpr )
      RETURN Self
   ENDIF

   aWatch := { "wp", cExpr }
   hb_DBG_AddWatch( ::pInfo, cExpr, .F. )
   AAdd( ::aWatch, aWatch )
   ::WatchpointsShow()

   RETURN Self


METHOD WatchpointDel( nPos ) CLASS HBDebugger

   IF ::oWndPnt != NIL .AND. ::oWndPnt:lVisible
      IF nPos == NIL
         // called from the menu
         nPos := ::InputBox( "Enter item number to delete", ::oBrwPnt:cargo[ 1 ] - 1 )
      ELSE
         nPos--
      ENDIF
      IF LastKey() != K_ESC
         IF nPos >=0 .AND. nPos < Len( ::aWatch )
            ::oBrwPnt:gotop()
            hb_DBG_DelWatch( ::pInfo, nPos )
            ADel( ::aWatch, nPos + 1 )
            ASize( ::aWatch, Len( ::aWatch ) - 1 )
            IF Len( ::aWatch ) == 0
               ::WatchpointsHide()
            ELSE
               ::WatchpointsShow()
            ENDIF
         ENDIF
      ENDIF
   ENDIF

   RETURN Self


METHOD WatchpointEdit( nPos ) CLASS HBDebugger

   LOCAL cExpr
   LOCAL aWatch

   cExpr := PadR( ::aWatch[ nPos ][ WP_EXPR ], 255 )
   cExpr := AllTrim( ::InputBox( "Enter Watchpoint", cExpr ) )

   IF LastKey() == K_ESC
      RETURN Self
   ENDIF

   cExpr := AllTrim( cExpr )

   IF Empty( cExpr )
      RETURN Self
   ENDIF

   aWatch := { "wp", cExpr }

   hb_DBG_SetWatch( ::pInfo, nPos - 1, cExpr, .F. )
   ::aWatch[ nPos ] := aWatch
   ::WatchpointsShow()

   RETURN Self


METHOD WatchpointInspect( nPos ) CLASS HBDebugger

   LOCAL xValue
   LOCAL lValid

   ::RestoreAppState()
   xValue := ::GetExprValue( ::aWatch[ nPos ][ WP_EXPR ], @lValid )
   ::SaveAppState()

   ::InputBox( ::aWatch[ nPos ][ WP_EXPR ], xValue, NIL, .F. )
   ::RefreshVars()

   RETURN Self


METHOD WatchpointsHide() CLASS HBDebugger

   ::oWndPnt:Hide()
   ::oWndCode:nTop := iif( ::oWndVars != NIL .AND. ::oWndVars:lVisible, ::oWndVars:nBottom + 1, 1 )
   ::oBrwText:Resize( ::oWndCode:nTop + 1 )
   IF ::aWindows[ ::nCurrentWindow ] == ::oWndPnt
      ::NextWindow()
   ENDIF

   RETURN NIL


METHOD WatchpointsShow() CLASS HBDebugger

   LOCAL nWidth
   LOCAL oCol
   LOCAL lRepaint := .F.
   LOCAL nTop

   IF ::lGo
      RETURN NIL
   ENDIF

   IF Len( ::aWatch ) == 0
      RETURN NIL
   ENDIF

   IF ::oWndPnt == NIL

      nTop := iif( ::oWndVars != NIL .AND. ::oWndVars:lVisible, ::oWndVars:nBottom, 0 ) + 1

      ::oWndPnt := HBDbWindow():New( nTop,;
         0, ;
         nTop + Min( 4, Len( ::aWatch ) ) + 1,;
         ::nMaxCol - iif( ::oWndStack != NIL, ::oWndStack:nWidth(), 0 ),;
         "Watch" )

//      ::oBrwText:Resize( ::oWndPnt:nBottom + 1 )
//      ::oWndCode:nTop := ::oWndPnt:nBottom + 1
//      ::oBrwText:Resize( ::oWndCode:nTop + 1 )
//      ::oBrwText:RefreshAll()
//      ::oWndCode:SetFocus( .T. )

//      ::oWndPnt:bLButtonDown := { | nMRow, nMCol | ::WndVarsLButtonDown( nMRow, nMCol ) }
//      ::oWndPnt:bLDblClick   := { | nMRow, nMCol | ::EditVar( ::oBrwPnt:Cargo[ 1 ] ) }

      ::oBrwPnt := HBDbBrowser():New( nTop + 1, 1, ::oWndPnt:nBottom - 1, ::nMaxCol - iif( ::oWndStack != NIL,;
                               ::oWndStack:nWidth(), 0 ) - 1 )

      ::oWndPnt:Browser := ::oBrwPnt

      ::oBrwPnt:Cargo := { 1, {} } // Actual highlighted row
      ::oBrwPnt:ColorSpec := ::aColors[ 2 ] + "," + ::aColors[ 5 ] + "," + ::aColors[ 3 ]
      ::oBrwPnt:goTopBlock := { || ::oBrwPnt:cargo[ 1 ] := Min( 1, Len(::aWatch ) ) }
      ::oBrwPnt:goBottomBlock := { || ::oBrwPnt:cargo[ 1 ] := Len( ::aWatch ) }
      ::oBrwPnt:skipBlock := { | nSkip, nOld | nOld := ::oBrwPnt:Cargo[ 1 ],;
                               ::oBrwPnt:Cargo[ 1 ] += nSkip,;
                               ::oBrwPnt:Cargo[ 1 ] := Min( Max( ::oBrwPnt:Cargo[ 1 ], 1 ),;
                                                             Len( ::aWatch ) ),;
                               iif( Len(::aWatch) > 0, ::oBrwPnt:Cargo[ 1 ] - nOld, 0 ) }

      nWidth := ::oWndPnt:nWidth() - 1
      oCol := TBColumnNew( "", ;
         { || PadR( iif( Len( ::aWatch ) > 0, ;
                       LTrim( Str( ::oBrwPnt:Cargo[ 1 ] - 1 ) ) + ") " + ;
                       ::WatchGetInfo( Max( ::oBrwPnt:Cargo[ 1 ], 1 ) ), ;
                       " " ), ;
                   ::oWndPnt:nWidth() - 2 ) } )
      ::oBrwPnt:AddColumn( oCol )
      AAdd( ::oBrwPnt:Cargo[ 2 ], ::aWatch)
      oCol:DefColor := { 1, 2 }

      ::oWndPnt:bPainted := { || iif( Len( ::aWatch ) > 0, ( ::oBrwPnt:RefreshAll():ForceStable(), RefreshVarsS( ::oBrwPnt ) /*, ::RefreshVars()*/ ) , ) }

      ::oWndPnt:bKeyPressed := { | nKey | ;
      ( iif( nKey == K_DOWN, ::oBrwPnt:Down(), NIL ) ;
      , iif( nKey == K_UP, ::oBrwPnt:Up(), NIL ) ;
      , iif( nKey == K_PGDN, ::oBrwPnt:PageDown(), NIL ) ;
      , iif( nKey == K_PGUP, ::oBrwPnt:PageUp(), NIL ) ;
      , iif( nKey == K_HOME, ::oBrwPnt:GoTop(), NIL ) ;
      , iif( nKey == K_END, ::oBrwPnt:GoBottom(), NIL ) ;
      , iif( nKey == K_DEL, ::WatchpointDel( ::oBrwPnt:Cargo[ 1 ] ), NIL ) ;
      , iif( nKey == K_ENTER, ::WatchpointEdit( ::oBrwPnt:Cargo[ 1 ] ), NIL ) ;
      , iif( nKey == K_CTRL_ENTER, ::WatchpointInspect( ::oBrwPnt:Cargo[ 1 ] ), NIL ) ;
      , ::oBrwPnt:ForceStable() ) }

      AAdd( ::aWindows, ::oWndPnt )
      ::oWndPnt:Show()
      ::ResizeWindows( ::oWndPnt )
   ELSE
      IF ::oBrwPnt:cargo[ 1 ] <= 0
         ::oBrwPnt:cargo[ 1 ] := 1
      ENDIF
      DispBegin()
      IF Len( ::aWatch ) > ::oWndPnt:nBottom - ::oWndPnt:nTop - 1
         //Resize( top, left, bottom, right )
         ::oWndPnt:Resize( ,, ::oWndPnt:nTop + Min( Len( ::aWatch ) + 1, 4 ) )
         lRepaint := .T.
      ELSEIF Len( ::aWatch ) < ::oWndPnt:nBottom - ::oWndPnt:nTop - 1
         ::oWndPnt:Resize( ,, ::oWndPnt:nTop + Len( ::aWatch ) + 1 )
         lRepaint := .T.
      ELSE
         ::oBrwPnt:RefreshAll():ForceStable()
      ENDIF
      IF ! ::oWndPnt:lVisible .OR. lRepaint
         ::ResizeWindows( ::oWndPnt )
      ENDIF
      DispEnd()
   ENDIF

   RETURN NIL


METHOD WndVarsLButtonDown( nMRow, nMCol ) CLASS HBDebugger

   IF nMRow > ::oWndVars:nTop .AND. ;
      nMRow < ::oWndVars:nBottom .AND. ;
      nMCol > ::oWndVars:nLeft .AND. ;
      nMCol < ::oWndVars:nRight

      IF nMRow - ::oWndVars:nTop >= 1 .AND. ;
         nMRow - ::oWndVars:nTop <= Len( ::aVars )

         DO WHILE ::oBrwVars:RowPos > nMRow - ::oWndVars:nTop
            ::oBrwVars:Up()
            ::oBrwVars:ForceStable()
         ENDDO

         DO WHILE ::oBrwVars:RowPos < nMRow - ::oWndVars:nTop
            ::oBrwVars:Down()
            ::oBrwVars:ForceStable()
         ENDDO

      ENDIF
   ENDIF

   RETURN NIL


STATIC PROCEDURE SetsKeyPressed( nKey, oBrwSets, nSets, oWnd, cCaption, bEdit )

   DO CASE
   CASE nKey == K_UP

      oBrwSets:up()

   CASE nKey == K_DOWN

      oBrwSets:down()

   CASE nKey == K_HOME .OR. nKey == K_CTRL_PGUP .OR. nKey == K_CTRL_HOME

      oBrwSets:goTop()

   CASE nKey == K_END .OR. nKey == K_CTRL_PGDN .OR. nKey == K_CTRL_END

      oBrwSets:goBottom()

   CASE nKey == K_PGDN

      oBrwSets:pageDown()

   CASE nKey == K_PGUP

      oBrwSets:pageUp()

   CASE nKey == K_ENTER

      IF bEdit != NIL
         Eval( bEdit )
      ENDIF

      IF LastKey() == K_ENTER
         KEYBOARD Chr( K_DOWN )
      ENDIF

   ENDCASE

   RefreshVarsS( oBrwSets )

   oWnd:SetCaption( cCaption + "[" + RTrim( Str( oBrwSets:Cargo[ 1 ] ) ) + ".." + RTrim( Str( nSets ) ) + "]" )

   RETURN


STATIC PROCEDURE StripUntil( pcLine, i, cChar )

   LOCAL j
   LOCAL n
   LOCAL nLen := Len( pcLine )

   n := Len( cChar )
   j := i + n
   DO WHILE j <= nLen .AND. SubStr( pcLine, j, n ) != cChar
      j++
   ENDDO

   IF j <= nLen
      pcLine := Left( pcLine, i - 1 ) + SubStr( pcLine, j + n )
   ENDIF

   RETURN


FUNCTION __DbgColors()
   RETURN iif( ! s_oDebugger:lMonoDisplay,;
             s_oDebugger:aColors,;
             { "W+/N", "W+/N", "N/W", "N/W", "N/W", "N/W", "W+/N", "N/W", "W+/W", "W/N", "W+/N" } )


FUNCTION __Dbg()
   RETURN s_oDebugger


STATIC PROCEDURE RefreshVarsS( oBrowse )

   LOCAL nLen := oBrowse:colCount

   IF nLen == 2
      oBrowse:deHilite():colPos := 2
   ENDIF
   oBrowse:deHilite():forceStable()

   IF nLen == 2
      oBrowse:hilite():colPos := 1
   ENDIF
   oBrowse:hilite()

   RETURN


STATIC FUNCTION ArrayBrowseSkip( nPos, oBrwSets )
   RETURN iif( oBrwSets:cargo[ 1 ] + nPos < 1, 0 - oBrwSets:cargo[ 1 ] + 1 , ;
             iif( oBrwSets:cargo[ 1 ] + nPos > Len( oBrwSets:cargo[ 2 ][ 1 ] ), ;
                Len( oBrwSets:cargo[ 2 ][ 1 ] ) - oBrwSets:cargo[ 1 ], nPos ) )


STATIC FUNCTION PathToArray( cList )

   LOCAL aList := {}
   LOCAL cSep := hb_OSPathListSeparator()
   LOCAL cDirSep := hb_OSPathDelimiters()
   LOCAL nPos

   IF cList != NIL

      DO WHILE ( nPos := At( cSep, cList ) ) != 0
         AAdd( aList, SubStr( cList, 1, nPos - 1 ) )        // Add a new element
         cList := SubStr( cList, nPos + 1 )
      ENDDO

      AAdd( aList, cList )              // Add final element

      /* Strip ending delimiters */
      AEval( aList, { | x, i | iif( Right( x, 1 ) $ cDirSep,  aList[ i ] := Left( x, Len( x ) - 1 ), ) } )
   ENDIF

   RETURN aList


/* Check if a string starts with another string */
STATIC FUNCTION starts( cLine, cStart )
   RETURN cStart == Left( cLine, Len( cStart ) )


/* Strip path from filename */
STATIC FUNCTION strip_path( cFileName )

   LOCAL cName
   LOCAL cExt

   DEFAULT cFileName TO ""

   hb_FNameSplit( cFileName, NIL, @cName, @cExt )

   RETURN cName + cExt


#ifdef HB_NO_READDBG

STATIC FUNCTION getdbginput( nTop, nLeft, uValue, bValid, cColor )

   LOCAL nOldCursor := SetCursor( SC_NORMAL )
   LOCAL uTemp := uValue

   IF cColor != NIL
      SetColor( cColor )
   ENDIF

   DO WHILE .T.
      @ nTop, nLeft SAY Space( Len( uTemp ) )
      @ nTop, nLeft SAY ""

      ACCEPT TO uTemp

      IF bValid != NIL .AND. !Eval( bValid, uTemp )
         uTemp := uValue
      ELSE
         EXIT
      ENDIF
   ENDDO

   SetCursor( nOldCursor )

   RETURN uTemp

#endif

FUNCTION __dbgValToStr( uVal )

   LOCAL cType := ValType( uVal )

   DO CASE
   CASE uVal == NIL  ; RETURN "NIL"
   CASE cType == "B" ; RETURN "{ || ... }"
   CASE cType == "A" ; RETURN "{ ... }"
   CASE cType $ "CM" ; RETURN '"' + uVal + '"'
   CASE cType == "L" ; RETURN iif( uVal, ".T.", ".F." )
   CASE cType == "D" ; RETURN DToC( uVal )
   CASE cType == "N" ; RETURN RTrim( Str( uVal ) )
   CASE cType == "O" ; RETURN "Class " + uVal:ClassName() + " object"
   CASE cType == "H" ; RETURN "Hash of " + RTrim( Str( Len( uVal ) ) ) + " elements"
   CASE cType == "P" ; RETURN "Pointer"
   ENDCASE

   RETURN "U"
