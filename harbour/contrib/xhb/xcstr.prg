/*
 * $Id$
 */

/*
 * xHarbour Project source code:
 * CStr( xAnyType ) -> String
 *
 * Copyright 2001 Ron Pinkas <ron@@ronpinkas.com>
 * www - http://www.xharbour.org
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
 * As a special exception, xHarbour license gives permission for
 * additional uses of the text contained in its release of xHarbour.
 *
 * The exception is that, if you link the xHarbour libraries with other
 * files to produce an executable, this does not by itself cause the
 * resulting executable to be covered by the GNU General Public License.
 * Your use of that executable is in no way restricted on account of
 * linking the xHarbour library code into it.
 *
 * This exception does not however invalidate any other reasons why
 * the executable file might be covered by the GNU General Public License.
 *
 * This exception applies only to the code released with this xHarbour
 * explicit exception.  If you add/copy code from other sources,
 * as the General Public License permits, the above exception does
 * not apply to the code that you add in this way.  To avoid misleading
 * anyone as to the status of such modified files, you must delete
 * this exception notice from them.
 *
 * If you write modifications of your own for xHarbour, it is your choice
 * whether to permit this exception to apply to your modifications.
 * If you do not wish that, delete this exception notice.
 *
 */

#include "common.ch"
#include "error.ch"

#include "hbclass.ch"

/*
   For performance NOT using OS indpendant R/T function,
   this define only used in ValTpPrg() which currently only used in win32.
 */
#undef CRLF
#define CRLF Chr(13) + Chr(10)

#xtranslate THROW(<oErr>) => (Eval(ErrorBlock(), <oErr>), Break(<oErr>))

//--------------------------------------------------------------//
FUNCTION CStrToVal( cExp, cType )

   IF ! ISCHAR( cExp )
      Throw( ErrorNew( "CSTR", 0, 3101, ProcName(), "Argument error", { cExp, cType } ) )
   ENDIF

   SWITCH cType
      CASE 'C'
         RETURN cExp

      CASE 'P'
         RETURN hb_HexToNum( cExp )

      CASE 'D'
         IF cExp[3] >= '0' .AND. cExp[3] <= '9' .AND. cExp[5] >= '0' .AND. cExp[5] <= '9'
            RETURN hb_SToD( cExp )
         ELSE
            RETURN cToD( cExp )
         ENDIF

      CASE 'L'
         RETURN IIF( cExp[1] == 'T' .OR. cExp[1] == 'Y' .OR. cExp[2] == 'T' .OR. cExp[2] == 'Y', .T., .F. )

      CASE 'N'
         RETURN Val( cExp )

      CASE 'U'
         RETURN NIL

      /*
      CASE 'A'
         Throw( ErrorNew( "CSTRTOVAL", 0, 3101, ProcName(), "Argument error", { cExp, cType } ) )

      CASE 'B'
         Throw( ErrorNew( "CSTRTOVAL", 0, 3101, ProcName(), "Argument error", { cExp, cType } ) )

      CASE 'O'
         Throw( ErrorNew( "CSTRTOVAL", 0, 3101, ProcName(), "Argument error", { cExp, cType } ) )
      */

      OTHERWISE
         Throw( ErrorNew( "CSTRTOVAL", 0, 3101, ProcName(), "Argument error", { cExp, cType } ) )
   ENDSWITCH

RETURN NIL

//--------------------------------------------------------------//
FUNCTION StringToLiteral( cString )

   LOCAL lDouble := .F., lSingle := .F.

   IF hb_RegExHas( "\n|\r", cString ) .OR. ;
      ( ( lDouble := '"' $ cString ) .AND. ( lSingle := "'" $ cString ) .AND. hb_RegExHas( "\[|\]", cString ) )

      cString := StrTran( cString, '"', '\"' )
      cString := StrTran( cString, Chr(10), '\n' )
      cString := StrTran( cString, Chr(13), '\r' )

      //TraceLog( cString )

      RETURN 'E"' + cString + '"'
   ELSEIF lDouble == .F.
      RETURN '"' + cString + '"'
   ELSEIF lSingle == .F.
      RETURN "'" + cString + "'"
   ENDIF

RETURN "[" + cString + "]"

//--------------------------------------------------------------//
FUNCTION ValToPrg( xVal, cName, nPad, aObjs )

   LOCAL cType := ValType( xVal )
   LOCAL aVar, cRet, cPad, nObj

   //TraceLog( xVal, cName, nPad, aObjs )

   SWITCH cType
      CASE 'C'
         RETURN StringToLiteral( xVal )

      CASE 'D'
         RETURN "hb_SToD( '" + dToS( xVal ) + "' )"

      CASE 'L'
         RETURN IIF( xVal, ".T.", ".F." )

      CASE 'N'
         RETURN Str( xVal )

      CASE 'A'
         IF cName == NIL
            nPad := 0
            cName := "M->__ValToPrg_Array"
            aObjs := {}
            cRet  := cName + " := "
         ELSE
            IF ( nObj := aScan( aObjs, {|a| HB_ArrayID( a[1] ) == HB_ArrayID( xVal ) } ) ) > 0
                RETURN aObjs[ nObj ][2] + " /* Cyclic */"
            ENDIF

            cRet := ""
         ENDIF

         aAdd( aObjs, { xVal, cName } )

         cRet  += "Array(" + hb_ntos( Len( xVal ) ) + ")" + CRLF

         nPad += 3
         cPad  := Space( nPad )

         FOR EACH aVar IN xVal
            cRet += cPad + cName + "[" + hb_ntos( aVar:__EnumIndex() ) + "] := " + ValToPrg( aVar, cName + "[" + hb_ntos( aVar:__EnumIndex() ) + "]", nPad, aObjs ) + CRLF
         NEXT

         nPad -=3

         RETURN cRet

      CASE 'H'
         IF Len( xVal ) == 0
            RETURN "hb_Hash()"
         ELSE
            cRet := "{ "

            FOR EACH aVar IN xVal:Keys
               cRet += ValToPrg( aVar ) + " => "
               cRet += ValToPrg( xVal:Values[ aVar:__EnumIndex() ] ) + ", "
            NEXT

            /* We know for sure xVal isn't empty, and a last ',' is here */
            cRet = SubStr( cRet, 1, Len( cRet ) - 2 ) + " }"

            RETURN cRet
         ENDIF

/* There is no support for codeblock serialization */
#if 0
      CASE 'B'
         RETURN ValToPrgExp( xVal )
#endif

      CASE 'P'
         RETURN "0x" + hb_NumToHex( xVal )

      CASE 'O'
         /* TODO: Use HBPersistent() when avialable! */
         IF cName == NIL
            cName := "M->__ValToPrg_Object"
            nPad := 0
            aObjs := {}
            cRet  := cName + " := "
         ELSE
            IF ( nObj := aScan( aObjs, {|a| HB_ArrayID( a[1] ) == HB_ArrayID( xVal ) } ) ) > 0
                RETURN aObjs[ nObj ][2] + " /* Cyclic */"
            ENDIF

            cRet := ""
         ENDIF

         aAdd( aObjs, { xVal, cName } )

         cRet += xVal:ClassName + "():New()" + CRLF

         nPad += 3
         cPad := Space( nPad )

         FOR EACH aVar IN __objGetValueList( xVal )
            cRet += cPad + cName + ":" + aVar[1] + " := " + ValToPrg( aVar[2], cName + ":" + aVar[1], nPad, aObjs ) + CRLF
         NEXT

         nPad -=3
         RETURN cRet

      OTHERWISE
         //TraceLog( xVal, cName, nPad )
         IF xVal == NIL
            cRet := "NIL"
         ELSE
            Throw( ErrorNew( "VALTOPRG", 0, 3103, ProcName(), "Unsupported type", { xVal } ) )
         ENDIF
   ENDSWITCH

   //TraceLog( cRet )

RETURN cRet

//--------------------------------------------------------------//
FUNCTION PrgExpToVal( cExp )
RETURN &( cExp )

//--------------------------------------------------------------//
FUNCTION ValToArray( xVal )

   IF ISARRAY( xVal )
      RETURN xVal
   ENDIF

RETURN { xVal }

//--------------------------------------------------------------//
FUNCTION ValToBlock( xVal )

   IF ISBLOCK( xVal )
      RETURN xVal
   ENDIF

RETURN { || xVal }

//--------------------------------------------------------------//
FUNCTION ValToCharacter( xVal )

   IF ISCHAR( xVal )
      RETURN xVal
   ENDIF

RETURN LTrim( CStr( xVal ) )


//--------------------------------------------------------------//
FUNCTION ValToDate( xVal )

   LOCAL cType := ValType( xVal )

   SWITCH cType
      CASE 'A'
      CASE 'H'
      CASE 'L'
      CASE 'O'
      CASE 'U'
         EXIT

      CASE 'B'
         RETURN ValToDate( Eval( xVal ) )

      CASE 'C'
         IF SubStr( DToS( xVal ), 3, 1 ) >= '0' .AND. ;
            SubStr( DToS( xVal ), 3, 1 ) <= '9' .AND. ;
            SubStr( DToS( xVal ), 5, 1 ) >= '0' .AND. ;
            SubStr( DToS( xVal ), 5, 1 ) <= '9'
            RETURN hb_SToD( xVal )
         ELSE
            RETURN cToD( xVal )
         ENDIF

      CASE 'D'
         RETURN xVal

      CASE 'N'
      CASE 'P'
         RETURN 0d19000101 + xVal

      OTHERWISE
         Throw( ErrorNew( "VALTODATE", 0, 3103, ProcName(), "Unsupported type", { xVal } ) )
   ENDSWITCH

RETURN hb_SToD()

//--------------------------------------------------------------//
FUNCTION ValToHash( xVal )

   IF hb_IsHash( xVal )
      RETURN xVal
   ENDIF

RETURN { ValToCharacter( xVal ) => xVal }

//--------------------------------------------------------------//
FUNCTION ValToLogical( xVal )

   LOCAL cType := ValType( xVal )

   SWITCH cType
      CASE 'A'
      CASE 'D'
      CASE 'H'
      CASE 'N'
      CASE 'O'
      CASE 'P'
         RETURN ! Empty( xVal )

      CASE 'B'
         RETURN ValToLogical( Eval( xVal ) )

      CASE 'C'
         IF Left( xVal, 1 ) == '.' .AND. SubStr( xVal, 3, 1 ) == '.' .AND. Upper( SubStr( xVal, 2, 1 ) ) $ "TFYN"
            RETURN Upper( SubStr( xVal, 2, 1 ) ) $ "TY"
         ELSEIF Len( xVal ) == 1 .AND. Upper( xVal ) $ "TFYN"
            RETURN Upper( xVal ) $ "TY"
         ELSE
            RETURN ! Empty( xVal )
         ENDIF
         EXIT

      CASE 'L'
         RETURN xVal

      CASE 'U'
         RETURN .F.

      OTHERWISE
         Throw( ErrorNew( "VALTOLOGICAL", 0, 3103, ProcName(), "Unsupported type", { xVal } ) )
   ENDSWITCH

RETURN .F.

//--------------------------------------------------------------//
FUNCTION ValToNumber( xVal )

   LOCAL cType := ValType( xVal )

   SWITCH cType
      CASE 'A'
      CASE 'H'
         RETURN Len( xVal )

      CASE 'B'
         RETURN ValToNumber( Eval( xVal ) )

      CASE 'C'
         RETURN Val( xVal )

      CASE 'D'
         RETURN xVal - 0d19000101

      CASE 'L'
         RETURN IIF( xVal, 1, 0 )

      CASE 'O'
         RETURN xVal:hClass

      CASE 'N'
         RETURN xVal

      CASE 'P'
         RETURN xVal - 0

      CASE 'U'
         RETURN 0

      OTHERWISE
         Throw( ErrorNew( "VALTONUMBER", 0, 3103, ProcName(), "Unsupported type", { xVal } ) )
   ENDSWITCH

RETURN 0

//--------------------------------------------------------------//
FUNCTION ValToObject( xVal )

   LOCAL cType := ValType( xVal )

   SWITCH cType
      CASE 'A'
         ENABLE TYPE CLASS ARRAY
         EXIT

      CASE 'B'
         ENABLE TYPE CLASS BLOCK
         EXIT

      CASE 'C'
         ENABLE TYPE CLASS CHARACTER
         EXIT

      CASE 'D'
         ENABLE TYPE CLASS DATE
         EXIT

      CASE 'H'
         ENABLE TYPE CLASS HASH
         EXIT

      CASE 'L'
         ENABLE TYPE CLASS LOGICAL
         EXIT

      CASE 'N'
         ENABLE TYPE CLASS NUMERIC
         EXIT

      CASE 'O'
         RETURN xVal

      CASE 'P'
         ENABLE TYPE CLASS POINTER
         EXIT

      CASE 'U'
         ENABLE TYPE CLASS NIL
         EXIT

      OTHERWISE
         Throw( ErrorNew( "VALTOOBJECT", 0, 3103, ProcName(), "Unsupported type", { xVal } ) )
   ENDSWITCH

RETURN 0

//--------------------------------------------------------------//
FUNCTION ValToType( xVal, cType )

   SWITCH cType
      CASE 'A'
         RETURN ValToArray( xVal )

      CASE 'B'
         RETURN ValToBlock( xVal )

      CASE 'C'
         RETURN ValToCharacter( xVal )

      CASE 'D'
         RETURN ValToDate( xVal )

      CASE 'H'
         RETURN ValToHash( xVal )

      CASE 'L'
         RETURN ValToLogical( xVal )

      CASE 'N'
         RETURN ValToNumber( xVal )

      CASE 'O'
         RETURN ValToObject( xVal )

      CASE 'P'
         RETURN ValToNumber( xVal )

      CASE 'U'
         RETURN NIL

      OTHERWISE
         Throw( ErrorNew( "VALTOTYPE", 0, 3103, ProcName(), "Unsupported type", { xVal } ) )
   ENDSWITCH

RETURN NIL
//--------------------------------------------------------------//
