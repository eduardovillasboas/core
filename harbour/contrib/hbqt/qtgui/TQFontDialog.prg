/*
 * $Id$
 */

/* -------------------------------------------------------------------- */
/* WARNING: Automatically generated source file. DO NOT EDIT!           */
/*          Instead, edit corresponding .qth file,                      */
/*          or the generator tool itself, and run regenarate.           */
/* -------------------------------------------------------------------- */

/*
 * Harbour Project source code:
 * QT wrapper main header
 *
 * Copyright 2009 Pritpal Bedi <pritpal@vouchcac.com>
 *
 * Copyright 2009 Marcos Antonio Gambeta <marcosgambeta at gmail dot com>
 * www - http://www.harbour-project.org
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
/*----------------------------------------------------------------------*/


#include "hbclass.ch"


CREATE CLASS QFontDialog INHERIT QDialog

   VAR     pPtr

   METHOD  new()
   METHOD  configure( xObject )

   METHOD  currentFont()
   METHOD  options()
   METHOD  selectedFont()
   METHOD  setCurrentFont( pFont )
   METHOD  setOption( nOption, lOn )
   METHOD  setOptions( nOptions )
   METHOD  testOption( nOption )
   METHOD  getFont( lOk, pInitial, pParent, cTitle, nOptions )
   METHOD  getFont_1( lOk, pInitial, pParent, pName )
   METHOD  getFont_2( lOk, pInitial, pParent, cTitle )
   METHOD  getFont_3( lOk, pInitial, pParent )
   METHOD  getFont_4( lOk, pParent )

   ENDCLASS

/*----------------------------------------------------------------------*/

METHOD QFontDialog:new( pParent )
   ::pPtr := Qt_QFontDialog( pParent )
   RETURN Self


METHOD QFontDialog:configure( xObject )
   IF hb_isObject( xObject )
      ::pPtr := xObject:pPtr
   ELSEIF hb_isPointer( xObject )
      ::pPtr := xObject
   ENDIF
   RETURN Self


METHOD QFontDialog:currentFont()
   RETURN Qt_QFontDialog_currentFont( ::pPtr )


METHOD QFontDialog:options()
   RETURN Qt_QFontDialog_options( ::pPtr )


METHOD QFontDialog:selectedFont()
   RETURN Qt_QFontDialog_selectedFont( ::pPtr )


METHOD QFontDialog:setCurrentFont( pFont )
   RETURN Qt_QFontDialog_setCurrentFont( ::pPtr, pFont )


METHOD QFontDialog:setOption( nOption, lOn )
   RETURN Qt_QFontDialog_setOption( ::pPtr, nOption, lOn )


METHOD QFontDialog:setOptions( nOptions )
   RETURN Qt_QFontDialog_setOptions( ::pPtr, nOptions )


METHOD QFontDialog:testOption( nOption )
   RETURN Qt_QFontDialog_testOption( ::pPtr, nOption )


METHOD QFontDialog:getFont( lOk, pInitial, pParent, cTitle, nOptions )
   RETURN Qt_QFontDialog_getFont( ::pPtr, lOk, pInitial, pParent, cTitle, nOptions )


METHOD QFontDialog:getFont_1( lOk, pInitial, pParent, pName )
   RETURN Qt_QFontDialog_getFont_1( ::pPtr, lOk, pInitial, pParent, pName )


METHOD QFontDialog:getFont_2( lOk, pInitial, pParent, cTitle )
   RETURN Qt_QFontDialog_getFont_2( ::pPtr, lOk, pInitial, pParent, cTitle )


METHOD QFontDialog:getFont_3( lOk, pInitial, pParent )
   RETURN Qt_QFontDialog_getFont_3( ::pPtr, lOk, pInitial, pParent )


METHOD QFontDialog:getFont_4( lOk, pParent )
   RETURN Qt_QFontDialog_getFont_4( ::pPtr, lOk, pParent )

