/*
 * $Id$
 */

/*
 * xHarbour Project source code:
 * TIP Class oriented Internet protocol library
 *
 * Copyright 2003 Giancarlo Niccolai <gian@niccolai.ws>
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

/* 2007-04-12, Hannes Ziegler <hz AT knowlexbase.com>
   Added method :sendMail()
*/

#include "hbclass.ch"
#include "tip.ch"

CREATE CLASS tIPClientSMTP FROM tIPClient

   METHOD New( oUrl, lTrace, oCredentials )
   METHOD Open( cUrl )
   METHOD Close()
   METHOD Write( cData, nLen, bCommit )
   METHOD Mail( cFrom )
   METHOD Rcpt( cRcpt )
   METHOD Data( cData )
   METHOD Commit()
   METHOD Quit()
   METHOD GetOK()
   METHOD SendMail( oTIpMail )

   /* Methods for smtp server that require login */
   METHOD OpenSecure( cUrl )
   METHOD Auth( cUser, cPass ) // Auth by login method
   METHOD AuthPlain( cUser, cPass ) // Auth by plain method
   METHOD ServerSuportSecure( lAuthPlain, lAuthLogin )

   HIDDEN:

   VAR isAuth INIT .F.

ENDCLASS

METHOD New( oUrl, lTrace, oCredentials ) CLASS tIPClientSMTP
   LOCAL n

   ::super:New( oUrl, lTrace, oCredentials )

   ::nDefaultPort := 25
   ::nConnTimeout := 5000
   ::nAccessMode := TIP_WO  // a write only

   IF ::ltrace
      IF ! hb_FileExists( "sendmail.log" )
         ::nHandle := FCreate( "sendmail.log" )
      ELSE
         n := 1
         DO WHILE hb_FileExists( "sendmail" + hb_ntos( n ) + ".log" )
            n++
         ENDDO
         ::nHandle := FCreate( "sendmail" + hb_ntos( n ) + ".log" )
      ENDIF
   ENDIF

   RETURN Self

METHOD Open( cUrl ) CLASS tIPClientSMTP

   IF ! ::super:Open( cUrl )
      RETURN .F.
   ENDIF

   hb_inetTimeout( ::SocketCon, ::nConnTimeout )

   ::InetSendall( ::SocketCon, "HELO " + iif( Empty( ::oUrl:cUserid ), "tipClientSMTP", ::oUrl:cUserid ) + ::cCRLF )

   RETURN ::GetOk()

METHOD OpenSecure( cUrl ) CLASS tIPClientSMTP

   IF ! ::super:Open( cUrl )
      RETURN .F.
   ENDIF

   hb_inetTimeout( ::SocketCon, ::nConnTimeout )

   ::InetSendall( ::SocketCon, "EHLO " + iif( Empty( ::oUrl:cUserid ), "tipClientSMTP", ::oUrl:cUserid ) + ::cCRLF )

   RETURN ::GetOk()

METHOD GetOk() CLASS tIPClientSMTP

   ::cReply := ::InetRecvLine( ::SocketCon,, 512 )
   IF ::InetErrorCode( ::SocketCon ) != 0 .OR. Left( ::cReply, 1 ) == "5"
      RETURN .F.
   ENDIF

   RETURN .T.

METHOD Close() CLASS tIPClientSMTP
   hb_inetTimeOut( ::SocketCon, ::nConnTimeout )
   IF ::ltrace
      FClose( ::nHandle )
   ENDIF
   ::Quit()
   RETURN ::super:Close()

METHOD Commit() CLASS tIPClientSMTP
   ::InetSendall( ::SocketCon, ::cCRLF + "." + ::cCRLF )
   RETURN ::GetOk()

METHOD Quit() CLASS tIPClientSMTP
   ::InetSendall( ::SocketCon, "QUIT" + ::cCRLF )
   ::isAuth := .F.
   RETURN ::GetOk()

METHOD Mail( cFrom ) CLASS tIPClientSMTP
   ::InetSendall( ::SocketCon, "MAIL FROM: <" + cFrom + ">" + ::cCRLF )
   RETURN ::GetOk()

METHOD Rcpt( cTo ) CLASS tIPClientSMTP
   ::InetSendall( ::SocketCon, "RCPT TO: <" + cTo + ">" + ::cCRLF )
   RETURN ::GetOk()

METHOD Data( cData ) CLASS tIPClientSMTP
   ::InetSendall( ::SocketCon, "DATA" + ::cCRLF )
   IF ! ::GetOk()
      RETURN .F.
   ENDIF
   ::InetSendall(::SocketCon, cData + ::cCRLF + "." + ::cCRLF )
   RETURN ::GetOk()

METHOD Auth( cUser, cPass ) CLASS tIPClientSMTP

   ::InetSendall( ::SocketCon, "AUTH LOGIN" + ::cCRLF )

   IF ::GetOk()
      ::InetSendall( ::SocketCon, hb_BASE64( StrTran( cUser, "&at;", "@" ) ) + ::cCRLF  )
      IF ::GetOk()
         ::InetSendall( ::SocketCon, hb_BASE64( cPass ) + ::cCRLF )
      ENDIF
   ENDIF

   RETURN ::isAuth := ::GetOk()

METHOD AuthPlain( cUser, cPass ) CLASS tIPClientSMTP

   ::InetSendall( ::SocketCon, "AUTH PLAIN" + hb_BASE64( Chr( 0 ) + cUser + Chr( 0 ) + cPass ) + ::cCRLF )

   RETURN ::isAuth := ::GetOk()

METHOD Write( cData, nLen, bCommit ) CLASS tIPClientSMTP
   LOCAL cRcpt

   IF ! ::bInitialized

      IF Empty( ::oUrl:cFile )  // GD user id not needed if we did not auth
         RETURN -1
      ENDIF

      IF ! ::Mail( ::oUrl:cUserid )
         RETURN -1
      ENDIF

      FOR EACH cRcpt IN hb_regexSplit( ",", ::oUrl:cFile )
         IF ! ::Rcpt( cRcpt )
            RETURN -1
         ENDIF
      NEXT

      ::InetSendall( ::SocketCon, "DATA" + ::cCRLF )
      IF ! ::GetOk()
         RETURN -1
      ENDIF
      ::bInitialized := .T.
   ENDIF

   ::nLastWrite := ::super:Write( cData, nLen, bCommit )

   RETURN ::nLastWrite

METHOD ServerSuportSecure( /* @ */ lAuthPlain, /* @ */ lAuthLogin ) CLASS tIPClientSMTP

   lAuthLogin := .F.
   lAuthPlain := .F.

   IF ::OpenSecure()
      DO WHILE .T.
         ::GetOk()
         IF ::cReply == NIL
            EXIT
         ELSEIF "LOGIN" $ ::cReply
            lAuthLogin := .T.
         ELSEIF "PLAIN" $ ::cReply
            lAuthPlain := .T.
         ENDIF
      ENDDO
      ::Close()
   ENDIF

   RETURN lAuthLogin .OR. lAuthPlain

METHOD SendMail( oTIpMail ) CLASS TIpClientSmtp
   LOCAL cTo

   IF ! ::isOpen
      RETURN .F.
   ENDIF

   IF ! ::isAuth
      ::Auth( ::oUrl:cUserId, ::oUrl:cPassWord )
      IF ! ::isAuth
         RETURN .F.
      ENDIF
   ENDIF

   ::mail( oTIpMail:getFieldPart( "From" ) )

   cTo   := oTIpMail:getFieldPart( "To" )
   cTo   := StrTran( cTo, hb_inetCRLF() )
   cTo   := StrTran( cTo, Chr( 9 ) )
   cTo   := StrTran( cTo, Chr( 32 ) )

   FOR EACH cTo IN hb_regexSplit( ",", cTo )
      ::rcpt( cTo )
   NEXT

   RETURN ::data( oTIpMail:toString() )
